import SwiftUI

struct HistoryView: View {
    let historyService: HistoryService

    var body: some View {
        if historyService.records.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "clock")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                    .symbolEffect(.pulse, options: .repeating)

                Text(L10n.isPL ? "Brak aktywności" : "No Activity")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Text(L10n.isPL
                    ? "Ostatnio brak aktywności.\nHistoria synchronizacji i przesłanych plików pojawi się tutaj."
                    : "No recent activity.\nSync and transfer history will appear here.")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LazyVStack(spacing: 6) {
                ForEach(historyService.records) { record in
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
            }
        }
    }
}
