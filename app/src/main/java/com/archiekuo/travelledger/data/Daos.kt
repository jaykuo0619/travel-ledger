package com.archiekuo.travelledger.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

data class TripSummary(
    val id: Long,
    val name: String,
    val startDate: Long,
    val endDate: Long,
    val budget: Double?,
    val coverPath: String?,
    val coverTheme: String?,
    val totalHome: Double,
    val memberCount: Int,
    /** Comma-separated foreign currencies used in this trip, or null. */
    val currencies: String?,
    /** Non-null for a read-only copy someone shared with us. */
    val sharedBy: String? = null,
)

@Dao
interface TripDao {
    @Query(
        """SELECT t.id, t.name, t.startDate, t.endDate, t.budget, t.coverPath, t.coverTheme, t.sharedBy,
                  COALESCE((SELECT SUM(homeAmount) FROM expense WHERE tripId = t.id), 0) AS totalHome,
                  (SELECT COUNT(*) FROM member WHERE tripId = t.id) AS memberCount,
                  (SELECT GROUP_CONCAT(currency) FROM
                      (SELECT DISTINCT currency FROM expense WHERE tripId = t.id AND currency != 'TWD'
                       UNION SELECT currency FROM trip_currency_rate WHERE tripId = t.id)) AS currencies
           FROM trip t WHERE t.archived = 0 ORDER BY t.startDate DESC"""
    )
    fun observeSummaries(): Flow<List<TripSummary>>

    @Query("SELECT * FROM trip WHERE archived = 0 ORDER BY startDate DESC")
    suspend fun getTrips(): List<Trip>

    @Query("SELECT * FROM trip WHERE id = :id")
    suspend fun getTrip(id: Long): Trip?

    @Query("SELECT * FROM trip WHERE uuid = :uuid LIMIT 1")
    suspend fun findByUuid(uuid: String): Trip?

    @Query("SELECT * FROM trip_currency_rate WHERE tripId = :tripId")
    suspend fun getRates(tripId: Long): List<TripCurrencyRate>

    @Query("SELECT * FROM trip WHERE id = :id")
    fun observeTrip(id: Long): Flow<Trip?>

    @Query("SELECT * FROM member WHERE tripId = :tripId ORDER BY id")
    fun observeMembers(tripId: Long): Flow<List<Member>>

    @Insert suspend fun insertTrip(trip: Trip): Long
    @Insert suspend fun insertMembers(members: List<Member>)
    @Insert suspend fun insertMember(member: Member): Long

    /** Every trip, archived or not, for a full backup. */
    @Query("SELECT id FROM trip ORDER BY startDate")
    suspend fun allIds(): List<Long>

    @Query("DELETE FROM expense WHERE tripId = :tripId AND pending = 0") suspend fun deleteExpenses(tripId: Long)
    @Query("DELETE FROM plan_item WHERE tripId = :tripId AND pending = 0") suspend fun deletePlans(tripId: Long)

    @Query("SELECT COUNT(*) FROM expense WHERE tripId = :tripId AND pending = 1")
    fun observePendingExpenses(tripId: Long): Flow<Int>

    @Query("SELECT COUNT(*) FROM plan_item WHERE tripId = :tripId AND pending = 1")
    fun observePendingPlans(tripId: Long): Flow<Int>
    @Query("DELETE FROM member WHERE tripId = :tripId") suspend fun deleteMembers(tripId: Long)
    @Query("DELETE FROM day_note WHERE tripId = :tripId") suspend fun deleteDayNotes(tripId: Long)

    @Query("DELETE FROM expense WHERE tripId = :tripId") suspend fun deleteAllExpenses(tripId: Long)
    @Query("DELETE FROM plan_item WHERE tripId = :tripId") suspend fun deleteAllPlans(tripId: Long)

    /** Empties a trip completely, for restoring a backup over it. */
    @Transaction
    suspend fun clearAll(tripId: Long) {
        deleteDayNotes(tripId)
        deleteAllExpenses(tripId)
        deleteAllPlans(tripId)
        deleteMembers(tripId)
        deleteRates(tripId)
    }

    /** Empties a trip (photo rows go with their expenses) so an import can refill it under the same id; my pending additions stay. */
    @Transaction
    suspend fun clearContents(tripId: Long) {
        deleteDayNotes(tripId)
        deleteExpenses(tripId)
        deletePlans(tripId)
        deleteMembers(tripId)
        deleteRates(tripId)
    }

    @Transaction
    suspend fun createTrip(trip: Trip, memberNames: List<String>, rates: List<TripCurrencyRate>): Long {
        val id = insertTrip(trip)
        insertMembers(memberNames.map { Member(tripId = id, name = it) })
        rates.forEach { upsertRate(it.copy(tripId = id)) }
        return id
    }

    @Query("SELECT * FROM member WHERE tripId = :tripId ORDER BY id")
    suspend fun getMembers(tripId: Long): List<Member>

    @Query("DELETE FROM member WHERE id = :id")
    suspend fun deleteMemberRow(id: Long)

    @Query("UPDATE expense SET payerId = NULL WHERE payerId = :memberId")
    suspend fun clearPayer(memberId: Long)

    /** A removed member no longer pays for anything: their expenses keep no dangling payer. */
    @Transaction
    suspend fun deleteMember(id: Long) {
        clearPayer(id)
        deleteMemberRow(id)
    }

    @Update suspend fun updateTrip(trip: Trip)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertRate(rate: TripCurrencyRate)

    @Query("DELETE FROM trip_currency_rate WHERE tripId = :tripId")
    suspend fun deleteRates(tripId: Long)

    /** Keeps existing members that still appear by name so expense references stay valid. */
    @Transaction
    suspend fun updateTrip(trip: Trip, memberNames: List<String>, rates: List<TripCurrencyRate>) {
        updateTrip(trip)
        val existing = getMembers(trip.id)
        existing.filter { it.name !in memberNames }.forEach { deleteMember(it.id) }
        val kept = existing.map { it.name }.toSet()
        insertMembers(memberNames.filter { it !in kept }.map { Member(tripId = trip.id, name = it) })
        deleteRates(trip.id)
        rates.forEach { upsertRate(it.copy(tripId = trip.id)) }
    }

    @Query("DELETE FROM trip WHERE id = :id")
    suspend fun deleteTrip(id: Long)

    @Query("SELECT coverPath FROM trip WHERE id = :id")
    suspend fun coverPath(id: Long): String?
}

data class ExpenseRow(
    val id: Long,
    val date: Long,
    val minuteOfDay: Int?,
    val title: String,
    val amount: Double,
    val currency: String,
    val rate: Double,
    val homeAmount: Double,
    val categoryId: Long?,
    val categoryName: String?,
    val categoryIcon: String?,
    val categoryColor: Int?,
    val paymentMethodName: String?,
    val note: String,
    val thumbPath: String?,
    val planItemId: Long?,
    val addedBy: String? = null,
    /** My own addition on a shared trip, not yet taken in by the organizer. */
    val pending: Boolean = false,
)

/** A previously used expense title and the category it was last filed under. */
data class TitleSuggestion(val title: String, val categoryId: Long?, val lastUsed: Long)

@Dao
interface ExpenseDao {
    @Query(
        """SELECT e.id, e.date, e.minuteOfDay, e.title, e.amount, e.currency, e.rate, e.homeAmount,
                  e.categoryId, c.name AS categoryName, c.icon AS categoryIcon, c.color AS categoryColor,
                  p.name AS paymentMethodName, e.note,
                  (SELECT path FROM photo WHERE expenseId = e.id ORDER BY id LIMIT 1) AS thumbPath, e.planItemId,
                  e.addedBy, e.pending
           FROM expense e
           LEFT JOIN category c ON c.id = e.categoryId
           LEFT JOIN payment_method p ON p.id = e.paymentMethodId
           WHERE e.tripId = :tripId
           ORDER BY e.date DESC, COALESCE(e.minuteOfDay, -1) DESC, e.id DESC"""
    )
    fun observeRows(tripId: Long): Flow<List<ExpenseRow>>

    @Query("SELECT * FROM expense WHERE id = :id")
    suspend fun get(id: Long): Expense?

    @Query("SELECT * FROM expense WHERE tripId = :tripId ORDER BY id")
    suspend fun forTrip(tripId: Long): List<Expense>

    @Query("SELECT uuid FROM expense WHERE tripId = :tripId")
    suspend fun uuids(tripId: Long): List<String>

    @Query("UPDATE expense SET planItemId = :planId WHERE id = :id")
    suspend fun setPlan(id: Long, planId: Long?)

    @Query("SELECT * FROM expense WHERE tripId = :tripId ORDER BY createdAt DESC LIMIT 1")
    suspend fun latest(tripId: Long): Expense?

    /** SQLite returns the other columns from the row holding MAX(createdAt). */
    @Query(
        """SELECT title, categoryId, MAX(createdAt) AS lastUsed FROM expense
           WHERE title != '' GROUP BY title ORDER BY lastUsed DESC LIMIT 300"""
    )
    suspend fun titleSuggestions(): List<TitleSuggestion>

    @Insert suspend fun insert(expense: Expense): Long
    @Update suspend fun update(expense: Expense)

    @Query("DELETE FROM expense WHERE id = :id")
    suspend fun delete(id: Long)

    @Query("SELECT * FROM trip_currency_rate WHERE tripId = :tripId ORDER BY currency")
    fun observeRates(tripId: Long): Flow<List<TripCurrencyRate>>

    @Query("SELECT * FROM trip_currency_rate WHERE tripId = :tripId ORDER BY currency")
    suspend fun getRates(tripId: Long): List<TripCurrencyRate>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertRate(rate: TripCurrencyRate)
}

/** A plan item with its category look and what has been spent on it so far. */
data class PlanRow(
    val id: Long,
    val title: String,
    val categoryId: Long?,
    val categoryName: String?,
    val categoryIcon: String?,
    val categoryColor: Int?,
    val date: Long?,
    val minuteOfDay: Int?,
    val status: String,
    val reservation: String,
    val reservationNote: String,
    val location: String,
    val estCost: Double?,
    val spent: Double,
    val addedBy: String? = null,
    val pending: Boolean = false,
    val photoCount: Int = 0,
)

@Dao
interface PlanDao {
    @Query(
        """SELECT pl.id, pl.title, pl.categoryId, c.name AS categoryName, c.icon AS categoryIcon, c.color AS categoryColor,
                  pl.date, pl.minuteOfDay, pl.status, pl.reservation, pl.reservationNote, pl.location, pl.estCost,
                  COALESCE((SELECT SUM(homeAmount) FROM expense WHERE planItemId = pl.id), 0) AS spent,
                  pl.addedBy, pl.pending, (SELECT COUNT(*) FROM plan_photo WHERE planItemId = pl.id) AS photoCount
           FROM plan_item pl LEFT JOIN category c ON c.id = pl.categoryId
           WHERE pl.tripId = :tripId
           ORDER BY pl.date IS NULL, pl.date, pl.minuteOfDay IS NULL, pl.minuteOfDay, pl.id"""
    )
    fun observeRows(tripId: Long): Flow<List<PlanRow>>

    @Query("SELECT * FROM plan_item WHERE id = :id")
    suspend fun get(id: Long): PlanItem?

    @Query("SELECT * FROM plan_item WHERE id = :id")
    fun observe(id: Long): Flow<PlanItem?>

    @Query("SELECT * FROM plan_item WHERE tripId = :tripId ORDER BY id")
    suspend fun forTrip(tripId: Long): List<PlanItem>

    @Query("SELECT uuid FROM plan_item WHERE tripId = :tripId")
    suspend fun uuids(tripId: Long): List<String>

    @Query("SELECT * FROM plan_item WHERE tripId = :tripId AND uuid = :uuid LIMIT 1")
    suspend fun findByUuid(tripId: Long, uuid: String): PlanItem?

    @Insert suspend fun insert(item: PlanItem): Long
    @Insert suspend fun insertAll(items: List<PlanItem>)
    @Update suspend fun update(item: PlanItem)

    @Query("UPDATE plan_item SET status = :status WHERE id = :id")
    suspend fun setStatus(id: Long, status: String)

    @Query("UPDATE plan_item SET date = :date WHERE id = :id")
    suspend fun setDate(id: Long, date: Long?)

    @Query("UPDATE expense SET planItemId = NULL WHERE planItemId = :id")
    suspend fun unlinkExpenses(id: Long)

    @Query("DELETE FROM plan_item WHERE id = :id")
    suspend fun deleteRow(id: Long)

    @Transaction
    suspend fun delete(id: Long) {
        unlinkExpenses(id)
        deleteRow(id)
    }
}

@Dao
interface PhotoDao {
    @Query("SELECT * FROM photo WHERE expenseId = :expenseId ORDER BY id")
    suspend fun forExpense(expenseId: Long): List<Photo>

    @Query("SELECT path FROM photo WHERE expenseId IN (SELECT id FROM expense WHERE tripId = :tripId)")
    suspend fun pathsForTrip(tripId: Long): List<String>

    @Query("SELECT path FROM photo WHERE expenseId IN (SELECT id FROM expense WHERE tripId = :tripId AND pending = 0)")
    suspend fun pathsForOfficial(tripId: Long): List<String>

    @Insert suspend fun insert(photo: Photo): Long
    @Update suspend fun update(photo: Photo)

    @Query("DELETE FROM photo WHERE id = :id")
    suspend fun delete(id: Long)
}

@Dao
interface LookupDao {
    @Query("SELECT * FROM category ORDER BY sortOrder, id")
    fun observeCategories(): Flow<List<Category>>

    @Query("SELECT * FROM category ORDER BY sortOrder, id")
    suspend fun getCategories(): List<Category>

    @Query("SELECT * FROM payment_method ORDER BY sortOrder, id")
    suspend fun getPaymentMethods(): List<PaymentMethod>

    @Query("SELECT * FROM payment_method ORDER BY sortOrder, id")
    fun observePaymentMethods(): Flow<List<PaymentMethod>>

    @Insert suspend fun insertCategory(item: Category): Long
    @Insert suspend fun insertPaymentMethod(item: PaymentMethod): Long
    @Update suspend fun updateCategories(items: List<Category>)
    @Update suspend fun updatePaymentMethods(items: List<PaymentMethod>)

    @Query("SELECT id FROM category WHERE builtIn = :builtIn LIMIT 1")
    suspend fun findBuiltInCategoryId(builtIn: String): Long?

    @Query("SELECT * FROM category WHERE id = :id")
    suspend fun getCategory(id: Long): Category?

    @Query("SELECT * FROM payment_method WHERE id = :id")
    suspend fun getPaymentMethod(id: Long): PaymentMethod?

    @Query("SELECT COUNT(*) FROM expense WHERE categoryId = :id")
    suspend fun expensesWithCategory(id: Long): Int

    @Query("SELECT COUNT(*) FROM plan_item WHERE categoryId = :id")
    suspend fun plansWithCategory(id: Long): Int

    @Query("SELECT COUNT(*) FROM expense WHERE paymentMethodId = :id")
    suspend fun expensesWithPaymentMethod(id: Long): Int

    @Query("UPDATE expense SET categoryId = :to WHERE categoryId = :from")
    suspend fun reassignCategory(from: Long, to: Long?)

    @Query("UPDATE plan_item SET categoryId = :to WHERE categoryId = :from")
    suspend fun reassignPlanCategory(from: Long, to: Long?)

    @Query("DELETE FROM category WHERE id = :id")
    suspend fun deleteCategoryRow(id: Long)

    @Query("UPDATE expense SET paymentMethodId = NULL WHERE paymentMethodId = :id")
    suspend fun clearPaymentMethod(id: Long)

    @Query("DELETE FROM payment_method WHERE id = :id")
    suspend fun deletePaymentMethodRow(id: Long)

    /**
     * Deletes a category the user added; the app's own categories can only be renamed. Expenses and plan items using it
     * move to 「其他」 (whatever it is called now). Returns false when the category may not be deleted.
     */
    @Transaction
    suspend fun deleteCategory(id: Long): Boolean {
        val c = getCategory(id) ?: return false
        if (c.builtIn != null) return false
        val other = findBuiltInCategoryId(FALLBACK_CATEGORY)
        reassignCategory(id, other)
        reassignPlanCategory(id, other)
        deleteCategoryRow(id)
        return true
    }

    /** Deletes a payment method the user added (expenses using it become 未指定); the app's own ones can only be renamed. */
    @Transaction
    suspend fun deletePaymentMethod(id: Long): Boolean {
        val m = getPaymentMethod(id) ?: return false
        if (m.builtIn != null) return false
        clearPaymentMethod(id)
        deletePaymentMethodRow(id)
        return true
    }
}

@Dao
interface DayNoteDao {
    @Query("SELECT * FROM day_note WHERE tripId = :tripId")
    fun observe(tripId: Long): Flow<List<DayNote>>

    @Query("SELECT * FROM day_note WHERE tripId = :tripId")
    suspend fun forTrip(tripId: Long): List<DayNote>

    @Query("SELECT * FROM day_note WHERE tripId = :tripId AND day = :day")
    suspend fun get(tripId: Long, day: Long): DayNote?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun put(note: DayNote)

    @Query("DELETE FROM day_note WHERE tripId = :tripId AND day = :day")
    suspend fun delete(tripId: Long, day: Long)

    /** Saves the note, or removes it when the text is blank. */
    @Transaction
    suspend fun set(tripId: Long, day: Long, text: String) {
        if (text.isBlank()) delete(tripId, day) else put(DayNote(tripId, day, text.trim()))
    }
}

@Dao
interface PlanPhotoDao {
    @Query("SELECT * FROM plan_photo WHERE planItemId = :planId ORDER BY id")
    suspend fun forPlan(planId: Long): List<PlanPhoto>

    @Query("SELECT * FROM plan_photo WHERE planItemId = :planId ORDER BY id")
    fun observe(planId: Long): Flow<List<PlanPhoto>>

    @Query("SELECT path FROM plan_photo WHERE planItemId IN (SELECT id FROM plan_item WHERE tripId = :tripId)")
    suspend fun pathsForTrip(tripId: Long): List<String>

    @Query("SELECT path FROM plan_photo WHERE planItemId IN (SELECT id FROM plan_item WHERE tripId = :tripId AND pending = 0)")
    suspend fun pathsForOfficial(tripId: Long): List<String>

    @Insert suspend fun insert(photo: PlanPhoto): Long

    @Query("DELETE FROM plan_photo WHERE id = :id")
    suspend fun delete(id: Long)

    @Query("UPDATE plan_photo SET planItemId = :to WHERE planItemId = :from")
    suspend fun move(from: Long, to: Long)
}
