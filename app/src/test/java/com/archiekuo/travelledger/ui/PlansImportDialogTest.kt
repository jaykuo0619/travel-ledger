package com.archiekuo.travelledger.ui

import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import com.archiekuo.travelledger.backup.TripArchive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Opening a computer file on a phone without that trip: say whose ledger it is. */
@RunWith(RobolectricTestRunner::class)
class PlansImportDialogTest {
    @get:Rule val rule = createComposeRule()
    private val newTrip = TripArchive.PlansPreview("2026首爾賞楓", newTrip = true, added = 12, updated = 0, deleted = 0)

    @Test fun someoneElsesTripNeedsTheirName() {
        var got: String? = "unset"
        rule.setContent { AppTheme { PlansImportDialog(newTrip, false, onDismiss = {}, onConfirm = { got = it }) } }
        rule.onNodeWithText("這趟旅程是誰記帳?").assertExists()
        rule.onNodeWithText("別人記帳(我只能看,我的補充傳給他)").performClick()
        rule.onNodeWithText("匯入").assertIsNotEnabled() // no name yet
        rule.onNode(hasSetTextAction()).performTextInput(" 小明 ")
        rule.onNodeWithText("匯入").assertIsEnabled().performClick()
        assertEquals("小明", got)
    }

    @Test fun myOwnTripByDefault() {
        var got: String? = "unset"
        rule.setContent { AppTheme { PlansImportDialog(newTrip, false, onDismiss = {}, onConfirm = { got = it }) } }
        rule.onNodeWithText("併入").performClick()
        assertEquals(null, got)
    }

    @Test fun noQuestionWhenThePhoneHasTheTrip() {
        rule.setContent { AppTheme { PlansImportDialog(newTrip.copy(newTrip = false, added = 1, updated = 3), false, onDismiss = {}, onConfirm = {}) } }
        assertTrue(rule.onAllNodes(hasSetTextAction()).fetchSemanticsNodes().isEmpty())
        rule.onNodeWithText("這趟旅程是誰記帳?").assertDoesNotExist()
        rule.onNodeWithText("併入").assertIsEnabled()
    }
}
