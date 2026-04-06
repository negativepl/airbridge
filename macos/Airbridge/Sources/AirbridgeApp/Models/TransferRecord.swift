import Foundation

struct TransferRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let type: TransferType
    let direction: Direction
    let description: String

    enum TransferType: String, Codable {
        case clipboard
        case file
    }

    enum Direction: String, Codable {
        case sent
        case received
    }

    init(id: UUID = UUID(), timestamp: Date = Date(), type: TransferType, direction: Direction, description: String) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.direction = direction
        self.description = description
    }
}
