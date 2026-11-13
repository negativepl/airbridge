package com.airbridge.widget

import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.net.toUri
import com.airbridge.R
import com.airbridge.capture.CaptureActivity
import com.airbridge.protocol.ContentType
import com.airbridge.service.AirbridgeService
import com.airbridge.ui.currentMirrorIntent

/**
 * Invisible host for the home screen widget's buttons: it runs one action and
 * finishes, so the user stays where they were instead of landing in the app.
 *
 * Reading the clipboard is why it exists at all: since Android 10 only the app
 * in focus may read it, so the clipboard is read once this window has focus.
 * The pickers for a file or a photo need an activity for their result, and the
 * chosen file goes to the service with the read grant, as from the app.
 */
class WidgetActionActivity : ComponentActivity() {

    private val pickFile = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        sendFile(uri)
    }

    private val pickPhoto = registerForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        sendFile(uri)
    }

    private var action: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        action = intent.getStringExtra(EXTRA_ACTION)
        // A picker already on screen after a configuration change: wait for its result.
        if (savedInstanceState != null) return

        if (!AirbridgeService.isConnected.value) {
            toast(R.string.widget_mac_not_connected)
            finish()
            return
        }
        when (action) {
            ACTION_FILE -> pickFile.launch(arrayOf("*/*"))
            ACTION_PHOTO -> pickPhoto.launch(
                PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo)
            )
            ACTION_SCAN -> {
                // Google's scanner; the PDF goes to the Mac as an ordinary file offer.
                startActivity(CaptureActivity.intent(this, requestId = "", scan = true))
                finish()
            }
            ACTION_MAC_SCREEN -> {
                val mirror = currentMirrorIntent(this, mode = 0)
                if (mirror != null) startActivity(mirror) else toast(R.string.widget_mac_not_connected)
                finish()
            }
            ACTION_CLIPBOARD -> Unit // read in onWindowFocusChanged
            else -> finish()
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || action != ACTION_CLIPBOARD || isFinishing) return
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = clipboard.primaryClip
        val text = if (clip != null && clip.itemCount > 0) clip.getItemAt(0).coerceToText(this).toString() else ""
        if (text.isNotEmpty()) {
            AirbridgeService.sendClipboardToMac(ContentType.PLAIN_TEXT, text)
            toast(R.string.sent_to_mac)
        } else {
            toast(R.string.clipboard_empty)
        }
        finish()
    }

    private fun sendFile(uri: Uri?) {
        if (uri != null) {
            startService(
                Intent(this, AirbridgeService::class.java).apply {
                    action = AirbridgeService.ACTION_SEND_FILE
                    data = uri
                    // The picker's grant is this activity's; hand it to the
                    // service, which reads the file after this has finished.
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            )
        }
        finish()
    }

    private fun toast(message: Int) = Toast.makeText(this, getString(message), Toast.LENGTH_SHORT).show()

    companion object {
        private const val EXTRA_ACTION = "com.airbridge.widget.ACTION"
        const val ACTION_CLIPBOARD = "clipboard"
        const val ACTION_FILE = "file"
        const val ACTION_PHOTO = "photo"
        const val ACTION_SCAN = "scan"
        const val ACTION_MAC_SCREEN = "mac_screen"

        fun intent(context: Context, action: String): Intent =
            Intent(context, WidgetActionActivity::class.java)
                .putExtra(EXTRA_ACTION, action)
                // One activity per action, so a pending picker never swallows another tap.
                .setData("airbridge-widget://$action".toUri())
    }
}
