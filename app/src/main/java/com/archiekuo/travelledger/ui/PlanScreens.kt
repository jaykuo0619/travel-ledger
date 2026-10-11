@file:OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)

package com.archiekuo.travelledger.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import com.archiekuo.travelledger.data.Category
import com.archiekuo.travelledger.data.ExpenseRow
import com.archiekuo.travelledger.data.PlanItem
import com.archiekuo.travelledger.data.PlanRow
import com.archiekuo.travelledger.data.PlanStatus
import com.archiekuo.travelledger.data.Reservation
import com.archiekuo.travelledger.data.Trip
import com.archiekuo.travelledger.data.UNSCHEDULED_DAY
import java.time.LocalDate
import com.archiekuo.travelledger.logic.PlanParser

// ───────────────────────────── Today ─────────────────────────────

@Composable
fun TodayTab(
    trip: Trip,
    plans: List<PlanRow>,
    expenses: List<ExpenseRow>,
    today: LocalDate,
    pad: PaddingValues,
    actions: TripActions,
    onTab: (TripTab) -> Unit,
) {
    val t = today.toEpochDay()
    LazyColumn(
        Modifier.padding(pad).fillMaxSize(),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 40.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        actions.dayNotes[t]?.let { note -> item { DayNoteCard(note, startOpen = true, canEdit = !actions.readOnly) { actions.editDayNote(t) } } }
        when {
            t < trip.startDate -> beforeTrip(trip, plans, expenses, t, actions, onTab)
            t > trip.endDate -> afterTrip(trip, plans, expenses, onTab, actions)
            else -> onTrip(trip, plans, expenses, t, actions)
        }
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.onTrip(
    trip: Trip, plans: List<PlanRow>, expenses: List<ExpenseRow>, t: Long, actions: TripActions,
) {
    val todays = plans.filter { it.date == t }
    val spent = expenses.filter { it.date == t }
    val done = todays.count { it.status == PlanStatus.DONE }
    item {
        LedgerCard(Modifier.fillMaxWidth(), padding = PaddingValues(horizontal = 18.dp, vertical = 16.dp)) {
            Text("第 ${t - trip.startDate + 1} 天 · ${fmtDayHeader(t)}", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.Bottom) {
                Column(Modifier.weight(1f)) {
                    Text("今天已花", style = CaptionStyle, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(fmtMoney(spent.sumOf { it.homeAmount }), style = MaterialTheme.typography.headlineMedium, color = MaterialTheme.colorScheme.primary)
                }
                if (todays.isNotEmpty()) {
                    Column(horizontalAlignment = Alignment.End) {
                        Text("行程", style = CaptionStyle, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text("$done / ${todays.size} 完成", style = MaterialTheme.typography.titleMedium)
                    }
                }
            }
        }
    }
    item { SectionHeader("今天的行程") { SmallAdd("新增") { actions.addPlan(t) } } }
    if (todays.isEmpty()) {
        item { Text("今天還沒有安排,可以從「行程」的待排清單排進來。", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    } else {
        item { PlanCard(todays, trip, showDate = false, withActions = true, actions = actions) }
    }
    val missed = plans.filter { it.date != null && it.date < t && it.date >= trip.startDate && it.status == PlanStatus.TODO }
    if (missed.isNotEmpty()) {
        item {
            SectionHeader("之前沒去的 · ${missed.size} 項") {
                if (!actions.readOnly) SmallAdd("全部移到今天", Icons.Rounded.Redo) { actions.movePlans(missed.map { it.id }, t) }
            }
        }
        item { PlanCard(missed, trip, showDate = true, withActions = false, actions = actions) }
    }
    item { SectionHeader("今天的支出") }
    if (spent.isEmpty()) {
        item { Text("還沒有支出", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    } else {
        item {
            LedgerCard(Modifier.fillMaxWidth(), padding = PaddingValues(vertical = 2.dp)) {
                spent.forEachIndexed { i, e ->
                    if (i > 0) HorizontalDivider(Modifier.padding(start = 66.dp), color = ledger.hairline)
                    ExpenseRowItem(e) { actions.openExpense(e.id) }
                }
            }
        }
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.beforeTrip(
    trip: Trip, plans: List<PlanRow>, expenses: List<ExpenseRow>, t: Long, actions: TripActions, onTab: (TripTab) -> Unit,
) {
    val needBooking = plans.filter { it.reservation == Reservation.NEEDED && it.status == PlanStatus.TODO }
    val unscheduled = plans.count { it.date == null }
    item {
        LedgerCard(Modifier.fillMaxWidth(), padding = PaddingValues(horizontal = 18.dp, vertical = 18.dp)) {
            Text("出發倒數", style = CaptionStyle, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Row(verticalAlignment = Alignment.Bottom) {
                Text("${trip.startDate - t}", style = MaterialTheme.typography.displaySmall, color = MaterialTheme.colorScheme.primary)
                Text(" 天", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(bottom = 4.dp))
            }
            Text(
                "${fmtShortDate(trip.startDate)} 出發 · 共 ${trip.endDate - trip.startDate + 1} 天",
                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            val prepaid = expenses.sumOf { it.homeAmount }
            if (prepaid > 0) {
                Spacer(Modifier.height(10.dp))
                Text("目前已付 ${fmtMoney(prepaid)}", style = MaterialTheme.typography.titleSmall)
            }
        }
    }
    item {
        LedgerCard(Modifier.fillMaxWidth(), onClick = { onTab(TripTab.PLAN) }, padding = PaddingValues(horizontal = 14.dp, vertical = 12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconTile(Icons.Rounded.Map, MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text("行程準備", style = MaterialTheme.typography.titleSmall)
                    Text(
                        if (plans.isEmpty()) "還沒有任何行程,把做好的功課放進來" else "已排 ${plans.size - unscheduled} 項 · 待排 $unscheduled 項",
                        style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Icon(Icons.Rounded.ChevronRight, null, tint = ledger.textMuted)
            }
        }
    }
    if (needBooking.isNotEmpty()) {
        item { SectionHeader("還沒訂位 · ${needBooking.size} 項") }
        item { PlanCard(needBooking, trip, showDate = true, withActions = false, actions = actions) }
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.afterTrip(
    trip: Trip, plans: List<PlanRow>, expenses: List<ExpenseRow>, onTab: (TripTab) -> Unit, actions: TripActions,
) {
    val visited = plans.count { it.status == PlanStatus.DONE }
    val missed = plans.filter { it.status != PlanStatus.DONE }
    item {
        LedgerCard(Modifier.fillMaxWidth(), onClick = { onTab(TripTab.STATS) }, padding = PaddingValues(horizontal = 18.dp, vertical = 18.dp)) {
            Text("旅程已結束", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(6.dp))
            Text(fmtMoney(expenses.sumOf { it.homeAmount }), style = MaterialTheme.typography.headlineMedium, color = MaterialTheme.colorScheme.primary)
            Text(
                "共 ${trip.endDate - trip.startDate + 1} 天 · ${expenses.size} 筆支出" + if (plans.isNotEmpty()) " · 去了 $visited 個地方" else "",
                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
    if (missed.isNotEmpty()) {
        item { SectionHeader("沒去成的 · ${missed.size} 項(下次的口袋名單)") }
        item { PlanCard(missed, trip, showDate = false, withActions = false, actions = actions) }
    }
}

// ───────────────────────────── Plan ─────────────────────────────

@Composable
fun PlanTab(trip: Trip, plans: List<PlanRow>, pad: PaddingValues, actions: TripActions) {
    var byType by rememberSaveable { mutableStateOf(false) }
    var pasting by remember { mutableStateOf(false) }
    val needBooking = plans.filter { it.reservation == Reservation.NEEDED && it.status == PlanStatus.TODO }
    LazyColumn(
        Modifier.padding(pad).fillMaxSize(),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 40.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Segmented(listOf("依天", "依類型"), if (byType) 1 else 0, Modifier.weight(1f)) { byType = it == 1 }
                IconButton({ pasting = true }) { Icon(Icons.Rounded.ContentPaste, "貼上多筆") }
                Button(
                    { actions.addPlan(null) }, shape = RoundedCornerShape(50),
                    contentPadding = PaddingValues(horizontal = 14.dp), modifier = Modifier.heightIn(min = 40.dp),
                ) {
                    Icon(Icons.Rounded.Add, null, Modifier.size(18.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("新增")
                }
            }
        }
        if (plans.isEmpty()) {
            item {
                Column(Modifier.fillMaxWidth().padding(vertical = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    IconTile(Icons.Rounded.Map, MaterialTheme.colorScheme.primary, size = 64.dp, corner = 20.dp)
                    Spacer(Modifier.height(12.dp))
                    Text(if (actions.readOnly) "對方還沒有安排行程" else "把出發前做的功課放進來", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(4.dp))
                    Text(
                        if (actions.readOnly) "你想去的地方可以先加進來,再按上方「傳給記帳人」。"
                        else "想去的景點、要訂位的餐廳都可以先放進「待排」,之後再排到某一天。\n在 Google 地圖按「分享 → 卡溜趴」也能直接加入。",
                        style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(16.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        OutlinedButton({ pasting = true }, shape = RoundedCornerShape(14.dp)) { Text("貼上多筆") }
                        Button({ actions.addPlan(null) }, shape = RoundedCornerShape(14.dp)) { Text("新增行程") }
                    }
                }
            }
            return@LazyColumn
        }
        if (needBooking.isNotEmpty()) {
            item {
                Row(
                    Modifier.fillMaxWidth().clip(MaterialTheme.shapes.medium).background(ledger.danger.copy(alpha = if (ledger.dark) 0.18f else 0.08f))
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Rounded.NotificationImportant, null, tint = ledger.danger)
                    Spacer(Modifier.width(10.dp))
                    Text(
                        "${needBooking.size} 項需要訂位:" + needBooking.joinToString("、") { it.title },
                        style = MaterialTheme.typography.bodyMedium, maxLines = 2, overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
        if (!byType) {
            val unscheduled = plans.filter { it.date == null }
            val looseNote = actions.dayNotes[UNSCHEDULED_DAY]
            if (unscheduled.isNotEmpty() || looseNote != null) {
                item { SectionHeader("待排 · ${unscheduled.size} 項") }
                looseNote?.let { n -> item { DayNoteCard(n, canEdit = !actions.readOnly) { actions.editDayNote(UNSCHEDULED_DAY) } } }
                if (unscheduled.isNotEmpty()) item { PlanCard(unscheduled, trip, showDate = false, withActions = false, actions = actions) }
            }
            for (day in trip.startDate..trip.endDate) {
                val rows = plans.filter { it.date == day }
                item(key = "d$day") {
                    Row(Modifier.fillMaxWidth().padding(start = 4.dp, top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("Day ${day - trip.startDate + 1}", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary, softWrap = false)
                        Text(
                            "  ${fmtShortDate(day)}", style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f),
                            maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis,
                        )
                        if (!actions.readOnly && actions.dayNotes[day] == null) {
                            IconButton({ actions.editDayNote(day) }, Modifier.size(40.dp)) {
                                Icon(Icons.Rounded.EditNote, "寫當日筆記", tint = MaterialTheme.colorScheme.primary)
                            }
                        }
                        SmallAdd("加入") { actions.addPlan(day) }
                    }
                }
                actions.dayNotes[day]?.let { n -> item(key = "n$day") { DayNoteCard(n, canEdit = !actions.readOnly) { actions.editDayNote(day) } } }
                item(key = "c$day") {
                    if (rows.isEmpty()) {
                        Text("還沒有安排", style = MaterialTheme.typography.bodyMedium, color = ledger.textMuted, modifier = Modifier.padding(start = 4.dp))
                    } else {
                        PlanCard(rows, trip, showDate = false, withActions = false, actions = actions)
                    }
                }
            }
            val outside = plans.filter { it.date != null && (it.date < trip.startDate || it.date > trip.endDate) }
            if (outside.isNotEmpty()) {
                item { SectionHeader("旅程日期以外") }
                item { PlanCard(outside, trip, showDate = true, withActions = false, actions = actions) }
            }
        } else {
            plans.groupBy { it.categoryName ?: "未分類" }.toList().sortedByDescending { it.second.size }.forEach { (name, rows) ->
                val style = categoryStyle(rows.first().categoryName, rows.first().categoryIcon, rows.first().categoryColor)
                item(key = "t$name") {
                    Row(Modifier.fillMaxWidth().padding(start = 4.dp, top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(style.icon, null, Modifier.size(20.dp), tint = style.color)
                        Spacer(Modifier.width(6.dp))
                        Text("$name · ${rows.size}", style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                        val pending = rows.count { it.reservation == Reservation.NEEDED && it.status == PlanStatus.TODO }
                        if (pending > 0) Text("$pending 項待訂位", style = MaterialTheme.typography.labelMedium, color = ledger.danger)
                    }
                }
                item(key = "l$name") { PlanCard(rows, trip, showDate = true, withActions = false, actions = actions) }
            }
        }
    }
    if (pasting) PasteDialog(onDismiss = { pasting = false }) { text -> actions.pastePlans(text, null); pasting = false }
}

@Composable
private fun SmallAdd(text: String, icon: ImageVector = Icons.Rounded.Add, onClick: () -> Unit) {
    Row(
        Modifier.clip(RoundedCornerShape(50)).clickable(onClick = onClick).padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.width(4.dp))
        Text(text, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
    }
}

@Composable
fun Segmented(options: List<String>, selected: Int, modifier: Modifier = Modifier, onSelect: (Int) -> Unit) {
    Row(modifier.clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surfaceVariant).padding(3.dp)) {
        options.forEachIndexed { i, o ->
            val on = i == selected
            Box(
                Modifier.weight(1f).clip(RoundedCornerShape(10.dp))
                    .background(if (on) MaterialTheme.colorScheme.surfaceContainerLowest else Color.Transparent)
                    .clickable { onSelect(i) }.padding(vertical = 8.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(o, style = MaterialTheme.typography.labelLarge, color = if (on) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun PlanCard(rows: List<PlanRow>, trip: Trip, showDate: Boolean, withActions: Boolean, actions: TripActions) {
    LedgerCard(Modifier.fillMaxWidth(), padding = PaddingValues(vertical = 2.dp)) {
        rows.forEachIndexed { i, p ->
            if (i > 0) HorizontalDivider(Modifier.padding(start = 60.dp), color = ledger.hairline)
            PlanRowItem(p, trip, showDate, withActions, actions)
        }
    }
}

@Composable
private fun PlanRowItem(p: PlanRow, trip: Trip, showDate: Boolean, withActions: Boolean, actions: TripActions) {
    val style = categoryStyle(p.categoryName, p.categoryIcon, p.categoryColor)
    val done = p.status == PlanStatus.DONE
    val skipped = p.status == PlanStatus.SKIPPED
    Row(
        Modifier.fillMaxWidth().clickable { actions.openPlan(p.id) }.padding(start = 8.dp, end = 6.dp, top = 9.dp, bottom = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Status: tap toggles done.
        Box(
            Modifier.size(44.dp).clip(CircleShape).clickable(enabled = !actions.readOnly || p.pending) {
                actions.setPlanStatus(p.id, if (done) PlanStatus.TODO else PlanStatus.DONE)
            },
            contentAlignment = Alignment.Center,
        ) {
            when {
                done -> Box(Modifier.size(26.dp).clip(CircleShape).background(ledger.success), contentAlignment = Alignment.Center) {
                    Icon(Icons.Rounded.Check, "已去", Modifier.size(18.dp), tint = Color.White)
                }
                skipped -> Icon(Icons.Rounded.RemoveCircleOutline, "跳過", Modifier.size(26.dp), tint = ledger.textMuted)
                else -> Box(Modifier.size(24.dp).clip(CircleShape).border(2.dp, style.color, CircleShape))
            }
        }
        Spacer(Modifier.width(4.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                p.minuteOfDay?.let {
                    Text(fmtTime(it), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.width(8.dp))
                }
                Icon(style.icon, null, Modifier.size(18.dp), tint = style.color)
                Spacer(Modifier.width(6.dp))
                Text(
                    p.title,
                    style = MaterialTheme.typography.bodyLarge.copy(
                        fontWeight = FontWeight.Medium,
                        textDecoration = if (skipped) TextDecoration.LineThrough else null,
                    ),
                    color = if (done || skipped) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
            }
            val tags = buildList {
                if (showDate) add((p.date?.let { "Day ${it - trip.startDate + 1} ${fmtShortDate(it)}" } ?: "待排") to MaterialTheme.colorScheme.onSurfaceVariant)
                when (p.reservation) {
                    Reservation.NEEDED -> add("需訂位" to ledger.danger)
                    Reservation.BOOKED -> add(("已訂" + p.reservationNote.takeIf { it.isNotBlank() }?.let { " $it" }.orEmpty()) to ledger.success)
                }
                if (p.pending) add("我的補充" to ledger.warning)
                p.addedBy?.let { add("$it 補充" to ledger.warning) }
                if (p.spent > 0) add("已花 ${fmtMoney(p.spent)}" to MaterialTheme.colorScheme.primary)
                if (p.photoCount > 0) add("圖 ${p.photoCount}" to MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (tags.isNotEmpty()) {
                Row(Modifier.padding(top = 3.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    tags.forEach { (text, color) -> Tag(text, color) }
                }
            }
        }
        if (withActions) {
            if (p.location.isNotBlank()) {
                IconButton({ actions.openMap(p) }) { Icon(Icons.Rounded.Directions, "導航", tint = MaterialTheme.colorScheme.primary) }
            }
            IconButton({ actions.addExpense(p.id) }) { Icon(Icons.Rounded.AddCard, "記一筆", tint = MaterialTheme.colorScheme.primary) }
        }
    }
}

@Composable
private fun Tag(text: String, color: Color) {
    Text(
        text,
        Modifier.clip(RoundedCornerShape(6.dp)).background(color.copy(alpha = if (ledger.dark) 0.2f else 0.1f)).padding(horizontal = 6.dp, vertical = 1.dp),
        style = MaterialTheme.typography.labelMedium, color = color, maxLines = 1,
    )
}

@Composable
internal fun PasteDialog(onDismiss: () -> Unit, onAdd: (String) -> Unit) {
    var text by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("貼上多筆") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("一行一個地點,會加到「待排」,並自動猜分類。", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                OutlinedTextField(
                    text, { text = it }, Modifier.fillMaxWidth().heightIn(min = 180.dp),
                    placeholder = { Text("一蘭拉麵 本店\n淺草寺\n晴空塔\n敘敘苑 燒肉") },
                    shape = MaterialTheme.shapes.medium,
                )
            }
        },
        confirmButton = { TextButton({ onAdd(text) }, enabled = text.isNotBlank()) { Text("加入待排") } },
        dismissButton = { TextButton(onDismiss) { Text("取消") } },
    )
}

// ───────────────────────────── Plan editor ─────────────────────────────

data class PlanActions(
    val edit: ((PlanItem) -> PlanItem) -> Unit = {},
    val save: () -> Unit = {},
    val delete: () -> Unit = {},
    val back: () -> Unit = {},
    val record: () -> Unit = {},
    val openMap: (PlanItem) -> Unit = {},
    val addPictures: () -> Unit = {},
    val removePicture: (Int) -> Unit = {},
)

@Composable
fun PlanEditScreen(
    item: PlanItem?, trip: Trip?, categories: List<Category>, isNew: Boolean, actions: PlanActions,
    pictures: List<PlanPicture> = emptyList(),
    addingPictures: Boolean = false,
) {
    var pickTime by remember { mutableStateOf(false) }
    // Saving needs a name: ✓ always answers, pointing at the name when it is missing.
    var nameMissing by remember { mutableStateOf(false) }
    val nameFocus = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    val hasName = item?.title?.isNotBlank() == true
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            AppTopBar(
                if (isNew) "新增行程" else "編輯行程", subtitle = trip?.name, onBack = actions.back, closeIcon = true,
                actions = {
                    ConfirmButton(item != null, ready = hasName) {
                        if (hasName) actions.save()
                        else { nameMissing = true; runCatching { nameFocus.requestFocus() }; keyboard?.show() }
                    }
                },
            )
        },
    ) { pad ->
        val p = item ?: return@Scaffold
        val t = trip ?: return@Scaffold
        Column(
            Modifier.padding(pad).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            TitleField(p.title, "景點、餐廳或活動名稱", error = nameMissing && p.title.isBlank(), focusRequester = nameFocus) { v ->
                actions.edit { it.copy(title = v) }
            }
            if (nameMissing && p.title.isBlank()) {
                Text("請輸入名稱才能儲存", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(start = 6.dp))
            }
            CategoryRow(categories, p.categoryId) { id -> actions.edit { it.copy(categoryId = id) } }

            SectionHeader("哪一天") {
                SmallAdd(p.minuteOfDay?.let { "時間 ${fmtTime(it)}" } ?: "加時間", Icons.Rounded.Schedule) { pickTime = true }
            }
            DayGrid(t, p.date) { d -> actions.edit { it.copy(date = d) } }

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (!isNew) {
                    val statuses = listOf(PlanStatus.TODO, PlanStatus.DONE, PlanStatus.SKIPPED)
                    ChoiceChip(
                        listOf("未去", "已去", "跳過"), statuses.indexOf(p.status).coerceAtLeast(0),
                        listOf(Icons.Rounded.RadioButtonUnchecked, Icons.Rounded.CheckCircle, Icons.Rounded.RemoveCircleOutline),
                        Modifier.weight(1f),
                    ) { i -> actions.edit { it.copy(status = statuses[i]) } }
                }
                val res = listOf(Reservation.NONE, Reservation.NEEDED, Reservation.BOOKED)
                ChoiceChip(
                    listOf("不用訂位", "需要訂位", "已訂好"), res.indexOf(p.reservation).coerceAtLeast(0),
                    listOf(Icons.Rounded.EventBusy, Icons.Rounded.NotificationImportant, Icons.Rounded.EventAvailable),
                    Modifier.weight(1f),
                ) { i -> actions.edit { it.copy(reservation = res[i]) } }
            }
            if (p.reservation != Reservation.NONE) {
                FieldBox("訂位資訊") { LinkAwareInput(p.reservationNote, { v -> actions.edit { it.copy(reservationNote = v) } }, "例如:19:00 · 4 位 · 確認碼 AB123", singleLine = false) }
                LinkButtons(p.reservationNote)
            }

            FieldBox(
                "地點",
                trailing = {
                    IconButton({ actions.openMap(p) }, enabled = p.title.isNotBlank() || p.location.isNotBlank()) {
                        Icon(Icons.Rounded.Map, "在地圖開啟", tint = MaterialTheme.colorScheme.primary)
                    }
                },
            ) { LinkAwareInput(p.location, { v -> actions.edit { it.copy(location = v) } }, "地址或 Google 地圖連結", singleLine = false) }
            LinkButtons(p.location)

            FieldBox("筆記") {
                LinkAwareInput(p.note, { v -> actions.edit { it.copy(note = v) } }, "必點菜色、營業時間、注意事項…", singleLine = false, minLines = 2)
            }
            LinkButtons(p.note)

            PictureStrip(pictures.map { it.path }, onRemove = actions.removePicture, onAdd = actions.addPictures.takeIf { pictures.size < MAX_PLAN_PICTURES }, busy = addingPictures)


        }
        if (pickTime) {
            val m = p.minuteOfDay ?: 12 * 60
            val st = rememberTimePickerState(m / 60, m % 60, is24Hour = true)
            AlertDialog(
                onDismissRequest = { pickTime = false },
                title = { Text("時間") },
                text = { TimePicker(st) },
                confirmButton = { TextButton({ actions.edit { it.copy(minuteOfDay = st.hour * 60 + st.minute) }; pickTime = false }) { Text("確定") } },
                dismissButton = { TextButton({ actions.edit { it.copy(minuteOfDay = null) }; pickTime = false }) { Text("不指定時間") } },
            )
        }
    }
}

/**
 * Which day: one row of square tiles (date, weekday underneath) that scrolls sideways.
 * Tiles are sized so three to five fit on screen, depending on the text size; the chosen day is scrolled into view.
 */
@Composable
private fun DayGrid(trip: Trip, selected: Long?, onSelect: (Long?) -> Unit) {
    val measurer = rememberTextMeasurer()
    val dateStyle = MaterialTheme.typography.titleMedium
    val density = LocalDensity.current
    val needed = with(density) { measurer.measure("10/28", dateStyle).size.width.toDp() } + 16.dp
    val days = remember(trip.startDate, trip.endDate) { listOf<Long?>(null) + (trip.startDate..trip.endDate).toList() }
    val state = rememberLazyListState(initialFirstVisibleItemIndex = (days.indexOf(selected) - 1).coerceAtLeast(0))
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val gap = 8.dp
        // Fit whole tiles plus a peek of the next one, so it is clear the row scrolls.
        val cols = ((maxWidth + gap) / (needed + gap)).toInt().coerceIn(3, 5)
        val tile = if (days.size > cols) (maxWidth - gap * cols) / (cols + 0.4f) else (maxWidth - gap * (cols - 1)) / cols
        LazyRow(state = state, horizontalArrangement = Arrangement.spacedBy(gap)) {
            items(days) { d ->
                val date = d?.let { LocalDate.ofEpochDay(it) }
                DayTile(
                    top = date?.let { "${it.monthValue}/${it.dayOfMonth}" } ?: "待排",
                    bottom = date?.let { weekday(it) } ?: "未定",
                    selected = selected == d, size = tile, style = dateStyle,
                ) { onSelect(d) }
            }
        }
    }
}

@Composable
private fun DayTile(top: String, bottom: String, selected: Boolean, size: Dp, style: TextStyle, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(14.dp)
    Column(
        Modifier.width(size).heightIn(min = size).clip(shape)
            .background(if (selected) cs.primary else cs.surfaceContainerLowest)
            .border(1.dp, if (selected) cs.primary else ledger.hairline, shape)
            .clickable(onClick = onClick).padding(vertical = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
    ) {
        Text(top, style = style, color = if (selected) cs.onPrimary else cs.onSurface, maxLines = 1, softWrap = false)
        Text(bottom, style = MaterialTheme.typography.labelMedium, color = if (selected) cs.onPrimary.copy(alpha = 0.85f) else cs.onSurfaceVariant, maxLines = 1, softWrap = false)
    }
}

/** One compact choice: shows the current option, tap for a menu of all of them. */
@Composable
private fun ChoiceChip(options: List<String>, selected: Int, icons: List<ImageVector>, modifier: Modifier, onSelect: (Int) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val cs = MaterialTheme.colorScheme
    Box(modifier) {
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(cs.surfaceContainerLowest)
                .border(1.dp, ledger.hairline, RoundedCornerShape(14.dp)).clickable { open = true }
                .padding(horizontal = 12.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(icons[selected], null, Modifier.size(20.dp), tint = cs.primary)
            Spacer(Modifier.width(8.dp))
            Text(options[selected], style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f), maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis)
            Icon(Icons.Rounded.ArrowDropDown, null, tint = cs.onSurfaceVariant)
        }
        DropdownMenu(open, { open = false }) {
            options.forEachIndexed { i, o ->
                DropdownMenuItem(text = { Text(o) }, leadingIcon = { Icon(icons[i], null) }, onClick = { open = false; onSelect(i) })
            }
        }
    }
}

/**
 * Preview of a note split into plan items: every line is listed (nothing is silently dropped), with the guessed
 * time and category. Untick lines that are not places, tap a category to change it.
 */
@Composable
fun SplitNoteDialog(source: PlanItem, categories: List<Category>, onDismiss: () -> Unit, onCreate: (List<PlanItem>) -> Unit) {
    val parsed = remember(source.note) { PlanParser.splitNote(source.note) }
    val byName = categories.associateBy { it.name }
    val chosen = remember(source.note) { mutableStateListOf(*Array(parsed.size) { true }) }
    val cats = remember(source.note) { mutableStateListOf(*parsed.map { p -> p.categoryHint?.let { byName[it]?.id } }.toTypedArray()) }
    var menuFor by remember { mutableStateOf<Int?>(null) }
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = { Icon(Icons.Rounded.CallSplit, null) },
        title = { Text("拆成 ${chosen.count { it }} 個行程") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    "每一行一個行程,排在" + (source.date?.let { " ${fmtShortDate(it)} " } ?: "「待排」") + "。不是地點的行取消勾選;分類猜錯點一下改。",
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                parsed.forEachIndexed { i, item ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(chosen[i], { chosen[i] = it })
                        Column(Modifier.weight(1f)) {
                            Text(item.title, style = MaterialTheme.typography.bodyLarge)
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                item.minuteOfDay?.let {
                                    Text(fmtTime(it), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                                    Spacer(Modifier.width(8.dp))
                                }
                                val cat = categories.firstOrNull { it.id == cats[i] }
                                Box {
                                    Text(
                                        (cat?.name ?: "未分類") + " ▾",
                                        style = MaterialTheme.typography.labelLarge,
                                        color = if (cat == null) ledger.warning else MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable { menuFor = i }.padding(horizontal = 4.dp, vertical = 2.dp),
                                    )
                                    DropdownMenu(menuFor == i, { menuFor = null }) {
                                        categories.forEach { c ->
                                            DropdownMenuItem(text = { Text(c.name) }, onClick = { cats[i] = c.id; menuFor = null })
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Spacer(Modifier.height(6.dp))
                Text(
                    if (source.pending) "原本的「${source.title}」會保留。"
                    else "原本的「${source.title}」整段筆記會移到" + (source.date?.let { " ${fmtShortDate(it)} " } ?: "「待排」") +
                        "的「當日筆記」,方便對照;拆完也可以按「復原」。",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        confirmButton = {
            TextButton(
                {
                    val items = parsed.indices.filter { chosen[it] }.map { i ->
                        val p = parsed[i]
                        PlanItem(
                            tripId = source.tripId, title = p.title, categoryId = cats[i], date = source.date,
                            minuteOfDay = p.minuteOfDay, location = p.location, pending = source.pending,
                        )
                    }
                    onCreate(items)
                },
                enabled = chosen.any { it },
            ) { Text("建立") }
        },
        dismissButton = { TextButton(onDismiss) { Text("取消") } },
    )
}

/**
 * A day's note under its heading: one line until tapped, then the whole text (links tappable) and a pencil.
 * Long notes moved here when a plan item was split stay readable for comparing.
 */
@Composable
fun DayNoteCard(text: String, startOpen: Boolean = false, canEdit: Boolean, onEdit: () -> Unit) {
    var open by rememberSaveable(text) { mutableStateOf(startOpen || text.lines().size <= 2) }
    val cs = MaterialTheme.colorScheme
    Column(
        Modifier.fillMaxWidth().clip(MaterialTheme.shapes.medium).background(ledger.warning.copy(alpha = if (ledger.dark) 0.14f else 0.09f))
            .clickable { open = !open }.padding(start = 14.dp, end = 4.dp, top = 8.dp, bottom = 8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.EditNote, null, Modifier.size(20.dp), tint = ledger.warning)
            Spacer(Modifier.width(8.dp))
            Text(
                if (open) "當日筆記" else "當日筆記 · " + text.lineSequence().first { it.isNotBlank() }.trim(),
                style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
            )
            if (canEdit) IconButton(onEdit, Modifier.size(40.dp)) { Icon(Icons.Rounded.Edit, "編輯當日筆記", Modifier.size(18.dp), tint = cs.onSurfaceVariant) }
            Icon(if (open) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore, if (open) "收起" else "展開", tint = cs.onSurfaceVariant)
            Spacer(Modifier.width(6.dp))
        }
        if (open) {
            LinkText(text, Modifier.padding(top = 4.dp, end = 10.dp), style = MaterialTheme.typography.bodyMedium.copy(color = cs.onSurface))
        }
    }
}

/** Writing a day's note; clearing the text removes it. */
@Composable
fun DayNoteDialog(title: String, initial: String, onDismiss: () -> Unit, onSave: (String) -> Unit) {
    var text by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            OutlinedTextField(
                text, { text = it }, Modifier.fillMaxWidth().heightIn(min = 160.dp),
                placeholder = { Text("例如:今天早點出門、記得帶護照…") }, shape = MaterialTheme.shapes.medium,
            )
        },
        confirmButton = { TextButton({ onSave(text) }) { Text("儲存") } },
        dismissButton = { TextButton(onDismiss) { Text("取消") } },
    )
}

/**
 * Pictures on a plan item (menu, opening hours, a route screenshot): thumbnails in a row, with an add tile in
 * the editor ([onAdd]) and a remove badge ([onRemove]); [onOpen] views one full screen.
 */
@Composable
fun PictureStrip(
    paths: List<String>,
    onRemove: ((Int) -> Unit)? = null,
    onAdd: (() -> Unit)? = null,
    onOpen: (Int) -> Unit = {},
    busy: Boolean = false,
) {
    if (paths.isEmpty() && onAdd == null) return
    val cs = MaterialTheme.colorScheme
    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items(paths.size) { i ->
            Box(Modifier.size(88.dp).clip(RoundedCornerShape(12.dp)).background(cs.surfaceVariant).clickable { onOpen(i) }) {
                val img by rememberLocalImage(paths[i], targetPx = 300)
                img?.let { androidx.compose.foundation.Image(it, null, Modifier.matchParentSize(), contentScale = androidx.compose.ui.layout.ContentScale.Crop) }
                if (onRemove != null) {
                    Box(
                        Modifier.align(Alignment.TopEnd).padding(4.dp).size(26.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.55f))
                            .clickable { onRemove(i) },
                        contentAlignment = Alignment.Center,
                    ) { Icon(Icons.Rounded.Close, "移除圖片", Modifier.size(16.dp), tint = Color.White) }
                }
            }
        }
        if (onAdd != null) {
            item {
                Column(
                    Modifier.size(88.dp).clip(RoundedCornerShape(12.dp)).border(1.dp, ledger.hairline, RoundedCornerShape(12.dp))
                        .clickable(enabled = !busy, onClick = onAdd),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                ) {
                    if (busy) CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                    else Icon(Icons.Rounded.AddPhotoAlternate, null, tint = cs.primary)
                    Text("截圖/圖片", style = MaterialTheme.typography.labelMedium, color = cs.primary, maxLines = 1, softWrap = false)
                }
            }
        }
    }
}

/** Large single-line title input used at the top of editors. */
@Composable
fun TitleField(value: String, placeholder: String, error: Boolean = false, focusRequester: FocusRequester? = null, onChange: (String) -> Unit) {
    // Plan names are often whole sentences ("搭乘 01A 循環公車到南大門市場站…"): one line until it needs a second, Enter allowed.
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    val cs = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(16.dp)
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).clip(shape).background(cs.surfaceContainerLowest)
            .border(if (focused || error) 1.5.dp else 1.dp, if (error) cs.error else if (focused) cs.primary else ledger.hairline, shape)
            .padding(start = 14.dp, end = 4.dp, top = 6.dp, bottom = 6.dp),
        verticalAlignment = Alignment.Top,
    ) {
        val style = MaterialTheme.typography.titleMedium.copy(color = cs.onSurface)
        BasicTextField(
            value, onChange, Modifier.weight(1f).padding(top = 8.dp, bottom = 8.dp).then(focusRequester?.let { Modifier.focusRequester(it) } ?: Modifier),
            minLines = 1, maxLines = 2, textStyle = style,
            cursorBrush = SolidColor(cs.primary), interactionSource = interaction,
            decorationBox = { inner ->
                if (value.isEmpty()) Text(placeholder, style = style.copy(fontWeight = FontWeight.Normal), color = ledger.textMuted)
                inner()
            },
        )
        if (value.isNotEmpty()) {
            IconButton({ onChange("") }, Modifier.size(40.dp)) { Icon(Icons.Rounded.Cancel, "清除", Modifier.size(20.dp), tint = ledger.textMuted) }
        }
    }
}
