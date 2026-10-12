package com.archiekuo.travelledger.backup

import androidx.room.withTransaction
import com.archiekuo.travelledger.data.AppDatabase
import com.archiekuo.travelledger.data.Category
import com.archiekuo.travelledger.data.DayNote
import com.archiekuo.travelledger.data.Expense
import com.archiekuo.travelledger.data.Member
import com.archiekuo.travelledger.data.PaymentMethod
import com.archiekuo.travelledger.data.Photo
import com.archiekuo.travelledger.data.PhotoType
import com.archiekuo.travelledger.data.PlanItem
import com.archiekuo.travelledger.data.PlanPhoto
import com.archiekuo.travelledger.data.Trip
import com.archiekuo.travelledger.data.TripCurrencyRate
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.OutputStream
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

/**
 * One zip file for both jobs:
 *  - a full backup (kind "backup") that restores every trip on a new phone, and
 *  - one trip shared with companions (kind "trip"), imported on their phone as a read-only copy.
 *
 * Layout: manifest.json (what it is), data.json (trips and the category/payment names they use),
 * files/… (photos and covers, only when asked for). Rows refer to each other by position, never by
 * database id, so the file can be imported into any database.
 */
object TripArchive {
    const val FORMAT = "travelledger"
    const val VERSION = 1
    const val KIND_TRIP = "trip"
    const val KIND_BACKUP = "backup"
    /** A companion's suggestions for a shared trip, sent back to its organizer. */
    const val KIND_ADDITIONS = "additions"
    /** Plans made on the desktop planner (卡溜趴行程桌), merged into the phone's own trip. */
    const val KIND_PLANS = "plans"

    data class TripInfo(val uuid: String, val name: String, val startDate: Long, val endDate: Long, val expenseCount: Int, val totalHome: Double)

    /** What the file holds, read before asking the user to confirm. */
    data class Summary(
        val kind: String,
        val sharedBy: String?,
        val exportedAt: Long,
        val trips: List<TripInfo>,
        val photoCount: Int,
    )

    sealed interface Result {
        /** [tripIds] are the local ids of the trips written (in file order). */
        data class Imported(val kind: String, val tripIds: List<Long>, val updated: Int) : Result
        data class Failed(val message: String) : Result
    }

    class BadArchive(message: String) : Exception(message)

    // ───────────────────────────── export ─────────────────────────────

    /**
     * Writes [tripIds] to [out]. For a shared trip, [sharedBy] is the sender's name shown on the
     * companion's copy; a trip that was itself shared with us keeps its original sender.
     */
    suspend fun export(
        db: AppDatabase,
        out: OutputStream,
        kind: String,
        tripIds: List<Long>,
        includePhotos: Boolean,
        sharedBy: String? = null,
        appVersion: String = "",
        now: Long = System.currentTimeMillis(),
    ): Int = withContext(Dispatchers.IO) {
        val categories = db.lookupDao().getCategories()
        val methods = db.lookupDao().getPaymentMethods()
        val files = mutableListOf<Pair<String, File>>()
        // Plan pictures (screenshots) always travel; expense photos and covers only when asked for.
        fun attach(path: String?, folder: String, always: Boolean = false): String? {
            if ((!includePhotos && !always) || path == null) return null
            val f = File(path)
            if (!f.isFile) return null
            val name = "files/$folder/${files.size}-${f.name}"
            files += name to f
            return name
        }

        val trips = JSONArray()
        for (id in tripIds) {
            val trip = db.tripDao().getTrip(id) ?: continue
            val members = db.tripDao().getMembers(id)
            val memberIndex = members.withIndex().associate { (i, m) -> m.id to i }
            // A share carries only the organizer's book; a backup also keeps my own unsent additions.
            val plans = db.planDao().forTrip(id).filter { kind != KIND_TRIP || !it.pending }
            val planIndex = plans.withIndex().associate { (i, p) -> p.id to i }
            val expenses = db.expenseDao().forTrip(id).filter { kind != KIND_TRIP || !it.pending }
            trips.put(JSONObject().apply {
                put("uuid", trip.uuid.ifBlank { UUID.randomUUID().toString() })
                put("name", trip.name)
                put("startDate", trip.startDate)
                put("endDate", trip.endDate)
                put("homeCurrency", trip.homeCurrency)
                putOpt("budget", trip.budget)
                put("splitEnabled", trip.splitEnabled)
                put("createdAt", trip.createdAt)
                putOpt("coverTheme", trip.coverTheme)
                putOpt("navApp", trip.navApp)
                putOpt("cover", attach(trip.coverPath, "covers"))
                // A backup remembers which trips were someone else's; a share names the sender.
                putOpt("sharedBy", if (kind == KIND_TRIP) trip.sharedBy ?: sharedBy else trip.sharedBy)
                putOpt("sharedAt", if (kind == KIND_TRIP) trip.sharedAt.takeIf { trip.sharedBy != null } ?: now else trip.sharedAt)
                put("members", JSONArray(members.map { it.name }))
                put("rates", JSONArray(db.tripDao().getRates(id).map { r ->
                    JSONObject().put("currency", r.currency).put("rate", r.rate).put("updatedAt", r.updatedAt).put("source", r.source)
                }))
                put("plans", JSONArray(plans.map { p -> planJson(db, p, categories, ::attach) }))
                put("dayNotes", JSONArray(db.dayNoteDao().forTrip(id).map { n -> JSONObject().put("day", n.day).put("text", n.text).put("updatedAt", n.updatedAt) }))
                put("expenses", JSONArray(expenses.map { e ->
                    expenseJson(db, e, categories, methods, plans, ::attach).apply {
                        putOpt("payer", e.payerId?.let { memberIndex[it] })
                        putOpt("plan", e.planItemId?.let { planIndex[it] })
                    }
                }))
            })
        }

        val data = JSONObject().apply {
            put("categories", JSONArray(categories.map { c ->
                JSONObject().put("name", c.name).put("sortOrder", c.sortOrder).put("icon", c.icon).put("color", c.color)
            }))
            put("payments", JSONArray(methods.map { m -> JSONObject().put("name", m.name).put("sortOrder", m.sortOrder) }))
            put("trips", trips)
        }
        val manifest = JSONObject().apply {
            put("format", FORMAT)
            put("version", VERSION)
            put("kind", kind)
            put("exportedAt", now)
            putOpt("sharedBy", if (kind == KIND_TRIP) sharedBy else null)
            put("appVersion", appVersion)
            put("photoCount", files.size)
            put("trips", JSONArray((0 until trips.length()).map { i ->
                val t = trips.getJSONObject(i)
                val ex = t.getJSONArray("expenses")
                JSONObject().put("uuid", t.getString("uuid")).put("name", t.getString("name"))
                    .put("startDate", t.getLong("startDate")).put("endDate", t.getLong("endDate"))
                    .put("expenseCount", ex.length())
                    .put("totalHome", (0 until ex.length()).sumOf { ex.getJSONObject(it).getDouble("homeAmount") })
            }))
        }

        writeZip(out, manifest, data, files)
        trips.length()
    }

    private fun writeZip(out: OutputStream, manifest: JSONObject, data: JSONObject, files: List<Pair<String, File>>) {
        ZipOutputStream(out.buffered()).use { zip ->
            zip.putNextEntry(ZipEntry("manifest.json")); zip.write(manifest.toString(1).toByteArray()); zip.closeEntry()
            zip.putNextEntry(ZipEntry("data.json")); zip.write(data.toString().toByteArray()); zip.closeEntry()
            for ((name, file) in files) {
                zip.putNextEntry(ZipEntry(name))
                file.inputStream().use { it.copyTo(zip) }
                zip.closeEntry()
            }
        }
    }

    /** Copies one photo or cover out of the zip into app storage; null if it is missing or suspicious. */
    private fun copyEntry(zip: ZipFile, name: String, filesDir: File): String? {
        val entry = zip.getEntry(name) ?: return null
        if (entry.isDirectory || name.contains("..")) return null
        val folder = when {
            name.startsWith("files/covers/") -> "covers"
            name.startsWith("files/receipts/") -> "photos/receipts"
            name.startsWith("files/plans/") -> "photos/plans"
            else -> "photos/memories"
        }
        val dir = File(filesDir, folder).apply { mkdirs() }
        val dst = File(dir, "${UUID.randomUUID()}.jpg")
        zip.getInputStream(entry).use { input -> dst.outputStream().use { input.copyTo(it) } }
        return dst.absolutePath
    }

    private suspend fun planJson(
        db: AppDatabase, p: PlanItem, categories: List<Category>, attach: (String?, String, Boolean) -> String?,
    ) = JSONObject().apply {
        put("photos", JSONArray(db.planPhotoDao().forPlan(p.id).mapNotNull { ph ->
            attach(ph.path, "plans", true)?.let { name -> JSONObject().put("file", name).put("width", ph.width).put("height", ph.height).put("createdAt", ph.createdAt) }
        }))
        put("uuid", p.uuid)
        put("title", p.title)
        putOpt("category", categories.firstOrNull { it.id == p.categoryId }?.name)
        putOpt("date", p.date)
        putOpt("minuteOfDay", p.minuteOfDay)
        put("status", p.status)
        put("reservation", p.reservation)
        put("reservationNote", p.reservationNote)
        put("location", p.location)
        putOpt("estCost", p.estCost)
        put("note", p.note)
        put("createdAt", p.createdAt)
        putOpt("addedBy", p.addedBy)
        if (p.pending) put("pending", true)
    }

    private suspend fun expenseJson(
        db: AppDatabase, e: Expense, categories: List<Category>, methods: List<PaymentMethod>, plans: List<PlanItem>,
        attach: (String?, String) -> String?,
    ) = JSONObject().apply {
        put("uuid", e.uuid)
        put("date", e.date)
        putOpt("minuteOfDay", e.minuteOfDay)
        put("title", e.title)
        put("amount", e.amount)
        put("currency", e.currency)
        put("rate", e.rate)
        put("homeAmount", e.homeAmount)
        putOpt("category", categories.firstOrNull { it.id == e.categoryId }?.name)
        putOpt("payment", methods.firstOrNull { it.id == e.paymentMethodId }?.name)
        put("note", e.note)
        put("ocrText", e.ocrText)
        put("createdAt", e.createdAt)
        putOpt("planUuid", plans.firstOrNull { it.id == e.planItemId }?.uuid)
        putOpt("addedBy", e.addedBy)
        if (e.pending) put("pending", true)
        put("photos", JSONArray(db.photoDao().forExpense(e.id).mapNotNull { ph ->
            attach(ph.path, if (ph.type == PhotoType.RECEIPT) "receipts" else "memories")?.let { name ->
                JSONObject().put("file", name).put("type", ph.type).put("width", ph.width).put("height", ph.height).put("createdAt", ph.createdAt)
            }
        }))
    }

    // ───────────────────────────── read ─────────────────────────────

    private fun readJson(zip: ZipFile, name: String): JSONObject {
        val entry = zip.getEntry(name) ?: throw BadArchive("這不是卡溜趴的檔案")
        return JSONObject(zip.getInputStream(entry).use { it.readBytes().decodeToString() })
    }

    private fun openManifest(zip: ZipFile): JSONObject {
        val m = readJson(zip, "manifest.json")
        if (m.optString("format") != FORMAT) throw BadArchive("這不是卡溜趴的檔案")
        if (m.optInt("version") > VERSION) throw BadArchive("這個檔案來自較新版的卡溜趴,請先更新 App")
        return m
    }

    /** Reads only the manifest, for the confirmation dialog. */
    fun readSummary(file: File): Summary = try {
        ZipFile(file).use { zip ->
            val m = openManifest(zip)
            val trips = m.optJSONArray("trips") ?: JSONArray()
            Summary(
                kind = m.optString("kind", KIND_BACKUP),
                sharedBy = m.optStringOrNull("sharedBy"),
                exportedAt = m.optLong("exportedAt"),
                trips = (0 until trips.length()).map { i ->
                    val t = trips.getJSONObject(i)
                    TripInfo(t.getString("uuid"), t.getString("name"), t.getLong("startDate"), t.getLong("endDate"), t.optInt("expenseCount"), t.optDouble("totalHome", 0.0))
                },
                photoCount = m.optInt("photoCount"),
            )
        }
    } catch (e: BadArchive) {
        throw e
    } catch (e: Exception) {
        throw BadArchive("這不是卡溜趴的檔案")
    }

    // ───────────────────────────── import ─────────────────────────────

    /**
     * Imports [file] into [db], copying photos under [filesDir].
     *  - A shared trip becomes a read-only copy; sharing it again replaces that copy (matched by uuid).
     *    Our own trip coming back to us is refused rather than overwritten.
     *  - A backup restores every trip: one already on the phone (same uuid) is replaced, others are added.
     * Category and payment names missing on this phone are added.
     */
    suspend fun import(db: AppDatabase, file: File, filesDir: File): Result = withContext(Dispatchers.IO) {
        try {
            ZipFile(file).use { zip -> importZip(db, zip, filesDir) }
        } catch (e: BadArchive) {
            Result.Failed(e.message ?: "無法讀取檔案")
        } catch (e: Exception) {
            Result.Failed("檔案損壞,無法匯入")
        }
    }

    private suspend fun importZip(db: AppDatabase, zip: ZipFile, filesDir: File): Result {
        val manifest = openManifest(zip)
        val kind = manifest.optString("kind", KIND_BACKUP)
        if (kind == KIND_ADDITIONS) throw BadArchive("這是同伴的補充檔,請用審核畫面加入")
        if (kind == KIND_PLANS) throw BadArchive("這是電腦行程檔,請用併入行程畫面")
        val data = readJson(zip, "data.json")
        val trips = data.getJSONArray("trips")

        if (kind == KIND_TRIP) {
            for (i in 0 until trips.length()) {
                val existing = db.tripDao().findByUuid(trips.getJSONObject(i).getString("uuid"))
                if (existing != null && !existing.readOnly) {
                    return Result.Failed("「${existing.name}」是你自己記的旅程,不需要匯入")
                }
            }
        }

        // Copy files first (outside the transaction); remember them so a failure leaves nothing behind.
        val copied = mutableMapOf<String, String>()
        fun fileFor(name: String?): String? {
            if (name == null) return null
            copied[name]?.let { return it }
            return copyEntry(zip, name, filesDir)?.also { copied[name] = it }
        }

        val oldFiles = mutableListOf<String>()
        val ids = mutableListOf<Long>()
        var updated = 0
        try {
            // Resolve all files up front so the transaction only touches the database.
            for (i in 0 until trips.length()) {
                val t = trips.getJSONObject(i)
                fileFor(t.optStringOrNull("cover"))
                val ex = t.getJSONArray("expenses")
                for (j in 0 until ex.length()) {
                    val photos = ex.getJSONObject(j).optJSONArray("photos") ?: continue
                    for (k in 0 until photos.length()) fileFor(photos.getJSONObject(k).getString("file"))
                }
                val pl = t.getJSONArray("plans")
                for (j in 0 until pl.length()) {
                    val photos = pl.getJSONObject(j).optJSONArray("photos") ?: continue
                    for (k in 0 until photos.length()) fileFor(photos.getJSONObject(k).getString("file"))
                }
            }

            db.withTransaction {
                val categoryIds = mergeCategories(db, data.optJSONArray("categories"))
                val paymentIds = mergePayments(db, data.optJSONArray("payments"))
                val fallbackSharedBy = manifest.optStringOrNull("sharedBy")?.ifBlank { null } ?: "同伴"
                for (i in 0 until trips.length()) {
                    val t = trips.getJSONObject(i)
                    val uuid = t.getString("uuid")
                    val existing = db.tripDao().findByUuid(uuid)
                    val sharedBy = if (kind == KIND_TRIP) t.optStringOrNull("sharedBy") ?: fallbackSharedBy else t.optStringOrNull("sharedBy")
                    val trip = Trip(
                        id = existing?.id ?: 0,
                        name = t.getString("name"),
                        startDate = t.getLong("startDate"),
                        endDate = t.getLong("endDate"),
                        homeCurrency = t.optString("homeCurrency", "TWD"),
                        budget = t.optDoubleOrNull("budget"),
                        splitEnabled = t.optBoolean("splitEnabled"),
                        createdAt = t.optLong("createdAt", System.currentTimeMillis()),
                        coverPath = copied[t.optStringOrNull("cover")],
                        coverTheme = t.optStringOrNull("coverTheme"),
                        navApp = t.optStringOrNull("navApp"),
                        uuid = uuid,
                        sharedBy = sharedBy,
                        sharedAt = if (sharedBy != null) t.optLongOrNull("sharedAt") ?: manifest.optLong("exportedAt") else null,
                    )
                    // My unsent additions on a shared copy survive an update: remember which plan each one belongs to.
                    var myLinks = emptyMap<Long, String?>()
                    val tripId = if (existing != null) {
                        existing.coverPath?.let(oldFiles::add)
                        if (kind == KIND_TRIP) {
                            oldFiles += db.photoDao().pathsForOfficial(existing.id)
                            oldFiles += db.planPhotoDao().pathsForOfficial(existing.id)
                            val planUuids = db.planDao().forTrip(existing.id).associate { it.id to it.uuid }
                            myLinks = db.expenseDao().forTrip(existing.id).filter { it.pending && it.planItemId != null }
                                .associate { it.id to planUuids[it.planItemId] }
                            db.tripDao().clearContents(existing.id)
                        } else {
                            oldFiles += db.photoDao().pathsForTrip(existing.id)
                            oldFiles += db.planPhotoDao().pathsForTrip(existing.id)
                            db.tripDao().clearAll(existing.id)
                        }
                        db.tripDao().updateTrip(trip)
                        updated++
                        existing.id
                    } else {
                        db.tripDao().insertTrip(trip)
                    }
                    ids += tripId
                    writeContents(db, tripId, t, categoryIds, paymentIds, copied, keepPending = kind != KIND_TRIP)
                    if (existing != null && kind == KIND_TRIP) oldFiles += settleMyAdditions(db, tripId, t, myLinks)
                }
            }
        } catch (e: Exception) {
            copied.values.forEach { File(it).delete() }
            throw e
        }
        oldFiles.forEach { File(it).delete() }
        return Result.Imported(kind, ids, updated)
    }

    private suspend fun mergeCategories(db: AppDatabase, list: JSONArray?): Map<String, Long> {
        val dao = db.lookupDao()
        val have = dao.getCategories().associateBy { it.name }.toMutableMap()
        var next = (have.values.maxOfOrNull { it.sortOrder } ?: -1) + 1
        if (list != null) for (i in 0 until list.length()) {
            val c = list.getJSONObject(i)
            val name = c.getString("name")
            if (name !in have) {
                val id = dao.insertCategory(Category(name = name, sortOrder = next++, icon = c.optString("icon"), color = c.optInt("color", -1)))
                have[name] = Category(id = id, name = name)
            }
        }
        return have.mapValues { it.value.id }
    }

    private suspend fun mergePayments(db: AppDatabase, list: JSONArray?): Map<String, Long> {
        val dao = db.lookupDao()
        val have = dao.getPaymentMethods().associateBy { it.name }.toMutableMap()
        var next = (have.values.maxOfOrNull { it.sortOrder } ?: -1) + 1
        if (list != null) for (i in 0 until list.length()) {
            val name = list.getJSONObject(i).getString("name")
            if (name !in have) {
                val id = dao.insertPaymentMethod(PaymentMethod(name = name, sortOrder = next++))
                have[name] = PaymentMethod(id = id, name = name)
            }
        }
        return have.mapValues { it.value.id }
    }

    private suspend fun writeContents(
        db: AppDatabase, tripId: Long, t: JSONObject,
        categoryIds: Map<String, Long>, paymentIds: Map<String, Long>, copied: Map<String, String>,
        keepPending: Boolean,
        /** Adding to a trip that already has plan items: expenses may point at those too. */
        existingPlans: Boolean = false,
    ) {
        val earlierPlans = if (existingPlans) db.planDao().forTrip(tripId).associate { it.uuid to it.id } else emptyMap()
        t.optJSONArray("dayNotes")?.let { a ->
            for (i in 0 until a.length()) {
                val n = a.getJSONObject(i)
                db.dayNoteDao().put(DayNote(tripId, n.getLong("day"), n.getString("text"), n.optLong("updatedAt")))
            }
        }
        val names = t.getJSONArray("members").let { a -> (0 until a.length()).map { a.getString(it) } }
        val memberIds = names.map { db.tripDao().insertMember(Member(tripId = tripId, name = it)) }
        val rates = t.getJSONArray("rates")
        for (i in 0 until rates.length()) {
            val r = rates.getJSONObject(i)
            db.tripDao().upsertRate(TripCurrencyRate(tripId, r.getString("currency"), r.getDouble("rate"), r.optLong("updatedAt"), r.optString("source", "manual")))
        }
        val plans = t.getJSONArray("plans")
        val planIds = (0 until plans.length()).map { i ->
            val p = plans.getJSONObject(i)
            val planId = db.planDao().insert(
                PlanItem(
                    tripId = tripId,
                    title = p.getString("title"),
                    categoryId = p.optStringOrNull("category")?.let(categoryIds::get),
                    date = p.optLongOrNull("date"),
                    minuteOfDay = p.optLongOrNull("minuteOfDay")?.toInt(),
                    status = p.optString("status", "TODO"),
                    reservation = p.optString("reservation", "NONE"),
                    reservationNote = p.optString("reservationNote"),
                    location = p.optString("location"),
                    estCost = p.optDoubleOrNull("estCost"),
                    note = p.optString("note"),
                    createdAt = p.optLong("createdAt"),
                    uuid = p.optString("uuid").ifBlank { UUID.randomUUID().toString() },
                    addedBy = p.optStringOrNull("addedBy"),
                    pending = keepPending && p.optBoolean("pending"),
                )
            )
            p.optJSONArray("photos")?.let { photos ->
                for (k in 0 until photos.length()) {
                    val ph = photos.getJSONObject(k)
                    val path = copied[ph.getString("file")] ?: continue
                    db.planPhotoDao().insert(PlanPhoto(planItemId = planId, path = path, width = ph.optInt("width"), height = ph.optInt("height"), createdAt = ph.optLong("createdAt")))
                }
            }
            planId
        }
        val planByUuid = earlierPlans + (0 until plans.length()).associate { i -> plans.getJSONObject(i).optString("uuid") to planIds[i] }
        val expenses = t.getJSONArray("expenses")
        for (i in 0 until expenses.length()) {
            val e = expenses.getJSONObject(i)
            val id = db.expenseDao().insert(
                Expense(
                    tripId = tripId,
                    date = e.getLong("date"),
                    amount = e.getDouble("amount"),
                    currency = e.getString("currency"),
                    rate = e.getDouble("rate"),
                    homeAmount = e.getDouble("homeAmount"),
                    categoryId = e.optStringOrNull("category")?.let(categoryIds::get),
                    paymentMethodId = e.optStringOrNull("payment")?.let(paymentIds::get),
                    payerId = e.optLongOrNull("payer")?.toInt()?.let(memberIds::getOrNull),
                    note = e.optString("note"),
                    createdAt = e.optLong("createdAt"),
                    title = e.optString("title"),
                    minuteOfDay = e.optLongOrNull("minuteOfDay")?.toInt(),
                    ocrText = e.optString("ocrText"),
                    planItemId = e.optStringOrNull("planUuid")?.let(planByUuid::get)
                        ?: e.optLongOrNull("plan")?.toInt()?.let(planIds::getOrNull),
                    uuid = e.optString("uuid").ifBlank { UUID.randomUUID().toString() },
                    addedBy = e.optStringOrNull("addedBy"),
                    pending = keepPending && e.optBoolean("pending"),
                )
            )
            val photos = e.optJSONArray("photos") ?: continue
            for (k in 0 until photos.length()) {
                val ph = photos.getJSONObject(k)
                val path = copied[ph.getString("file")] ?: continue
                db.photoDao().insert(
                    Photo(
                        expenseId = id, type = ph.optString("type", PhotoType.MEMORY), path = path,
                        width = ph.optInt("width"), height = ph.optInt("height"), createdAt = ph.optLong("createdAt"),
                    )
                )
            }
        }
    }

    /**
     * After a shared copy is refilled: my additions the organizer has taken in now arrive as official rows,
     * so my own copies go; the rest stay and are re-linked to their plan item by identity. Returns photo files to delete.
     */
    private suspend fun settleMyAdditions(db: AppDatabase, tripId: Long, t: JSONObject, myLinks: Map<Long, String?>): List<String> {
        fun uuidsOf(key: String) = t.getJSONArray(key).let { a -> (0 until a.length()).map { a.getJSONObject(it).optString("uuid") }.toSet() }
        val officialExpenses = uuidsOf("expenses")
        val officialPlans = uuidsOf("plans")
        val gone = mutableListOf<String>()
        for (e in db.expenseDao().forTrip(tripId).filter { it.pending && it.uuid in officialExpenses }) {
            gone += db.photoDao().forExpense(e.id).map { it.path }
            db.expenseDao().delete(e.id)
        }
        for (p in db.planDao().forTrip(tripId).filter { it.pending && it.uuid in officialPlans }) {
            gone += db.planPhotoDao().forPlan(p.id).map { it.path }
            db.planDao().deleteRow(p.id)
        }
        val planIds = db.planDao().forTrip(tripId).filter { !it.pending || it.uuid !in officialPlans }.associate { it.uuid to it.id }
        for ((expenseId, planUuid) in myLinks) {
            if (db.expenseDao().get(expenseId) != null) db.expenseDao().setPlan(expenseId, planUuid?.let(planIds::get))
        }
        return gone
    }

    /**
     * Names of trips in a backup whose copy on this phone has records the backup lacks:
     * something recorded after the backup was made, or more items than the backup holds.
     */
    suspend fun newerOnPhone(db: AppDatabase, summary: Summary): List<String> = summary.trips.mapNotNull { t ->
        val local = db.tripDao().findByUuid(t.uuid) ?: return@mapNotNull null
        val expenses = db.expenseDao().forTrip(local.id)
        val latest = (expenses.map { it.createdAt } + db.planDao().forTrip(local.id).map { it.createdAt }).maxOrNull() ?: 0
        local.name.takeIf { latest > summary.exportedAt || expenses.size > t.expenseCount }
    }

    // ───────────────────────────── additions ─────────────────────────────

    /** One suggested item, as shown to the organizer for review. */
    data class AdditionItem(val uuid: String, val isExpense: Boolean, val title: String, val detail: String)

    data class Additions(val tripUuid: String, val tripName: String, val from: String, val items: List<AdditionItem>)

    /** How many of my additions on [tripId] are waiting to be sent. */
    suspend fun pendingCount(db: AppDatabase, tripId: Long): Int =
        db.expenseDao().forTrip(tripId).count { it.pending } + db.planDao().forTrip(tripId).count { it.pending }

    /** A companion's additions to a shared trip, for its organizer: kind "additions". */
    suspend fun exportAdditions(
        db: AppDatabase, out: OutputStream, tripId: Long, from: String, includePhotos: Boolean,
        appVersion: String = "", now: Long = System.currentTimeMillis(),
    ): Int = withContext(Dispatchers.IO) {
        val trip = db.tripDao().getTrip(tripId) ?: return@withContext 0
        val categories = db.lookupDao().getCategories()
        val methods = db.lookupDao().getPaymentMethods()
        val allPlans = db.planDao().forTrip(tripId)
        val plans = allPlans.filter { it.pending }
        val expenses = db.expenseDao().forTrip(tripId).filter { it.pending }
        val files = mutableListOf<Pair<String, File>>()
        // Plan pictures (screenshots) always travel; expense photos and covers only when asked for.
        fun attach(path: String?, folder: String, always: Boolean = false): String? {
            if ((!includePhotos && !always) || path == null) return null
            val f = File(path)
            if (!f.isFile) return null
            return "files/$folder/${files.size}-${f.name}".also { files += it to f }
        }
        val data = JSONObject().apply {
            put("tripUuid", trip.uuid)
            put("categories", JSONArray(categories.map { c ->
                JSONObject().put("name", c.name).put("sortOrder", c.sortOrder).put("icon", c.icon).put("color", c.color)
            }))
            put("payments", JSONArray(methods.map { m -> JSONObject().put("name", m.name).put("sortOrder", m.sortOrder) }))
            put("plans", JSONArray(plans.map { planJson(db, it, categories, ::attach).apply { put("addedBy", from); remove("pending") } }))
            put("expenses", JSONArray(expenses.map { expenseJson(db, it, categories, methods, allPlans, ::attach).apply { put("addedBy", from); remove("pending") } }))
        }
        val manifest = JSONObject().apply {
            put("format", FORMAT)
            put("version", VERSION)
            put("kind", KIND_ADDITIONS)
            put("exportedAt", now)
            put("sharedBy", from)
            put("appVersion", appVersion)
            put("photoCount", files.size)
            put("trips", JSONArray().put(
                JSONObject().put("uuid", trip.uuid).put("name", trip.name).put("startDate", trip.startDate).put("endDate", trip.endDate)
                    .put("expenseCount", expenses.size).put("totalHome", expenses.sumOf { it.homeAmount }),
            ))
        }
        writeZip(out, manifest, data, files)
        plans.size + expenses.size
    }

    /** The items in an additions file, for the review list. */
    fun readAdditions(file: File): Additions = try {
        ZipFile(file).use { zip ->
            val m = openManifest(zip)
            if (m.optString("kind") != KIND_ADDITIONS) throw BadArchive("這不是補充檔")
            val data = readJson(zip, "data.json")
            val trip = m.getJSONArray("trips").getJSONObject(0)
            val items = listItems(data.getJSONArray("plans"), data.getJSONArray("expenses")) { true }
            Additions(data.getString("tripUuid"), trip.getString("name"), m.optString("sharedBy", "同伴"), items)
        }
    } catch (e: BadArchive) {
        throw e
    } catch (e: Exception) {
        throw BadArchive("檔案損壞,無法讀取")
    }

    /** Review rows for plan items and expenses (in that order) whose uuid passes [keep]. */
    private fun listItems(plans: JSONArray, expenses: JSONArray, keep: (String) -> Boolean): List<AdditionItem> {
        val items = mutableListOf<AdditionItem>()
        for (i in 0 until plans.length()) {
            val p = plans.getJSONObject(i)
            if (!keep(p.getString("uuid"))) continue
            val day = p.optLongOrNull("date")?.let { d -> java.time.LocalDate.ofEpochDay(d).let { "${it.monthValue}/${it.dayOfMonth}" } } ?: "待排"
            items += AdditionItem(p.getString("uuid"), false, p.getString("title"), "行程 · $day" + (p.optStringOrNull("category")?.let { " · $it" } ?: ""))
        }
        for (i in 0 until expenses.length()) {
            val e = expenses.getJSONObject(i)
            if (!keep(e.getString("uuid"))) continue
            val day = java.time.LocalDate.ofEpochDay(e.getLong("date")).let { "${it.monthValue}/${it.dayOfMonth}" }
            val amount = java.text.NumberFormat.getNumberInstance().apply { maximumFractionDigits = 2 }.format(e.getDouble("amount"))
            items += AdditionItem(
                e.getString("uuid"), true, e.optString("title").ifBlank { e.optString("category", "支出") },
                "$day · ${e.getString("currency")} $amount" + (e.optStringOrNull("category")?.let { " · $it" } ?: ""),
            )
        }
        return items
    }

    // ───────────────────────────── my own trip, sent back by someone else ─────────────────────────────

    /** The trip in a shared file that is one of my own trips here (not a copy someone shared with me), if any. */
    private suspend fun ownTripIn(db: AppDatabase, data: JSONObject): Pair<Trip, JSONObject>? {
        val trips = data.getJSONArray("trips")
        for (i in 0 until trips.length()) {
            val t = trips.getJSONObject(i)
            val local = db.tripDao().findByUuid(t.getString("uuid")) ?: continue
            if (!local.readOnly) return local to t
        }
        return null
    }

    /**
     * Someone sent me a trip file of a trip that is mine here (they shared their copy instead of sending additions,
     * or their copy was made from my computer file). Lists what their copy has that mine doesn't, to take in like
     * additions; null when the file is not that.
     */
    suspend fun readNewItems(db: AppDatabase, file: File): Additions? = withContext(Dispatchers.IO) {
        try {
            ZipFile(file).use { zip ->
                val m = openManifest(zip)
                if (m.optString("kind") != KIND_TRIP) return@withContext null
                val data = readJson(zip, "data.json")
                val (local, t) = ownTripIn(db, data) ?: return@withContext null
                val havePlans = db.planDao().uuids(local.id).toSet()
                val haveExpenses = db.expenseDao().uuids(local.id).toSet()
                val items = listItems(t.getJSONArray("plans"), t.getJSONArray("expenses")) { it !in havePlans && it !in haveExpenses }
                Additions(local.uuid, local.name, t.optStringOrNull("sharedBy") ?: m.optStringOrNull("sharedBy") ?: "同伴", items)
            }
        } catch (e: BadArchive) {
            null
        } catch (e: Exception) {
            null
        }
    }

    /** Takes in the [accepted] new items from someone's copy of my own trip (see [readNewItems]); mine are left as they are. */
    suspend fun importNewItems(db: AppDatabase, file: File, filesDir: File, accepted: Set<String>): Result = withContext(Dispatchers.IO) {
        try {
            ZipFile(file).use { zip ->
                val m = openManifest(zip)
                val data = readJson(zip, "data.json")
                val (local, t) = ownTripIn(db, data) ?: throw BadArchive("手機上沒有這趟旅程")
                val from = t.optStringOrNull("sharedBy") ?: m.optStringOrNull("sharedBy") ?: "同伴"
                fun pick(key: String) = t.getJSONArray(key).let { a -> (0 until a.length()).map { a.getJSONObject(it) } }
                    .filter { it.getString("uuid") in accepted }
                    .onEach { o ->
                        // Their members and plan positions mean nothing here; who added it does.
                        o.remove("payer"); o.remove("plan"); o.remove("pending")
                        o.put("addedBy", o.optStringOrNull("addedBy") ?: from)
                    }
                addItems(db, zip, local, data, pick("plans"), pick("expenses"), filesDir, KIND_ADDITIONS) // reported like additions
            }
        } catch (e: BadArchive) {
            Result.Failed(e.message ?: "無法讀取檔案")
        } catch (e: Exception) {
            Result.Failed("檔案損壞,無法匯入")
        }
    }

    /**
     * The organizer takes in the [accepted] items (by uuid) from a companion's additions file.
     * Items already in the trip (the same file opened twice) are skipped.
     */
    suspend fun importAdditions(db: AppDatabase, file: File, filesDir: File, accepted: Set<String>): Result = withContext(Dispatchers.IO) {
        try {
            ZipFile(file).use { zip ->
                val m = openManifest(zip)
                if (m.optString("kind") != KIND_ADDITIONS) throw BadArchive("這不是補充檔")
                val data = readJson(zip, "data.json")
                val trip = db.tripDao().findByUuid(data.getString("tripUuid"))
                    ?: throw BadArchive("手機上沒有「${m.getJSONArray("trips").getJSONObject(0).getString("name")}」這趟旅程")
                if (trip.readOnly) throw BadArchive("這是給記帳人(${trip.sharedBy})的補充,請轉傳給他")
                val from = m.optString("sharedBy", "同伴")
                fun pick(key: String) = data.getJSONArray(key).let { a -> (0 until a.length()).map { a.getJSONObject(it) } }
                    .filter { it.getString("uuid") in accepted }
                    .onEach { it.put("addedBy", it.optStringOrNull("addedBy") ?: from).remove("pending") }
                addItems(db, zip, trip, data, pick("plans"), pick("expenses"), filesDir, KIND_ADDITIONS)
            }
        } catch (e: BadArchive) {
            Result.Failed(e.message ?: "無法讀取檔案")
        } catch (e: Exception) {
            Result.Failed("檔案損壞,無法匯入")
        }
    }

    /**
     * Adds [plans] and [expenses] (file JSON) to [trip], skipping any it already has (the same file opened twice), with
     * their pictures. Expenses may link to plan items already in the trip. [data] gives the category and payment names.
     */
    private suspend fun addItems(
        db: AppDatabase, zip: ZipFile, trip: Trip, data: JSONObject, plans: List<JSONObject>, expenses: List<JSONObject>,
        filesDir: File, kind: String,
    ): Result {
        val havePlans = db.planDao().uuids(trip.id).toSet()
        val haveExpenses = db.expenseDao().uuids(trip.id).toSet()
        val newPlans = plans.filter { it.getString("uuid") !in havePlans }
        val newExpenses = expenses.filter { it.getString("uuid") !in haveExpenses }
        val copied = mutableMapOf<String, String>()
        for (o in newPlans + newExpenses) {
            val photos = o.optJSONArray("photos") ?: continue
            for (k in 0 until photos.length()) {
                val name = photos.getJSONObject(k).getString("file")
                copyEntry(zip, name, filesDir)?.let { copied[name] = it }
            }
        }
        try {
            db.withTransaction {
                val categoryIds = mergeCategories(db, data.optJSONArray("categories"))
                val paymentIds = mergePayments(db, data.optJSONArray("payments"))
                val t = JSONObject().put("members", JSONArray()).put("rates", JSONArray())
                    .put("plans", JSONArray(newPlans)).put("expenses", JSONArray(newExpenses))
                writeContents(db, trip.id, t, categoryIds, paymentIds, copied, keepPending = false, existingPlans = true)
            }
        } catch (e: Exception) {
            copied.values.forEach { File(it).delete() }
            throw e
        }
        return Result.Imported(kind, listOf(trip.id), newPlans.size + newExpenses.size)
    }

    // ───────────────────────────── plans from the desktop planner ─────────────────────────────

    /** What merging a desktop plans file will do, for the confirmation dialog. */
    data class PlansPreview(
        val tripName: String, val newTrip: Boolean, val added: Int, val updated: Int, val deleted: Int,
        /** Set when the file cannot go into this phone (someone else's shared trip). */
        val refused: String? = null,
    )

    private fun plansOf(data: JSONObject) = data.getJSONArray("plans").let { a -> (0 until a.length()).map { a.getJSONObject(it) } }
    private fun deletedOf(data: JSONObject) = data.optJSONArray("deleted")?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList()

    suspend fun previewPlans(db: AppDatabase, file: File): PlansPreview = withContext(Dispatchers.IO) {
        ZipFile(file).use { zip ->
            openManifest(zip)
            val data = readJson(zip, "data.json")
            val t = data.getJSONObject("trip")
            val trip = db.tripDao().findByUuid(t.getString("uuid"))
            if (trip?.readOnly == true) {
                return@withContext PlansPreview(trip.name, false, 0, 0, 0, "「${trip.name}」是${trip.sharedBy}記帳的旅程,請把這個檔案傳給${trip.sharedBy}")
            }
            val have = trip?.let { db.planDao().uuids(it.id).toSet() } ?: emptySet()
            val incoming = plansOf(data).map { it.getString("uuid") }
            PlansPreview(
                trip?.name ?: t.getString("name"), trip == null,
                added = incoming.count { it !in have }, updated = incoming.count { it in have },
                deleted = deletedOf(data).count { it in have },
            )
        }
    }

    /**
     * Merges a desktop plans file into this phone: the trip is matched by identity (and created if the phone does
     * not have it yet); each plan item is updated or added by its identity, items deleted on the desktop are
     * deleted here, and the desktop's day notes replace these days' notes. Expenses are never touched.
     */
    suspend fun importPlans(
        db: AppDatabase, file: File, filesDir: File,
        /** When the phone does not have the trip yet and it is someone else's: who keeps its ledger. It then arrives read-only. */
        organizer: String? = null,
    ): Result = withContext(Dispatchers.IO) {
        try {
            ZipFile(file).use { zip ->
                val m = openManifest(zip)
                if (m.optString("kind") != KIND_PLANS) throw BadArchive("這不是電腦行程檔")
                val data = readJson(zip, "data.json")
                val t = data.getJSONObject("trip")
                val existing = db.tripDao().findByUuid(t.getString("uuid"))
                if (existing?.readOnly == true) throw BadArchive("「${existing.name}」是${existing.sharedBy}記帳的旅程,請把這個檔案傳給${existing.sharedBy}")
                val plans = plansOf(data)
                val copied = mutableMapOf<String, String>()
                for (p in plans) {
                    val photos = p.optJSONArray("photos") ?: continue
                    for (k in 0 until photos.length()) {
                        val name = photos.getJSONObject(k).getString("file")
                        copyEntry(zip, name, filesDir)?.let { copied[name] = it }
                    }
                }
                val oldFiles = mutableListOf<String>()
                var changed = 0
                val tripId = try {
                    db.withTransaction {
                        val categoryIds = mergeCategories(db, data.optJSONArray("categories"))
                        val id = existing?.id ?: db.tripDao().insertTrip(
                            Trip(
                                name = t.getString("name"), startDate = t.getLong("startDate"), endDate = t.getLong("endDate"),
                                uuid = t.getString("uuid"), navApp = t.optStringOrNull("navApp"),
                                sharedBy = organizer?.trim()?.ifBlank { null },
                                sharedAt = organizer?.trim()?.ifBlank { null }?.let { m.optLong("exportedAt", System.currentTimeMillis()) },
                            ),
                        )
                        for (p in plans) {
                            val uuid = p.getString("uuid")
                            val fields = { base: PlanItem ->
                                base.copy(
                                    title = p.getString("title"),
                                    categoryId = p.optStringOrNull("category")?.let(categoryIds::get),
                                    date = p.optLongOrNull("date"),
                                    minuteOfDay = p.optLongOrNull("minuteOfDay")?.toInt(),
                                    status = p.optString("status", "TODO"),
                                    reservation = p.optString("reservation", "NONE"),
                                    reservationNote = p.optString("reservationNote"),
                                    location = p.optString("location"),
                                    note = p.optString("note"),
                                )
                            }
                            val current = db.planDao().findByUuid(id, uuid)
                            val planId = if (current != null) {
                                db.planDao().update(fields(current))
                                db.planPhotoDao().forPlan(current.id).forEach { ph -> oldFiles += ph.path; db.planPhotoDao().delete(ph.id) }
                                current.id
                            } else {
                                db.planDao().insert(fields(PlanItem(tripId = id, title = "", uuid = uuid, createdAt = p.optLong("createdAt", System.currentTimeMillis()))))
                            }
                            p.optJSONArray("photos")?.let { photos ->
                                for (k in 0 until photos.length()) {
                                    val ph = photos.getJSONObject(k)
                                    val path = copied[ph.getString("file")] ?: continue
                                    db.planPhotoDao().insert(PlanPhoto(planItemId = planId, path = path, width = ph.optInt("width"), height = ph.optInt("height")))
                                }
                            }
                            changed++
                        }
                        for (uuid in deletedOf(data)) {
                            val gone = db.planDao().findByUuid(id, uuid) ?: continue
                            oldFiles += db.planPhotoDao().forPlan(gone.id).map { it.path }
                            db.planDao().delete(gone.id)
                            changed++
                        }
                        data.optJSONArray("dayNotes")?.let { a ->
                            for (i in 0 until a.length()) {
                                val n = a.getJSONObject(i)
                                db.dayNoteDao().set(id, n.getLong("day"), n.optString("text"))
                            }
                        }
                        id
                    }
                } catch (e: Exception) {
                    copied.values.forEach { File(it).delete() }
                    throw e
                }
                oldFiles.forEach { File(it).delete() }
                // A new read-only copy reads like any trip someone shared ("只能看、不能改").
                if (existing == null && !organizer.isNullOrBlank()) Result.Imported(KIND_TRIP, listOf(tripId), 0)
                else Result.Imported(KIND_PLANS, listOf(tripId), changed)
            }
        } catch (e: BadArchive) {
            Result.Failed(e.message ?: "無法讀取檔案")
        } catch (e: Exception) {
            Result.Failed("檔案損壞,無法匯入")
        }
    }

    private fun JSONObject.optStringOrNull(key: String): String? = if (isNull(key)) null else optString(key)
    private fun JSONObject.optLongOrNull(key: String): Long? = if (isNull(key)) null else optLong(key)
    private fun JSONObject.optDoubleOrNull(key: String): Double? = if (isNull(key)) null else optDouble(key)
}
