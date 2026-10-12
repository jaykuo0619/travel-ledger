package com.archiekuo.travelledger.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.rememberTextMeasurer
import com.archiekuo.travelledger.data.Category
import com.archiekuo.travelledger.data.ExpenseRow
import com.archiekuo.travelledger.data.HOME_CURRENCY
import com.archiekuo.travelledger.data.PaymentMethod
import com.archiekuo.travelledger.data.PlanItem
import com.archiekuo.travelledger.data.PlanStatus
import com.archiekuo.travelledger.data.Reservation
import com.archiekuo.travelledger.data.Trip
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId

/**
 * Shown on a trip someone shared with us: who sent it and when, and what I have added myself
 * (with the button that sends it to the organizer).
 */
@Composable
fun ReadOnlyBanner(trip: Trip, pendingCount: Int, onSend: () -> Unit, modifier: Modifier = Modifier) {
    val cs = MaterialTheme.colorScheme
    val at = trip.sharedAt?.let { Instant.ofEpochMilli(it).atZone(ZoneId.systemDefault()).toLocalDateTime() }
    Column(modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(cs.secondaryContainer).padding(horizontal = 12.dp, vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Visibility, null, Modifier.size(20.dp), tint = cs.onSecondaryContainer)
            Spacer(Modifier.width(8.dp))
            Text(
                "${trip.sharedBy} 記帳" + (at?.let { " · %d/%d %02d:%02d 更新".format(it.monthValue, it.dayOfMonth, it.hour, it.minute) } ?: ""),
                style = MaterialTheme.typography.bodyMedium, color = cs.onSecondaryContainer,
            )
        }
        if (pendingCount > 0) {
            Spacer(Modifier.height(6.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "我補充了 $pendingCount 項", style = MaterialTheme.typography.bodyMedium, color = cs.onSecondaryContainer,
                    modifier = Modifier.weight(1f),
                )
                Button(onSend, shape = RoundedCornerShape(50), contentPadding = PaddingValues(horizontal = 14.dp)) {
                    Icon(Icons.Rounded.Send, null, Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("傳給記帳人", softWrap = false)
                }
            }
        }
    }
}

@Composable
private fun DetailLine(icon: ImageVector, label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(12.dp))
        Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.width(72.dp))
        LinkText(value, Modifier.weight(1f))
    }
}

@Composable
private fun DetailCard(lines: List<Triple<ImageVector, String, String>>) {
    LedgerCard(Modifier.fillMaxWidth(), padding = PaddingValues(vertical = 2.dp)) {
        lines.forEachIndexed { i, (icon, label, value) ->
            if (i > 0) HorizontalDivider(Modifier.padding(start = 50.dp), color = ledger.hairline)
            DetailLine(icon, label, value)
        }
    }
}

/** An expense in a shared trip. */
@Composable
fun ExpenseDetailScreen(
    state: EditState?,
    categories: List<Category>,
    methods: List<PaymentMethod>,
    photos: List<PhotoItem>,
    onBack: () -> Unit,
    onSavePhoto: (Int) -> Unit,
) {
    var viewing by remember { mutableStateOf<Int?>(null) }
    Box(Modifier.fillMaxSize()) {
        Scaffold(containerColor = MaterialTheme.colorScheme.background, topBar = { AppTopBar("支出明細", onBack = onBack, closeIcon = true) }) { pad ->
            val s = state ?: return@Scaffold
            val category = categories.firstOrNull { it.id == s.categoryId }
            val style = categoryStyle(category?.name, category?.icon, category?.color)
            Column(
                Modifier.padding(pad).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                LedgerCard(Modifier.fillMaxWidth()) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        IconTile(style.icon, style.color, size = 48.dp, corner = 14.dp)
                        Spacer(Modifier.width(14.dp))
                        Column(Modifier.weight(1f)) {
                            Text(s.title.ifBlank { category?.name ?: "支出" }, style = MaterialTheme.typography.titleLarge)
                            Text(fmtShortDateTime(s.date, s.minuteOfDay), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    Spacer(Modifier.height(14.dp))
                    Text(fmtAmount(s.amountValue ?: 0.0, s.currency), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.SemiBold)
                    if (s.currency != HOME_CURRENCY) {
                        Text(
                            "≈ ${fmtMoney(s.homeAmount ?: 0.0)} · 匯率 ${s.rate}",
                            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                if (photos.isNotEmpty()) PhotoStrip(photos, onOpen = { viewing = it })
                DetailCard(
                    buildList {
                        add(Triple(Icons.Rounded.Category, "分類", category?.name ?: "未分類"))
                        add(Triple(Icons.Rounded.CreditCard, "付款", methods.firstOrNull { it.id == s.paymentId }?.name ?: "未指定"))
                        if (s.note.isNotBlank()) add(Triple(Icons.Rounded.Notes, "備註", s.note))
                    },
                )
            }
        }
        viewing?.let { i ->
            if (i in photos.indices) PhotoViewer(photos, i, onClose = { viewing = null }, onType = { _, _ -> }, onDelete = {}, onSave = onSavePhoto, editable = false)
        }
    }
}

/** Everything the plan view can ask for; defaults keep previews and snapshots short. */
data class PlanViewActions(
    val back: () -> Unit = {},
    val edit: () -> Unit = {},
    val delete: () -> Unit = {},
    val setStatus: (String) -> Unit = {},
    val record: () -> Unit = {},
    val openMap: (PlanItem) -> Unit = {},
    val openExpense: (Long) -> Unit = {},
    val split: (List<PlanItem>) -> Unit = {},
)

/**
 * One plan item, to read: tapping a plan opens this, not the editor. Editing and deleting are the two icons
 * at the top right ([canEdit] false on someone else's shared trip); the day's actions are the buttons below.
 */
@Composable
fun PlanViewScreen(
    item: PlanItem?,
    trip: Trip?,
    categories: List<Category>,
    expenses: List<ExpenseRow>,
    canEdit: Boolean,
    actions: PlanViewActions,
    pictures: List<String> = emptyList(),
) {
    var confirmDelete by remember { mutableStateOf(false) }
    var viewing by remember { mutableStateOf<Int?>(null) }
    var splitting by remember { mutableStateOf(false) }
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            AppTopBar(
                "行程", subtitle = trip?.name, onBack = actions.back,
                actions = {
                    if (canEdit && item != null) {
                        IconButton(actions.edit) { Icon(Icons.Rounded.Edit, "編輯") }
                        IconButton({ confirmDelete = true }) { Icon(Icons.Rounded.DeleteOutline, "刪除") }
                    }
                },
            )
        },
    ) { pad ->
        val p = item ?: return@Scaffold
        val t = trip ?: return@Scaffold
        val category = categories.firstOrNull { it.id == p.categoryId }
        val style = categoryStyle(category?.name, category?.icon, category?.color)
        val done = p.status == PlanStatus.DONE
        Column(
            Modifier.padding(pad).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            LedgerCard(Modifier.fillMaxWidth()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconTile(style.icon, style.color, size = 48.dp, corner = 14.dp)
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        Text(p.title, style = MaterialTheme.typography.titleLarge)
                        Text(
                            (p.date?.let { "Day ${it - t.startDate + 1} · ${fmtShortDate(it)}" } ?: "待排") + (p.minuteOfDay?.let { " · ${fmtTime(it)}" } ?: ""),
                            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            listOfNotNull(
                                category?.name ?: "未分類",
                                when (p.status) { PlanStatus.DONE -> "已去"; PlanStatus.SKIPPED -> "跳過"; else -> "未去" },
                                p.addedBy?.let { "$it 補充" },
                                "我的補充".takeIf { p.pending },
                            ).joinToString(" · "),
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            val spent = expenses.sumOf { it.homeAmount }
            val lines = buildList {
                when (p.reservation) {
                    Reservation.NEEDED -> add(Triple(Icons.Rounded.EventSeat, "訂位", "需要訂位" + p.reservationNote.let { if (it.isBlank()) "" else "\n$it" }))
                    Reservation.BOOKED -> add(Triple(Icons.Rounded.EventSeat, "訂位", "已訂好" + p.reservationNote.let { if (it.isBlank()) "" else "\n$it" }))
                }
                if (p.location.isNotBlank()) add(Triple(Icons.Rounded.Place, "地點", p.location))
                if (spent > 0) add(Triple(Icons.Rounded.ReceiptLong, "已花", fmtMoney(spent)))
            }
            if (lines.isNotEmpty()) DetailCard(lines)

            if (p.note.isNotBlank()) {
                LedgerCard(Modifier.fillMaxWidth(), padding = PaddingValues(14.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.Notes, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.width(8.dp))
                        Text("筆記", style = MaterialTheme.typography.titleSmall)
                    }
                    Spacer(Modifier.height(6.dp))
                    LinkText(p.note)
                    if (canEdit && p.note.lines().count { it.isNotBlank() } >= 2) {
                        Spacer(Modifier.height(10.dp))
                        OutlinedButton({ splitting = true }, Modifier.fillMaxWidth().heightIn(min = 46.dp), shape = RoundedCornerShape(14.dp)) {
                            Icon(Icons.Rounded.CallSplit, null)
                            Spacer(Modifier.width(6.dp))
                            Text("把筆記拆成多個行程")
                        }
                    }
                }
            }

            if (pictures.isNotEmpty()) PictureStrip(pictures, onOpen = { viewing = it })

            if (expenses.isNotEmpty()) {
                SectionHeader("為這個行程記的帳")
                LedgerCard(Modifier.fillMaxWidth(), padding = PaddingValues(0.dp)) {
                    expenses.forEachIndexed { i, e ->
                        if (i > 0) HorizontalDivider(Modifier.padding(start = 66.dp), color = ledger.hairline)
                        ExpenseRowItem(e) { actions.openExpense(e.id) }
                    }
                }
            }

            Button(actions.record, Modifier.fillMaxWidth().heightIn(min = 52.dp), shape = RoundedCornerShape(14.dp)) {
                Icon(Icons.Rounded.AddCard, null)
                Spacer(Modifier.width(8.dp))
                Text("為這個行程記一筆")
            }
            // Side by side when both labels fit; stacked when the text is large.
            val statusLabel = if (done) "改回未去" else "標記已去"
            val buttons = buildList {
                if (canEdit) add(Triple(statusLabel, if (done) Icons.Rounded.Undo else Icons.Rounded.CheckCircle) { actions.setStatus(if (done) PlanStatus.TODO else PlanStatus.DONE) })
                add(Triple("導航", Icons.Rounded.Directions) { actions.openMap(p) })
            }
            val measurer = rememberTextMeasurer()
            val labelStyle = MaterialTheme.typography.labelLarge
            val density = LocalDensity.current
            BoxWithConstraints(Modifier.fillMaxWidth()) {
                val widest = buttons.maxOf { with(density) { measurer.measure(it.first, labelStyle).size.width.toDp() } } + 24.dp + 6.dp + 48.dp
                val sideBySide = widest * buttons.size + 10.dp * (buttons.size - 1) <= maxWidth
                val button: @Composable (Triple<String, ImageVector, () -> Unit>, Modifier) -> Unit = { (label, icon, onClick), m ->
                    FilledTonalButton(onClick, m.heightIn(min = 50.dp), shape = RoundedCornerShape(14.dp)) {
                        Icon(icon, null)
                        Spacer(Modifier.width(6.dp))
                        Text(label, softWrap = false)
                    }
                }
                if (sideBySide) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) { buttons.forEach { button(it, Modifier.weight(1f)) } }
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) { buttons.forEach { button(it, Modifier.fillMaxWidth()) } }
                }
            }
        }

        if (splitting) {
            SplitNoteDialog(p, categories, onDismiss = { splitting = false }) { items ->
                splitting = false
                actions.split(items)
            }
        }
        viewing?.let { i ->
            if (i in pictures.indices) {
                val context = androidx.compose.ui.platform.LocalContext.current
                val scope = rememberCoroutineScope()
                PhotoViewer(
                    pictures.map { PhotoItem(null, it, com.archiekuo.travelledger.data.PhotoType.MEMORY) }, i,
                    onClose = { viewing = null }, onType = { _, _ -> }, onDelete = {}, editable = false,
                    onSave = { k ->
                        val path = pictures.getOrNull(k) ?: return@PhotoViewer
                        scope.launch {
                            val ok = com.archiekuo.travelledger.photo.PhotoProcessor.saveToGallery(context, android.net.Uri.fromFile(java.io.File(path)))
                            android.widget.Toast.makeText(context, if (ok) "已存到相簿" else "存檔失敗", android.widget.Toast.LENGTH_SHORT).show()
                        }
                    },
                )
            }
        }
        if (confirmDelete) {
            AlertDialog(
                onDismissRequest = { confirmDelete = false },
                icon = { Icon(Icons.Rounded.DeleteOutline, null) },
                title = { Text("刪除「${p.title}」?") },
                text = { Text("已記的支出會保留,只是不再連到這個行程。") },
                confirmButton = { TextButton({ confirmDelete = false; actions.delete() }) { Text("刪除", color = MaterialTheme.colorScheme.error) } },
                dismissButton = { TextButton({ confirmDelete = false }) { Text("取消") } },
            )
        }
    }
}
