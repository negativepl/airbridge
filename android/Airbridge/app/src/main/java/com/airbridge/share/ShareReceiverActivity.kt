package com.airbridge.share

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import com.airbridge.service.AirbridgeService

class ShareReceiverActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
        finish()
    }

    private fun handleIntent(intent: Intent) {
        when (intent.action) {
            Intent.ACTION_SEND -> {
                val uri: Uri? = intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                if (uri != null) {
                    forwardFile(uri)
                } else {
                    val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                    if (text != null) {
                        forwardText(text)
                    }
                }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val uris: ArrayList<Uri>? =
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                uris?.forEach { uri -> forwardFile(uri) }
            }
        }
        Toast.makeText(this, getString(com.airbridge.R.string.share_sending), Toast.LENGTH_SHORT).show()
    }

    private fun forwardFile(uri: Uri) {
        val serviceIntent = Intent(this, AirbridgeService::class.java).apply {
            action = AirbridgeService.ACTION_SEND_FILE
            data = uri
        }
        startService(serviceIntent)
    }

    private fun forwardText(text: String) {
        // Text sharing — forward as a file intent with text data URI
        val serviceIntent = Intent(this, AirbridgeService::class.java).apply {
            action = AirbridgeService.ACTION_SEND_FILE
            putExtra(Intent.EXTRA_TEXT, text)
        }
        startService(serviceIntent)
    }
}
