package com.archiekuo.travelledger.ui

import android.app.Application
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.archiekuo.travelledger.data.AppDatabase
import com.archiekuo.travelledger.data.UNSCHEDULED_DAY
import com.archiekuo.travelledger.data.Category
import com.archiekuo.travelledger.data.FALLBACK_CATEGORY
import com.archiekuo.travelledger.data.Expense
import com.archiekuo.travelledger.data.ExpenseRow
import com.archiekuo.travelledger.data.HOME_CURRENCY
import com.archiekuo.travelledger.data.Member
import com.archiekuo.travelledger.data.PaymentMethod
import com.archiekuo.travelledger.data.Photo
import com.archiekuo.travelledger.data.PhotoType
import com.archiekuo.travelledger.data.PlanItem
import com.archiekuo.travelledger.data.PlanPhoto
import com.archiekuo.travelledger.data.PlanRow
import com.archiekuo.travelledger.data.PlanStatus
import com.archiekuo.travelledger.data.TitleSuggestion
import com.archiekuo.travelledger.data.Trip
import com.archiekuo.travelledger.data.TripCurrencyRate
import com.archiekuo.travelledger.data.TripSummary
import com.archiekuo.travelledger.logic.ParsedPlace
import com.archiekuo.travelledger.logic.ReceiptGuess
import com.archiekuo.travelledger.photo.PhotoProcessor
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.io.File
import java.time.LocalDate
import java.time.LocalTime

private fun <T> Flow<T>.stateIn(vm: ViewModel, initial: T): StateFlow<T> =
    stateIn(vm.viewModelScope, SharingStarted.WhileSubscribed(5000), initial)

/** Days before departure during which a trip already counts as the current one (pre-paid flights, hotels). */
const val PRE_TRIP_DAYS = 30L

/** The trip to open on launch: ongoing, else the nearest one starting within [PRE_TRIP_DAYS]. */
fun currentTrip(trips: List<Trip>, today: LocalDate): Trip? {
    val t = today.toEpochDay()
    // A trip of our own wins over one a companion shared for the same dates.
    return trips.filter { t in (it.startDate - PRE_TRIP_DAYS)..it.endDate }.minWithOrNull(compareBy({ it.readOnly }, { it.startDate }))
}

class TripListViewModel(private val db: AppDatabase) : ViewModel() {
    val trips: StateFlow<List<TripSummary>> = db.tripDao().observeSummaries().stateIn(this, emptyList())

    fun create(trip: Trip, members: List<String>, rates: List<TripCurrencyRate>, onCreated: (Long) -> Unit) {
        viewModelScope.launch { onCreated(db.tripDao().createTrip(trip, members, rates)) }
    }

    suspend fun currentTripId(today: LocalDate, ownOnly: Boolean = false): Long? =
        currentTrip(db.tripDao().getTrips().filter { !ownOnly || !it.readOnly }, today)?.id
}

class TripDetailViewModel(private val db: AppDatabase, private val id: Long) : ViewModel() {
    val trip: StateFlow<Trip?> = db.tripDao().observeTrip(id).stateIn(this, null)
    val members: StateFlow<List<Member>> = db.tripDao().observeMembers(id).stateIn(this, emptyList())
    val expenses: StateFlow<List<ExpenseRow>> = db.expenseDao().observeRows(id).stateIn(this, emptyList())
    val rates: StateFlow<List<TripCurrencyRate>> = db.expenseDao().observeRates(id).stateIn(this, emptyList())
    val plans: StateFlow<List<PlanRow>> = db.planDao().observeRows(id).stateIn(this, emptyList())
    val categories: StateFlow<List<Category>> = db.lookupDao().observeCategories().stateIn(this, emptyList())
    /** My additions on a shared trip, not yet taken in by its organizer. */
    val pendingCount: StateFlow<Int> = combine(db.tripDao().observePendingExpenses(id), db.tripDao().observePendingPlans(id)) { a, b -> a + b }
        .stateIn(this, 0)

    /** Day notes by epoch day ([UNSCHEDULED_DAY] for the 待排 list). */
    val dayNotes: StateFlow<Map<Long, String>> = db.dayNoteDao().observe(id).map { list -> list.associate { it.day to it.text } }
        .stateIn(this, emptyMap())

    fun setDayNote(day: Long, text: String) = viewModelScope.launch { db.dayNoteDao().set(id, day, text) }

    fun setPlanStatus(planId: Long, status: String) = viewModelScope.launch { db.planDao().setStatus(planId, status) }

    fun movePlans(planIds: List<Long>, date: Long?) = viewModelScope.launch { planIds.forEach { db.planDao().setDate(it, date) } }

    /** Pasted lines become unscheduled items (or items on [date]), with a guessed category. */
    fun addParsed(places: List<ParsedPlace>, date: Long?) = viewModelScope.launch {
        val byName = categories.value.associateBy { it.name }
        val mine = trip.value?.readOnly ?: db.tripDao().getTrip(id)?.readOnly ?: false
        db.planDao().insertAll(
            places.map { p ->
                PlanItem(
                    tripId = id, title = p.title, location = p.location, date = date, minuteOfDay = p.minuteOfDay,
                    categoryId = p.categoryHint?.let { byName[it]?.id }, pending = mine,
                )
            },
        )
    }

    fun update(trip: Trip, memberNames: List<String>, rates: List<TripCurrencyRate>) {
        viewModelScope.launch { db.tripDao().updateTrip(trip, memberNames, rates) }
    }

    fun delete() {
        viewModelScope.launch {
            val cover = db.tripDao().coverPath(id)
            val photos = db.photoDao().pathsForTrip(id) + db.planPhotoDao().pathsForTrip(id)
            db.tripDao().deleteTrip(id)
            CoverStore.delete(cover)
            photos.forEach { PhotoProcessor.delete(it) }
        }
    }
}

data class EditState(
    val title: String = "",
    val amount: String = "",
    val currency: String = HOME_CURRENCY,
    val rate: String = "1",
    val categoryId: Long? = null,
    val paymentId: Long? = null,
    val date: Long = LocalDate.now().toEpochDay(),
    val minuteOfDay: Int? = LocalTime.now().let { it.hour * 60 + it.minute },
    val note: String = "",
    val noteOpen: Boolean = false,
) {
    val amountValue: Double? get() = amount.toDoubleOrNull()?.takeIf { it > 0 }
    val rateValue: Double? get() = rate.toDoubleOrNull()?.takeIf { it > 0 }
    val homeAmount: Double? get() = amountValue?.let { a -> rateValue?.let { toHomeAmount(a, it) } }
    val canSave: Boolean get() = homeAmount != null
}

/** A photo attached to the expense being edited; [id] is null until saved. */
data class PhotoItem(
    val id: Long?,
    val path: String,
    val type: String,
    val text: String = "",
    /** Picked from the gallery: it is already there, so it is never copied back. */
    val fromAlbum: Boolean = false,
    /** The camera's full-quality file, kept until save so the gallery gets it rather than our smaller copy. */
    val original: String? = null,
)

const val MAX_PHOTOS = 3

class ExpenseEditViewModel(
    private val app: Application,
    private val db: AppDatabase,
    private val tripId: Long,
    private val expenseId: Long?,
    private val saveMemoriesToGallery: Boolean,
    /** Recording money for this itinerary item: prefill from it and tick it off on save. */
    private val planItemId: Long? = null,
) : ViewModel() {
    var state by mutableStateOf<EditState?>(null)
        private set
    val photos = mutableStateListOf<PhotoItem>()
    var receipt by mutableStateOf<ReceiptGuess?>(null)
        private set
    var processing by mutableStateOf(false)
        private set
    var suggestions by mutableStateOf<List<TitleSuggestion>>(emptyList())
        private set
    var tripCurrencies by mutableStateOf(listOf(HOME_CURRENCY))
        private set
    val categories: StateFlow<List<Category>> = db.lookupDao().observeCategories().stateIn(this, emptyList())
    val methods: StateFlow<List<PaymentMethod>> = db.lookupDao().observePaymentMethods().stateIn(this, emptyList())

    private var tripRates: Map<String, Double> = emptyMap()
    private var original: Expense? = null
    private val originalPhotos = mutableListOf<Photo>()
    private var ocrText = ""
    /** On a trip someone shared with us, what we record becomes our own pending addition. */
    private var sharedTrip = false

    init {
        viewModelScope.launch {
            sharedTrip = db.tripDao().getTrip(tripId)?.readOnly == true
            tripRates = db.expenseDao().getRates(tripId).associate { it.currency to it.rate }
            suggestions = db.expenseDao().titleSuggestions()
            val existing = expenseId?.let { db.expenseDao().get(it) }
            original = existing
            if (existing != null) {
                ocrText = existing.ocrText
                originalPhotos += db.photoDao().forExpense(existing.id)
                photos += originalPhotos.map { PhotoItem(it.id, it.path, it.type) }
                state = EditState(
                    title = existing.title, amount = fmtNumber(existing.amount), currency = existing.currency,
                    rate = fmtNumber(existing.rate), categoryId = existing.categoryId,
                    paymentId = existing.paymentMethodId, date = existing.date, minuteOfDay = existing.minuteOfDay,
                    note = existing.note, noteOpen = existing.note.isNotBlank(),
                )
            } else {
                // New expense: default to the previous expense's currency, category and payment method.
                val last = db.expenseDao().latest(tripId)
                val plan = planItemId?.let { db.planDao().get(it) }
                val currency = last?.currency ?: tripRates.keys.firstOrNull() ?: HOME_CURRENCY
                state = EditState(
                    title = plan?.title ?: "",
                    currency = currency,
                    rate = rateFor(currency, last),
                    categoryId = plan?.categoryId ?: last?.categoryId ?: db.lookupDao().observeCategories().first().firstOrNull()?.id,
                    paymentId = last?.paymentMethodId ?: db.lookupDao().observePaymentMethods().first().firstOrNull()?.id,
                )
            }
            tripCurrencies = (listOf(HOME_CURRENCY) + tripRates.keys + listOfNotNull(state?.currency)).distinct()
        }
    }

    private fun rateFor(currency: String, fallbackFrom: Expense? = null): String = when {
        currency == HOME_CURRENCY -> "1"
        tripRates[currency] != null -> fmtNumber(tripRates.getValue(currency))
        fallbackFrom?.currency == currency -> fmtNumber(fallbackFrom.rate)
        else -> ""
    }

    fun edit(transform: (EditState) -> EditState) {
        state = state?.let(transform)
    }

    fun setCurrency(code: String) {
        edit { it.copy(currency = code, rate = rateFor(code)) }
        if (code !in tripCurrencies) tripCurrencies = tripCurrencies + code
    }

    fun key(k: String) = edit { it.copy(amount = applyKey(it.amount, k)) }

    /** Picking a remembered title also restores the category it was filed under. */
    fun pickSuggestion(s: TitleSuggestion) = edit { it.copy(title = s.title, categoryId = s.categoryId ?: it.categoryId) }

    /** [mode]: RECEIPT reads it, MEMORY just keeps it, null decides from the content (gallery picks). */
    /** [cameraFile] is the camera's own file (null for a photo picked from the gallery). */
    fun addPhoto(uri: Uri, mode: String?, cameraFile: File? = null) {
        if (photos.size >= MAX_PHOTOS) { cameraFile?.delete(); return }
        processing = true
        viewModelScope.launch {
            var keep = false
            runCatching { PhotoProcessor.process(app, uri, state?.currency?.takeIf { it != HOME_CURRENCY }, mode) }
                .onSuccess { p ->
                    // A memory from the camera: the gallery gets the full-quality original when the expense is saved.
                    keep = cameraFile != null && p.type == PhotoType.MEMORY && saveMemoriesToGallery
                    photos += PhotoItem(null, p.path, p.type, p.text, fromAlbum = cameraFile == null, original = cameraFile?.absolutePath?.takeIf { keep })
                    if (p.text.isNotBlank()) ocrText = listOf(ocrText, p.text).filter { it.isNotBlank() }.joinToString("\n")
                    if (p.type == PhotoType.RECEIPT && p.guess.hasData) receipt = p.guess
                }
            if (!keep) cameraFile?.delete()
            processing = false
        }
    }

    fun removePhoto(index: Int) {
        val p = photos.getOrNull(index) ?: return
        photos.removeAt(index)
        p.original?.let { File(it).delete() }
        if (p.id == null) PhotoProcessor.delete(p.path) // saved photos are removed on save
    }

    fun setPhotoType(index: Int, type: String) {
        val p = photos.getOrNull(index) ?: return
        photos[index] = p.copy(type = type)
    }

    fun savePhotoToGallery(index: Int, onDone: (Boolean) -> Unit) {
        val p = photos.getOrNull(index) ?: return
        viewModelScope.launch { onDone(PhotoProcessor.saveToGallery(app, Uri.fromFile(File(p.path)))) }
    }

    /** Fills empty or default fields from the recognized receipt. */
    fun applyReceipt() {
        val g = receipt ?: return
        edit { s ->
            var n = s
            g.store?.let { if (s.title.isBlank()) n = n.copy(title = it) }
            g.currency?.let { if (it != s.currency) n = n.copy(currency = it, rate = rateFor(it)) }
            g.total?.let { n = n.copy(amount = fmtNumber(it)) }
            g.date?.let { n = n.copy(date = it.toEpochDay()) }
            g.minuteOfDay?.let { n = n.copy(minuteOfDay = it) }
            n
        }
        g.currency?.let { if (it !in tripCurrencies) tripCurrencies = tripCurrencies + it }
        receipt = null
    }

    fun dismissReceipt() {
        receipt = null
    }

    fun save(onDone: () -> Unit) {
        val s = state ?: return
        val amount = s.amountValue ?: return
        val rate = s.rateValue ?: return
        val home = s.homeAmount ?: return
        viewModelScope.launch {
            val dao = db.expenseDao()
            val base = original ?: Expense(
                tripId = tripId, date = s.date, amount = amount, currency = s.currency, rate = rate,
                homeAmount = home, categoryId = s.categoryId, paymentMethodId = s.paymentId, payerId = null,
                pending = sharedTrip,
            )
            val e = base.copy(
                date = s.date, minuteOfDay = s.minuteOfDay, title = s.title.trim(), amount = amount,
                currency = s.currency, rate = rate, homeAmount = home, categoryId = s.categoryId,
                paymentMethodId = s.paymentId, note = s.note.trim(), ocrText = ocrText,
                planItemId = original?.planItemId ?: planItemId,
            )
            val id = if (original == null) dao.insert(e) else { dao.update(e); e.id }
            if (original == null && planItemId != null && !sharedTrip) db.planDao().setStatus(planItemId, PlanStatus.DONE)

            val photoDao = db.photoDao()
            val keptIds = photos.mapNotNull { it.id }.toSet()
            originalPhotos.filter { it.id !in keptIds }.forEach { photoDao.delete(it.id); PhotoProcessor.delete(it.path) }
            photos.forEach { p ->
                val path = PhotoProcessor.moveToType(app, p.path, p.type)
                val old = originalPhotos.find { it.id == p.id }
                if (old == null) {
                    // Memories go to the gallery, at the camera's full quality when we have it. A photo picked from the
                    // gallery is already there and is not copied again.
                    val saved = when {
                        p.type != PhotoType.MEMORY -> false
                        p.fromAlbum -> true
                        saveMemoriesToGallery -> PhotoProcessor.saveToGallery(app, Uri.fromFile(File(p.original ?: path)))
                        else -> false
                    }
                    photoDao.insert(Photo(expenseId = id, type = p.type, path = path, savedToGallery = saved))
                } else if (old.type != p.type || old.path != path) {
                    photoDao.update(old.copy(type = p.type, path = path))
                }
            }

            photos.forEach { p -> p.original?.let { File(it).delete() } }

            // First time a foreign currency is used in this trip: remember its rate as the trip default.
            if (s.currency != HOME_CURRENCY && s.currency !in tripRates && !sharedTrip) {
                dao.upsertRate(TripCurrencyRate(tripId, s.currency, rate))
            }
            onDone()
        }
    }

    /** Leaving without saving: drop photos taken in this session. */
    fun cancel() {
        photos.filter { it.id == null }.forEach { PhotoProcessor.delete(it.path) }
        photos.forEach { p -> p.original?.let { File(it).delete() } }
    }

    fun delete(onDone: () -> Unit) {
        val id = expenseId ?: return
        viewModelScope.launch {
            photos.forEach { PhotoProcessor.delete(it.path) }
            originalPhotos.forEach { PhotoProcessor.delete(it.path) }
            db.expenseDao().delete(id)
            onDone()
        }
    }
}

class LookupViewModel(private val db: AppDatabase) : ViewModel() {
    val categories: StateFlow<List<Category>> = db.lookupDao().observeCategories().stateIn(this, emptyList())
    val methods: StateFlow<List<PaymentMethod>> = db.lookupDao().observePaymentMethods().stateIn(this, emptyList())

    fun addCategory(name: String, icon: String, color: Int) = viewModelScope.launch {
        val order = (categories.value.maxOfOrNull { it.sortOrder } ?: -1) + 1
        db.lookupDao().insertCategory(Category(name = name, sortOrder = order, icon = icon, color = color))
    }

    fun updateCategory(id: Long, name: String, icon: String, color: Int) = viewModelScope.launch {
        categories.value.find { it.id == id }?.let {
            db.lookupDao().updateCategories(listOf(it.copy(name = name, icon = icon, color = color)))
        }
    }

    fun deleteCategory(id: Long) = viewModelScope.launch { db.lookupDao().deleteCategory(id) }

    /** What deleting this category would change, for the confirmation. */
    suspend fun categoryDeleteHint(id: Long): String {
        val dao = db.lookupDao()
        val expenses = dao.expensesWithCategory(id)
        val plans = dao.plansWithCategory(id)
        val other = dao.findBuiltInCategoryId(FALLBACK_CATEGORY)?.let { dao.getCategory(it)?.name } ?: FALLBACK_CATEGORY
        val used = listOfNotNull(if (expenses > 0) "$expenses 筆支出" else null, if (plans > 0) "$plans 個行程" else null)
        return if (used.isEmpty()) "沒有支出或行程使用這個分類。" else "有 ${used.joinToString("、")}使用這個分類,刪除後會改成「$other」。"
    }

    suspend fun methodDeleteHint(id: Long): String {
        val n = db.lookupDao().expensesWithPaymentMethod(id)
        return if (n == 0) "沒有支出使用這個付款方式。" else "有 $n 筆支出使用這個付款方式,刪除後會變成「未指定」。"
    }

    fun moveCategory(from: Int, to: Int) = viewModelScope.launch {
        val list = categories.value.toMutableList()
        if (from !in list.indices || to !in list.indices) return@launch
        list.add(to, list.removeAt(from))
        db.lookupDao().updateCategories(list.mapIndexed { i, c -> c.copy(sortOrder = i) })
    }

    fun addMethod(name: String) = viewModelScope.launch {
        db.lookupDao().insertPaymentMethod(PaymentMethod(name = name, sortOrder = (methods.value.maxOfOrNull { it.sortOrder } ?: -1) + 1))
    }

    fun renameMethod(id: Long, name: String) = viewModelScope.launch {
        methods.value.find { it.id == id }?.let { db.lookupDao().updatePaymentMethods(listOf(it.copy(name = name))) }
    }

    fun deleteMethod(id: Long) = viewModelScope.launch { db.lookupDao().deletePaymentMethod(id) }

    fun moveMethod(from: Int, to: Int) = viewModelScope.launch {
        val list = methods.value.toMutableList()
        if (from !in list.indices || to !in list.indices) return@launch
        list.add(to, list.removeAt(from))
        db.lookupDao().updatePaymentMethods(list.mapIndexed { i, m -> m.copy(sortOrder = i) })
    }
}

/** Editing one itinerary item (new when [planId] is null; may be prefilled from a map share). */
class PlanEditViewModel(
    private val db: AppDatabase,
    private val tripId: Long,
    private val planId: Long?,
    initialDate: Long?,
    shared: ParsedPlace?,
    /** Needed to store pictures; null in tests that don't add any. */
    private val app: Application? = null,
) : ViewModel() {
    var item by mutableStateOf<PlanItem?>(null)
        private set
    /** Pictures on this item as edited; saved with the item. */
    val pictures = mutableStateListOf<PlanPicture>()
    private val originalPictures = mutableListOf<PlanPhoto>()
    var addingPictures by mutableStateOf(false)
        private set
    var trip by mutableStateOf<Trip?>(null)
        private set
    val categories: StateFlow<List<Category>> = db.lookupDao().observeCategories().stateIn(this, emptyList())

    init {
        viewModelScope.launch {
            trip = db.tripDao().observeTrip(tripId).first()
            planId?.let { id ->
                originalPictures += db.planPhotoDao().forPlan(id)
                pictures += originalPictures.map { PlanPicture(it.id, it.path, it.width, it.height) }
            }
            item = planId?.let { db.planDao().get(it) } ?: run {
                val cats = db.lookupDao().observeCategories().first()
                PlanItem(
                    tripId = tripId, title = shared?.title ?: "", location = shared?.location ?: "", date = initialDate,
                    categoryId = shared?.categoryHint?.let { h -> cats.find { it.name == h }?.id },
                )
            }
        }
    }

    fun edit(transform: (PlanItem) -> PlanItem) {
        item = item?.let(transform)
    }

    fun addPictures(uris: List<android.net.Uri>) {
        val context = app ?: return
        addingPictures = true
        viewModelScope.launch {
            uris.take(MAX_PLAN_PICTURES - pictures.size).forEach { uri -> PlanPictures.import(context, uri)?.let { pictures += it } }
            addingPictures = false
        }
    }

    fun removePicture(index: Int) {
        val p = pictures.getOrNull(index) ?: return
        pictures.removeAt(index)
        if (p.id == null) PlanPictures.delete(p.path) // saved ones go on save
    }

    /** Leaving without saving: pictures added this time are thrown away. */
    fun cancel() {
        pictures.filter { it.id == null }.forEach { PlanPictures.delete(it.path) }
    }

    fun save(onDone: () -> Unit) {
        val i = item?.takeIf { it.title.isNotBlank() } ?: return
        viewModelScope.launch {
            val clean = i.copy(title = i.title.trim(), location = i.location.trim(), note = i.note.trim())
            val id = if (planId == null) db.planDao().insert(clean.copy(pending = trip?.readOnly == true)) else { db.planDao().update(clean); planId }
            val kept = pictures.mapNotNull { it.id }.toSet()
            originalPictures.filter { it.id !in kept }.forEach { db.planPhotoDao().delete(it.id); PlanPictures.delete(it.path) }
            pictures.filter { it.id == null }.forEach { p -> db.planPhotoDao().insert(PlanPhoto(planItemId = id, path = p.path, width = p.width, height = p.height)) }
            onDone()
        }
    }

    fun delete(onDone: () -> Unit) {
        val id = planId ?: return
        viewModelScope.launch { deletePlan(db, id); onDone() }
    }
}

/** A map place shared into the app, waiting to be added to a trip. */
/** Viewing one plan item: what it is, what was spent on it, and the quick actions around it. */
class PlanViewModel(private val db: AppDatabase, private val tripId: Long, private val planId: Long) : ViewModel() {
    val item: StateFlow<PlanItem?> = db.planDao().observe(planId).stateIn(this, null)
    val trip: StateFlow<Trip?> = db.tripDao().observeTrip(tripId).stateIn(this, null)
    val categories: StateFlow<List<Category>> = db.lookupDao().observeCategories().stateIn(this, emptyList())
    val expenses: StateFlow<List<ExpenseRow>> = db.expenseDao().observeRows(tripId)
        .map { rows -> rows.filter { it.planItemId == planId } }.stateIn(this, emptyList())
    val pictures: StateFlow<List<PlanPhoto>> = db.planPhotoDao().observe(planId).stateIn(this, emptyList())

    fun setStatus(status: String) = viewModelScope.launch { db.planDao().setStatus(planId, status) }

    fun delete(onDone: () -> Unit) = viewModelScope.launch { deletePlan(db, planId); onDone() }

    /**
     * Replaces this item by [items] on the same day. Its note is kept word for word in that day's note (on a
     * shared trip, where day notes belong to the organizer, the item simply stays). Hands back an undo.
     */
    fun split(items: List<PlanItem>, onDone: (PendingUndo) -> Unit) {
        val original = item.value ?: return
        val shared = trip.value?.readOnly == true
        viewModelScope.launch {
            val undo = splitPlan(db, original, items, shared)
            onDone(undo)
        }
    }
}

const val MAX_PLAN_PICTURES = 9

/** Deletes a plan item with its pictures' files (expenses stay, unlinked). */
suspend fun deletePlan(db: AppDatabase, id: Long) {
    val paths = db.planPhotoDao().forPlan(id).map { it.path }
    db.planDao().delete(id)
    paths.forEach { PlanPictures.delete(it) }
}

/** An action that can be taken back from the snackbar for a short while. */
class PendingUndo(val message: String, val undo: suspend () -> Unit)

/** The latest undoable action, shown as a snackbar on the trip screen. */
object UndoInbox {
    var pending by mutableStateOf<PendingUndo?>(null)
}

/** See [PlanViewModel.split]; separate so tests can call it directly. */
suspend fun splitPlan(db: AppDatabase, original: PlanItem, items: List<PlanItem>, sharedTrip: Boolean): PendingUndo {
    val day = original.date ?: UNSCHEDULED_DAY
    val noteDao = db.dayNoteDao()
    val before = noteDao.get(original.tripId, day)
    val linked = db.expenseDao().forTrip(original.tripId).filter { it.planItemId == original.id }.map { it.id }
    val created = items.map { db.planDao().insert(it.copy(pending = it.pending || sharedTrip)) }
    // Pictures go with the first new item so no screenshot is lost.
    val movedPictures = !sharedTrip && created.isNotEmpty() && db.planPhotoDao().forPlan(original.id).isNotEmpty()
    if (movedPictures) db.planPhotoDao().move(original.id, created.first())
    if (!sharedTrip) {
        val moved = "【${original.title}】\n${original.note.trim()}"
        noteDao.set(original.tripId, day, listOfNotNull(before?.text, moved).joinToString("\n\n"))
        db.planDao().delete(original.id)
    }
    return PendingUndo("已拆成 ${items.size} 個行程" + if (sharedTrip) "" else ",原筆記放在當日筆記") {
        // Bring the original back first, so its pictures can move home before the new items (and their rows) go.
        if (!sharedTrip) {
            db.planDao().insert(original)
            if (movedPictures) db.planPhotoDao().move(created.first(), original.id)
            linked.forEach { db.expenseDao().setPlan(it, original.id) }
            if (before == null) noteDao.delete(original.tripId, day) else noteDao.put(before)
        }
        created.forEach { db.planDao().deleteRow(it) }
    }
}

object SharedPlaceInbox {
    var pending by mutableStateOf<ParsedPlace?>(null)
}
