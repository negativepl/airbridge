package com.airbridge.mirror

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Bundle

class MirrorActivity : Activity() {

    private var host: String = ""
    private var port: Int = 0
    private var token: ByteArray = ByteArray(0)
    private var certFingerprint: String = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        host = intent.getStringExtra(EXTRA_HOST) ?: return finish()
        port = intent.getIntExtra(EXTRA_PORT, 0)
        token = intent.getByteArrayExtra(EXTRA_TOKEN) ?: return finish()
        certFingerprint = intent.getStringExtra(EXTRA_CERT_FINGERPRINT) ?: ""

        val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        startActivityForResult(mpm.createScreenCaptureIntent(), REQUEST_CAPTURE)
    }

    @Deprecated("Activity result API in older form; sufficient for short-lived gate activity.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CAPTURE) { finish(); return }
        if (resultCode != RESULT_OK || data == null) { finish(); return }

        val svc = Intent(this, MirrorService::class.java).apply {
            action = MirrorService.ACTION_START
            putExtra(MirrorService.EXTRA_RESULT_CODE, resultCode)
            putExtra(MirrorService.EXTRA_RESULT_DATA, data)
            putExtra(MirrorService.EXTRA_HOST, host)
            putExtra(MirrorService.EXTRA_PORT, port)
            putExtra(MirrorService.EXTRA_TOKEN, token)
            putExtra(MirrorService.EXTRA_CERT_FINGERPRINT, certFingerprint)
        }
        startForegroundService(svc)
        finish()
    }

    companion object {
        const val EXTRA_HOST = "host"
        const val EXTRA_PORT = "port"
        const val EXTRA_TOKEN = "token"
        const val EXTRA_CERT_FINGERPRINT = "certFingerprint"
        private const val REQUEST_CAPTURE = 4711
    }
}
