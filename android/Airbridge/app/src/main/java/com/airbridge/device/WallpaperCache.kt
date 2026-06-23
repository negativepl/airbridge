package com.airbridge.device

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import android.util.Log
import java.io.File

/**
 * Persists the connected Mac's wallpaper to internal storage so the paired-device
 * card can show it even while the Mac is offline. The file is overwritten on every
 * MacWallpaperResponse, so it tracks the Mac's current wallpaper automatically.
 */
object WallpaperCache {
    private const val TAG = "WallpaperCache"

    private fun fileFor(context: Context, deviceName: String): File =
        File(context.filesDir, "wallpaper_${Integer.toHexString(deviceName.hashCode())}.jpg")

    /** Decode the incoming base64 JPEG and store it for [deviceName]. */
    fun save(context: Context, deviceName: String, base64: String) {
        runCatching {
            val bytes = Base64.decode(base64, Base64.NO_WRAP)
            fileFor(context, deviceName).writeBytes(bytes)
        }.onFailure { Log.w(TAG, "save failed for $deviceName", it) }
    }

    /** Last known wallpaper for [deviceName], or null if never cached. */
    fun load(context: Context, deviceName: String): Bitmap? =
        runCatching {
            val file = fileFor(context, deviceName)
            if (!file.exists()) return null
            BitmapFactory.decodeFile(file.absolutePath)
        }.getOrNull()

    /** Drop the cached wallpaper, e.g. when the pairing is removed. */
    fun delete(context: Context, deviceName: String) {
        runCatching { fileFor(context, deviceName).delete() }
    }
}
