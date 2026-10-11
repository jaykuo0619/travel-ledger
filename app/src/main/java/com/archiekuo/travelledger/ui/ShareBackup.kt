package com.archiekuo.travelledger.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.archiekuo.travelledger.BuildConfig
import com.archiekuo.travelledger.backup.TripArchive
import com.archiekuo.travelledger.data.AppDatabase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** A 卡溜趴 file opened from LINE, a file manager or "從檔案還原", waiting for the user to confirm. */
object ImportInbox {
    var pending by mutableStateOf<Uri?>(null)
}

/** Writing archives to the cache for sharing, and reading incoming ones. */
object ArchiveFiles {
    private fun safe(name: String) = name.replace(Regex("""[\\/:*?"<>|\s]+"""), "_").take(40).ifBlank { "旅程" }

    fun backupName(today: LocalDate = LocalDate.now()) = "卡溜趴備份-$today.zip"
    fun tripName(tripName: String) = "卡溜趴-${safe(tripName)}.zip"

    /** Exports to cache/share/[fileName] and returns a content Uri other apps can read. */
    suspend fun exportForShare(
        context: Context, db: AppDatabase, fileName: String, kind: String, tripIds: List<Long>, photos: Boolean, sharedBy: String?,
    ): Uri = withContext(Dispatchers.IO) {
        val dir = File(context.cacheDir, "share").apply { deleteRecursively(); mkdirs() }
        val file = File(dir, fileName)
        file.outputStream().use { TripArchive.export(db, it, kind, tripIds, photos, sharedBy, BuildConfig.VERSION_NAME) }
        FileProvider.getUriForFile(context, "${context.packageName}.files", file)
    }

    /** My additions to a shared trip, as a file for its organizer. */
    suspend fun exportAdditions(context: Context, db: AppDatabase, trip: com.archiekuo.travelledger.data.Trip, from: String, photos: Boolean): Uri =
        withContext(Dispatchers.IO) {
            val dir = File(context.cacheDir, "share").apply { deleteRecursively(); mkdirs() }
            val file = File(dir, "卡溜趴補充-${safe(trip.name)}-${safe(from)}.zip")
            file.outputStream().use { TripArchive.exportAdditions(db, it, trip.id, from, photos, BuildConfig.VERSION_NAME) }
            FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        }

    suspend fun exportTo(context: Context, db: AppDatabase, target: Uri, tripIds: List<Long>, photos: Boolean) = withContext(Dispatchers.IO) {
        context.contentResolver.openOutputStream(target, "wt")!!.use {
            TripArchive.export(db, it, TripArchive.KIND_BACKUP, tripIds, photos, null, BuildConfig.VERSION_NAME)
        }
    }

    fun send(context: Context, uri: Uri, title: String, text: String) {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "application/zip"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, title)
            putExtra(Intent.EXTRA_TEXT, text)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(send, title).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
    }

    /** Copies an incoming file to the cache so it can be opened as a zip. */
    suspend fun copyIn(context: Context, uri: Uri): File = withContext(Dispatchers.IO) {
        val dir = File(context.cacheDir, "incoming").apply { deleteRecursively(); mkdirs() }
        val file = File(dir, "import.zip")
        context.contentResolver.openInputStream(uri)!!.use { input -> file.outputStream().use { input.copyTo(it) } }
        file
    }

    /**
     * Deletes the file the user opened once it has been imported. Android allows this for a document picked in
     * 「從檔案還原或匯入」 and for some file managers; a file opened from LINE belongs to LINE and stays there.
     * Returns whether it was deleted.
     */
    suspend fun deleteSource(context: Context, uri: Uri): Boolean = withContext(Dispatchers.IO) {
        runCatching { DocumentsContract.isDocumentUri(context, uri) && DocumentsContract.deleteDocument(context.contentResolver, uri) }
            .getOrDefault(false) ||
            runCatching { context.contentResolver.delete(uri, null, null) > 0 }.getOrDefault(false)
    }
}

/** Whether the opened file goes after [result]: only when the setting is on, the import worked, and it is not a backup. */
internal fun shouldDeleteSource(enabled: Boolean, result: TripArchive.Result): Boolean =
    enabled && result is TripArchive.Result.Imported && result.kind != TripArchive.KIND_BACKUP

/** "分享給同伴": who is sharing and whether to include photos. */
@Composable
fun ShareTripDialog(tripName: String, myName: String, busy: Boolean, onDismiss: () -> Unit, onShare: (name: String, photos: Boolean) -> Unit) {
    var name by remember { mutableStateOf(myName) }
    var photos by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        icon = { Icon(Icons.Rounded.IosShare, null) },
        title = { Text("分享給同伴") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    "把「$tripName」的帳目和行程做成一個檔案,傳到 LINE 群組。同伴用卡溜趴打開就能看(只能看、不能改);你之後再分享一次,他們的會自動更新。",
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                OutlinedTextField(
                    name, { name = it.take(20) }, Modifier.fillMaxWidth(),
                    label = { Text("你的名字(同伴會看到)") }, singleLine = true, shape = MaterialTheme.shapes.medium,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                )
                CheckRow("包含照片", "檔案會變大,LINE 傳送比較慢", photos) { photos = it }
            }
        },
        confirmButton = {
            TextButton({ onShare(name.trim(), photos) }, enabled = name.isNotBlank() && !busy) {
                if (busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Text("分享")
            }
        },
        dismissButton = { TextButton(onDismiss, enabled = !busy) { Text("取消") } },
    )
}

/** "傳給記帳人": my additions on a shared trip go to its organizer for review. */
@Composable
fun SendAdditionsDialog(
    trip: com.archiekuo.travelledger.data.Trip, count: Int, myName: String, busy: Boolean,
    onDismiss: () -> Unit, onSend: (name: String, photos: Boolean) -> Unit,
) {
    var name by remember { mutableStateOf(myName) }
    var photos by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        icon = { Icon(Icons.Rounded.Send, null) },
        title = { Text("傳給記帳人") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    "把你在「${trip.name}」補充的 $count 項做成一個檔案,傳給${trip.sharedBy}(例如 LINE)。${trip.sharedBy}確認加入後再分享一次,大家的就會統一。",
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                OutlinedTextField(
                    name, { name = it.take(20) }, Modifier.fillMaxWidth(),
                    label = { Text("你的名字") }, singleLine = true, shape = MaterialTheme.shapes.medium,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                )
                CheckRow("包含照片", "收據照片也一起傳", photos) { photos = it }
            }
        },
        confirmButton = {
            TextButton({ onSend(name.trim(), photos) }, enabled = name.isNotBlank() && !busy) {
                if (busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Text("傳送")
            }
        },
        dismissButton = { TextButton(onDismiss, enabled = !busy) { Text("取消") } },
    )
}

/** The organizer looks through a companion's additions and ticks what goes into the book. */
@Composable
fun ReviewAdditionsDialog(additions: TripArchive.Additions, busy: Boolean, onDismiss: () -> Unit, onAccept: (Set<String>) -> Unit) {
    var chosen by remember(additions) { mutableStateOf(additions.items.map { it.uuid }.toSet()) }
    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        icon = { Icon(Icons.Rounded.PlaylistAdd, null) },
        title = { Text("${additions.from} 的補充") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    "要加入「${additions.tripName}」的項目打勾。加入後記得再分享一次給大家。",
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                additions.items.forEach { item ->
                    val on = item.uuid in chosen
                    Row(
                        Modifier.fillMaxWidth().clickable { chosen = if (on) chosen - item.uuid else chosen + item.uuid },
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Checkbox(on, { chosen = if (on) chosen - item.uuid else chosen + item.uuid })
                        Column(Modifier.weight(1f)) {
                            Text(item.title, style = MaterialTheme.typography.bodyLarge)
                            Text(item.detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            }
        },
        confirmButton = { TextButton({ onAccept(chosen) }, enabled = chosen.isNotEmpty() && !busy) { Text("加入 ${chosen.size} 項") } },
        dismissButton = { TextButton(onDismiss, enabled = !busy) { Text("略過全部") } },
    )
}

/** The whole backup: the dialog, then either the system "save as" screen or the share sheet. */
@Composable
fun BackupFlow(db: AppDatabase, onClose: () -> Unit, onBackedUp: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var photos by remember { mutableStateOf(true) }
    fun done(ok: Boolean, message: String? = null) {
        busy = false
        if (ok) onBackedUp()
        (if (ok) message else "備份失敗")?.let { Toast.makeText(context, it, Toast.LENGTH_SHORT).show() }
        onClose()
    }
    val saveTo = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/zip")) { target ->
        if (target == null) { busy = false; return@rememberLauncherForActivityResult }
        scope.launch {
            val ok = runCatching { ArchiveFiles.exportTo(context, db, target, db.tripDao().allIds(), photos) }.isSuccess
            withContext(Dispatchers.Main) { done(ok, "已備份") }
        }
    }
    BackupDialog(
        busy, onDismiss = onClose,
        onSave = { p -> photos = p; busy = true; saveTo.launch(ArchiveFiles.backupName()) },
        onSend = { p ->
            busy = true
            scope.launch {
                val result = runCatching {
                    ArchiveFiles.exportForShare(context, db, ArchiveFiles.backupName(), TripArchive.KIND_BACKUP, db.tripDao().allIds(), p, null)
                }
                withContext(Dispatchers.Main) {
                    result.onSuccess { uri -> ArchiveFiles.send(context, uri, "卡溜趴備份", "卡溜趴備份檔") }
                    done(result.isSuccess)
                }
            }
        },
    )
}

/** "備份全部資料": with or without photos, to a file on the phone or through another app. */
@Composable
fun BackupDialog(busy: Boolean, onDismiss: () -> Unit, onSave: (photos: Boolean) -> Unit, onSend: (photos: Boolean) -> Unit) {
    var photos by remember { mutableStateOf(true) }
    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        icon = { Icon(Icons.Rounded.Backup, null) },
        title = { Text("備份全部資料") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    "所有旅程、帳目、行程、分類與付款方式會存成一個檔案。換手機時,在新手機的卡溜趴打開這個檔案就能還原。",
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                CheckRow("包含照片", "收據、回憶照片與封面", photos) { photos = it }
                if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            }
        },
        confirmButton = {
            Row {
                TextButton({ onSend(photos) }, enabled = !busy) { Text("傳送到…") }
                TextButton({ onSave(photos) }, enabled = !busy) { Text("存到手機") }
            }
        },
        dismissButton = { TextButton(onDismiss, enabled = !busy) { Text("取消") } },
    )
}

@Composable
private fun CheckRow(title: String, subtitle: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().clickable { onChange(!checked) }, verticalAlignment = Alignment.CenterVertically) {
        Checkbox(checked, onChange)
        Column {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** What an incoming file will do, before anything is written. */
@Composable
fun ImportConfirmDialog(
    summary: TripArchive.Summary, existing: Set<String>, busy: Boolean, onDismiss: () -> Unit, onConfirm: () -> Unit,
    /** Trips on this phone holding more recent records than the backup; restoring would lose them. */
    newerHere: List<String> = emptyList(),
) {
    val shared = summary.kind == TripArchive.KIND_TRIP
    val when_ = Instant.ofEpochMilli(summary.exportedAt).atZone(ZoneId.systemDefault()).toLocalDateTime()
    val stamp = "%d/%d %02d:%02d".format(when_.monthValue, when_.dayOfMonth, when_.hour, when_.minute)
    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        icon = { Icon(if (shared) Icons.Rounded.GroupAdd else Icons.Rounded.SettingsBackupRestore, null) },
        title = { Text(if (shared) "${summary.sharedBy ?: "同伴"} 分享的旅程" else "還原備份") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                summary.trips.take(6).forEach { t ->
                    Column {
                        Text(t.name, style = MaterialTheme.typography.titleMedium)
                        Text(
                            "${fmtShortDate(t.startDate)} – ${fmtShortDate(t.endDate)} · ${t.expenseCount} 筆 · ${fmtMoney(t.totalHome)}",
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        if (t.uuid in existing) {
                            Text("手機上已有這趟旅程,會更新成這份", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
                if (summary.trips.size > 6) Text("…共 ${summary.trips.size} 個旅程", style = MaterialTheme.typography.bodySmall)
                Text(
                    buildString {
                        append("$stamp 製作")
                        append(if (summary.photoCount > 0) " · 含 ${summary.photoCount} 張照片" else " · 不含照片")
                        append("\n")
                        append(
                            if (shared) "匯入後只能看、不能改。對方再分享一次,打開新檔案就會更新。"
                            else "手機上已有的同一趟旅程會被備份內容取代,其他旅程保留不動。",
                        )
                    },
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (newerHere.isNotEmpty()) {
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.errorContainer).padding(10.dp),
                    ) {
                        Icon(Icons.Rounded.Warning, null, tint = MaterialTheme.colorScheme.error)
                        Spacer(Modifier.width(8.dp))
                        Text(
                            "手機上的「${newerHere.joinToString("」「")}」比這份備份新,還原會蓋掉備份之後記的內容。",
                            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onErrorContainer,
                        )
                    }
                }
                if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            }
        },
        confirmButton = {
            TextButton(onConfirm, enabled = !busy) { Text(if (!shared && newerHere.isNotEmpty()) "仍要還原" else if (!shared) "還原" else if (summary.trips.any { it.uuid in existing }) "更新" else "匯入") }
        },
        dismissButton = { TextButton(onDismiss, enabled = !busy) { Text("取消") } },
    )
}

/**
 * Watches [ImportInbox]: reads the incoming file, asks for confirmation, imports it and opens the trip.
 * Lives at the top of the navigation graph so a file can arrive on any screen.
 */
@Composable
fun ImportHost(db: AppDatabase, deleteImportedFile: Boolean = true, onImported: (tripId: Long?) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val uri = ImportInbox.pending
    var file by remember { mutableStateOf<File?>(null) }
    var summary by remember { mutableStateOf<TripArchive.Summary?>(null) }
    var existing by remember { mutableStateOf(emptySet<String>()) }
    var additions by remember { mutableStateOf<TripArchive.Additions?>(null) }
    var newerHere by remember { mutableStateOf(emptyList<String>()) }
    var plans by remember { mutableStateOf<TripArchive.PlansPreview?>(null) }
    var busy by remember { mutableStateOf(false) }

    fun fail(message: String) {
        Toast.makeText(context, message, Toast.LENGTH_LONG).show()
        ImportInbox.pending = null
        summary = null
    }

    LaunchedEffect(uri) {
        if (uri == null) return@LaunchedEffect
        runCatching {
            val f = ArchiveFiles.copyIn(context, uri)
            val s = withContext(Dispatchers.IO) { TripArchive.readSummary(f) }
            val adds = if (s.kind == TripArchive.KIND_ADDITIONS) withContext(Dispatchers.IO) { TripArchive.readAdditions(f) } else null
            val plansPreview = if (s.kind == TripArchive.KIND_PLANS) TripArchive.previewPlans(db, f) else null
            val known = withContext(Dispatchers.IO) { s.trips.mapNotNull { t -> db.tripDao().findByUuid(t.uuid)?.uuid }.toSet() }
            val newer = if (s.kind != TripArchive.KIND_BACKUP) emptyList() else withContext(Dispatchers.IO) { TripArchive.newerOnPhone(db, s) }
            withContext(Dispatchers.Main) {
                existing = known
                newerHere = newer
                additions = adds
                plans = plansPreview
                file = f
                summary = s
            }
        }.onFailure { e -> withContext(Dispatchers.Main) { fail((e as? TripArchive.BadArchive)?.message ?: "無法開啟這個檔案") } }
    }

    fun finish(result: TripArchive.Result, sourceDeleted: Boolean = false) {
        busy = false
        summary = null
        additions = null
        plans = null
        ImportInbox.pending = null
        file?.delete()
        when (result) {
            is TripArchive.Result.Failed -> Toast.makeText(context, result.message, Toast.LENGTH_LONG).show()
            is TripArchive.Result.Imported -> {
                val msg = when {
                    result.kind == TripArchive.KIND_PLANS -> "已併入電腦排的行程"
                    result.kind == TripArchive.KIND_ADDITIONS ->
                        if (result.updated > 0) "已加入 ${result.updated} 項,記得再分享一次給大家" else "這些項目之前已經加入過了"
                    result.kind == TripArchive.KIND_TRIP && result.updated > 0 -> "已更新同伴分享的旅程"
                    result.kind == TripArchive.KIND_TRIP -> "已匯入,這趟旅程只能看、不能改"
                    else -> "已還原 ${result.tripIds.size} 個旅程"
                }
                Toast.makeText(context, if (sourceDeleted) "$msg(原檔已刪除)" else msg, Toast.LENGTH_LONG).show()
                onImported(result.tripIds.singleOrNull())
            }
        }
    }

    /**
     * After an import the opened file is no longer needed, so it goes (when Android lets us and the setting is on).
     * A backup is never deleted: it may be the only copy.
     */
    suspend fun done(result: TripArchive.Result, source: Uri?) {
        val deleted = shouldDeleteSource(deleteImportedFile, result) && source != null && ArchiveFiles.deleteSource(context, source)
        withContext(Dispatchers.Main) { finish(result, deleted) }
    }

    plans?.let { pv ->
        AlertDialog(
            onDismissRequest = { if (!busy) { ImportInbox.pending = null; summary = null; plans = null } },
            icon = { Icon(Icons.Rounded.Computer, null) },
            title = { Text(if (pv.refused != null) "無法併入" else "電腦排的行程") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(pv.tripName, style = MaterialTheme.typography.titleMedium)
                    Text(
                        pv.refused ?: buildString {
                            if (pv.newTrip) append("手機上還沒有這趟旅程,會新建一趟。\n")
                            append("新增 ${pv.added} 個、更新 ${pv.updated} 個")
                            if (pv.deleted > 0) append("、刪除 ${pv.deleted} 個")
                            append("行程。\n帳目不會被改動;同一個行程以電腦上的內容為準。")
                        },
                        style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
                }
            },
            confirmButton = {
                if (pv.refused == null) {
                    TextButton(
                        {
                            val f = file ?: return@TextButton
                            busy = true
                            scope.launch {
                                done(TripArchive.importPlans(db, f, context.filesDir), uri)
                            }
                        },
                        enabled = !busy,
                    ) { Text("併入") }
                }
            },
            dismissButton = { TextButton({ ImportInbox.pending = null; summary = null; plans = null }, enabled = !busy) { Text(if (pv.refused == null) "取消" else "知道了") } },
        )
        return
    }
    additions?.let { adds ->
        ReviewAdditionsDialog(
            adds, busy,
            onDismiss = { ImportInbox.pending = null; summary = null; additions = null; file?.delete() },
            onAccept = { chosen ->
                val f = file ?: return@ReviewAdditionsDialog
                busy = true
                scope.launch {
                    done(TripArchive.importAdditions(db, f, context.filesDir, chosen), uri)
                }
            },
        )
        return
    }
    val s = summary ?: return
    ImportConfirmDialog(
        s, existing, busy, newerHere = newerHere,
        onDismiss = { ImportInbox.pending = null; summary = null },
        onConfirm = {
            val f = file ?: return@ImportConfirmDialog
            busy = true
            scope.launch {
                done(TripArchive.import(db, f, context.filesDir), uri)
            }
        },
    )
}
