import Foundation

@Observable
@MainActor
final class HistoryViewModel {
    @ObservationIgnored private let historyService: HistoryService

    init(historyService: HistoryService) {
        self.historyService = historyService
    }

    var records: [TransferRecord] { historyService.records }
    var isEmpty: Bool { records.isEmpty }
}
