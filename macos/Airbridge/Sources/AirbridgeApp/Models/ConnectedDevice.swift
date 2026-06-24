import Foundation
import Protocol

/// One live phone connection. Keyed for routing by `connectionId` ("host:port");
/// identified across reconnects by `publicKey` (Ed25519, base64).
struct ConnectedDevice: Identifiable, Equatable {
    let connectionId: String
    let publicKey: String
    var name: String
    var clientIP: String?
    var deviceInfo: DeviceInfo?
    var wallpaper: Data?      // the phone's wallpaper (phone → Mac), for the Home hero
    var id: String { connectionId }
}
