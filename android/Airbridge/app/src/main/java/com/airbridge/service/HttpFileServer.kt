package com.airbridge.service

import android.util.Log
import com.airbridge.files.SafeFileName
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class HttpFileServer(private val port: Int = 8767) {

    companion object {
        private const val TAG = "HttpFileServer"
        private const val BUFFER_SIZE = 256 * 1024 // 256KB buffer
    }

    private var serverSocket: ServerSocket? = null
    var onFileReceived: ((filename: String, mimeType: String, file: File) -> Unit)? = null
    var onProgress: ((filename: String, bytesReceived: Int, totalBytes: Int) -> Unit)? = null

    /**
     * Decides whether the remote address may POST to this server. The owner
     * (AirbridgeService) wires this to "is it the currently connected Mac?".
     * Default: reject everything — an unconfigured server accepts nobody.
     */
    var isAllowedSender: (InetAddress) -> Boolean = { false }

    var actualPort: Int = port
        private set

    fun start() {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val socket = ServerSocket(port)
                serverSocket = socket
                actualPort = socket.localPort
                Log.d(TAG, "HTTP server started on port $actualPort")

                while (!socket.isClosed) {
                    try {
                        val client = socket.accept()
                        launch { handleClient(client) }
                    } catch (e: Exception) {
                        if (!socket.isClosed) Log.e(TAG, "Accept failed", e)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Server start failed", e)
            }
        }
    }

    fun stop() {
        serverSocket?.close()
        serverSocket = null
    }

    private fun handleClient(client: Socket) {
        try {
            // Only the currently connected Mac may upload; anyone else in the
            // LAN gets a 403 before a single request byte is processed.
            val remote = client.inetAddress
            if (remote == null || !isAllowedSender(remote)) {
                Log.w(TAG, "Rejected upload from unauthorized address ${remote?.hostAddress}")
                sendResponse(client, 403, """{"status":"error","message":"forbidden"}""")
                return
            }

            val input = client.getInputStream()

            // Read request line byte-by-byte (avoid BufferedReader stealing binary data)
            val requestLine = readLine(input)
            if (!requestLine.startsWith("POST /upload")) {
                sendResponse(client, 404, """{"status":"error","message":"not found"}""")
                return
            }

            // Read headers byte-by-byte
            val headers = mutableMapOf<String, String>()
            while (true) {
                val line = readLine(input)
                if (line.isEmpty()) break
                val colon = line.indexOf(": ")
                if (colon > 0) {
                    headers[line.substring(0, colon).lowercase()] = line.substring(colon + 2)
                }
            }

            val contentLength = headers["content-length"]?.toLongOrNull() ?: 0L
            // X-Filename is attacker-controlled input — keep only a safe last
            // path segment so it can never traverse outside the target dir.
            val filename = headers["x-filename"]
                ?.let { java.net.URLDecoder.decode(it, "UTF-8") }
                ?.let { SafeFileName.sanitize(it) }
                ?: "file"
            val mimeType = headers["x-mime-type"] ?: "application/octet-stream"

            Log.d(TAG, "Receiving: $filename ($mimeType, $contentLength bytes)")

            // Stream directly to temp file
            val tempFile = File.createTempFile("airbridge_", "_$filename")
            val buffer = ByteArray(BUFFER_SIZE)
            var totalRead = 0L

            FileOutputStream(tempFile).use { fos ->
                while (totalRead < contentLength) {
                    val toRead = minOf(buffer.size.toLong(), contentLength - totalRead).toInt()
                    val read = input.read(buffer, 0, toRead)
                    if (read == -1) break
                    fos.write(buffer, 0, read)
                    totalRead += read
                    onProgress?.invoke(filename, totalRead.toInt(), contentLength.toInt())
                }
            }

            Log.d(TAG, "Received $totalRead bytes for $filename")
            sendResponse(client, 200, """{"status":"ok","bytes_received":$totalRead}""")

            onFileReceived?.invoke(filename, mimeType, tempFile)
        } catch (e: Exception) {
            Log.e(TAG, "Client handling failed", e)
        } finally {
            try { client.close() } catch (_: Exception) {}
        }
    }

    // Read a line from InputStream byte-by-byte without buffering ahead
    private fun readLine(input: InputStream): String {
        val sb = StringBuilder()
        while (true) {
            val b = input.read()
            if (b == -1 || b == '\n'.code) break
            if (b != '\r'.code) sb.append(b.toChar())
        }
        return sb.toString()
    }

    private fun sendResponse(client: Socket, code: Int, body: String) {
        val status = when (code) {
            200 -> "OK"
            400 -> "Bad Request"
            403 -> "Forbidden"
            404 -> "Not Found"
            500 -> "Internal Server Error"
            else -> "Error"
        }
        val bodyBytes = body.toByteArray(Charsets.UTF_8)
        val headers = "HTTP/1.1 $code $status\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: ${bodyBytes.size}\r\n" +
            "Connection: close\r\n\r\n"
        val output = client.getOutputStream()
        output.write(headers.toByteArray(Charsets.UTF_8))
        output.write(bodyBytes)
        output.flush()
    }
}
