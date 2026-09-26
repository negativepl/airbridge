package com.airbridge.ui

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import com.airbridge.service.AirbridgeService

/**
 * Deleting a photo from the shared library needs the user's consent on
 * Android 11+: [MediaStore.createDeleteRequest] shows the system's own
 * "Delete this photo?" sheet. This invisible activity hosts that sheet for a
 * delete the Mac asked for and reports the outcome back to the service.
 */
class GalleryDeleteActivity : ComponentActivity() {

    private var photoId: String = ""

    private val consent = registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { result ->
        val ok = result.resultCode == Activity.RESULT_OK
        AirbridgeService.reportGalleryDelete(photoId, ok, if (ok) null else "declined")
        finish()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        photoId = intent.getStringExtra(EXTRA_PHOTO_ID) ?: run { finish(); return }
        val uri = intent.getParcelableExtra(EXTRA_URI, Uri::class.java) ?: run {
            AirbridgeService.reportGalleryDelete(photoId, false, "not_found")
            finish(); return
        }
        try {
            val pending = MediaStore.createDeleteRequest(contentResolver, listOf(uri))
            consent.launch(IntentSenderRequest.Builder(pending.intentSender).build())
        } catch (e: Exception) {
            Log.e("GalleryDelete", "createDeleteRequest failed", e)
            AirbridgeService.reportGalleryDelete(photoId, false, "delete_failed")
            finish()
        }
    }

    companion object {
        const val EXTRA_PHOTO_ID = "photo_id"
        const val EXTRA_URI = "uri"
    }
}
