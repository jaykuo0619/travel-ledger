package com.archiekuo.travelledger.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.Uri
import android.util.LruCache
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.produceState
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.asImageBitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

/** Trip cover photos, stored downscaled in app-private storage. */
object CoverStore {
    private const val MAX_EDGE = 1600

    suspend fun import(context: Context, uri: Uri): String? = withContext(Dispatchers.IO) {
        runCatching {
            val source = ImageDecoder.createSource(context.contentResolver, uri)
            val bitmap = ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                val w = info.size.width
                val h = info.size.height
                val scale = minOf(1f, MAX_EDGE.toFloat() / maxOf(w, h))
                decoder.setTargetSize((w * scale).toInt().coerceAtLeast(1), (h * scale).toInt().coerceAtLeast(1))
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }
            val dir = File(context.filesDir, "covers").apply { mkdirs() }
            val file = File(dir, "${UUID.randomUUID()}.jpg")
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 85, it) }
            file.absolutePath
        }.getOrNull()
    }

    fun delete(path: String?) {
        if (path != null) runCatching { File(path).delete() }
        if (path != null) ImageCache.remove(path)
    }
}

/** A picture on a plan item; [id] is null until the item is saved. */
data class PlanPicture(val id: Long?, val path: String, val width: Int = 0, val height: Int = 0)

/** Screenshots and pictures kept with plan items, downscaled into photos/plans. */
object PlanPictures {
    private const val MAX_EDGE = 1600

    suspend fun import(context: Context, uri: Uri): PlanPicture? = withContext(Dispatchers.IO) {
        runCatching {
            val source = ImageDecoder.createSource(context.contentResolver, uri)
            val bitmap = ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                val scale = minOf(1f, MAX_EDGE.toFloat() / maxOf(info.size.width, info.size.height))
                decoder.setTargetSize((info.size.width * scale).toInt().coerceAtLeast(1), (info.size.height * scale).toInt().coerceAtLeast(1))
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }
            val dir = File(context.filesDir, "photos/plans").apply { mkdirs() }
            val file = File(dir, "${UUID.randomUUID()}.jpg")
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 82, it) }
            PlanPicture(null, file.absolutePath, bitmap.width, bitmap.height)
        }.getOrNull()
    }

    fun delete(path: String) {
        runCatching { File(path).delete() }
        ImageCache.remove(path)
    }
}

/**
 * Decoded pictures, kept per file *and* size: a 160px list thumbnail must not stand in for the full-screen viewer.
 * Bounded by memory rather than count, since a full-size picture is ~100 times a thumbnail.
 */
internal object ImageCache {
    private val cache = object : LruCache<String, ImageBitmap>((Runtime.getRuntime().maxMemory() / 8).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()) {
        override fun sizeOf(key: String, value: ImageBitmap) = value.asAndroidBitmap().byteCount
    }
    private fun key(path: String, targetPx: Int) = "$targetPx|$path"
    fun get(path: String, targetPx: Int): ImageBitmap? = cache.get(key(path, targetPx))
    fun put(path: String, targetPx: Int, image: ImageBitmap) { cache.put(key(path, targetPx), image) }
    /** Forgets every size of [path] (the file was deleted or replaced). */
    fun remove(path: String) { cache.snapshot().keys.filter { it.substringAfter('|') == path }.forEach { cache.remove(it) } }
}

/** How much to shrink a [width]×[height] picture so its shorter side still covers [targetPx] (power of two, as BitmapFactory wants). */
internal fun sampleSize(width: Int, height: Int, targetPx: Int): Int {
    val side = minOf(width, height)
    var sample = 1
    while (side / (sample * 2) >= targetPx) sample *= 2
    return sample
}

/** Loads a local image file off the main thread, sampled down to roughly [targetPx] on its shorter side. */
@Composable
fun rememberLocalImage(path: String?, targetPx: Int = 1080): State<ImageBitmap?> =
    produceState(initialValue = path?.let { ImageCache.get(it, targetPx) }, path, targetPx) {
        if (path == null) { value = null; return@produceState }
        ImageCache.get(path, targetPx)?.let { value = it; return@produceState }
        value = withContext(Dispatchers.IO) {
            runCatching {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(path, bounds)
                val sample = sampleSize(bounds.outWidth, bounds.outHeight, targetPx)
                BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
                    ?.asImageBitmap()?.also { ImageCache.put(path, targetPx, it) }
            }.getOrNull()
        }
    }
