package com.archiekuo.travelledger.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.junit4.ComposeContentTestRule
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import com.archiekuo.travelledger.backup.TripArchive
import com.archiekuo.travelledger.data.Category
import com.archiekuo.travelledger.data.ExpenseRow
import com.archiekuo.travelledger.data.PaymentMethod
import com.archiekuo.travelledger.data.PlanItem
import com.archiekuo.travelledger.data.PlanRow
import com.archiekuo.travelledger.data.PlanStatus
import com.archiekuo.travelledger.data.Reservation
import com.archiekuo.travelledger.data.Trip
import com.archiekuo.travelledger.data.TripCurrencyRate
import com.archiekuo.travelledger.data.TripSummary
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.time.LocalDate

/**
 * Every screen at the largest text (system font enlarged + the app's 特大) on a narrow phone:
 * no text may end up stacked a character or two per line, and no number or word may be split across lines
 * (like "2026/10/2" / "2 –" or "K" / "R" / "W").
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w360dp-h2400dp-xxhdpi", fontScale = 1.5f)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class NoVerticalTextTest {
    @get:Rule val rule = createComposeRule()

    private val today = LocalDate.of(2026, 10, 10)
    private fun d(m: Int, day: Int) = LocalDate.of(2026, m, day).toEpochDay()

    private val trips = listOf(
        TripSummary(1, "韓國賞楓", d(10, 22), d(10, 27), null, null, "AUTUMN", 100.0, 2, "KRW"),
        TripSummary(2, "2026首爾賞楓五天四夜自由行", d(10, 22), d(10, 27), 60000.0, null, null, 6498.0, 4, "KRW,JPY,USD"),
        TripSummary(3, "沖繩夏日跳島", d(7, 20), d(7, 24), 30000.0, null, null, 126450.0, 2, "JPY", sharedBy = "阿姨"),
        TripSummary(4, "大阪親子遊", LocalDate.of(2023, 12, 20).toEpochDay(), LocalDate.of(2024, 1, 2).toEpochDay(), null, null, null, 52300.0, 4, "JPY"),
    )
    private val trip = Trip(1, "2026首爾賞楓五天四夜自由行", d(10, 8), d(10, 13), budget = 60000.0, splitEnabled = true)
    private val shared = trip.copy(sharedBy = "小明", sharedAt = 1_791_600_000_000)
    private val categories = listOf("吃", "交通", "購物", "住宿", "景點", "其他").mapIndexed { i, n -> Category(i + 1L, n, i) }
    private val methods = listOf("現金", "信用卡", "行動支付").mapIndexed { i, n -> PaymentMethod(i + 1L, n, i) }
    private fun row(id: Long, date: Long, title: String, amount: Double, cur: String, rate: Double, c: Int) =
        ExpenseRow(id, date, 12 * 60, title, amount, cur, rate, amount * rate, c + 1L, categories[c].name, "", -1, "信用卡", "", null, null)
    private val expenses = listOf(
        row(1, d(10, 10), "明洞餃子 本店 刀削麵", 120000.0, "KRW", 0.024, 0),
        row(2, d(10, 10), "T-money 加值", 50000.0, "KRW", 0.024, 1),
        row(3, d(10, 9), "樂天免稅店 化妝品", 1234567.0, "KRW", 0.024, 2),
        row(4, d(10, 1), "首爾飯店 5 晚", 28000.0, "TWD", 1.0, 3),
    )
    private fun plan(id: Long, title: String, date: Long?, res: String = Reservation.NONE, note: String = "") =
        PlanRow(id, title, 1, "吃", "", -1, date, 19 * 60, PlanStatus.TODO, res, note, "首爾特別市中區明洞10街29", 3000.0, 1500.0)
    private val plans = listOf(
        plan(1, "明洞餃子", d(10, 10)),
        plan(2, "廣藏市場 綠豆煎餅", d(10, 10), Reservation.BOOKED, "19:00 · 4 位 · 確認碼 AB123"),
        plan(3, "景福宮 韓服體驗", null, Reservation.NEEDED),
        plan(4, "南山首爾塔", d(10, 11)),
    )
    private val item = PlanItem(
        2, 1, "廣藏市場 綠豆煎餅", 1, d(10, 10), 19 * 60, PlanStatus.TODO, Reservation.BOOKED,
        "19:00 · 4 位 · 電話 02-2267-0291", "https://maps.app.goo.gl/abc123", 3000.0, "官網 https://www.visitkorea.or.kr 必點綠豆煎餅",
    )
    private val edit = EditState(
        title = "明洞餃子 本店 刀削麵", amount = "1234567", currency = "KRW", rate = "0.024", categoryId = 1, paymentId = 2,
        date = d(10, 10), minuteOfDay = 12 * 60, note = "訂位 https://tabelog.com/kr 電話 +82 2-776-5348", noteOpen = true,
    )

    private val screens: List<Pair<String, @Composable () -> Unit>> = listOf(
        "首頁" to { TripListScreen(trips, {}, {}, {}, today, "0.8.0") },
        "首頁(備份提醒)" to { TripListScreen(trips.drop(3), {}, {}, {}, today, "0.8.0", reminder = trips[3]) },
        "首頁(全部)" to { TripListScreen(trips.drop(2), {}, {}, {}, today, "0.8.0") },
        "今天" to { TripScreen(trip, 4, expenses, plans, TripTab.TODAY, {}, TripActions(), today) },
        "行程" to { TripScreen(trip, 4, expenses, plans, TripTab.PLAN, {}, TripActions(), today) },
        "帳本" to { TripScreen(trip, 4, expenses, plans, TripTab.LEDGER, {}, TripActions(), today) },
        "統計" to { TripScreen(trip, 4, expenses, plans, TripTab.STATS, {}, TripActions(), today) },
        "唯讀帳本" to { TripScreen(shared, 4, expenses, plans, TripTab.LEDGER, {}, TripActions(readOnly = true, pendingCount = 12), today) },
        "唯讀行程" to { TripScreen(shared, 4, expenses, plans, TripTab.PLAN, {}, TripActions(readOnly = true), today) },
        "記一筆" to {
            ExpenseEditScreen(edit, true, categories, methods, emptyList(), emptyList(), listOf("TWD", "KRW", "JPY"), null, false, ExpenseActions())
        },
        "支出明細" to { ExpenseDetailScreen(edit, categories, methods, emptyList(), {}, {}) },
        "編輯行程" to { PlanEditScreen(item, trip, categories, false, PlanActions()) },
        "行程明細" to { PlanViewScreen(item, shared, categories, expenses.take(2), canEdit = false, PlanViewActions()) },
        "行程內容" to { PlanViewScreen(item, trip, categories, expenses.take(2), canEdit = true, PlanViewActions()) },
        "行程內容(長名稱)" to {
            PlanViewScreen(
                item.copy(title = "【交通】:搭乘 01A 循環公車下山直達「南大門市場」站(約 20 分鐘)。", note = "", reservation = Reservation.NONE),
                trip, categories, emptyList(), canEdit = true, PlanViewActions(),
            )
        },
        "行程(當日筆記)" to {
            TripScreen(
                trip, 4, expenses, plans, TripTab.PLAN, {},
                TripActions(dayNotes = mapOf(d(10, 10) to "【第三天行程】\n09:00 景福宮 韓服體驗\n中午 土俗村蔘雞湯", d(10, 11) to "早點出門")),
                today,
            )
        },
        "編輯旅程" to {
            TripEditScreen(trip, listOf("我", "小美", "小華", "阿姨"), listOf(TripCurrencyRate(1, "KRW", 0.024), TripCurrencyRate(1, "JPY", 0.21)), null, false, {}, {}, {}, { _, _, _ -> }, today)
        },
        "設定" to { SettingsScreen(AppSettings(myName = "小明"), {}, {}, {}, {}, "0.8.0") },
        "分類管理" to {
            ManageListScreen(
                "分類管理", categories.map { c -> categoryStyle(c.name, c.icon, c.color).let { ManageItem(c.id, c.name, it.icon, it.color, deletable = c.name == "飲料") } },
                true, "基礎分類不能刪除,可以改名;自己新增的可以刪除。", { "" }, {}, { _, _, _ -> }, { _, _, _, _ -> }, {}, { _, _ -> },
            )
        },
    )

    @Test fun noScreenStacksOrSplitsText() {
        var current by mutableStateOf(0)
        // Some screens animate forever (progress, pulsing badges): step the clock by hand instead of waiting for idle.
        rule.mainClock.autoAdvance = false
        rule.setContent { AppTheme(ThemeMode.LIGHT, FontSize.XLARGE) { screens[current].second() } }
        val found = mutableListOf<String>()
        screens.forEachIndexed { i, (name, _) ->
            current = i
            androidx.compose.runtime.snapshots.Snapshot.sendApplyNotifications()
            rule.mainClock.advanceTimeBy(2_000)
            found += check(name)
        }
        assertTrue("有文字被擠成直排或斷字:\n" + found.distinct().joinToString("\n"), found.isEmpty())
    }

    private fun check(name: String): List<String> = textProblems(rule, name)
}

/** Every text on screen that is stacked vertically or split mid-word. */
internal fun textProblems(rule: ComposeContentTestRule, name: String): List<String> {
    val nodes = rule.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsActions.GetTextLayoutResult), useUnmergedTree = true).fetchSemanticsNodes()
    assertTrue("$name has text", nodes.isNotEmpty())
    val found = mutableListOf<String>()
    for (node in nodes) {
        val results = mutableListOf<TextLayoutResult>()
        node.config.getOrNull(SemanticsActions.GetTextLayoutResult)?.action?.invoke(results)
        results.forEach { found += problems(name, it) }
    }
    return found
}

/** Characters that belong to one "word": splitting a line between two of them breaks a number or a code. */
private fun Char.wordy() = isLetterOrDigit() && code < 0x2E80 || this in "/.:,$%+-"

private fun problems(where: String, r: TextLayoutResult): List<String> {
    val text = r.layoutInput.text.text
    // Squeezed into a box shorter than its lines (like a fixed-height button): the tops or bottoms get cut.
    if (r.size.height + 1 < r.multiParagraph.height) {
        return listOf("$where:「$text」被切到(高 ${r.size.height} < 需要 ${r.multiParagraph.height.toInt()})")
    }
    if (r.lineCount < 2) return emptyList()
    val lines = (0 until r.lineCount).map { i -> text.substring(r.getLineStart(i), r.getLineEnd(i, visibleEnd = true)).trim() }
    val out = mutableListOf<String>()
    if (text.count { !it.isWhitespace() } >= 3 && lines.all { it.length <= 2 }) out += "$where:直排「$text」→ $lines"
    for (i in 0 until r.lineCount - 1) {
        val end = r.getLineEnd(i)
        // A long web address has to wrap somewhere; short words and numbers must not.
        var from = end
        while (from > 0 && text[from - 1].wordy()) from--
        var to = end
        while (to < text.length && text[to].wordy()) to++
        if (end in 1 until text.length && text[end - 1].wordy() && text[end].wordy() && to - from <= 16) {
            out += "$where:「$text」在「${text.substring(maxOf(0, end - 4), minOf(text.length, end + 4))}」中間斷行 → $lines"
        }
    }
    return out
}


/**
 * Dialogs, same check, on Robolectric's default 320dp phone (narrower still).
 * A text field inside a dialog never settles at high density under Robolectric, so no density qualifier here.
 */
@RunWith(RobolectricTestRunner::class)
@Config(fontScale = 1.5f)
class NoVerticalTextDialogTest {
    @get:Rule val rule = createComposeRule()
    private val name = "2026首爾賞楓五天四夜自由行"

    private fun dialog(where: String, content: @Composable () -> Unit) {
        rule.setContent { AppTheme(ThemeMode.LIGHT, FontSize.XLARGE, content = content) }
        val found = textProblems(rule, where)
        assertTrue("有文字被擠成直排或斷字:\n" + found.distinct().joinToString("\n"), found.isEmpty())
    }

    @Test fun shareDialog() = dialog("分享給同伴") { ShareTripDialog(name, "小明", false, {}) { _, _ -> } }
    @Test fun sendAdditionsDialog() = dialog("傳給記帳人") {
        SendAdditionsDialog(Trip(1, name, 0, 5, sharedBy = "小明"), 3, "小美", false, {}) { _, _ -> }
    }
    @Test fun reviewDialog() = dialog("審核補充") {
        ReviewAdditionsDialog(
            TripArchive.Additions(
                "u", name, "小美",
                listOf(
                    TripArchive.AdditionItem("a", false, "廣藏市場 綠豆煎餅", "行程 · 10/24 · 吃"),
                    TripArchive.AdditionItem("b", true, "樂天免稅店 化妝品", "10/25 · KRW 1,234,567 · 購物"),
                ),
            ),
            false, {}, {},
        )
    }
    @Test fun ownTripBackDialog() = dialog("傳回的旅程") {
        ReviewAdditionsDialog(
            TripArchive.Additions("u", name, "小美", listOf(TripArchive.AdditionItem("b", true, "機票", "10/11 · TWD 12,000 · 交通"))),
            false, {}, {}, ownTripBack = true,
        )
    }
    @Test fun plansImportDialog() = dialog("電腦排的行程") {
        PlansImportDialog(TripArchive.PlansPreview(name, newTrip = true, added = 12, updated = 0, deleted = 0), false, {}, {})
    }
    @Test fun splitDialog() = dialog("拆成多個行程") {
        SplitNoteDialog(
            com.archiekuo.travelledger.data.PlanItem(1, 1, "第三天行程", null, 20750, note = "09:00 景福宮 韓服體驗\n中午 土俗村蔘雞湯\n下午3點半 北村韓屋村 → 仁寺洞\n記得帶護照"),
            listOf("吃", "交通", "購物", "住宿", "景點", "其他").mapIndexed { i, n -> com.archiekuo.travelledger.data.Category(i + 1L, n, i) },
            {},
        ) {}
    }
    @Test fun backupDialog() = dialog("備份") { BackupDialog(false, {}, {}, {}) }
    @Test fun importDialog() = dialog("匯入確認") {
        val start = LocalDate.of(2026, 10, 22).toEpochDay()
        ImportConfirmDialog(
            TripArchive.Summary("trip", "小明", 1_791_600_000_000, listOf(TripArchive.TripInfo("u", name, start, start + 5, 32, 126450.0)), 3),
            setOf("u"), false, {}, {},
        )
    }
}
