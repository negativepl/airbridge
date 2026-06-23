package com.airbridge.clipboard

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.util.Log

/**
 * Writes remote clipboard updates (Mac -> phone) into the local clipboard.
 *
 * There is no passive phone -> Mac path here on purpose: Android 10+ blocks
 * clipboard reads for background apps, so a PrimaryClipChangedListener would
 * only ever see empty content. Phone -> Mac sends go through the explicit
 * ACTION_PROCESS_TEXT entry (SendToMacActivity) and the "Send clipboard" button,
 * both of which read the clipboard while in the foreground.
 */
class ClipboardSync(private val context: Context) {

    companion object {
        private const val TAG = "ClipboardSync"
    }

    private val clipboardManager: ClipboardManager =
        context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    fun setClipboard(text: String) {
        clipboardManager.setPrimaryClip(ClipData.newPlainText("AirBridge", text))
        Log.d(TAG, "Clipboard set from remote update")
    }
}
