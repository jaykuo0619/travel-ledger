package com.archiekuo.travelledger.snap

import androidx.compose.runtime.Composable
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.archiekuo.travelledger.data.Category
import com.archiekuo.travelledger.data.ExpenseRow
import com.archiekuo.travelledger.data.PaymentMethod
import com.archiekuo.travelledger.data.PhotoType
import com.archiekuo.travelledger.data.PlanItem
import com.archiekuo.travelledger.data.PlanRow
import com.archiekuo.travelledger.data.PlanStatus
import com.archiekuo.travelledger.data.Reservation
import com.archiekuo.travelledger.data.TitleSuggestion
import com.archiekuo.travelledger.data.Trip
import com.archiekuo.travelledger.data.TripCurrencyRate
import com.archiekuo.travelledger.data.TripSummary
import com.archiekuo.travelledger.logic.ReceiptGuess
import com.archiekuo.travelledger.ui.*
import org.junit.Rule
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import org.junit.Test
import java.time.LocalDate

/** Renders each screen with sample data in light and dark themes (run recordPaparazziDebug). */
class ScreenSnapshots {
    @get:Rule val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5, maxPercentDifference = 0.1)

    private val today = LocalDate.of(2024, 6, 12)
    private fun d(m: Int, day: Int) = LocalDate.of(2024, m, day).toEpochDay()

    private val trips = listOf(
        TripSummary(1, "東京美食之旅", d(6, 10), d(6, 15), 40000.0, null, null, 28450.0, 4, "JPY"),
        TripSummary(2, "沖繩夏日跳島", d(7, 20), d(7, 24), 30000.0, null, null, 6200.0, 2, "JPY"),
        TripSummary(3, "大阪親子遊", LocalDate.of(2023, 12, 20).toEpochDay(), LocalDate.of(2023, 12, 26).toEpochDay(), null, null, null, 52300.0, 4, "JPY"),
    )
    private val trip = Trip(1, "東京美食之旅", d(6, 10), d(6, 15), budget = 40000.0, splitEnabled = true)
    private val categories = listOf("吃", "交通", "購物", "住宿", "景點", "飲料", "其他").mapIndexed { i, n -> Category(i + 1L, n, i) }
    private fun cat(name: String) = categories.first { it.name == name }.id
    private fun row(id: Long, date: Long, min: Int?, title: String, amount: Double, cur: String, rate: Double, c: String, pay: String, thumb: Boolean = false) =
        ExpenseRow(id, date, min, title, amount, cur, rate, Math.round(amount * rate * 100) / 100.0, cat(c), c, "", -1, pay, "", if (thumb) "/nope.jpg" else null, null)
    private val expenses = listOf(
        row(1, d(6, 12), 12 * 60 + 5, "一蘭拉麵 本店", 1320.0, "JPY", 0.21, "吃", "信用卡", thumb = true),
        row(2, d(6, 12), 10 * 60 + 40, "地鐵一日券", 680.0, "JPY", 0.21, "交通", "行動支付"),
        row(3, d(6, 12), 16 * 60, "唐吉訶德 澀谷店", 5980.0, "JPY", 0.21, "購物", "信用卡", thumb = true),
        row(4, d(6, 12), 18 * 60 + 30, "自動販賣機飲料", 150.0, "JPY", 0.21, "飲料", "現金"),
        row(5, d(6, 11), 19 * 60, "敘敘苑 燒肉", 12800.0, "JPY", 0.21, "吃", "信用卡"),
        row(6, d(6, 1), null, "新宿飯店 5 晚", 18000.0, "TWD", 1.0, "住宿", "信用卡"),
        row(7, d(5, 20), null, "來回機票", 8516.0, "TWD", 1.0, "交通", "信用卡"),
    )
    private fun plan(id: Long, title: String, c: String, date: Long?, min: Int? = null, status: String = PlanStatus.TODO, res: String = Reservation.NONE, note: String = "", spent: Double = 0.0, loc: String = "") =
        PlanRow(id, title, cat(c), c, "", -1, date, min, status, res, note, loc, null, spent)
    private val plans = listOf(
        plan(1, "淺草寺", "景點", d(6, 12), 9 * 60, PlanStatus.DONE, loc = "淺草"),
        plan(2, "一蘭拉麵 本店", "吃", d(6, 12), 12 * 60, PlanStatus.DONE, spent = 277.2, loc = "x"),
        plan(3, "晴空塔", "景點", d(6, 12), 15 * 60, loc = "x"),
        plan(4, "敘敘苑 燒肉", "吃", d(6, 12), 19 * 60, res = Reservation.BOOKED, note = "19:00 4位"),
        plan(5, "築地場外市場", "吃", d(6, 11), 8 * 60),
        plan(6, "壽司大", "吃", null, res = Reservation.NEEDED),
        plan(7, "唐吉訶德 澀谷店", "購物", null),
        plan(8, "明治神宮", "景點", d(6, 13)),
        plan(9, "新宿飯店 check-in", "住宿", d(6, 10), 15 * 60, PlanStatus.DONE),
    )
    private val rates = listOf(TripCurrencyRate(1, "JPY", 0.21), TripCurrencyRate(1, "USD", 32.5))
    private val methods = listOf("現金", "信用卡", "行動支付").mapIndexed { i, n -> PaymentMethod(i + 1L, n, i) }
    private val editState = EditState(
        title = "一蘭拉麵 本店", amount = "1320", currency = "JPY", rate = "0.21",
        categoryId = 1, paymentId = 2, date = d(6, 12), minuteOfDay = 12 * 60 + 5,
    )

    private fun both(name: String, content: @Composable () -> Unit) {
        paparazzi.snapshot("${name}_light") { AppTheme(ThemeMode.LIGHT, content = content) }
        paparazzi.snapshot("${name}_dark") { AppTheme(ThemeMode.DARK, content = content) }
    }

    @Test fun home() = both("home") { TripListScreen(trips, {}, {}, {}, today, "0.6.1") }

    /** Large system font + extra-large app font, dark: the header must not cut the signature. */
    @Test fun homeXLDark() = paparazzi.snapshot {
        AppTheme(ThemeMode.DARK, FontSize.XLARGE) { TripListScreen(trips.take(1), {}, {}, {}, today, "0.6.1") }
    }

    private fun trip(tab: TripTab, day: LocalDate = today) = @Composable {
        TripScreen(trip, 4, expenses, plans, tab, {}, TripActions(), day)
    }

    @Test fun tabToday() = both("tabToday", trip(TripTab.TODAY))
    @Test fun tabTodayBefore() = paparazzi.snapshot { AppTheme(ThemeMode.LIGHT) { trip(TripTab.TODAY, LocalDate.of(2024, 5, 28))() } }
    @Test fun tabPlan() = both("tabPlan", trip(TripTab.PLAN))
    @Test fun tabLedger() = both("tabLedger", trip(TripTab.LEDGER))
    @Test fun tabStats() = both("tabStats", trip(TripTab.STATS))

    @Test fun tabLedgerXL() = paparazzi.snapshot { AppTheme(ThemeMode.LIGHT, FontSize.XLARGE) { trip(TripTab.LEDGER)() } }

    @Test fun planEdit() = both("planEdit") {
        PlanEditScreen(
            PlanItem(4, 1, "敘敘苑 燒肉", cat("吃"), d(6, 12), 19 * 60, PlanStatus.TODO, Reservation.BOOKED, "19:00 · 4 位 · AB123", "新宿區西新宿 1-26-2", 6000.0, "必點:特選牛舌"),
            trip, categories, false, PlanActions(),
        )
    }

    @Test fun tripEdit() = both("tripEdit") {
        TripEditScreen(
            trip, listOf("我", "小美", "小華", "阿姨"), rates, null, false,
            {}, {}, {}, { _, _, _ -> }, today,
        )
    }

    @Test fun expenseNew() = both("expenseNew") {
        ExpenseEditScreen(
            EditState(currency = "JPY", rate = "0.21", categoryId = 1, paymentId = 2, date = d(6, 12), minuteOfDay = 14 * 60 + 32),
            true, categories, methods, emptyList(), emptyList(), listOf("TWD", "JPY"), null, false, ExpenseActions(),
        )
    }

    @Test fun expenseReceipt() = both("expenseReceipt") {
        ExpenseEditScreen(
            editState.copy(title = "", amount = ""), true, categories, methods,
            listOf(PhotoItem(null, "/nope.jpg", PhotoType.RECEIPT)),
            emptyList(), listOf("TWD", "JPY"),
            ReceiptGuess(true, "一蘭 新宿中央東口店", 1330.0, "JPY", LocalDate.of(2024, 6, 12), 13 * 60 + 5),
            false, ExpenseActions(),
        )
    }

    @Test fun expenseEditXL() = paparazzi.snapshot {
        AppTheme(ThemeMode.LIGHT, FontSize.XLARGE) {
            ExpenseEditScreen(
                editState.copy(note = "點了特製拉麵", noteOpen = true), false, categories, methods,
                listOf(PhotoItem(1, "/a.jpg", PhotoType.RECEIPT), PhotoItem(2, "/b.jpg", PhotoType.MEMORY)),
                listOf(TitleSuggestion("一蘭拉麵 本店", 1, 0)), listOf("TWD", "JPY"), null, false, ExpenseActions(),
            )
        }
    }

    /** One card per scene so the illustrations can be reviewed side by side. */
    @Test fun coverGallery() = paparazzi.snapshot {
        AppTheme(ThemeMode.LIGHT) {
            androidx.compose.foundation.layout.Column(
                androidx.compose.ui.Modifier.padding(12.dp),
                verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp),
            ) {
                listOf(
                    "韓國賞楓" to d(10, 22), "東京美食之旅" to d(6, 10), "沖繩夏日跳島" to d(7, 20), "京都賞櫻" to d(4, 1),
                    "北海道滑雪" to d(1, 10), "大阪親子遊" to d(12, 20), "跟阿嬤出去玩" to d(6, 1),
                ).forEach { (n, day) ->
                    TripCover(null, n, androidx.compose.ui.Modifier.fillMaxWidth().height(104.dp).clip(androidx.compose.foundation.shape.RoundedCornerShape(14.dp)), day)
                }
            }
        }
    }

    @Test fun categories() = both("categories") {
        ManageListScreen(
            "分類管理",
            categories.map { c -> categoryStyle(c.name, c.icon, c.color).let { ManageItem(c.id, c.name, it.icon, it.color, deletable = c.name == "飲料") } },
            true, "基礎分類不能刪除,可以改名;自己新增的可以刪除。", { "" }, {}, { _, _, _ -> }, { _, _, _, _ -> }, {}, { _, _ -> },
        )
    }

    @Test fun settings() = both("settings") { SettingsScreen(AppSettings(ThemeMode.DARK, FontSize.LARGE, myName = "小明"), {}, {}, {}, {}, "0.7.0") }

    // ── Sharing with companions ──
    private val shared = trip.copy(sharedBy = "小明", sharedAt = java.time.LocalDateTime.of(2024, 6, 12, 21, 5).atZone(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli())

    @Test fun sharedLedger() = both("sharedLedger") {
        TripScreen(shared, 4, expenses, plans, TripTab.LEDGER, {}, TripActions(readOnly = true, pendingCount = 2), today)
    }
    @Test fun sharedPlan() = paparazzi.snapshot {
        AppTheme(ThemeMode.LIGHT) { TripScreen(shared, 4, expenses, plans, TripTab.PLAN, {}, TripActions(readOnly = true), today) }
    }
    @Test fun sharedExpense() = both("sharedExpense") {
        ExpenseDetailScreen(editState.copy(note = "點了特製拉麵"), categories, methods, emptyList(), {}, {})
    }
    @Test fun sharedPlanDetail() = paparazzi.snapshot {
        AppTheme(ThemeMode.LIGHT) {
            PlanViewScreen(
                PlanItem(4, 1, "敘敘苑 燒肉", cat("吃"), d(6, 12), 19 * 60, PlanStatus.TODO, Reservation.BOOKED, "19:00 · 4 位 · AB123", "新宿區西新宿 1-26-2", 6000.0, "必點:特選牛舌"),
                shared, categories, emptyList(), canEdit = false, PlanViewActions(),
            )
        }
    }
    @Test fun shareDialog() = paparazzi.snapshot { AppTheme(ThemeMode.LIGHT) { ShareTripDialog("東京美食之旅", "小明", false, {}) { _, _ -> } } }
    @Test fun backupDialog() = paparazzi.snapshot { AppTheme(ThemeMode.LIGHT) { BackupDialog(false, {}, {}, {}) } }
    @Test fun importDialog() = paparazzi.snapshot {
        AppTheme(ThemeMode.LIGHT) {
            ImportConfirmDialog(
                com.archiekuo.travelledger.backup.TripArchive.Summary(
                    "trip", "小明", shared.sharedAt!!,
                    listOf(com.archiekuo.travelledger.backup.TripArchive.TripInfo("u", "東京美食之旅", d(6, 10), d(6, 15), 32, 28450.0)), 0,
                ),
                setOf("u"), false, {}, {},
            )
        }
    }
    @Test fun homeWithShared() = paparazzi.snapshot {
        AppTheme(ThemeMode.LIGHT) { TripListScreen(trips.take(1) + trips[1].copy(sharedBy = "阿姨") , {}, {}, {}, today, "0.7.0") }
    }

    // ── Largest text: system font enlarged + 特大 (what the author's own phone looks like) ──
    private fun huge(content: @Composable () -> Unit) {
        paparazzi.unsafeUpdateConfig(deviceConfig = DeviceConfig.PIXEL_5.copy(fontScale = 1.3f))
        paparazzi.snapshot { AppTheme(ThemeMode.DARK, FontSize.XLARGE, content = content) }
    }
    @Test fun homeHuge() = huge {
        TripListScreen(
            listOf(
                TripSummary(1, "韓國賞楓", d(10, 22), d(10, 27), null, null, "AUTUMN", 100.0, 2, "KRW"),
                TripSummary(2, "2026首爾賞楓五天四夜", d(10, 22), d(10, 27), null, null, null, 6498.0, 4, "KRW"),
            ),
            {}, {}, {}, LocalDate.of(2024, 10, 10), "0.8.0",
        )
    }
    @Test fun planEditHuge() = huge {
        PlanEditScreen(
            PlanItem(4, 1, "第三天行程", cat("吃"), d(6, 12), null, PlanStatus.TODO, Reservation.NONE, "", "", null, ""),
            trip, categories, false, PlanActions(),
        )
    }

    @Test fun reviewAdditions() = paparazzi.snapshot {
        AppTheme(ThemeMode.LIGHT) {
            ReviewAdditionsDialog(
                com.archiekuo.travelledger.backup.TripArchive.Additions(
                    "u", "東京美食之旅", "小美",
                    listOf(
                        com.archiekuo.travelledger.backup.TripArchive.AdditionItem("a", false, "築地 壽司大", "行程 · 6/13 · 吃"),
                        com.archiekuo.travelledger.backup.TripArchive.AdditionItem("b", true, "抹茶冰", "6/12 · JPY 900 · 吃"),
                        com.archiekuo.travelledger.backup.TripArchive.AdditionItem("c", true, "唐吉訶德 伴手禮", "6/12 · JPY 5,980 · 購物"),
                    ),
                ),
                false, {}, {},
            )
        }
    }
    @Test fun sendAdditions() = paparazzi.snapshot {
        AppTheme(ThemeMode.LIGHT) { SendAdditionsDialog(shared, 2, "小美", false, {}) { _, _ -> } }
    }
    @Test fun homeReminder() = paparazzi.snapshot {
        AppTheme(ThemeMode.LIGHT) { TripListScreen(trips.drop(2), {}, {}, {}, today, "0.8.0", reminder = trips[2]) }
    }
    @Test fun ledgerLinks() = paparazzi.snapshot {
        AppTheme(ThemeMode.LIGHT) {
            ExpenseDetailScreen(editState.copy(note = "訂位 https://tabelog.com/tokyo 電話 03-1234-5678"), categories, methods, emptyList(), {}, {})
        }
    }

    @Test fun splitNote() = paparazzi.snapshot {
        AppTheme(ThemeMode.LIGHT) {
            SplitNoteDialog(
                PlanItem(1, 1, "第三天行程", null, d(6, 12), note = "09:00 淺草寺 → 仲見世通\n中午 一蘭拉麵 本店\n下午3點 晴空塔\nhttps://maps.app.goo.gl/x\n晚上 敘敘苑 燒肉\n記得帶護照"),
                categories, {},
            ) {}
        }
    }

    @Test fun planView() = both("planView") {
        PlanViewScreen(
            PlanItem(
                4, 1, "敘敘苑 燒肉", cat("吃"), d(6, 12), 19 * 60, PlanStatus.TODO, Reservation.BOOKED, "19:00 · 4 位 · 電話 03-3343-6091",
                "https://maps.app.goo.gl/abc", 6000.0, "必點:特選牛舌\n官網 https://www.jojoen.co.jp",
            ),
            trip, categories, listOf(expenses[4]), canEdit = true, PlanViewActions(),
        )
    }
    @Test fun planTabNotes() = paparazzi.snapshot {
        AppTheme(ThemeMode.LIGHT) {
            TripScreen(
                trip, 4, expenses, plans, TripTab.PLAN, {},
                TripActions(dayNotes = mapOf(d(6, 11) to "【第二天行程】\n08:00 築地場外市場\n中午 壽司大\n記得帶護照", d(6, 12) to "今天早點出門")),
                today,
            )
        }
    }

    @Test fun planEditPictures() = paparazzi.snapshot {
        AppTheme(ThemeMode.LIGHT) {
            PlanEditScreen(
                PlanItem(2, 1, "廣藏市場 綠豆煎餅", cat("吃"), d(6, 12), 12 * 60, PlanStatus.TODO, Reservation.NONE, "", "", null, "必點綠豆煎餅、麻藥飯捲"),
                trip, categories, false, PlanActions(),
                pictures = listOf(PlanPicture(1, "/nope1.jpg"), PlanPicture(2, "/nope2.jpg")),
            )
        }
    }
}
