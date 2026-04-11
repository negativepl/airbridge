import SwiftUI

struct HistoryView: View {
    let historyService: HistoryService

    @State private var displayedCount: Int = 30
    private let pageSize: Int = 30

    var body: some View {
        if historyService.records.isEmpty {
            emptyView
        } else {
            LazyVStack(spacing: 10) {
                ForEach(historyService.records.prefix(displayedCount)) { record in
                    recordRow(record)
                }

                if displayedCount < historyService.records.count {
                    paginationLoader
                }
            }
            .onChange(of: historyService.records.count) { _, _ in
                // Reset pagination when records refresh entirely
                if displayedCount > historyService.records.count {
                    displayedCount = min(pageSize, historyService.records.count)
                }
            }
        }
    }

    private var emptyView: some View {
        EmptyStateView(
            systemImage: "clock",
            title: L10n.isPL ? "Brak aktywności" : "No Activity",
            subtitle: L10n.isPL
                ? "Ostatnio brak aktywności.\nHistoria synchronizacji i przesłanych plików pojawi się tutaj."
                : "No recent activity.\nSync and transfer history will appear here.",
            pulseIcon: true
        )
    }

    private func recordRow(_ record: TransferRecord) -> some View {
        GlassRow {
            HStack(spacing: 12) {
                Image(systemName: record.type == .clipboard ? "doc.on.clipboard" : "doc.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .glassEffect(
                        record.direction == .sent
                            ? .regular.tint(.blue)
                            : .regular.tint(.green),
                        in: .rect(cornerRadius: 8)
                    )
                    .contentTransition(.symbolEffect(.replace))

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.description)
                        .font(.system(size: 15))
                        .lineLimit(1)
                    Text(record.direction == .sent
                         ? (L10n.isPL ? "Wysłano" : "Sent")
                         : (L10n.isPL ? "Odebrano" : "Received"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(record.timestamp, style: .relative)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var paginationLoader: some View {
        ProgressView()
            .controlSize(.regular)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .onAppear {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    withAnimation(.airbridgeQuick) {
                        displayedCount = min(displayedCount + pageSize, historyService.records.count)
                    }
                }
            }
    }
}
