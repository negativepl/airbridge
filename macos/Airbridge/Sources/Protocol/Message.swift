import Foundation

// MARK: - ContentType

/// MIME types supported for clipboard content.
public enum ContentType: String, Codable, Equatable, Sendable {
    case plainText = "text/plain"
    case html = "text/html"
    case png = "image/png"
}

// MARK: - Message

/// All message types in the Airbridge protocol.
///
/// Encoding produces snake_case JSON matching the protocol specification.
/// `clipboardUpdate` and `fileTransferStart` automatically inject a
/// millisecond-precision Unix `timestamp` on encode.
public enum Message: Equatable, Sendable {
    case clipboardUpdate(sourceId: String, contentType: ContentType, data: String)
    case fileTransferStart(
        sourceId: String,
        transferId: String,
        filename: String,
        mimeType: String,
        totalSize: Int,
        totalChunks: Int
    )
    case fileChunk(transferId: String, chunkIndex: Int, data: String)
    case fileChunkAck(transferId: String, chunkIndex: Int)
    case fileTransferComplete(transferId: String, checksumSHA256: String)
    case pairRequest(deviceName: String, publicKey: String, pairingToken: String)
    case pairResponse(deviceName: String, publicKey: String, accepted: Bool)
    case ping(timestamp: Int)
    case pong(timestamp: Int)
    case authRequest(publicKey: String, signature: String, timestamp: Int64)
    case authResponse(accepted: Bool, reason: String?)
    case galleryRequest(page: Int, pageSize: Int)
    case galleryResponse(photos: [GalleryPhotoMeta], totalCount: Int, page: Int)
    case galleryThumbnailRequest(photoId: String)
    case galleryThumbnailResponse(photoId: String, data: String)
    case galleryDownloadRequest(photoId: String)
    case smsConversationsRequest(page: Int, pageSize: Int)
    case smsConversationsResponse(conversations: [SmsConversationMeta], totalCount: Int, page: Int)
    case smsMessagesRequest(threadId: String, page: Int, pageSize: Int)
    case smsMessagesResponse(threadId: String, messages: [SmsMessageMeta], totalCount: Int, page: Int)
    case smsSendRequest(address: String, body: String)
    case smsSendResponse(success: Bool, error: String?)
}

// MARK: - GalleryPhotoMeta

public struct GalleryPhotoMeta: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let filename: String
    public let dateTaken: Int64
    public let width: Int
    public let height: Int
    public let size: Int64
    public let mimeType: String

    private enum CodingKeys: String, CodingKey {
        case id, filename, width, height, size
        case dateTaken = "date_taken"
        case mimeType = "mime_type"
    }

    public init(id: String, filename: String, dateTaken: Int64, width: Int, height: Int, size: Int64, mimeType: String) {
        self.id = id
        self.filename = filename
        self.dateTaken = dateTaken
        self.width = width
        self.height = height
        self.size = size
        self.mimeType = mimeType
    }
}

// MARK: - SmsConversationMeta

public struct SmsConversationMeta: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let threadId: String
    public let address: String
    public let displayName: String
    public let snippet: String
    public let date: Int64
    public let messageCount: Int
    public let unreadCount: Int

    public var id: String { threadId }

    private enum CodingKeys: String, CodingKey {
        case address, snippet, date
        case threadId = "thread_id"
        case displayName = "display_name"
        case messageCount = "message_count"
        case unreadCount = "unread_count"
    }

    public init(threadId: String, address: String, displayName: String, snippet: String, date: Int64, messageCount: Int, unreadCount: Int) {
        self.threadId = threadId
        self.address = address
        self.displayName = displayName
        self.snippet = snippet
        self.date = date
        self.messageCount = messageCount
        self.unreadCount = unreadCount
    }
}

// MARK: - SmsMessageMeta

public struct SmsMessageMeta: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let address: String
    public let body: String
    public let date: Int64
    public let type: Int
    public let read: Bool

    private enum CodingKeys: String, CodingKey {
        case id, address, body, date, type, read
    }

    public init(id: String, address: String, body: String, date: Int64, type: Int, read: Bool) {
        self.id = id
        self.address = address
        self.body = body
        self.date = date
        self.type = type
        self.read = read
    }
}

// MARK: - Codable

extension Message: Codable {

    // MARK: CodingKeys

    private enum TypeKey: String, Codable {
        case clipboardUpdate    = "clipboard_update"
        case fileTransferStart  = "file_transfer_start"
        case fileChunk          = "file_chunk"
        case fileChunkAck       = "file_chunk_ack"
        case fileTransferComplete = "file_transfer_complete"
        case pairRequest        = "pair_request"
        case pairResponse       = "pair_response"
        case ping               = "ping"
        case pong               = "pong"
        case authRequest        = "auth_request"
        case authResponse       = "auth_response"
        case galleryRequest     = "gallery_request"
        case galleryResponse    = "gallery_response"
        case galleryThumbnailRequest  = "gallery_thumbnail_request"
        case galleryThumbnailResponse = "gallery_thumbnail_response"
        case galleryDownloadRequest   = "gallery_download_request"
        case smsConversationsRequest  = "sms_conversations_request"
        case smsConversationsResponse = "sms_conversations_response"
        case smsMessagesRequest       = "sms_messages_request"
        case smsMessagesResponse      = "sms_messages_response"
        case smsSendRequest           = "sms_send_request"
        case smsSendResponse          = "sms_send_response"
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case sourceId           = "source_id"
        case contentType        = "content_type"
        case data
        case timestamp
        case transferId         = "transfer_id"
        case filename
        case mimeType           = "mime_type"
        case totalSize          = "total_size"
        case totalChunks        = "total_chunks"
        case chunkIndex         = "chunk_index"
        case checksumSHA256     = "checksum_sha256"
        case deviceName         = "device_name"
        case publicKey          = "public_key"
        case pairingToken       = "pairing_token"
        case accepted
        case signature
        case reason
        case page
        case pageSize           = "page_size"
        case totalCount         = "total_count"
        case photos
        case photoId            = "photo_id"
        case conversations
        case messages
        case threadId           = "thread_id"
        case address
        case body
        case success
        case error
    }

    // MARK: Encode

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {

        case .clipboardUpdate(let sourceId, let contentType, let data):
            try container.encode(TypeKey.clipboardUpdate.rawValue, forKey: .type)
            try container.encode(sourceId, forKey: .sourceId)
            try container.encode(contentType, forKey: .contentType)
            try container.encode(data, forKey: .data)
            try container.encode(currentTimestamp(), forKey: .timestamp)

        case .fileTransferStart(let sourceId, let transferId, let filename,
                                let mimeType, let totalSize, let totalChunks):
            try container.encode(TypeKey.fileTransferStart.rawValue, forKey: .type)
            try container.encode(sourceId, forKey: .sourceId)
            try container.encode(transferId, forKey: .transferId)
            try container.encode(filename, forKey: .filename)
            try container.encode(mimeType, forKey: .mimeType)
            try container.encode(totalSize, forKey: .totalSize)
            try container.encode(totalChunks, forKey: .totalChunks)
            try container.encode(currentTimestamp(), forKey: .timestamp)

        case .fileChunk(let transferId, let chunkIndex, let data):
            try container.encode(TypeKey.fileChunk.rawValue, forKey: .type)
            try container.encode(transferId, forKey: .transferId)
            try container.encode(chunkIndex, forKey: .chunkIndex)
            try container.encode(data, forKey: .data)

        case .fileChunkAck(let transferId, let chunkIndex):
            try container.encode(TypeKey.fileChunkAck.rawValue, forKey: .type)
            try container.encode(transferId, forKey: .transferId)
            try container.encode(chunkIndex, forKey: .chunkIndex)

        case .fileTransferComplete(let transferId, let checksumSHA256):
            try container.encode(TypeKey.fileTransferComplete.rawValue, forKey: .type)
            try container.encode(transferId, forKey: .transferId)
            try container.encode(checksumSHA256, forKey: .checksumSHA256)

        case .pairRequest(let deviceName, let publicKey, let pairingToken):
            try container.encode(TypeKey.pairRequest.rawValue, forKey: .type)
            try container.encode(deviceName, forKey: .deviceName)
            try container.encode(publicKey, forKey: .publicKey)
            try container.encode(pairingToken, forKey: .pairingToken)

        case .pairResponse(let deviceName, let publicKey, let accepted):
            try container.encode(TypeKey.pairResponse.rawValue, forKey: .type)
            try container.encode(deviceName, forKey: .deviceName)
            try container.encode(publicKey, forKey: .publicKey)
            try container.encode(accepted, forKey: .accepted)

        case .ping(let timestamp):
            try container.encode(TypeKey.ping.rawValue, forKey: .type)
            try container.encode(timestamp, forKey: .timestamp)

        case .pong(let timestamp):
            try container.encode(TypeKey.pong.rawValue, forKey: .type)
            try container.encode(timestamp, forKey: .timestamp)

        case .authRequest(let publicKey, let signature, let timestamp):
            try container.encode(TypeKey.authRequest.rawValue, forKey: .type)
            try container.encode(publicKey, forKey: .publicKey)
            try container.encode(signature, forKey: .signature)
            try container.encode(timestamp, forKey: .timestamp)

        case .authResponse(let accepted, let reason):
            try container.encode(TypeKey.authResponse.rawValue, forKey: .type)
            try container.encode(accepted, forKey: .accepted)
            try container.encodeIfPresent(reason, forKey: .reason)

        case .galleryRequest(let page, let pageSize):
            try container.encode(TypeKey.galleryRequest.rawValue, forKey: .type)
            try container.encode(page, forKey: .page)
            try container.encode(pageSize, forKey: .pageSize)

        case .galleryResponse(let photos, let totalCount, let page):
            try container.encode(TypeKey.galleryResponse.rawValue, forKey: .type)
            try container.encode(photos, forKey: .photos)
            try container.encode(totalCount, forKey: .totalCount)
            try container.encode(page, forKey: .page)

        case .galleryThumbnailRequest(let photoId):
            try container.encode(TypeKey.galleryThumbnailRequest.rawValue, forKey: .type)
            try container.encode(photoId, forKey: .photoId)

        case .galleryThumbnailResponse(let photoId, let data):
            try container.encode(TypeKey.galleryThumbnailResponse.rawValue, forKey: .type)
            try container.encode(photoId, forKey: .photoId)
            try container.encode(data, forKey: .data)

        case .galleryDownloadRequest(let photoId):
            try container.encode(TypeKey.galleryDownloadRequest.rawValue, forKey: .type)
            try container.encode(photoId, forKey: .photoId)

        case .smsConversationsRequest(let page, let pageSize):
            try container.encode(TypeKey.smsConversationsRequest.rawValue, forKey: .type)
            try container.encode(page, forKey: .page)
            try container.encode(pageSize, forKey: .pageSize)

        case .smsConversationsResponse(let conversations, let totalCount, let page):
            try container.encode(TypeKey.smsConversationsResponse.rawValue, forKey: .type)
            try container.encode(conversations, forKey: .conversations)
            try container.encode(totalCount, forKey: .totalCount)
            try container.encode(page, forKey: .page)

        case .smsMessagesRequest(let threadId, let page, let pageSize):
            try container.encode(TypeKey.smsMessagesRequest.rawValue, forKey: .type)
            try container.encode(threadId, forKey: .threadId)
            try container.encode(page, forKey: .page)
            try container.encode(pageSize, forKey: .pageSize)

        case .smsMessagesResponse(let threadId, let messages, let totalCount, let page):
            try container.encode(TypeKey.smsMessagesResponse.rawValue, forKey: .type)
            try container.encode(threadId, forKey: .threadId)
            try container.encode(messages, forKey: .messages)
            try container.encode(totalCount, forKey: .totalCount)
            try container.encode(page, forKey: .page)

        case .smsSendRequest(let address, let body):
            try container.encode(TypeKey.smsSendRequest.rawValue, forKey: .type)
            try container.encode(address, forKey: .address)
            try container.encode(body, forKey: .body)

        case .smsSendResponse(let success, let error):
            try container.encode(TypeKey.smsSendResponse.rawValue, forKey: .type)
            try container.encode(success, forKey: .success)
            try container.encodeIfPresent(error, forKey: .error)
        }
    }

    // MARK: Decode

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeRaw = try container.decode(String.self, forKey: .type)

        guard let typeKey = TypeKey(rawValue: typeRaw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown message type: \(typeRaw)"
            )
        }

        switch typeKey {

        case .clipboardUpdate:
            let sourceId = try container.decode(String.self, forKey: .sourceId)
            let contentType = try container.decode(ContentType.self, forKey: .contentType)
            let data = try container.decode(String.self, forKey: .data)
            self = .clipboardUpdate(sourceId: sourceId, contentType: contentType, data: data)

        case .fileTransferStart:
            let sourceId    = try container.decode(String.self, forKey: .sourceId)
            let transferId  = try container.decode(String.self, forKey: .transferId)
            let filename    = try container.decode(String.self, forKey: .filename)
            let mimeType    = try container.decode(String.self, forKey: .mimeType)
            let totalSize   = try container.decode(Int.self, forKey: .totalSize)
            let totalChunks = try container.decode(Int.self, forKey: .totalChunks)
            self = .fileTransferStart(
                sourceId: sourceId,
                transferId: transferId,
                filename: filename,
                mimeType: mimeType,
                totalSize: totalSize,
                totalChunks: totalChunks
            )

        case .fileChunk:
            let transferId  = try container.decode(String.self, forKey: .transferId)
            let chunkIndex  = try container.decode(Int.self, forKey: .chunkIndex)
            let data        = try container.decode(String.self, forKey: .data)
            self = .fileChunk(transferId: transferId, chunkIndex: chunkIndex, data: data)

        case .fileChunkAck:
            let transferId = try container.decode(String.self, forKey: .transferId)
            let chunkIndex = try container.decode(Int.self, forKey: .chunkIndex)
            self = .fileChunkAck(transferId: transferId, chunkIndex: chunkIndex)

        case .fileTransferComplete:
            let transferId      = try container.decode(String.self, forKey: .transferId)
            let checksumSHA256  = try container.decode(String.self, forKey: .checksumSHA256)
            self = .fileTransferComplete(transferId: transferId, checksumSHA256: checksumSHA256)

        case .pairRequest:
            let deviceName    = try container.decode(String.self, forKey: .deviceName)
            let publicKey     = try container.decode(String.self, forKey: .publicKey)
            let pairingToken  = try container.decode(String.self, forKey: .pairingToken)
            self = .pairRequest(deviceName: deviceName, publicKey: publicKey, pairingToken: pairingToken)

        case .pairResponse:
            let deviceName = try container.decode(String.self, forKey: .deviceName)
            let publicKey  = try container.decode(String.self, forKey: .publicKey)
            let accepted   = try container.decode(Bool.self, forKey: .accepted)
            self = .pairResponse(deviceName: deviceName, publicKey: publicKey, accepted: accepted)

        case .ping:
            let timestamp = try container.decode(Int.self, forKey: .timestamp)
            self = .ping(timestamp: timestamp)

        case .pong:
            let timestamp = try container.decode(Int.self, forKey: .timestamp)
            self = .pong(timestamp: timestamp)

        case .authRequest:
            let publicKey = try container.decode(String.self, forKey: .publicKey)
            let signature = try container.decode(String.self, forKey: .signature)
            let timestamp = try container.decode(Int64.self, forKey: .timestamp)
            self = .authRequest(publicKey: publicKey, signature: signature, timestamp: timestamp)

        case .authResponse:
            let accepted = try container.decode(Bool.self, forKey: .accepted)
            let reason = try container.decodeIfPresent(String.self, forKey: .reason)
            self = .authResponse(accepted: accepted, reason: reason)

        case .galleryRequest:
            let page = try container.decode(Int.self, forKey: .page)
            let pageSize = try container.decode(Int.self, forKey: .pageSize)
            self = .galleryRequest(page: page, pageSize: pageSize)

        case .galleryResponse:
            let photos = try container.decode([GalleryPhotoMeta].self, forKey: .photos)
            let totalCount = try container.decode(Int.self, forKey: .totalCount)
            let page = try container.decode(Int.self, forKey: .page)
            self = .galleryResponse(photos: photos, totalCount: totalCount, page: page)

        case .galleryThumbnailRequest:
            let photoId = try container.decode(String.self, forKey: .photoId)
            self = .galleryThumbnailRequest(photoId: photoId)

        case .galleryThumbnailResponse:
            let photoId = try container.decode(String.self, forKey: .photoId)
            let data = try container.decode(String.self, forKey: .data)
            self = .galleryThumbnailResponse(photoId: photoId, data: data)

        case .galleryDownloadRequest:
            let photoId = try container.decode(String.self, forKey: .photoId)
            self = .galleryDownloadRequest(photoId: photoId)

        case .smsConversationsRequest:
            let page = try container.decode(Int.self, forKey: .page)
            let pageSize = try container.decode(Int.self, forKey: .pageSize)
            self = .smsConversationsRequest(page: page, pageSize: pageSize)

        case .smsConversationsResponse:
            let conversations = try container.decode([SmsConversationMeta].self, forKey: .conversations)
            let totalCount = try container.decode(Int.self, forKey: .totalCount)
            let page = try container.decode(Int.self, forKey: .page)
            self = .smsConversationsResponse(conversations: conversations, totalCount: totalCount, page: page)

        case .smsMessagesRequest:
            let threadId = try container.decode(String.self, forKey: .threadId)
            let page = try container.decode(Int.self, forKey: .page)
            let pageSize = try container.decode(Int.self, forKey: .pageSize)
            self = .smsMessagesRequest(threadId: threadId, page: page, pageSize: pageSize)

        case .smsMessagesResponse:
            let threadId = try container.decode(String.self, forKey: .threadId)
            let messages = try container.decode([SmsMessageMeta].self, forKey: .messages)
            let totalCount = try container.decode(Int.self, forKey: .totalCount)
            let page = try container.decode(Int.self, forKey: .page)
            self = .smsMessagesResponse(threadId: threadId, messages: messages, totalCount: totalCount, page: page)

        case .smsSendRequest:
            let address = try container.decode(String.self, forKey: .address)
            let body = try container.decode(String.self, forKey: .body)
            self = .smsSendRequest(address: address, body: body)

        case .smsSendResponse:
            let success = try container.decode(Bool.self, forKey: .success)
            let error = try container.decodeIfPresent(String.self, forKey: .error)
            self = .smsSendResponse(success: success, error: error)
        }
    }

    // MARK: Private Helpers

    private func currentTimestamp() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
    }
}

// MARK: - QRPayload

/// The payload encoded in the pairing QR code displayed on the macOS device.
public struct QRPayload: Codable, Equatable, Sendable {
    public let host: String
    public let port: Int
    public let publicKey: String
    public let pairingToken: String
    public let protocolVersion: Int

    private enum CodingKeys: String, CodingKey {
        case host
        case port
        case publicKey       = "public_key"
        case pairingToken    = "pairing_token"
        case protocolVersion = "protocol_version"
    }

    public init(
        host: String,
        port: Int,
        publicKey: String,
        pairingToken: String,
        protocolVersion: Int = 1
    ) {
        self.host = host
        self.port = port
        self.publicKey = publicKey
        self.pairingToken = pairingToken
        self.protocolVersion = protocolVersion
    }
}
