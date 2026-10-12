package com.archiekuo.travelledger.ui

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import com.archiekuo.travelledger.backup.TripArchive
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import java.io.File

/** After an import the opened file is deleted when the app holding it allows that, and left alone (no crash) when not. */
@RunWith(RobolectricTestRunner::class)
class DeleteSourceTest {
    /** A file manager that lets the opener delete the file. */
    class FilesProvider : ContentProvider() {
        override fun onCreate() = true
        override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int =
            if (File(uri.path!!).delete()) 1 else 0
        override fun query(uri: Uri, p: Array<out String>?, s: String?, a: Array<out String>?, o: String?): Cursor? = null
        override fun getType(uri: Uri): String = "application/zip"
        override fun insert(uri: Uri, values: ContentValues?): Uri? = null
        override fun update(uri: Uri, values: ContentValues?, s: String?, a: Array<out String>?) = 0
    }

    /** Like LINE: the file can be read but not deleted by others. */
    class LineProvider : ContentProvider() {
        override fun onCreate() = true
        override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = throw SecurityException("not yours")
        override fun query(uri: Uri, p: Array<out String>?, s: String?, a: Array<out String>?, o: String?): Cursor? = null
        override fun getType(uri: Uri): String = "application/zip"
        override fun insert(uri: Uri, values: ContentValues?): Uri? = null
        override fun update(uri: Uri, values: ContentValues?, s: String?, a: Array<out String>?) = 0
    }

    @Test fun deletedWhenAllowed() = runBlocking {
        Robolectric.setupContentProvider(FilesProvider::class.java, "test.files")
        val file = File.createTempFile("卡溜趴備份", ".zip")
        assertTrue(ArchiveFiles.deleteSource(ApplicationProvider.getApplicationContext(), Uri.parse("content://test.files${file.absolutePath}")))
        assertFalse(file.exists())
    }

    /** A backup may be the only copy, so it is never deleted; nor anything when the setting is off or the import failed. */
    @Test fun whichImportsDeleteTheFile() {
        fun imported(kind: String) = TripArchive.Result.Imported(kind, listOf(1L), 0)
        for (kind in listOf(TripArchive.KIND_TRIP, TripArchive.KIND_ADDITIONS, TripArchive.KIND_PLANS)) assertTrue(shouldDeleteSource(true, imported(kind)))
        assertFalse(shouldDeleteSource(true, imported(TripArchive.KIND_BACKUP)))
        assertFalse(shouldDeleteSource(false, imported(TripArchive.KIND_TRIP)))
        assertFalse(shouldDeleteSource(true, TripArchive.Result.Failed("壞掉")))
    }

    @Test fun keptWhenNotAllowed() = runBlocking {
        Robolectric.setupContentProvider(LineProvider::class.java, "test.line")
        assertFalse(ArchiveFiles.deleteSource(ApplicationProvider.getApplicationContext(), Uri.parse("content://test.line/chat/file.zip")))
    }
}
