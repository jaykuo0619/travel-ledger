package com.archiekuo.travelledger.ui

import android.graphics.Bitmap
import android.graphics.Color
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.GraphicsMode
import java.io.File

/**
 * A picture first seen as a small list thumbnail must still open sharp in the full-screen viewer
 * (the cache used to hand the 160px thumbnail to the viewer).
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ImageSharpnessTest {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val tmp = TemporaryFolder()

    private fun jpeg(w: Int, h: Int): File {
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.rgb(230, 80, 60)) }
        return tmp.newFile("pic.jpg").also { f -> f.outputStream().use { bmp.compress(Bitmap.CompressFormat.JPEG, 82, it) } }
    }

    /** The picture loads on a background thread, then lands on the main looper. */
    private fun waitFor(what: () -> Boolean) {
        repeat(200) {
            if (what()) return
            Thread.sleep(25)
            shadowOf(Looper.getMainLooper()).idle()
            rule.waitForIdle()
        }
        throw AssertionError("timed out")
    }

    @Test fun viewerGetsTheFullPictureAfterTheThumbnail() {
        val file = jpeg(1600, 1200)
        var target by mutableStateOf(160)
        var shown: ImageBitmap? = null
        rule.setContent {
            val img by rememberLocalImage(file.absolutePath, targetPx = target)
            shown = img
        }
        waitFor { shown != null }
        assertTrue("thumbnail is small: ${shown!!.width}", shown!!.width <= 400)

        target = 1600 // open the viewer
        rule.waitForIdle()
        waitFor { (shown?.width ?: 0) >= 1600 }
        assertEquals(1600, shown!!.width)
    }

    @Test fun sampleKeepsTheShorterSideCovered() {
        assertEquals(1, sampleSize(1600, 1200, 1600))
        assertEquals(4, sampleSize(1600, 1200, 160))
        // A long screenshot: its narrow side decides, so a square thumbnail stays sharp.
        assertEquals(2, sampleSize(800, 3200, 300))
        assertEquals(1, sampleSize(400, 1600, 300))
    }
}
