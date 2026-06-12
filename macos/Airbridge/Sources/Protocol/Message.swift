import Foundation

// MARK: - ProtocolConstants

/// Constants shared across the Airbridge wire protocol.
public enum ProtocolConstants {
    /// Version of the wire protocol this build speaks. Included in the pairing
    /// QR payload and the auth handshake; peers that omit the field are
    /// treated as version 1.
    public static let version = 1
}

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
    case authRequest(publicKey: String, signature: String, timestamp: Int64, protocolVersion: Int)
    case authResponse(accepted: Bool, reason: String?, mirrorPort: Int?, protocolVersion: Int)
    case galleryRequest(page: Int, pageSize: Int)
    case galleryResponse(photos: [GalleryPhotoMeta], totalCount: Int, page: Int)
    case galleryThumbnailRequest(photoId: String)
    case galleryThumbnailResponse(photoId: String, data: String)
    case galleryPreviewRequest(photoId: String, maxSize: Int)
    case galleryPreviewResponse(photoId: String, data: String)
    case galleryDownloadRequest(photoId: String)
    case filesListRequest(path: String, page: Int, pageSize: Int,
                          sortBy: String = "name", sortDir: String = "asc",
                          foldersFirst: Bool = true, query: String = "")
    case filesListResponse(path: String, entries: [FileEntry], totalCount: Int, page: Int, needsPermission: Bool)
    case fileThumbnailRequest(path: String)
    case fileThumbnailResponse(path: String, data: String)
    case fileDownloadRequest(transferId: String, path: String)
    case fileDeleteRequest(path: String)
    case fileDeleteResponse(path: String, success: Bool, error: String?)
    case smsConversationsRequest(page: Int, pageSize: Int)
    case smsConversationsResponse(conversations: [SmsConversationMeta], totalCount: Int, page: Int)
    case smsMessagesRequest(threadId: String, page: Int, pageSize: Int)
    case smsMessagesResponse(threadId: String, messages: [SmsMessageMeta], totalCount: Int, page: Int)
    case smsSendRequest(address: String, body: String)
    case smsSendResponse(success: Bool, error: String?)
    case fileTransferOffer(transferId: String, filename: String, mimeType: String, fileSize: Int64, destinationDir: String?)
    case fileTransferAccept(transferId: String)
    case fileTransferReject(transferId: String)
    case mirrorStartRequest(token: String)
    /// Mac -> phone: "show MY screen on your phone" (reverse mirror).
    /// mode: 0 = mirror Mac's main display, 1 = virtual display shaped to phone.
    case reverseMirrorStart(token: String, mode: Int)
    case mirrorStop
    case mirrorError(reason: String)
    /// Mac -> phone: zadzwoń/znajdź telefon (głośny alarm) i zatrzymaj.
    case phoneRing
    case phoneRingStop
    case deviceInfoRequest
    case deviceInfoResponse(info: DeviceInfo)
    /// Mac -> phone: send your wallpaper for the Home hero. phone -> Mac: the
    /// wallpaper as base64 JPEG (empty string if unavailable).
    case wallpaperRequest
    case wallpaperResponse(imageBase64: String)
    /// phone -> Mac: send your own system info / wallpaper (phone as a Mac monitor).
    case macInfoRequest
    case macInfoResponse(info: MacInfo)
    case macWallpaperRequest
    case macWallpaperResponse(imageBase64: String)
    case folderStatsRequest(path: String)
    case folderStatsResponse(path: String, dirCount: Int, fileCount: Int, totalSize: Int64)
    case notificationPosted(packageName: String, appName: String, title: String, text: String, timestamp: Int64, appIcon: String, notificationKey: String, canReply: Bool)
    case notificationReply(notificationKey: String, text: String)
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

// MARK: - FileEntry

public struct FileEntry: Codable, Equatable, Identifiable, Sendable {
    public let name: String
    public let relativePath: String
    public let isDirectory: Bool
    public let size: Int64
    public let modified: Int64   // epoch millis
    public let mimeType: String

    public var id: String { relativePath }

    private enum CodingKeys: String, CodingKey {
        case name, size, modified
        case relativePath = "relative_path"
        case isDirectory  = "is_directory"
        case mimeType     = "mime_type"
    }

    public init(name: String, relativePath: String, isDirectory: Bool, size: Int64, modified: Int64, mimeType: String) {
        self.name = name
        self.relativePath = relativePath
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
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

// MARK: - DeviceInfo

public struct DeviceInfo: Codable, Equatable, Sendable {
    public let name: String            // exact / user-set device name (e.g. "Galaxy Z Fold7")
    public let model: String           // Build.MODEL (codename, e.g. "SM-F966B")
    public let manufacturer: String
    public let androidVersion: String  // Build.VERSION.RELEASE, e.g. "16"
    public let sdkInt: Int             // API level
    public let totalStorageBytes: Int64
    public let freeStorageBytes: Int64
    public let totalRamBytes: Int64
    public let freeRamBytes: Int64
    public let batteryPercent: Int
    public let batteryCharging: Bool
    public let chargeTimeRemainingMs: Int64

    private enum CodingKeys: String, CodingKey {
        case name, model, manufacturer
        case androidVersion     = "android_version"
        case sdkInt             = "sdk_int"
        case totalStorageBytes  = "total_storage_bytes"
        case freeStorageBytes   = "free_storage_bytes"
        case totalRamBytes      = "total_ram_bytes"
        case freeRamBytes       = "free_ram_bytes"
        case batteryPercent     = "battery_percent"
        case batteryCharging      = "battery_charging"
        case chargeTimeRemainingMs = "charge_time_remaining_ms"
    }

    public init(name: String, model: String, manufacturer: String, androidVersion: String, sdkInt: Int, totalStorageBytes: Int64, freeStorageBytes: Int64, totalRamBytes: Int64, freeRamBytes: Int64, batteryPercent: Int, batteryCharging: Bool = false, chargeTimeRemainingMs: Int64 = -1) {
        self.name = name
        self.model = model
        self.manufacturer = manufacturer
        self.androidVersion = androidVersion
        self.sdkInt = sdkInt
        self.totalStorageBytes = totalStorageBytes
        self.freeStorageBytes = freeStorageBytes
        self.totalRamBytes = totalRamBytes
        self.freeRamBytes = freeRamBytes
        self.batteryPercent = batteryPercent
        self.batteryCharging = batteryCharging
        self.chargeTimeRemainingMs = chargeTimeRemainingMs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        model = try c.decode(String.self, forKey: .model)
        manufacturer = try c.decode(String.self, forKey: .manufacturer)
        androidVersion = try c.decode(String.self, forKey: .androidVersion)
        sdkInt = try c.decode(Int.self, forKey: .sdkInt)
        totalStorageBytes = try c.decode(Int64.self, forKey: .totalStorageBytes)
        freeStorageBytes = try c.decode(Int64.self, forKey: .freeStorageBytes)
        totalRamBytes = try c.decode(Int64.self, forKey: .totalRamBytes)
        freeRamBytes = try c.decode(Int64.self, forKey: .freeRamBytes)
        batteryPercent = try c.decode(Int.self, forKey: .batteryPercent)
        batteryCharging = try c.decodeIfPresent(Bool.self, forKey: .batteryCharging) ?? false
        chargeTimeRemainingMs = try c.decodeIfPresent(Int64.self, forKey: .chargeTimeRemainingMs) ?? -1
    }
}

// MARK: - MacInfo

/// The Mac's own system info, sent to the phone so it can act as a resource
/// monitor / controller for the computer.
public struct MacInfo: Codable, Equatable, Sendable {
    public let name: String              // computer name
    public let model: String             // friendly model, e.g. "MacBook Pro"
    public let chip: String              // e.g. "Apple M3 Pro"
    public let osVersion: String         // e.g. "macOS 26.0"
    public let cpuCores: Int
    public let cpuLoadPercent: Int       // live CPU usage 0-100
    public let totalRamBytes: Int64
    public let usedRamBytes: Int64
    public let totalStorageBytes: Int64
    public let freeStorageBytes: Int64
    public let batteryPercent: Int       // -1 if no battery (desktop)
    public let batteryCharging: Bool
    public let onACPower: Bool
    public let uptimeSeconds: Int64

    private enum CodingKeys: String, CodingKey {
        case name, model, chip
        case osVersion          = "os_version"
        case cpuCores           = "cpu_cores"
        case cpuLoadPercent     = "cpu_load_percent"
        case totalRamBytes      = "total_ram_bytes"
        case usedRamBytes       = "used_ram_bytes"
        case totalStorageBytes  = "total_storage_bytes"
        case freeStorageBytes   = "free_storage_bytes"
        case batteryPercent     = "battery_percent"
        case batteryCharging    = "battery_charging"
        case onACPower          = "on_ac_power"
        case uptimeSeconds      = "uptime_seconds"
    }

    public init(name: String, model: String, chip: String, osVersion: String, cpuCores: Int, cpuLoadPercent: Int, totalRamBytes: Int64, usedRamBytes: Int64, totalStorageBytes: Int64, freeStorageBytes: Int64, batteryPercent: Int, batteryCharging: Bool, onACPower: Bool, uptimeSeconds: Int64) {
        self.name = name; self.model = model; self.chip = chip; self.osVersion = osVersion
        self.cpuCores = cpuCores; self.cpuLoadPercent = cpuLoadPercent
        self.totalRamBytes = totalRamBytes; self.usedRamBytes = usedRamBytes
        self.totalStorageBytes = totalStorageBytes; self.freeStorageBytes = freeStorageBytes
        self.batteryPercent = batteryPercent; self.batteryCharging = batteryCharging
        self.onACPower = onACPower; self.uptimeSeconds = uptimeSeconds
    }

    /// Tolerant decoding mirroring the Android decoder (Message.kt), which
    /// reads these fields with optInt/optBoolean/optLong and defaults. Encoding
    /// stays synthesized so every field is always sent.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        model = try c.decode(String.self, forKey: .model)
        chip = try c.decode(String.self, forKey: .chip)
        osVersion = try c.decode(String.self, forKey: .osVersion)
        cpuCores = try c.decode(Int.self, forKey: .cpuCores)
        cpuLoadPercent = try c.decodeIfPresent(Int.self, forKey: .cpuLoadPercent) ?? 0
        totalRamBytes = try c.decode(Int64.self, forKey: .totalRamBytes)
        usedRamBytes = try c.decode(Int64.self, forKey: .usedRamBytes)
        totalStorageBytes = try c.decode(Int64.self, forKey: .totalStorageBytes)
        freeStorageBytes = try c.decode(Int64.self, forKey: .freeStorageBytes)
        batteryPercent = try c.decode(Int.self, forKey: .batteryPercent)
        batteryCharging = try c.decodeIfPresent(Bool.self, forKey: .batteryCharging) ?? false
        onACPower = try c.decodeIfPresent(Bool.self, forKey: .onACPower) ?? false
        uptimeSeconds = try c.decodeIfPresent(Int64.self, forKey: .uptimeSeconds) ?? 0
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
        case galleryPreviewRequest    = "gallery_preview_request"
        case galleryPreviewResponse   = "gallery_preview_response"
        case galleryDownloadRequest   = "gallery_download_request"
        case filesListRequest         = "files_list_request"
        case filesListResponse        = "files_list_response"
        case fileThumbnailRequest     = "file_thumbnail_request"
        case fileThumbnailResponse    = "file_thumbnail_response"
        case fileDownloadRequest      = "file_download_request"
        case fileDeleteRequest        = "file_delete_request"
        case fileDeleteResponse       = "file_delete_response"
        case smsConversationsRequest  = "sms_conversations_request"
        case smsConversationsResponse = "sms_conversations_response"
        case smsMessagesRequest       = "sms_messages_request"
        case smsMessagesResponse      = "sms_messages_response"
        case smsSendRequest           = "sms_send_request"
        case smsSendResponse          = "sms_send_response"
        case fileTransferOffer        = "file_transfer_offer"
        case fileTransferAccept       = "file_transfer_accept"
        case fileTransferReject       = "file_transfer_reject"
        case mirrorStartRequest       = "mirror_start_request"
        case reverseMirrorStart       = "reverse_mirror_start"
        case mirrorStop               = "mirror_stop"
        case phoneRing                = "phone_ring"
        case phoneRingStop            = "phone_ring_stop"
        case mirrorError              = "mirror_error"
        case deviceInfoRequest        = "device_info_request"
        case deviceInfoResponse       = "device_info_response"
        case wallpaperRequest         = "wallpaper_request"
        case wallpaperResponse        = "wallpaper_response"
        case macInfoRequest           = "mac_info_request"
        case macInfoResponse          = "mac_info_response"
        case macWallpaperRequest      = "mac_wallpaper_request"
        case macWallpaperResponse     = "mac_wallpaper_response"
        case folderStatsRequest       = "folder_stats_request"
        case folderStatsResponse      = "folder_stats_response"
        case notificationPosted       = "notification_posted"
        case notificationReply        = "notification_reply"
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
        case mirrorPort         = "mirror_port"
        case protocolVersion    = "protocol_version"
        case page
        case pageSize           = "page_size"
        case sortBy             = "sort_by"
        case sortDir            = "sort_dir"
        case foldersFirst       = "folders_first"
        case query
        case totalCount         = "total_count"
        case photos
        case photoId            = "photo_id"
        case maxSize            = "max_size"
        case conversations
        case messages
        case threadId           = "thread_id"
        case address
        case body
        case success
        case error
        case fileSize           = "file_size"
        case token
        case path
        case entries
        case isDirectory        = "is_directory"
        case needsPermission    = "needs_permission"
        case destinationDir     = "destination_dir"
        case info
        case dirCount           = "dir_count"
        case fileCount          = "file_count"
        case mode
        case image
        case title
        case text
        case packageName        = "package_name"
        case appName            = "app_name"
        case appIcon            = "app_icon"
        case notificationKey    = "notification_key"
        case canReply           = "can_reply"
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

        case .authRequest(let publicKey, let signature, let timestamp, let protocolVersion):
            try container.encode(TypeKey.authRequest.rawValue, forKey: .type)
            try container.encode(publicKey, forKey: .publicKey)
            try container.encode(signature, forKey: .signature)
            try container.encode(timestamp, forKey: .timestamp)
            try container.encode(protocolVersion, forKey: .protocolVersion)

        case .authResponse(let accepted, let reason, let mirrorPort, let protocolVersion):
            try container.encode(TypeKey.authResponse.rawValue, forKey: .type)
            try container.encode(accepted, forKey: .accepted)
            try container.encodeIfPresent(reason, forKey: .reason)
            try container.encodeIfPresent(mirrorPort, forKey: .mirrorPort)
            try container.encode(protocolVersion, forKey: .protocolVersion)

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

        case .galleryPreviewRequest(let photoId, let maxSize):
            try container.encode(TypeKey.galleryPreviewRequest.rawValue, forKey: .type)
            try container.encode(photoId, forKey: .photoId)
            try container.encode(maxSize, forKey: .maxSize)

        case .galleryPreviewResponse(let photoId, let data):
            try container.encode(TypeKey.galleryPreviewResponse.rawValue, forKey: .type)
            try container.encode(photoId, forKey: .photoId)
            try container.encode(data, forKey: .data)

        case .galleryDownloadRequest(let photoId):
            try container.encode(TypeKey.galleryDownloadRequest.rawValue, forKey: .type)
            try container.encode(photoId, forKey: .photoId)

        case .filesListRequest(let path, let page, let pageSize, let sortBy, let sortDir, let foldersFirst, let query):
            try container.encode(TypeKey.filesListRequest.rawValue, forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encode(page, forKey: .page)
            try container.encode(pageSize, forKey: .pageSize)
            try container.encode(sortBy, forKey: .sortBy)
            try container.encode(sortDir, forKey: .sortDir)
            try container.encode(foldersFirst, forKey: .foldersFirst)
            try container.encode(query, forKey: .query)

        case .filesListResponse(let path, let entries, let totalCount, let page, let needsPermission):
            try container.encode(TypeKey.filesListResponse.rawValue, forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encode(entries, forKey: .entries)
            try container.encode(totalCount, forKey: .totalCount)
            try container.encode(page, forKey: .page)
            try container.encode(needsPermission, forKey: .needsPermission)

        case .fileThumbnailRequest(let path):
            try container.encode(TypeKey.fileThumbnailRequest.rawValue, forKey: .type)
            try container.encode(path, forKey: .path)

        case .fileThumbnailResponse(let path, let data):
            try container.encode(TypeKey.fileThumbnailResponse.rawValue, forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encode(data, forKey: .data)

        case .fileDownloadRequest(let transferId, let path):
            try container.encode(TypeKey.fileDownloadRequest.rawValue, forKey: .type)
            try container.encode(transferId, forKey: .transferId)
            try container.encode(path, forKey: .path)

        case .fileDeleteRequest(let path):
            try container.encode(TypeKey.fileDeleteRequest.rawValue, forKey: .type)
            try container.encode(path, forKey: .path)

        case .fileDeleteResponse(let path, let success, let error):
            try container.encode(TypeKey.fileDeleteResponse.rawValue, forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encode(success, forKey: .success)
            try container.encodeIfPresent(error, forKey: .error)

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

        case .fileTransferOffer(let transferId, let filename, let mimeType, let fileSize, let destinationDir):
            try container.encode(TypeKey.fileTransferOffer.rawValue, forKey: .type)
            try container.encode(transferId, forKey: .transferId)
            try container.encode(filename, forKey: .filename)
            try container.encode(mimeType, forKey: .mimeType)
            try container.encode(fileSize, forKey: .fileSize)
            try container.encodeIfPresent(destinationDir, forKey: .destinationDir)

        case .fileTransferAccept(let transferId):
            try container.encode(TypeKey.fileTransferAccept.rawValue, forKey: .type)
            try container.encode(transferId, forKey: .transferId)

        case .fileTransferReject(let transferId):
            try container.encode(TypeKey.fileTransferReject.rawValue, forKey: .type)
            try container.encode(transferId, forKey: .transferId)

        case let .mirrorStartRequest(token):
            try container.encode(TypeKey.mirrorStartRequest.rawValue, forKey: .type)
            try container.encode(token, forKey: .token)

        case let .reverseMirrorStart(token, mode):
            try container.encode(TypeKey.reverseMirrorStart.rawValue, forKey: .type)
            try container.encode(token, forKey: .token)
            try container.encode(mode, forKey: .mode)

        case .mirrorStop:
            try container.encode(TypeKey.mirrorStop.rawValue, forKey: .type)

        case .phoneRing:
            try container.encode(TypeKey.phoneRing.rawValue, forKey: .type)

        case .phoneRingStop:
            try container.encode(TypeKey.phoneRingStop.rawValue, forKey: .type)

        case let .mirrorError(reason):
            try container.encode(TypeKey.mirrorError.rawValue, forKey: .type)
            try container.encode(reason, forKey: .reason)

        case .deviceInfoRequest:
            try container.encode(TypeKey.deviceInfoRequest.rawValue, forKey: .type)

        case .deviceInfoResponse(let info):
            try container.encode(TypeKey.deviceInfoResponse.rawValue, forKey: .type)
            try container.encode(info, forKey: .info)

        case .wallpaperRequest:
            try container.encode(TypeKey.wallpaperRequest.rawValue, forKey: .type)

        case .wallpaperResponse(let imageBase64):
            try container.encode(TypeKey.wallpaperResponse.rawValue, forKey: .type)
            try container.encode(imageBase64, forKey: .image)

        case .macInfoRequest:
            try container.encode(TypeKey.macInfoRequest.rawValue, forKey: .type)

        case .macInfoResponse(let info):
            try container.encode(TypeKey.macInfoResponse.rawValue, forKey: .type)
            try container.encode(info, forKey: .info)

        case .macWallpaperRequest:
            try container.encode(TypeKey.macWallpaperRequest.rawValue, forKey: .type)

        case .macWallpaperResponse(let imageBase64):
            try container.encode(TypeKey.macWallpaperResponse.rawValue, forKey: .type)
            try container.encode(imageBase64, forKey: .image)

        case .folderStatsRequest(let path):
            try container.encode(TypeKey.folderStatsRequest.rawValue, forKey: .type)
            try container.encode(path, forKey: .path)

        case .folderStatsResponse(let path, let dirCount, let fileCount, let totalSize):
            try container.encode(TypeKey.folderStatsResponse.rawValue, forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encode(dirCount, forKey: .dirCount)
            try container.encode(fileCount, forKey: .fileCount)
            try container.encode(totalSize, forKey: .totalSize)

        case .notificationPosted(let packageName, let appName, let title, let text, let timestamp, let appIcon, let notificationKey, let canReply):
            try container.encode(TypeKey.notificationPosted.rawValue, forKey: .type)
            try container.encode(packageName, forKey: .packageName)
            try container.encode(appName, forKey: .appName)
            try container.encode(title, forKey: .title)
            try container.encode(text, forKey: .text)
            try container.encode(timestamp, forKey: .timestamp)
            try container.encode(appIcon, forKey: .appIcon)
            try container.encode(notificationKey, forKey: .notificationKey)
            try container.encode(canReply, forKey: .canReply)

        case .notificationReply(let notificationKey, let text):
            try container.encode(TypeKey.notificationReply.rawValue, forKey: .type)
            try container.encode(notificationKey, forKey: .notificationKey)
            try container.encode(text, forKey: .text)
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
            // Older peers do not send protocol_version — treat them as v1.
            let protocolVersion = try container.decodeIfPresent(Int.self, forKey: .protocolVersion) ?? 1
            self = .authRequest(publicKey: publicKey, signature: signature, timestamp: timestamp, protocolVersion: protocolVersion)

        case .authResponse:
            let accepted = try container.decode(Bool.self, forKey: .accepted)
            let reason = try container.decodeIfPresent(String.self, forKey: .reason)
            let mirrorPort = try container.decodeIfPresent(Int.self, forKey: .mirrorPort)
            // Older peers do not send protocol_version — treat them as v1.
            let protocolVersion = try container.decodeIfPresent(Int.self, forKey: .protocolVersion) ?? 1
            self = .authResponse(accepted: accepted, reason: reason, mirrorPort: mirrorPort, protocolVersion: protocolVersion)

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

        case .galleryPreviewRequest:
            let photoId = try container.decode(String.self, forKey: .photoId)
            let maxSize = try container.decode(Int.self, forKey: .maxSize)
            self = .galleryPreviewRequest(photoId: photoId, maxSize: maxSize)

        case .galleryPreviewResponse:
            let photoId = try container.decode(String.self, forKey: .photoId)
            let data = try container.decode(String.self, forKey: .data)
            self = .galleryPreviewResponse(photoId: photoId, data: data)

        case .galleryDownloadRequest:
            let photoId = try container.decode(String.self, forKey: .photoId)
            self = .galleryDownloadRequest(photoId: photoId)

        case .filesListRequest:
            let path = try container.decode(String.self, forKey: .path)
            let page = try container.decode(Int.self, forKey: .page)
            let pageSize = try container.decode(Int.self, forKey: .pageSize)
            let sortBy = try container.decodeIfPresent(String.self, forKey: .sortBy) ?? "name"
            let sortDir = try container.decodeIfPresent(String.self, forKey: .sortDir) ?? "asc"
            let foldersFirst = try container.decodeIfPresent(Bool.self, forKey: .foldersFirst) ?? true
            let query = try container.decodeIfPresent(String.self, forKey: .query) ?? ""
            self = .filesListRequest(path: path, page: page, pageSize: pageSize,
                                     sortBy: sortBy, sortDir: sortDir,
                                     foldersFirst: foldersFirst, query: query)

        case .filesListResponse:
            let path = try container.decode(String.self, forKey: .path)
            let entries = try container.decode([FileEntry].self, forKey: .entries)
            let totalCount = try container.decode(Int.self, forKey: .totalCount)
            let page = try container.decode(Int.self, forKey: .page)
            let needsPermission = try container.decode(Bool.self, forKey: .needsPermission)
            self = .filesListResponse(path: path, entries: entries, totalCount: totalCount, page: page, needsPermission: needsPermission)

        case .fileThumbnailRequest:
            let path = try container.decode(String.self, forKey: .path)
            self = .fileThumbnailRequest(path: path)

        case .fileThumbnailResponse:
            let path = try container.decode(String.self, forKey: .path)
            let data = try container.decode(String.self, forKey: .data)
            self = .fileThumbnailResponse(path: path, data: data)

        case .fileDownloadRequest:
            let transferId = try container.decode(String.self, forKey: .transferId)
            let path = try container.decode(String.self, forKey: .path)
            self = .fileDownloadRequest(transferId: transferId, path: path)

        case .fileDeleteRequest:
            let path = try container.decode(String.self, forKey: .path)
            self = .fileDeleteRequest(path: path)

        case .fileDeleteResponse:
            let path = try container.decode(String.self, forKey: .path)
            let success = try container.decode(Bool.self, forKey: .success)
            let error = try container.decodeIfPresent(String.self, forKey: .error)
            self = .fileDeleteResponse(path: path, success: success, error: error)

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

        case .fileTransferOffer:
            let transferId = try container.decode(String.self, forKey: .transferId)
            let filename = try container.decode(String.self, forKey: .filename)
            let mimeType = try container.decode(String.self, forKey: .mimeType)
            let fileSize = try container.decode(Int64.self, forKey: .fileSize)
            let destinationDir = try container.decodeIfPresent(String.self, forKey: .destinationDir)
            self = .fileTransferOffer(transferId: transferId, filename: filename, mimeType: mimeType, fileSize: fileSize, destinationDir: destinationDir)

        case .fileTransferAccept:
            let transferId = try container.decode(String.self, forKey: .transferId)
            self = .fileTransferAccept(transferId: transferId)

        case .fileTransferReject:
            let transferId = try container.decode(String.self, forKey: .transferId)
            self = .fileTransferReject(transferId: transferId)

        case .mirrorStartRequest:
            let token = try container.decode(String.self, forKey: .token)
            self = .mirrorStartRequest(token: token)

        case .reverseMirrorStart:
            let token = try container.decode(String.self, forKey: .token)
            let mode = try container.decodeIfPresent(Int.self, forKey: .mode) ?? 0
            self = .reverseMirrorStart(token: token, mode: mode)

        case .mirrorStop:
            self = .mirrorStop

        case .phoneRing:
            self = .phoneRing

        case .phoneRingStop:
            self = .phoneRingStop

        case .mirrorError:
            let reason = try container.decode(String.self, forKey: .reason)
            self = .mirrorError(reason: reason)

        case .deviceInfoRequest:
            self = .deviceInfoRequest

        case .deviceInfoResponse:
            let info = try container.decode(DeviceInfo.self, forKey: .info)
            self = .deviceInfoResponse(info: info)

        case .wallpaperRequest:
            self = .wallpaperRequest

        case .wallpaperResponse:
            let image = try container.decode(String.self, forKey: .image)
            self = .wallpaperResponse(imageBase64: image)

        case .macInfoRequest:
            self = .macInfoRequest

        case .macInfoResponse:
            let info = try container.decode(MacInfo.self, forKey: .info)
            self = .macInfoResponse(info: info)

        case .macWallpaperRequest:
            self = .macWallpaperRequest

        case .macWallpaperResponse:
            let image = try container.decode(String.self, forKey: .image)
            self = .macWallpaperResponse(imageBase64: image)

        case .folderStatsRequest:
            let path = try container.decode(String.self, forKey: .path)
            self = .folderStatsRequest(path: path)

        case .folderStatsResponse:
            let path = try container.decode(String.self, forKey: .path)
            let dirCount = try container.decode(Int.self, forKey: .dirCount)
            let fileCount = try container.decode(Int.self, forKey: .fileCount)
            let totalSize = try container.decode(Int64.self, forKey: .totalSize)
            self = .folderStatsResponse(path: path, dirCount: dirCount, fileCount: fileCount, totalSize: totalSize)

        case .notificationPosted:
            let packageName = try container.decode(String.self, forKey: .packageName)
            let appName = try container.decode(String.self, forKey: .appName)
            let title = try container.decode(String.self, forKey: .title)
            let text = try container.decode(String.self, forKey: .text)
            let timestamp = try container.decode(Int64.self, forKey: .timestamp)
            let appIcon = try container.decodeIfPresent(String.self, forKey: .appIcon) ?? ""
            let notificationKey = try container.decodeIfPresent(String.self, forKey: .notificationKey) ?? ""
            let canReply = try container.decodeIfPresent(Bool.self, forKey: .canReply) ?? false
            self = .notificationPosted(packageName: packageName, appName: appName, title: title, text: text, timestamp: timestamp, appIcon: appIcon, notificationKey: notificationKey, canReply: canReply)

        case .notificationReply:
            let notificationKey = try container.decode(String.self, forKey: .notificationKey)
            let text = try container.decode(String.self, forKey: .text)
            self = .notificationReply(notificationKey: notificationKey, text: text)
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
    /// Lowercase SHA-256 hex over the Mac's TLS certificate DER. The phone
    /// pins this fingerprint for all TLS connections to the Mac.
    public let certFingerprint: String
    public let protocolVersion: Int

    private enum CodingKeys: String, CodingKey {
        case host
        case port
        case publicKey       = "public_key"
        case pairingToken    = "pairing_token"
        case certFingerprint = "cert_fingerprint"
        case protocolVersion = "protocol_version"
    }

    public init(
        host: String,
        port: Int,
        publicKey: String,
        pairingToken: String,
        certFingerprint: String,
        protocolVersion: Int = ProtocolConstants.version
    ) {
        self.host = host
        self.port = port
        self.publicKey = publicKey
        self.pairingToken = pairingToken
        self.certFingerprint = certFingerprint
        self.protocolVersion = protocolVersion
    }
}
