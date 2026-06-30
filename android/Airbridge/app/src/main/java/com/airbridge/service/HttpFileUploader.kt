package com.airbridge.service

import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import com.airbridge.network.PinnedTls
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okio.BufferedSink
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

class HttpFileUploader {

    companion object {
        private const val TAG = "HttpFileUploader"
        private const val BUFFER_SIZE = 1024 * 1024 // 1MB read buffer
    }

    fun upload(
        host: String,
        port: Int,
        certFingerprint: String,
        uri: Uri,
        contentResolver: ContentResolver,
        destinationDir: String? = null,
        onProgress: (bytesSent: Long, totalBytes: Long) -> Unit
    ): Boolean {
        // Built per call: the TLS pin is per-host, so the client cannot be a
        // long-lived field.
        val client = PinnedTls.apply(
            OkHttpClient.Builder()
                .connectTimeout(10, TimeUnit.SECONDS)
                .writeTimeout(5, TimeUnit.MINUTES)
                .readTimeout(30, TimeUnit.SECONDS),
            certFingerprint
        ).build()
        var mimeType = "application/octet-stream"
        var filename = "file"
        var fileSize = 0L

        // Reading a shared URI can fail with SecurityException if the temporary
        // read grant expired (e.g. the sharing activity already finished). Return
        // false instead of throwing — an uncaught throw here crashed the whole
        // app and dropped the connection.
        try {
            contentResolver.getType(uri)?.let { mimeType = it }
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIdx >= 0) filename = cursor.getString(nameIdx) ?: "file"
                    val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (sizeIdx >= 0) fileSize = cursor.getLong(sizeIdx)
                }
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "No permission to read shared URI (grant likely expired): $uri", e)
            return false
        }

        // file:// URIs (FilesProvider via MANAGE_EXTERNAL_STORAGE) are not
        // backed by a ContentProvider, so the query above returns null and
        // leaves name/size at their defaults. The Mac receiver requires a
        // valid Content-Length and uses X-Filename to name the saved file,
        // so resolve them directly from the File.
        if (uri.scheme == "file") {
            uri.path?.let { java.io.File(it) }?.takeIf { it.exists() }?.let { f ->
                filename = f.name
                fileSize = f.length()
            }
        }

        Log.d(TAG, "Uploading $filename ($mimeType, $fileSize bytes) to $host:$port")

        // Pre-compute SHA-256 in a full read pass so the checksum can travel
        // as a request header (which must be sent before the body) — the Mac
        // verifies X-Checksum-SHA256 against the bytes it receives. A single
        // streaming pass can't do this: the digest isn't known until after the
        // body has already been written. If hashing fails we still upload, just
        // without the integrity check rather than aborting the transfer.
        val checksum = try {
            val digest = MessageDigest.getInstance("SHA-256")
            contentResolver.openInputStream(uri)?.use { stream ->
                val buf = ByteArray(BUFFER_SIZE)
                var read: Int
                while (stream.read(buf).also { read = it } != -1) {
                    digest.update(buf, 0, read)
                }
            }
            digest.digest().joinToString("") { "%02x".format(it) }
        } catch (e: Exception) {
            Log.e(TAG, "Checksum pre-pass failed, uploading without checksum", e)
            null
        }

        val body = object : RequestBody() {
            override fun contentType() = mimeType.toMediaType()
            override fun contentLength() = fileSize

            override fun writeTo(sink: BufferedSink) {
                contentResolver.openInputStream(uri)?.use { stream ->
                    val buf = ByteArray(BUFFER_SIZE)
                    var totalSent = 0L
                    var read: Int
                    while (stream.read(buf).also { read = it } != -1) {
                        sink.write(buf, 0, read)
                        totalSent += read
                        onProgress(totalSent, fileSize)
                    }
                    sink.flush()
                }
            }
        }

        val encodedFilename = java.net.URLEncoder.encode(filename, "UTF-8")
        val request = Request.Builder()
            .url("https://$host:$port/upload")
            .header("X-Filename", encodedFilename)
            .header("X-Mime-Type", mimeType)
            .apply { if (destinationDir != null) header("X-Destination-Dir", java.net.URLEncoder.encode(destinationDir, "UTF-8")) }
            .apply { if (checksum != null) header("X-Checksum-SHA256", checksum) }
            .post(body)
            .build()

        return try {
            val response = client.newCall(request).execute()
            val success = response.isSuccessful
            if (!success) {
                Log.e(TAG, "Upload failed: ${response.code} ${response.body.string()}")
            } else {
                Log.d(TAG, "Upload successful: ${response.body.string()}")
            }
            response.close()
            success
        } catch (e: Exception) {
            Log.e(TAG, "Upload exception", e)
            false
        } finally {
            // The per-call client would otherwise leave a live Dispatcher and
            // ConnectionPool behind until GC (same pattern as MirrorClient.close()).
            client.dispatcher.executorService.shutdown()
            client.connectionPool.evictAll()
        }
    }
}
