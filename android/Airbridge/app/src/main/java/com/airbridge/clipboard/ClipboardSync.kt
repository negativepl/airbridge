package com.airbridge.clipboard

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.util.Log
import com.airbridge.protocol.ContentType
import java.security.MessageDigest

class ClipboardSync(private val context: Context) {

    companion object {
        private const val TAG = "ClipboardSync"
    }

    var onClipboardChanged: ((contentType: ContentType, data: String) -> Unit)? = null

    private val clipboardManager: ClipboardManager =
        context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    private var suppressNextChange: Boolean = false
    private var lastSetHash: String? = null

    private val listener = ClipboardManager.OnPrimaryClipChangedListener {
        try {
            val clip = clipboardManager.primaryClip ?: return@OnPrimaryClipChangedListener
            if (clip.itemCount == 0) return@OnPrimaryClipChangedListener

            val item = clip.getItemAt(0)
            val text = item?.coerceToText(context)?.toString() ?: return@OnPrimaryClipChangedListener

            val hash = sha256(text)

            if (suppressNextChange && hash == lastSetHash) {
                suppressNextChange = false
                Log.d(TAG, "Suppressed own clipboard change")
                return@OnPrimaryClipChangedListener
            }
            suppressNextChange = false

            val mimeType = clip.description?.getMimeType(0) ?: "text/plain"
            val contentType = when {
                mimeType.contains("html", ignoreCase = true) -> ContentType.HTML
                mimeType.contains("png", ignoreCase = true) -> ContentType.PNG
                else -> ContentType.PLAIN_TEXT
            }

            Log.d(TAG, "Clipboard changed locally: '${text.take(50)}' type=$contentType")
            onClipboardChanged?.invoke(contentType, text)
        } catch (e: Exception) {
            Log.e(TAG, "Error handling clipboard change", e)
        }
    }

    fun startListening() {
        clipboardManager.addPrimaryClipChangedListener(listener)
        Log.d(TAG, "Clipboard listener registered")
    }

    fun stopListening() {
        clipboardManager.removePrimaryClipChangedListener(listener)
        Log.d(TAG, "Clipboard listener removed")
    }

    fun setClipboard(text: String) {
        val hash = sha256(text)
        lastSetHash = hash
        suppressNextChange = true
        val clip = ClipData.newPlainText("AirBridge", text)
        clipboardManager.setPrimaryClip(clip)
        Log.d(TAG, "Clipboard set (suppress enabled)")
    }

    private fun sha256(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val bytes = digest.digest(input.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }
}
