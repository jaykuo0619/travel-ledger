package com.archiekuo.travelledger.ui

import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.printToString
import androidx.compose.ui.test.performImeAction
import androidx.compose.ui.test.performTextInput
import com.archiekuo.travelledger.MainActivity
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Drives the real app by tapping: create a trip, record expenses, plan a place, tick it off. */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
// Native graphics: with the legacy mode, touches on views with a shadow layer (the keypad panel) are lost.
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class AppFlowTest {
    @get:Rule val rule = createAndroidComposeRule<MainActivity>()

    private fun tap(text: String) {
        assertTrue("「$text」 should be on screen", seen(text))
        rule.onAllNodesWithText(text).onFirst().performClick()
    }
    private fun type(index: Int, text: String) = rule.onAllNodes(hasSetTextAction())[index].performTextInput(text)
    private fun key(k: String) {
        rule.waitUntil(5_000) { rule.onAllNodes(hasText(k) and hasClickAction()).fetchSemanticsNodes().isNotEmpty() }
        rule.onAllNodes(hasText(k) and hasClickAction()).onFirst().performClick()
    }

    /** Type into the n-th text field, then press the keyboard's 完成 like a person would. */
    private fun typeAndDone(index: Int, text: String) {
        type(index, text)
        rule.onAllNodes(hasSetTextAction())[index].performImeAction()
    }
    private fun keys(amount: String) = amount.forEach { key(it.toString()) }
    private fun present(text: String) = rule.onAllNodesWithText(text, substring = true).fetchSemanticsNodes().isNotEmpty()

    /** The database works on background threads, so wait for the screen to catch up. */
    private fun seen(text: String): Boolean = runCatching { rule.waitUntil(5_000) { present(text) } }.isSuccess

    @Test fun firstTripRecordAndPlan() {
        // Empty app: the trip list with the big "新增旅程" button.
        assertTrue(seen("還沒有旅程"))
        tap("新增旅程")

        // New trip (dates default to today + 4 days, so it is ongoing).
        type(0, "測試之旅")
        rule.onNodeWithContentDescription("儲存").performClick()

        // Created trips open right away, on the Today tab.
        assertTrue("today tab", seen("今天已花"))
        assertTrue("trip screen shows its name", seen("測試之旅"))

        // 記一筆: name, keypad, save.
        rule.onNodeWithContentDescription("記一筆").performClick()
        assertTrue(seen("店家或項目名稱"))
        typeAndDone(0, "一蘭拉麵")
        keys("1320")
        assertTrue("keypad shows the amount", seen("1,320"))
        tap("儲存")
        rule.waitForIdle()

        // Back on the trip: today's spending and the expense in the ledger.
        assertTrue("today total", seen("NT$ 1,320"))
        tap("帳本")
        rule.waitForIdle()
        assertTrue(seen("一蘭拉麵"))
        assertTrue(seen("總花費(新台幣)"))

        // A second expense defaults to the previous category/payment; use 00 and backspace.
        rule.onNodeWithContentDescription("記一筆").performClick()
        assertTrue(seen("店家或項目名稱"))
        typeAndDone(0, "地鐵")
        keys("15")
        key("00") // 1500
        rule.onNodeWithContentDescription("刪除(長按清除)").performClick() // 150
        tap("儲存")
        rule.waitForIdle()
        assertTrue("ledger total 1,470", seen("NT$ 1,470"))

        // Plan tab: add a place, it lands in 待排, then tick it off.
        tap("行程")
        rule.waitForIdle()
        assertTrue(seen("把出發前做的功課放進來"))
        tap("新增行程")
        assertTrue(seen("景點、餐廳或活動名稱"))
        type(0, "淺草寺")
        rule.onNodeWithContentDescription("儲存").performClick()
        rule.waitForIdle()
        assertTrue(seen("待排 · 1 項"))
        assertTrue(seen("淺草寺"))

        // Statistics tab renders the totals too.
        tap("統計")
        rule.waitForIdle()
        assertTrue(seen("NT$ 1,470"))
        assertTrue(seen("每天花多少"))

        // Switch trip → list shows the trip as ongoing with the small "+" instead of the big button.
        rule.onNodeWithContentDescription("切換旅程").performClick()
        assertTrue(seen("旅行中"))
        rule.onNodeWithContentDescription("新增旅程").assertExists()
        assertTrue("big button hidden while a trip is active", !present("新增旅程"))
    }

    private fun newTrip(name: String) {
        assertTrue(seen("還沒有旅程"))
        tap("新增旅程")
        type(0, name)
        rule.onNodeWithContentDescription("儲存").performClick()
        assertTrue(seen("今天已花"))
    }

    @Test fun scheduleAndRecordFromPlan() {
        newTrip("京都")
        tap("行程")
        assertTrue(seen("把出發前做的功課放進來"))

        // Add a place and put it on day 1 (= today, the trip starts today).
        tap("新增行程")
        assertTrue(seen("景點、餐廳或活動名稱"))
        type(0, "伏見稻荷神社")
        // Day tiles show the date with the weekday underneath; the trip starts today.
        val today = java.time.LocalDate.now()
        rule.onAllNodesWithText("${today.monthValue}/${today.dayOfMonth}").onFirst().performClick()
        rule.onNodeWithContentDescription("儲存").performClick()
        assertTrue(seen("Day 1"))
        assertTrue(seen("伏見稻荷神社"))

        // It shows up on the Today tab.
        tap("今天")
        assertTrue(seen("今天的行程"))
        assertTrue(seen("伏見稻荷神社"))

        // Tapping a plan shows it (edit and delete are icons); record money for it from there.
        tap("伏見稻荷神社")
        assertTrue(seen("為這個行程記一筆"))
        assertTrue(rule.onAllNodesWithContentDescription("編輯").fetchSemanticsNodes().isNotEmpty())
        assertTrue(rule.onAllNodesWithContentDescription("刪除").fetchSemanticsNodes().isNotEmpty())
        tap("為這個行程記一筆")
        assertTrue(seen("伏見稻荷神社"))
        keys("500")
        tap("儲存")
        assertTrue(seen("為這個行程記的帳")) // back on the plan, which lists the expense
        assertTrue(seen("改回未去")) // and it is ticked off
        rule.onNodeWithContentDescription("返回").performClick()
        assertTrue(seen("已花 NT$ 500"))
        assertTrue(seen("1 / 1 完成"))
    }

    @Test fun addAPlanToUnscheduled() {
        newTrip("大阪")
        tap("行程")
        tap("新增行程")
        assertTrue(seen("景點、餐廳或活動名稱"))
        type(0, "通天閣")
        val today = java.time.LocalDate.now()
        rule.onAllNodesWithText("${today.monthValue}/${today.dayOfMonth}").onFirst().performClick()
        rule.onAllNodesWithText("待排").onFirst().performClick()
        rule.onNodeWithContentDescription("儲存").assertIsEnabled().performClick()
        assertTrue(seen("待排 · 1 項"))
        assertTrue(seen("通天閣"))
        // Again from the top button with 待排 already chosen.
        rule.onAllNodesWithText("新增").onFirst().performClick()
        assertTrue(seen("景點、餐廳或活動名稱"))
        type(0, "黑門市場")
        rule.onNodeWithContentDescription("儲存").assertIsEnabled().performClick()
        assertTrue(seen("待排 · 2 項"))
    }

    @Test fun editAndDeleteAnExpense() {
        newTrip("首爾")
        rule.onNodeWithContentDescription("記一筆").performClick()
        assertTrue(seen("店家或項目名稱"))
        typeAndDone(0, "炸雞")
        keys("800")
        tap("儲存")
        tap("帳本")
        assertTrue(seen("NT$ 800"))

        // Open it, change the amount.
        tap("炸雞")
        assertTrue(seen("編輯"))
        key("C")
        keys("650")
        tap("儲存")
        assertTrue(seen("NT$ 650"))
        assertTrue(!present("NT$ 800"))

        // Delete it.
        tap("炸雞")
        rule.onNodeWithContentDescription("刪除").performClick()
        assertTrue(seen("刪除這筆支出?"))
        rule.onAllNodes(hasText("刪除") and hasClickAction()).onFirst().performClick()
        assertTrue(seen("還沒有支出"))
    }

    /** A companion opens the file the organizer sent on LINE: confirm, then browse the read-only copy. */
    @Test fun companionOpensSharedTrip() {
        assertTrue(seen("還沒有旅程"))
        val organizer = com.archiekuo.travelledger.data.testDb()
        val file = java.io.File(rule.activity.cacheDir, "卡溜趴-京都.zip")
        kotlinx.coroutines.runBlocking {
            val today = java.time.LocalDate.now().toEpochDay()
            val trip = organizer.tripDao().createTrip(
                com.archiekuo.travelledger.data.Trip(name = "京都賞楓", startDate = today, endDate = today + 3), listOf("我", "小美"), emptyList(),
            )
            organizer.expenseDao().insert(
                com.archiekuo.travelledger.data.Expense(
                    tripId = trip, date = today, amount = 2400.0, currency = "TWD", rate = 1.0, homeAmount = 2400.0,
                    categoryId = null, paymentMethodId = null, payerId = null, title = "湯豆腐", minuteOfDay = 12 * 60,
                ),
            )
            file.outputStream().use { com.archiekuo.travelledger.backup.TripArchive.export(organizer, it, "trip", listOf(trip), false, "小明") }
        }
        organizer.close()

        rule.runOnUiThread { ImportInbox.pending = android.net.Uri.fromFile(file) }
        assertTrue("confirmation names the sender", seen("小明 分享的旅程"))
        tap("匯入")

        // The copy opens with the organizer named; their expenses open as view-only details.
        assertTrue(rule.onRoot().printToString(), seen("小明 記帳"))
        tap("帳本")
        tap("湯豆腐")
        assertTrue(seen("支出明細"))
        assertTrue(rule.onAllNodesWithText("儲存").fetchSemanticsNodes().isEmpty())
        rule.onNodeWithContentDescription("關閉").performClick()

        // What the companion records becomes their own addition, ready to send to the organizer.
        rule.onNodeWithContentDescription("記一筆").performClick()
        assertTrue(seen("店家或項目名稱"))
        typeAndDone(0, "抹茶冰")
        keys("300")
        tap("儲存")
        assertTrue(seen("我補充了 1 項"))
        assertTrue(seen("我的補充 · 還沒傳給記帳人"))
        assertTrue(seen("傳給記帳人"))
    }
}
