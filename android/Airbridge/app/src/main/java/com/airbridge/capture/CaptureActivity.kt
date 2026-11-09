package com.airbridge.capture

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import com.airbridge.R
import com.airbridge.service.AirbridgeService
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Opened at the Mac's request ("Scan Document with Phone" / "Take Photo with
 * Phone"), or from the Scan tile on Home with no request id. Has no UI of its
 * own: it goes straight into Google's document scanner or the camera app, and
 * the result goes to the Mac as a file offer. Tagged with the Mac's request,
 * the Mac accepts it without asking; untagged, it is an ordinary offer.
 */
class CaptureActivity : ComponentActivity() {

    private var requestId: String = ""
    private var photoFile: File? = null
    /** Set once the result (or the cancellation) has been reported, so nothing is reported twice. */
    private var reported = false

    private val scanLauncher = registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { result ->
        val pdf = if (result.resultCode == Activity.RESULT_OK) {
            GmsDocumentScanningResult.fromActivityResultIntent(result.data)?.pdf?.uri
        } else null
        if (pdf != null) deliver(pdf, isScan = true) else cancel()
    }

    private val photoLauncher = registerForActivityResult(ActivityResultContracts.TakePicture()) { saved ->
        val file = photoFile
        if (saved && file != null && file.length() > 0) deliver(Uri.fromFile(file), isScan = false) else cancel()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestId = intent.getStringExtra(EXTRA_REQUEST_ID).orEmpty()
        started = true
        AirbridgeService.dismissCapturePrompt(this)
        // Recreated after a configuration change: the scanner / camera is
        // already open and will answer the launcher registered above.
        if (savedInstanceState != null) {
            photoFile = savedInstanceState.getString(STATE_PHOTO_FILE)?.let(::File)
            return
        }
        cleanOldCaptures(this)
        if (intent.getBooleanExtra(EXTRA_SCAN, true)) startScanner() else startCamera()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        photoFile?.let { outState.putString(STATE_PHOTO_FILE, it.path) }
    }

    private fun startScanner() {
        val options = GmsDocumentScannerOptions.Builder()
            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
            .setGalleryImportAllowed(true)
            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_PDF)
            .build()
        GmsDocumentScanning.getClient(options).getStartScanIntent(this)
            .addOnSuccessListener { sender -> scanLauncher.launch(IntentSenderRequest.Builder(sender).build()) }
            .addOnFailureListener { e ->
                // Play services missing or the scanner module not yet downloaded.
                Log.w(TAG, "Document scanner unavailable", e)
                cancel()
            }
    }

    private fun startCamera() {
        val file = File(captureDir(this), "${getString(R.string.capture_photo_name, timestamp())}.jpg")
        photoFile = file
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        try {
            photoLauncher.launch(uri)
        } catch (e: Exception) {
            // No camera app, or the camera permission was revoked.
            Log.w(TAG, "Camera unavailable", e)
            cancel()
        }
    }

    /** Copies the result under a readable name into our cache and hands it to the service to send. */
    private fun deliver(source: Uri, isScan: Boolean) {
        val target = if (isScan) {
            File(captureDir(this), "${getString(R.string.capture_scan_name, timestamp())}.pdf").also { out ->
                contentResolver.openInputStream(source)?.use { input -> out.outputStream().use { input.copyTo(it) } }
            }
        } else {
            photoFile
        }
        if (target == null || !target.exists() || target.length() == 0L) {
            cancel()
            return
        }
        reported = true
        startService(
            Intent(this, AirbridgeService::class.java).apply {
                action = AirbridgeService.ACTION_SEND_FILE
                data = FileProvider.getUriForFile(this@CaptureActivity, "$packageName.fileprovider", target)
                if (requestId.isNotEmpty()) putExtra(AirbridgeService.EXTRA_CAPTURE_ID, requestId)
            }
        )
        finish()
    }

    private fun cancel() {
        if (!reported) {
            reported = true
            AirbridgeService.sendCaptureCancelled(requestId)
        }
        finish()
    }

    override fun onDestroy() {
        super.onDestroy()
        started = false
        // Closed for good (not just rotated) without a result.
        if (isFinishing && !reported) AirbridgeService.sendCaptureCancelled(requestId)
    }

    companion object {
        private const val TAG = "CaptureActivity"
        const val EXTRA_REQUEST_ID = "request_id"
        const val EXTRA_SCAN = "scan"
        private const val STATE_PHOTO_FILE = "photo_file"

        /** Whether the activity came up, so the service knows when to fall back to a notification. */
        @Volatile var started = false

        fun intent(context: Context, requestId: String, scan: Boolean) =
            Intent(context, CaptureActivity::class.java).apply {
                putExtra(EXTRA_REQUEST_ID, requestId)
                putExtra(EXTRA_SCAN, scan)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

        private fun captureDir(context: Context) = File(context.cacheDir, "capture").apply { mkdirs() }

        /** Results are sent within minutes; anything older than a day is left over. */
        private fun cleanOldCaptures(context: Context) {
            val cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1000L
            captureDir(context).listFiles()?.filter { it.lastModified() < cutoff }?.forEach { it.delete() }
        }

        private fun timestamp(): String = SimpleDateFormat("yyyy-MM-dd HH.mm.ss", Locale.ROOT).format(Date())
    }
}
