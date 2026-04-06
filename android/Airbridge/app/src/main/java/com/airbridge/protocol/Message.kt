package com.airbridge.protocol

import org.json.JSONArray
import org.json.JSONObject

data class PhotoMeta(
    val id: String,
    val filename: String,
    val dateTaken: Long,
    val width: Int,
    val height: Int,
    val size: Long,
    val mimeType: String
)

data class SmsConversation(
    val threadId: String,
    val address: String,
    val displayName: String,
    val snippet: String,
    val date: Long,
    val messageCount: Int,
    val unreadCount: Int
)

data class SmsMessage(
    val id: String,
    val address: String,
    val body: String,
    val date: Long,
    val type: Int,
    val read: Boolean
)

enum class ContentType(val value: String) {
    PLAIN_TEXT("text/plain"),
    HTML("text/html"),
    PNG("image/png");

    companion object {
        fun fromValue(value: String): ContentType =
            entries.firstOrNull { it.value == value }
                ?: throw IllegalArgumentException("Unknown content type: $value")
    }
}

sealed class Message {

    abstract fun toJson(): String

    data class ClipboardUpdate(
        val sourceId: String,
        val contentType: ContentType,
        val data: String,
        val timestamp: Long = System.currentTimeMillis()
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "clipboard_update")
            put("source_id", sourceId)
            put("content_type", contentType.value)
            put("data", data)
            put("timestamp", timestamp)
        }.toString()
    }

    data class FileTransferStart(
        val sourceId: String,
        val transferId: String,
        val filename: String,
        val mimeType: String,
        val totalSize: Long,
        val totalChunks: Int,
        val timestamp: Long = System.currentTimeMillis()
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "file_transfer_start")
            put("source_id", sourceId)
            put("transfer_id", transferId)
            put("filename", filename)
            put("mime_type", mimeType)
            put("total_size", totalSize)
            put("total_chunks", totalChunks)
            put("timestamp", timestamp)
        }.toString()
    }

    data class FileChunk(
        val transferId: String,
        val chunkIndex: Int,
        val data: String
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "file_chunk")
            put("transfer_id", transferId)
            put("chunk_index", chunkIndex)
            put("data", data)
        }.toString()
    }

    data class FileChunkAck(
        val transferId: String,
        val chunkIndex: Int
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "file_chunk_ack")
            put("transfer_id", transferId)
            put("chunk_index", chunkIndex)
        }.toString()
    }

    data class FileTransferComplete(
        val transferId: String,
        val checksumSha256: String
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "file_transfer_complete")
            put("transfer_id", transferId)
            put("checksum_sha256", checksumSha256)
        }.toString()
    }

    data class FileTransferOffer(
        val transferId: String,
        val filename: String,
        val mimeType: String,
        val fileSize: Long
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "file_transfer_offer")
            put("transfer_id", transferId)
            put("filename", filename)
            put("mime_type", mimeType)
            put("file_size", fileSize)
        }.toString()
    }

    data class FileTransferAccept(
        val transferId: String
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "file_transfer_accept")
            put("transfer_id", transferId)
        }.toString()
    }

    data class FileTransferReject(
        val transferId: String
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "file_transfer_reject")
            put("transfer_id", transferId)
        }.toString()
    }

    data class PairRequest(
        val deviceName: String,
        val publicKey: String,
        val pairingToken: String
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "pair_request")
            put("device_name", deviceName)
            put("public_key", publicKey)
            put("pairing_token", pairingToken)
        }.toString()
    }

    data class PairResponse(
        val deviceName: String,
        val publicKey: String,
        val accepted: Boolean
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "pair_response")
            put("device_name", deviceName)
            put("public_key", publicKey)
            put("accepted", accepted)
        }.toString()
    }

    data class Ping(
        val timestamp: Long = System.currentTimeMillis()
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "ping")
            put("timestamp", timestamp)
        }.toString()
    }

    data class Pong(
        val timestamp: Long
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "pong")
            put("timestamp", timestamp)
        }.toString()
    }

    data class AuthRequest(
        val publicKey: String,
        val signature: String,
        val timestamp: Long
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "auth_request")
            put("public_key", publicKey)
            put("signature", signature)
            put("timestamp", timestamp)
        }.toString()
    }

    data class AuthResponse(
        val accepted: Boolean,
        val reason: String? = null
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "auth_response")
            put("accepted", accepted)
            if (reason != null) put("reason", reason)
        }.toString()
    }

    data class GalleryRequest(
        val page: Int,
        val pageSize: Int
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "gallery_request")
            put("page", page)
            put("page_size", pageSize)
        }.toString()
    }

    data class GalleryResponse(
        val photos: List<PhotoMeta>,
        val totalCount: Int,
        val page: Int
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "gallery_response")
            put("total_count", totalCount)
            put("page", page)
            put("photos", JSONArray().apply {
                photos.forEach { photo ->
                    put(JSONObject().apply {
                        put("id", photo.id)
                        put("filename", photo.filename)
                        put("date_taken", photo.dateTaken)
                        put("width", photo.width)
                        put("height", photo.height)
                        put("size", photo.size)
                        put("mime_type", photo.mimeType)
                    })
                }
            })
        }.toString()
    }

    data class GalleryThumbnailRequest(
        val photoId: String
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "gallery_thumbnail_request")
            put("photo_id", photoId)
        }.toString()
    }

    data class GalleryThumbnailResponse(
        val photoId: String,
        val data: String
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "gallery_thumbnail_response")
            put("photo_id", photoId)
            put("data", data)
        }.toString()
    }

    data class GalleryDownloadRequest(
        val photoId: String
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "gallery_download_request")
            put("photo_id", photoId)
        }.toString()
    }

    data class SmsConversationsRequest(
        val page: Int,
        val pageSize: Int
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "sms_conversations_request")
            put("page", page)
            put("page_size", pageSize)
        }.toString()
    }

    data class SmsConversationsResponse(
        val conversations: List<SmsConversation>,
        val totalCount: Int,
        val page: Int
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "sms_conversations_response")
            put("total_count", totalCount)
            put("page", page)
            put("conversations", JSONArray().apply {
                conversations.forEach { c ->
                    put(JSONObject().apply {
                        put("thread_id", c.threadId)
                        put("address", c.address)
                        put("display_name", c.displayName)
                        put("snippet", c.snippet)
                        put("date", c.date)
                        put("message_count", c.messageCount)
                        put("unread_count", c.unreadCount)
                    })
                }
            })
        }.toString()
    }

    data class SmsMessagesRequest(
        val threadId: String,
        val page: Int,
        val pageSize: Int
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "sms_messages_request")
            put("thread_id", threadId)
            put("page", page)
            put("page_size", pageSize)
        }.toString()
    }

    data class SmsMessagesResponse(
        val threadId: String,
        val messages: List<SmsMessage>,
        val totalCount: Int,
        val page: Int
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "sms_messages_response")
            put("thread_id", threadId)
            put("total_count", totalCount)
            put("page", page)
            put("messages", JSONArray().apply {
                messages.forEach { m ->
                    put(JSONObject().apply {
                        put("id", m.id)
                        put("address", m.address)
                        put("body", m.body)
                        put("date", m.date)
                        put("type", m.type)
                        put("read", m.read)
                    })
                }
            })
        }.toString()
    }

    data class SmsSendRequest(
        val address: String,
        val body: String
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "sms_send_request")
            put("address", address)
            put("body", body)
        }.toString()
    }

    data class SmsSendResponse(
        val success: Boolean,
        val error: String?
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "sms_send_response")
            put("success", success)
            if (error != null) put("error", error)
        }.toString()
    }

    companion object {
        fun fromJson(json: String): Message {
            val obj = JSONObject(json)
            return when (val type = obj.getString("type")) {
                "clipboard_update" -> ClipboardUpdate(
                    sourceId = obj.getString("source_id"),
                    contentType = ContentType.fromValue(obj.getString("content_type")),
                    data = obj.getString("data"),
                    timestamp = obj.getLong("timestamp")
                )
                "file_transfer_start" -> FileTransferStart(
                    sourceId = obj.getString("source_id"),
                    transferId = obj.getString("transfer_id"),
                    filename = obj.getString("filename"),
                    mimeType = obj.getString("mime_type"),
                    totalSize = obj.getLong("total_size"),
                    totalChunks = obj.getInt("total_chunks"),
                    timestamp = obj.getLong("timestamp")
                )
                "file_chunk" -> FileChunk(
                    transferId = obj.getString("transfer_id"),
                    chunkIndex = obj.getInt("chunk_index"),
                    data = obj.getString("data")
                )
                "file_chunk_ack" -> FileChunkAck(
                    transferId = obj.getString("transfer_id"),
                    chunkIndex = obj.getInt("chunk_index")
                )
                "file_transfer_complete" -> FileTransferComplete(
                    transferId = obj.getString("transfer_id"),
                    checksumSha256 = obj.getString("checksum_sha256")
                )
                "file_transfer_offer" -> FileTransferOffer(
                    transferId = obj.getString("transfer_id"),
                    filename = obj.getString("filename"),
                    mimeType = obj.getString("mime_type"),
                    fileSize = obj.getLong("file_size")
                )
                "file_transfer_accept" -> FileTransferAccept(
                    transferId = obj.getString("transfer_id")
                )
                "file_transfer_reject" -> FileTransferReject(
                    transferId = obj.getString("transfer_id")
                )
                "pair_request" -> PairRequest(
                    deviceName = obj.getString("device_name"),
                    publicKey = obj.getString("public_key"),
                    pairingToken = obj.getString("pairing_token")
                )
                "pair_response" -> PairResponse(
                    deviceName = obj.getString("device_name"),
                    publicKey = obj.getString("public_key"),
                    accepted = obj.getBoolean("accepted")
                )
                "ping" -> Ping(timestamp = obj.getLong("timestamp"))
                "pong" -> Pong(timestamp = obj.getLong("timestamp"))
                "auth_request" -> AuthRequest(
                    publicKey = obj.getString("public_key"),
                    signature = obj.getString("signature"),
                    timestamp = obj.getLong("timestamp")
                )
                "auth_response" -> AuthResponse(
                    accepted = obj.getBoolean("accepted"),
                    reason = if (obj.has("reason")) obj.getString("reason") else null
                )
                "gallery_request" -> GalleryRequest(
                    page = obj.optInt("page", 0),
                    pageSize = obj.optInt("page_size", 50)
                )
                "gallery_response" -> {
                    val photosArray = obj.getJSONArray("photos")
                    val photos = (0 until photosArray.length()).map { i ->
                        val p = photosArray.getJSONObject(i)
                        PhotoMeta(
                            id = p.getString("id"),
                            filename = p.getString("filename"),
                            dateTaken = p.getLong("date_taken"),
                            width = p.getInt("width"),
                            height = p.getInt("height"),
                            size = p.getLong("size"),
                            mimeType = p.getString("mime_type")
                        )
                    }
                    GalleryResponse(
                        photos = photos,
                        totalCount = obj.getInt("total_count"),
                        page = obj.getInt("page")
                    )
                }
                "gallery_thumbnail_request" -> GalleryThumbnailRequest(
                    photoId = obj.getString("photo_id")
                )
                "gallery_thumbnail_response" -> GalleryThumbnailResponse(
                    photoId = obj.getString("photo_id"),
                    data = obj.getString("data")
                )
                "gallery_download_request" -> GalleryDownloadRequest(
                    photoId = obj.getString("photo_id")
                )
                "sms_conversations_request" -> SmsConversationsRequest(
                    page = obj.optInt("page", 0),
                    pageSize = obj.optInt("page_size", 30)
                )
                "sms_conversations_response" -> {
                    val convArray = obj.getJSONArray("conversations")
                    val convos = (0 until convArray.length()).map { i ->
                        val c = convArray.getJSONObject(i)
                        SmsConversation(
                            threadId = c.getString("thread_id"),
                            address = c.getString("address"),
                            displayName = c.getString("display_name"),
                            snippet = c.getString("snippet"),
                            date = c.getLong("date"),
                            messageCount = c.getInt("message_count"),
                            unreadCount = c.getInt("unread_count")
                        )
                    }
                    SmsConversationsResponse(
                        conversations = convos,
                        totalCount = obj.getInt("total_count"),
                        page = obj.getInt("page")
                    )
                }
                "sms_messages_request" -> SmsMessagesRequest(
                    threadId = obj.getString("thread_id"),
                    page = obj.optInt("page", 0),
                    pageSize = obj.optInt("page_size", 30)
                )
                "sms_messages_response" -> {
                    val msgsArray = obj.getJSONArray("messages")
                    val msgs = (0 until msgsArray.length()).map { i ->
                        val m = msgsArray.getJSONObject(i)
                        SmsMessage(
                            id = m.getString("id"),
                            address = m.getString("address"),
                            body = m.getString("body"),
                            date = m.getLong("date"),
                            type = m.getInt("type"),
                            read = m.getBoolean("read")
                        )
                    }
                    SmsMessagesResponse(
                        threadId = obj.getString("thread_id"),
                        messages = msgs,
                        totalCount = obj.getInt("total_count"),
                        page = obj.getInt("page")
                    )
                }
                "sms_send_request" -> SmsSendRequest(
                    address = obj.getString("address"),
                    body = obj.getString("body")
                )
                "sms_send_response" -> SmsSendResponse(
                    success = obj.getBoolean("success"),
                    error = if (obj.has("error")) obj.getString("error") else null
                )
                else -> throw IllegalArgumentException("Unknown message type: $type")
            }
        }
    }
}
