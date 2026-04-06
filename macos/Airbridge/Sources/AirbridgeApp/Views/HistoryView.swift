import SwiftUI

struct HistoryView: View {
    let historyService: HistoryService

    var body: some View {
        if historyService.records.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "clock")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)

                Text(L10n.isPL ? "Brak aktywności" : "No Activity")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Text(L10n.isPL
                    ? "Ostatnio brak aktywności.\nHistoria synchronizacji i przesłanych plików pojawi się tutaj."
                    : "No recent activity.\nSync and transfer history will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(historyService.records) { record in
                        HStack(spacing: 10) {
                            Image(systemName: record.type == .clipboard ? "doc.on.clipboard" : "doc.fill")
                                .foregroundStyle(record.direction == .sent ? Color.primary : Color.accentColor)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.description).font(.body).lineLimit(1)
                                Text(record.direction == .sent
                                     ? (L10n.isPL ? "Wysłano" : "Sent")
                                     : (L10n.isPL ? "Odebrano" : "Received"))
                                    .font(.caption)
                                    .foregroundStyle(record.direction == .sent ? Color.secondary : Color.accentColor)
                            }
                            Spacer()
                            Text(record.timestamp, style: .relative)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        Divider().padding(.leading, 44)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
