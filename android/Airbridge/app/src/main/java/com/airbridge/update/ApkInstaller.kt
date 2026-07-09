package com.airbridge.update

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.security.MessageDigest

/**
 * Downloads the release APK and hands it to the system installer. The system
 * shows its own install confirmation — that dialog cannot and should not be
 * bypassed. Plain OkHttpClient on purpose: public HTTPS (GitHub), not a LAN
 * peer, so PinnedTls does not apply.
 */
class ApkInstaller(private val context: Context) {

    suspend fun downloadAndVerify(
        asset: UpdateManifest.Asset,
        onProgress: (Float) -> Unit
    ): File? {
        val dir = File(context.cacheDir, "updates").apply { mkdirs() }
        // One update at a time; stale downloads are just cache.
        val dest = File(dir, "AirBridge-update.apk")
        return downloadTo(asset.url, asset.sha256, dest, onProgress)
    }

    fun launchInstall(apk: File) {
        val uri: Uri = FileProvider.getUriForFile(
            context, "${context.packageName}.fileprovider", apk
        )
        context.startActivity(
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        )
    }

    companion object {
        fun sha256Hex(file: File): String {
            val md = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buf = ByteArray(64 * 1024)
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    md.update(buf, 0, n)
                }
            }
            return md.digest().joinToString("") { "%02x".format(it) }
        }

        suspend fun downloadTo(
            url: String,
            expectedSha256: String,
            dest: File,
            onProgress: (Float) -> Unit
        ): File? = withContext(Dispatchers.IO) {
            try {
                val client = OkHttpClient()
                client.newCall(Request.Builder().url(url).build()).execute().use { resp ->
                    if (!resp.isSuccessful) return@withContext null
                    val body = resp.body
                    val total = body.contentLength()
                    dest.outputStream().use { out ->
                        val src = body.byteStream()
                        val buf = ByteArray(64 * 1024)
                        var read = 0L
                        while (true) {
                            val n = src.read(buf)
                            if (n < 0) break
                            out.write(buf, 0, n)
                            read += n
                            if (total > 0) onProgress(read.toFloat() / total)
                        }
                    }
                }
                if (sha256Hex(dest).equals(expectedSha256, ignoreCase = true)) dest
                else { dest.delete(); null }
            } catch (e: Exception) {
                dest.delete()
                null
            }
        }
    }
}
