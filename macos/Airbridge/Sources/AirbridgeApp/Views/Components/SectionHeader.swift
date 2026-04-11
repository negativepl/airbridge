import SwiftUI

/// Small, uppercase, tracked section label. Used by GlassSection as the default header.
///
/// Matches the typography Settings.app uses for grouped list section titles.
struct SectionHeader: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil

    var body: some View {
        Group {
            if let systemImage, !systemImage.isEmpty {
                Label(title, systemImage: systemImage)
                    .labelStyle(.titleAndIcon)
            } else {
                Text(title)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .tracking(0.5)
    }
}
