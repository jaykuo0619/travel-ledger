package com.archiekuo.travelledger.ui

import android.app.Application
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.archiekuo.travelledger.BuildConfig
import com.archiekuo.travelledger.data.AppDatabase
import com.archiekuo.travelledger.data.PhotoType
import com.archiekuo.travelledger.data.Trip
import com.archiekuo.travelledger.data.TripCurrencyRate
import com.archiekuo.travelledger.photo.PhotoProcessor
import kotlinx.coroutines.launch
import java.io.File
import java.time.LocalDate

private val longArg = { name: String -> navArgument(name) { type = NavType.LongType } }

@Composable
fun AppNav(db: AppDatabase, settings: AppSettings, onSettings: (AppSettings) -> Unit) {
    val nav = rememberNavController()
    val context = LocalContext.current
    val listFactory = viewModelFactory { initializer { TripListViewModel(db) } }
    val lookupFactory = viewModelFactory { initializer { LookupViewModel(db) } }
    fun detailFactory(id: Long) = viewModelFactory { initializer { TripDetailViewModel(db, id) } }
    val listVm: TripListViewModel = viewModel(factory = listFactory)

    // On a cold start, jump straight into the current trip; the trip list stays underneath.
    var launched by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        if (!launched) {
            launched = true
            if (SharedPlaceInbox.pending == null && ImportInbox.pending == null) listVm.currentTripId(LocalDate.now())?.let { nav.navigate("trip/$it") }
        }
    }
    // A place shared from a map app goes to the current (or most recent) trip's unscheduled list.
    val shared = SharedPlaceInbox.pending
    LaunchedEffect(shared) {
        if (shared != null) {
            val id = listVm.currentTripId(LocalDate.now(), ownOnly = true) ?: db.tripDao().getTrips().firstOrNull { !it.readOnly }?.id
            if (id == null) {
                android.widget.Toast.makeText(context, "請先建立一趟旅程", android.widget.Toast.LENGTH_LONG).show()
                SharedPlaceInbox.pending = null
            } else {
                nav.navigate("trip/$id/plan/0?shared=true")
            }
        }
    }

    /** Navigate with the trip's chosen map app. */
    fun openMap(trip: Trip?, title: String, location: String) = MapLauncher.open(context, NavApp.of(trip?.navApp), title, location)

    ImportHost(db, settings.deleteImportedFile) { id ->
        if (id != null) nav.navigate("trip/$id") { popUpTo("trips") }
        else if (!nav.popBackStack("trips", inclusive = false)) nav.navigate("trips")
    }

    fun backedUp() = onSettings(settings.copy(lastBackupDay = LocalDate.now().toEpochDay()))

    NavHost(nav, startDestination = "trips") {
        composable("trips") {
            val trips by listVm.trips.collectAsStateWithLifecycle()
            var backingUp by remember { mutableStateOf(false) }
            val today = LocalDate.now()
            TripListScreen(
                trips,
                onOpen = { nav.navigate("trip/$it") },
                onAdd = { nav.navigate("trip/new") },
                onSettings = { nav.navigate("settings") },
                today = today,
                version = BuildConfig.VERSION_NAME,
                reminder = backupReminder(trips, today, settings.lastBackupDay, settings.reminderDismissedDay),
                onBackup = { backingUp = true },
                onLater = { onSettings(settings.copy(reminderDismissedDay = today.toEpochDay())) },
            )
            if (backingUp) BackupFlow(db, onClose = { backingUp = false }, onBackedUp = ::backedUp)
        }
        composable("trip/new") {
            TripEditRoute(null, emptyList(), emptyList(), onBack = { nav.popBackStack() }) { trip, members, rates ->
                listVm.create(trip, members, rates) { id ->
                    nav.navigate("trip/$id") { popUpTo("trips") }
                }
            }
        }
        composable("trip/{id}/edit", listOf(longArg("id"))) {
            val id = it.arguments!!.getLong("id")
            val vm: TripDetailViewModel = viewModel(key = "trip$id", factory = detailFactory(id))
            val trip by vm.trip.collectAsStateWithLifecycle()
            val members by vm.members.collectAsStateWithLifecycle()
            val rates by vm.rates.collectAsStateWithLifecycle()
            trip?.let { t ->
                TripEditRoute(t, members.map { m -> m.name }, rates, onBack = { nav.popBackStack() }) { updated, names, r ->
                    vm.update(updated, names, r); nav.popBackStack()
                }
            }
        }
        composable("trip/{id}", listOf(longArg("id"))) {
            val id = it.arguments!!.getLong("id")
            val vm: TripDetailViewModel = viewModel(key = "trip$id", factory = detailFactory(id))
            val trip by vm.trip.collectAsStateWithLifecycle()
            val members by vm.members.collectAsStateWithLifecycle()
            val expenses by vm.expenses.collectAsStateWithLifecycle()
            val plans by vm.plans.collectAsStateWithLifecycle()
            var tab by rememberSaveable { mutableStateOf<TripTab?>(null) }
            var sharing by remember { mutableStateOf(false) }
            var sendingAdditions by remember { mutableStateOf(false) }
            val pendingCount by vm.pendingCount.collectAsStateWithLifecycle()
            val dayNotes by vm.dayNotes.collectAsStateWithLifecycle()
            var shareBusy by remember { mutableStateOf(false) }
            val scope = rememberCoroutineScope()
            val readOnly = trip?.readOnly == true
            TripScreen(
                trip, members.size, expenses, plans, tab, { t -> tab = t },
                TripActions(
                    switchTrip = { if (!nav.popBackStack("trips", inclusive = false)) nav.navigate("trips") },
                    edit = { nav.navigate("trip/$id/edit") },
                    delete = { vm.delete(); if (!nav.popBackStack("trips", inclusive = false)) nav.navigate("trips") },
                    addExpense = { planId -> nav.navigate("trip/$id/expense/0" + (planId?.let { p -> "?plan=$p" } ?: "")) },
                    openExpense = { eid -> nav.navigate("trip/$id/expense/$eid") },
                    addPlan = { date -> nav.navigate("trip/$id/plan/0" + (date?.let { d -> "?date=$d" } ?: "")) },
                    openPlan = { pid -> nav.navigate("trip/$id/planview/$pid") },
                    setPlanStatus = { pid, st -> vm.setPlanStatus(pid, st) },
                    movePlans = { ids, date -> vm.movePlans(ids, date) },
                    pastePlans = { text, date -> vm.addParsed(com.archiekuo.travelledger.logic.PlanParser.splitNote(text), date) },
                    openMap = { p -> openMap(trip, p.title, p.location) },
                    share = { sharing = true },
                    sendToComputer = {
                        val t = trip ?: return@TripActions
                        scope.launch {
                            runCatching {
                                ArchiveFiles.exportForShare(
                                    context, db, "卡溜趴行程-${t.name.replace(Regex("[\\\\/:*?\"<>|\\s]+"), "_").take(40)}.zip",
                                    com.archiekuo.travelledger.backup.TripArchive.KIND_TRIP, listOf(t.id), false, settings.myName.ifBlank { "我" },
                                )
                            }.onSuccess { uri -> ArchiveFiles.send(context, uri, "傳到電腦", "卡溜趴行程:${t.name}(在電腦的卡溜趴行程桌打開)") }
                                .onFailure { android.widget.Toast.makeText(context, "產生檔案失敗", android.widget.Toast.LENGTH_LONG).show() }
                        }
                    },
                    readOnly = readOnly,
                    pendingCount = pendingCount,
                    dayNotes = dayNotes,
                    saveDayNote = { day, text -> vm.setDayNote(day, text) },
                    sendAdditions = { sendingAdditions = true },
                ),
            )
            val t = trip
            if (sendingAdditions && t != null) {
                SendAdditionsDialog(t, pendingCount, settings.myName, shareBusy, onDismiss = { sendingAdditions = false }) { name, photos ->
                    if (name != settings.myName) onSettings(settings.copy(myName = name))
                    shareBusy = true
                    scope.launch {
                        runCatching { ArchiveFiles.exportAdditions(context, db, t, name, photos) }
                            .onSuccess { uri ->
                                ArchiveFiles.send(context, uri, "傳給${t.sharedBy}", "$name 補充「${t.name}」(請用卡溜趴打開)")
                            }
                            .onFailure { android.widget.Toast.makeText(context, "傳送失敗", android.widget.Toast.LENGTH_LONG).show() }
                        shareBusy = false
                        sendingAdditions = false
                    }
                }
            }
            if (sharing && t != null) {
                ShareTripDialog(t.name, settings.myName, shareBusy, onDismiss = { sharing = false }) { name, photos ->
                    if (name != settings.myName) onSettings(settings.copy(myName = name))
                    shareBusy = true
                    scope.launch {
                        runCatching {
                            ArchiveFiles.exportForShare(context, db, ArchiveFiles.tripName(t.name), com.archiekuo.travelledger.backup.TripArchive.KIND_TRIP, listOf(t.id), photos, name)
                        }.onSuccess { uri ->
                            ArchiveFiles.send(context, uri, "分享「${t.name}」", "卡溜趴:${t.name}(用卡溜趴 App 打開這個檔案)")
                        }.onFailure {
                            android.widget.Toast.makeText(context, "分享失敗", android.widget.Toast.LENGTH_LONG).show()
                        }
                        shareBusy = false
                        sharing = false
                    }
                }
            }
        }
        composable(
            "trip/{id}/expense/{eid}?plan={plan}",
            listOf(longArg("id"), longArg("eid"), navArgument("plan") { type = NavType.LongType; defaultValue = 0L }),
        ) {
            val id = it.arguments!!.getLong("id")
            val eid = it.arguments!!.getLong("eid").takeIf { v -> v != 0L }
            val plan = it.arguments!!.getLong("plan").takeIf { v -> v != 0L }
            val app = context.applicationContext as Application
            val vm: ExpenseEditViewModel = viewModel(
                key = "expense$id/$eid/$plan",
                factory = viewModelFactory { initializer { ExpenseEditViewModel(app, db, id, eid, settings.saveMemoriesToGallery, plan) } },
            )
            // On a shared trip the organizer's expenses are view-only; my own additions stay editable.
            val readOnly by produceState(false, id, eid) {
                value = db.tripDao().getTrip(id)?.readOnly == true && eid != null && db.expenseDao().get(eid)?.pending != true
            }
            ExpenseEditRoute(
                vm, eid == null, readOnly, settings.keypadKeyHeight,
                onKeypadHeight = { h -> onSettings(settings.copy(keypadKeyHeight = h)) },
                onDone = { nav.popBackStack() },
            )
        }
        composable(
            "trip/{id}/plan/{pid}?date={date}&shared={shared}",
            listOf(
                longArg("id"), longArg("pid"),
                navArgument("date") { type = NavType.LongType; defaultValue = Long.MIN_VALUE },
                navArgument("shared") { type = NavType.BoolType; defaultValue = false },
            ),
        ) {
            val id = it.arguments!!.getLong("id")
            val pid = it.arguments!!.getLong("pid").takeIf { v -> v != 0L }
            val date = it.arguments!!.getLong("date").takeIf { v -> v != Long.MIN_VALUE }
            val fromShare = it.arguments!!.getBoolean("shared")
            val vm: PlanEditViewModel = viewModel(
                key = "plan$id/$pid/$date/$fromShare",
                factory = viewModelFactory {
                    initializer {
                        PlanEditViewModel(
                            db, id, pid, date, if (fromShare) SharedPlaceInbox.pending.also { SharedPlaceInbox.pending = null } else null,
                            context.applicationContext as Application,
                        )
                    }
                },
            )
            val categories by vm.categories.collectAsStateWithLifecycle()
            val pickPictures = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(MAX_PLAN_PICTURES)) { uris ->
                if (uris.isNotEmpty()) vm.addPictures(uris)
            }
            androidx.activity.compose.BackHandler { vm.cancel(); nav.popBackStack() }
            PlanEditScreen(
                vm.item, vm.trip, categories, isNew = pid == null,
                PlanActions(
                    edit = vm::edit,
                    save = { vm.save { nav.popBackStack() } },
                    delete = { vm.delete { nav.popBackStack() } },
                    back = { vm.cancel(); nav.popBackStack() },
                    addPictures = { pickPictures.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                    removePicture = vm::removePicture,
                    record = { pid?.let { p -> nav.navigate("trip/$id/expense/0?plan=$p") } },
                    openMap = { p -> openMap(vm.trip, p.title, p.location) },
                ),
                pictures = vm.pictures, addingPictures = vm.addingPictures,
            )
        }
        // Tapping a plan item shows it; the pencil at the top opens the editor above.
        composable("trip/{id}/planview/{pid}", listOf(longArg("id"), longArg("pid"))) {
            val id = it.arguments!!.getLong("id")
            val pid = it.arguments!!.getLong("pid")
            val vm: PlanViewModel = viewModel(key = "planview$id/$pid", factory = viewModelFactory { initializer { PlanViewModel(db, id, pid) } })
            val item by vm.item.collectAsStateWithLifecycle()
            val trip by vm.trip.collectAsStateWithLifecycle()
            val categories by vm.categories.collectAsStateWithLifecycle()
            val expenses by vm.expenses.collectAsStateWithLifecycle()
            val pictures by vm.pictures.collectAsStateWithLifecycle()
            // On a shared trip only my own additions can be changed.
            val canEdit = trip?.readOnly != true || item?.pending == true
            PlanViewScreen(
                item, trip, categories, expenses, canEdit,
                PlanViewActions(
                    back = { nav.popBackStack() },
                    edit = { nav.navigate("trip/$id/plan/$pid") },
                    delete = { vm.delete { nav.popBackStack() } },
                    setStatus = { st -> vm.setStatus(st) },
                    record = { nav.navigate("trip/$id/expense/0?plan=$pid") },
                    openMap = { p -> openMap(trip, p.title, p.location) },
                    openExpense = { eid -> nav.navigate("trip/$id/expense/$eid") },
                    split = { items ->
                        vm.split(items) { undo ->
                            UndoInbox.pending = undo
                            nav.popBackStack()
                        }
                    },
                ),
                pictures = pictures.map { it.path },
            )
        }
        composable("settings") {
            val scope = rememberCoroutineScope()
            var backingUp by remember { mutableStateOf(false) }
            val openFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
                if (uri != null) ImportInbox.pending = uri
            }
            if (backingUp) BackupFlow(db, onClose = { backingUp = false }, onBackedUp = ::backedUp)
            SettingsScreen(
                settings, onSettings,
                onBack = { nav.popBackStack() },
                onCategories = { nav.navigate("settings/categories") },
                onMethods = { nav.navigate("settings/methods") },
                version = BuildConfig.VERSION_NAME,
                onBackup = { backingUp = true },
                onRestore = { openFile.launch(arrayOf("application/zip", "application/octet-stream", "application/x-zip-compressed", "*/*")) },
            )
        }
        composable("settings/categories") {
            val vm: LookupViewModel = viewModel(factory = lookupFactory)
            val items by vm.categories.collectAsStateWithLifecycle()
            ManageListScreen(
                title = "分類管理",
                items = items.map { c ->
                    val st = categoryStyle(c.name, c.icon, c.color)
                    ManageItem(c.id, c.name, st.icon, st.color, c.icon, c.color, deletable = c.builtIn == null)
                },
                styleEditable = true,
                builtInNote = "基礎分類不能刪除,可以改名;自己新增的可以刪除。",
                deleteHint = vm::categoryDeleteHint,
                onBack = { nav.popBackStack() },
                onAdd = { n, i, c -> vm.addCategory(n, i, c) },
                onUpdate = { id, n, i, c -> vm.updateCategory(id, n, i, c) },
                onDelete = { id -> vm.deleteCategory(id) },
                onMove = { a, b -> vm.moveCategory(a, b) },
            )
        }
        composable("settings/methods") {
            val vm: LookupViewModel = viewModel(factory = lookupFactory)
            val items by vm.methods.collectAsStateWithLifecycle()
            ManageListScreen(
                title = "付款方式管理",
                items = items.map { m -> ManageItem(m.id, m.name, paymentIcon(m.name), Palette[0], deletable = m.builtIn == null) },
                styleEditable = false,
                builtInNote = "基礎付款方式不能刪除,可以改名;自己新增的可以刪除。",
                deleteHint = vm::methodDeleteHint,
                onBack = { nav.popBackStack() },
                onAdd = { n, _, _ -> vm.addMethod(n) },
                onUpdate = { id, n, _, _ -> vm.renameMethod(id, n) },
                onDelete = { id -> vm.deleteMethod(id) },
                onMove = { a, b -> vm.moveMethod(a, b) },
            )
        }
    }
}

/** Expense editor wired to the camera, photo picker and gallery. */
@Composable
private fun ExpenseEditRoute(
    vm: ExpenseEditViewModel, isNew: Boolean, readOnly: Boolean, keypadKeyHeight: Float,
    onKeypadHeight: (Float) -> Unit, onDone: () -> Unit,
) {
    val context = LocalContext.current
    val categories by vm.categories.collectAsStateWithLifecycle()
    val methods by vm.methods.collectAsStateWithLifecycle()
    var captureFile by rememberSaveable { mutableStateOf<String?>(null) }
    var captureMode by rememberSaveable { mutableStateOf(PhotoType.MEMORY) }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val f = captureFile?.let(::File)
        if (ok && f != null) vm.addPhoto(android.net.Uri.fromFile(f), captureMode, cameraFile = f) else f?.delete()
        captureFile = null
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) vm.addPhoto(uri, mode = null)
    }
    fun capture(mode: String) {
        val (file, uri) = PhotoProcessor.newCaptureUri(context)
        captureFile = file.absolutePath
        captureMode = mode
        camera.launch(uri)
    }
    androidx.activity.compose.BackHandler { vm.cancel(); onDone() }
    if (readOnly) {
        ExpenseDetailScreen(
            vm.state, categories, methods, vm.photos, onBack = { vm.cancel(); onDone() },
            onSavePhoto = { i ->
                vm.savePhotoToGallery(i) { ok ->
                    android.widget.Toast.makeText(context, if (ok) "已存到相簿" else "存檔失敗", android.widget.Toast.LENGTH_SHORT).show()
                }
            },
        )
        return
    }
    ExpenseEditScreen(
        state = vm.state, isNew = isNew, categories = categories, methods = methods,
        photos = vm.photos, suggestions = vm.suggestions, currencies = vm.tripCurrencies,
        receipt = vm.receipt, processing = vm.processing,
        actions = ExpenseActions(
            edit = vm::edit, key = vm::key, currency = vm::setCurrency, pickSuggestion = vm::pickSuggestion,
            takeReceipt = { capture(PhotoType.RECEIPT) },
            takePhoto = { capture(PhotoType.MEMORY) },
            pickPhoto = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
            removePhoto = vm::removePhoto, setPhotoType = vm::setPhotoType,
            savePhotoToGallery = { i ->
                vm.savePhotoToGallery(i) { ok ->
                    android.widget.Toast.makeText(context, if (ok) "已存到相簿" else "存檔失敗", android.widget.Toast.LENGTH_SHORT).show()
                }
            },
            applyReceipt = vm::applyReceipt, dismissReceipt = vm::dismissReceipt,
            save = { vm.save(onDone) }, delete = { vm.delete(onDone) },
            back = { vm.cancel(); onDone() },
            saveKeypadHeight = onKeypadHeight,
        ),
        keypadKeyHeight = keypadKeyHeight,
    )
}

/** Trip editor with the system photo picker for the cover; cleans up unsaved cover files. */
@Composable
private fun TripEditRoute(
    initial: Trip?,
    initialMembers: List<String>,
    initialRates: List<TripCurrencyRate>,
    onBack: () -> Unit,
    onSave: (Trip, List<String>, List<TripCurrencyRate>) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var cover by rememberSaveable { mutableStateOf(initial?.coverPath) }
    var busy by remember { mutableStateOf(false) }
    fun setCover(path: String) {
        if (cover != initial?.coverPath) CoverStore.delete(cover)
        cover = path
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            busy = true
            CoverStore.import(context, uri)?.let(::setCover)
            busy = false
        }
    }
    TripEditScreen(
        initial, initialMembers, initialRates, cover, busy,
        onPickCover = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
        onRemoveCover = {
            if (cover != initial?.coverPath) CoverStore.delete(cover) // an unsaved pick; a saved one goes on save
            cover = null
        },
        onBack = {
            if (cover != initial?.coverPath) CoverStore.delete(cover)
            onBack()
        },
        onSave = { trip, members, rates ->
            if (initial?.coverPath != null && initial.coverPath != cover) CoverStore.delete(initial.coverPath)
            onSave(trip, members, rates)
        },
    )
}
