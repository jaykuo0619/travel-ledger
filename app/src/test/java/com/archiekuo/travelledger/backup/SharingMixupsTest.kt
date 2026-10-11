package com.archiekuo.travelledger.backup

import com.archiekuo.travelledger.data.AppDatabase
import com.archiekuo.travelledger.data.Expense
import com.archiekuo.travelledger.data.testDb
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File

/**
 * The organizer (小明) plans on the computer. Files easily go to the wrong people:
 *  - the computer file reaches a companion's phone, which does not have the trip yet;
 *  - a companion sends back a whole trip file of the organizer's own trip instead of additions.
 * Both must still end with the companion's additions in the organizer's book.
 */
@RunWith(RobolectricTestRunner::class)
class SharingMixupsTest {
    @get:Rule val tmp = TemporaryFolder()
    private lateinit var organizer: AppDatabase
    private lateinit var companion: AppDatabase
    private val fixtures = File("../compat/fixtures")

    @Before fun setUp() = runBlocking {
        organizer = testDb()
        companion = testDb()
        // The organizer's own trip-seoul (as in the backup fixture).
        TripArchive.import(organizer, File(fixtures, "backup.zip"), tmp.newFolder())
        Unit
    }

    @After fun tearDown() {
        organizer.close()
        companion.close()
    }

    private fun cat(db: AppDatabase, name: String) = runBlocking { db.lookupDao().getCategories().first { it.name == name }.id }

    private fun airfare(db: AppDatabase, trip: Long, pending: Boolean) = runBlocking {
        db.expenseDao().insert(
            Expense(tripId = trip, date = 20740, amount = 12000.0, currency = "TWD", rate = 1.0, homeAmount = 12000.0,
                categoryId = cat(db, "交通"), paymentMethodId = null, payerId = null, title = "機票", uuid = "exp-flight", pending = pending),
        )
    }

    @Test fun computerFileOnACompanionsPhoneCanArriveReadOnly() = runBlocking {
        val plans = File(fixtures, "plans.zip")
        assertTrue(TripArchive.previewPlans(companion, plans).newTrip)
        val result = TripArchive.importPlans(companion, plans, tmp.newFolder(), organizer = "小明") as TripArchive.Result.Imported
        assertEquals(TripArchive.KIND_TRIP, result.kind) // reads "只能看、不能改"
        val copy = companion.tripDao().getTrip(result.tripIds.single())!!
        assertEquals("小明", copy.sharedBy)
        assertTrue(copy.readOnly)

        // The companion's airfare is an addition for 小明, who takes it in.
        airfare(companion, copy.id, pending = true)
        val file = tmp.newFile().also { f -> f.outputStream().use { TripArchive.exportAdditions(companion, it, copy.id, "小美", false) } }
        val added = TripArchive.importAdditions(organizer, file, tmp.newFolder(), setOf("exp-flight")) as TripArchive.Result.Imported
        assertEquals(1, added.updated)
        val mine = organizer.tripDao().findByUuid("trip-seoul")!!
        assertEquals("小美", organizer.expenseDao().forTrip(mine.id).single { it.uuid == "exp-flight" }.addedBy)
    }

    @Test fun computerFileOnMyOwnPhoneStaysMine() = runBlocking {
        val result = TripArchive.importPlans(companion, File(fixtures, "plans.zip"), tmp.newFolder()) as TripArchive.Result.Imported
        assertEquals(TripArchive.KIND_PLANS, result.kind)
        assertNull(companion.tripDao().getTrip(result.tripIds.single())!!.sharedBy)
    }

    @Test fun myOwnTripSentBackOffersWhatTheyAdded() = runBlocking {
        // The companion got the computer file as their own trip, recorded the airfare and shared the whole trip back.
        val theirs = (TripArchive.importPlans(companion, File(fixtures, "plans.zip"), tmp.newFolder()) as TripArchive.Result.Imported).tripIds.single()
        airfare(companion, theirs, pending = false)
        val file = tmp.newFile().also { f -> f.outputStream().use { TripArchive.export(companion, it, TripArchive.KIND_TRIP, listOf(theirs), false, "小美") } }

        // Importing it as a trip is still refused (it is mine); instead its new items are offered.
        assertTrue(TripArchive.import(organizer, file, tmp.newFolder()) is TripArchive.Result.Failed)
        val offer = TripArchive.readNewItems(organizer, file)!!
        assertEquals("小美", offer.from)
        assertTrue(offer.items.any { it.uuid == "exp-flight" && it.isExpense })
        val mine = organizer.tripDao().findByUuid("trip-seoul")!!
        val before = organizer.planDao().forTrip(mine.id).associate { it.uuid to it.title }

        val result = TripArchive.importNewItems(organizer, file, tmp.newFolder(), setOf("exp-flight")) as TripArchive.Result.Imported
        assertEquals(TripArchive.KIND_ADDITIONS, result.kind)
        assertEquals(1, result.updated)
        val flight = organizer.expenseDao().forTrip(mine.id).single { it.uuid == "exp-flight" }
        assertEquals(Triple("機票", 12000.0, "小美"), Triple(flight.title, flight.amount, flight.addedBy))
        assertNull(flight.payerId)
        // Nothing of mine changed, and the same file again has nothing new to take.
        assertEquals(before, organizer.planDao().forTrip(mine.id).associate { it.uuid to it.title })
        assertTrue(TripArchive.readNewItems(organizer, file)!!.items.none { it.uuid == "exp-flight" })
    }

    @Test fun aReSharedCopyCarriesNoAdditions() = runBlocking {
        // The usual mix-up: the companion re-shares the read-only copy (分享給同伴) instead of 傳給記帳人.
        val share = tmp.newFile().also { f ->
            val mine = organizer.tripDao().findByUuid("trip-seoul")!!
            f.outputStream().use { TripArchive.export(organizer, it, TripArchive.KIND_TRIP, listOf(mine.id), false, "小明") }
        }
        val copy = (TripArchive.import(companion, share, tmp.newFolder()) as TripArchive.Result.Imported).tripIds.single()
        airfare(companion, copy, pending = true)
        val reShared = tmp.newFile().also { f -> f.outputStream().use { TripArchive.export(companion, it, TripArchive.KIND_TRIP, listOf(copy), false, "小美") } }
        // My additions never travel in a share, so there is nothing new: the app then says to use 傳給記帳人.
        assertEquals(emptyList<TripArchive.AdditionItem>(), TripArchive.readNewItems(organizer, reShared)!!.items)
    }

    @Test fun aFileThatIsNotMyOwnTripIsNotOffered() = runBlocking {
        assertNull(TripArchive.readNewItems(companion, File(fixtures, "trip.zip"))) // companion has no such trip
        assertNull(TripArchive.readNewItems(organizer, File(fixtures, "additions.zip"))) // not a trip file
    }
}
