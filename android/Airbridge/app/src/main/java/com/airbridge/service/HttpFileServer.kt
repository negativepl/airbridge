package com.airbridge.service

import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
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
            val input = client.getInputStream()

            // Read request line byte-by-byte (avoid BufferedReader stealing binary data)
            val requestLine = readLine(input)
            if (!requestLine.startsWith("POST /upload")) {
                sendResponse(client, 404, "Not Found")
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
            val filename = headers["x-filename"]?.let {
                java.net.URLDecoder.decode(it, "UTF-8")
            } ?: "file"
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
        val status = if (code == 200) "OK" else "Error"
        val response = "HTTP/1.1 $code $status\r\nContent-Length: ${body.length}\r\nConnection: close\r\n\r\n$body"
        client.getOutputStream().write(response.toByteArray())
        client.getOutputStream().flush()
    }
}
