package com.airbridge.device

import android.app.WallpaperManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.util.Base64
import android.util.Log
import java.io.ByteArrayOutputStream

/**
 * Reads the phone's current wallpaper for the Mac's Home hero (Phone Link-style
 * preview). Best-effort: wallpaper access is restricted on newer Android, so any
 * failure returns an empty string and the Mac simply hides the preview.
 */
object WallpaperProvider {

    private const val TAG = "WallpaperProvider"
    private const val MAX_DIM = 720
    private const val JPEG_QUALITY = 82

    /** Current wallpaper as base64 JPEG, or "" if unavailable. */
    fun getWallpaperJpegBase64(context: Context): String {
        return try {
            val wm = WallpaperManager.getInstance(context)
            val drawable: Drawable = wm.peekDrawable() ?: wm.fastDrawable ?: wm.drawable ?: return ""
            val bitmap = drawableToBitmap(drawable) ?: return ""
            val scaled = downscale(bitmap, MAX_DIM)
            val baos = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, baos)
            Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP)
        } catch (e: SecurityException) {
            Log.w(TAG, "wallpaper access denied", e)
            ""
        } catch (e: Exception) {
            Log.w(TAG, "wallpaper read failed", e)
            ""
        }
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap? {
        if (drawable is BitmapDrawable && drawable.bitmap != null) return drawable.bitmap
        val w = drawable.intrinsicWidth.takeIf { it > 0 } ?: 1080
        val h = drawable.intrinsicHeight.takeIf { it > 0 } ?: 1920
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bmp
    }

    private fun downscale(src: Bitmap, maxDim: Int): Bitmap {
        val longEdge = maxOf(src.width, src.height)
        if (longEdge <= maxDim) return src
        val scale = maxDim.toFloat() / longEdge
        val w = (src.width * scale).toInt().coerceAtLeast(1)
        val h = (src.height * scale).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(src, w, h, true)
    }
}
