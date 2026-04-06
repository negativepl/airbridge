package com.airbridge.share

import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import androidx.activity.ComponentActivity
import com.airbridge.protocol.ContentType
import com.airbridge.protocol.Message
import com.airbridge.service.AirbridgeService

class SendToMacActivity : ComponentActivity() {

    companion object {
        private const val TAG = "SendToMac"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val text = intent?.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()

        if (text.isNullOrEmpty()) {
            Log.w(TAG, "No text received")
            finish()
            return
        }

        Log.d(TAG, "Received text: '${text.take(50)}'")

        // Send via AirbridgeService static method
        AirbridgeService.sendClipboardToMac(ContentType.PLAIN_TEXT, text)

        // Also copy to clipboard so Mac→Android echo prevention works
        val cm = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
        cm.setPrimaryClip(android.content.ClipData.newPlainText("Airbridge", text))

        Toast.makeText(this, getString(com.airbridge.R.string.sent_to_mac), Toast.LENGTH_SHORT).show()
        finish()
    }
}
