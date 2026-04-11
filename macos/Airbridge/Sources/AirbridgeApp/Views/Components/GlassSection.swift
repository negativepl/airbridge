import SwiftUI

/// Standard titled glass card for grouped content.
///
/// Uses `.containerRelative` shape so its corner radius is automatically
/// concentric with the enclosing window/GlassEffectContainer — no magic numbers.
///
/// Usage:
///
///     GlassSection(title: "Connection", systemImage: "antenna.radiowaves.left.and.right") {
///         Text("Pixel 8")
///         Text("192.168.1.14")
///     }
struct GlassSection<Content: View>: View {
    var title: LocalizedStringKey? = nil
    var systemImage: String? = nil
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                SectionHeader(title: title, systemImage: systemImage)
            }
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .containerRelative)
    }
}

/// Compact unnamed glass row for lists (history, conversations, gallery tiles).
///
/// Smaller padding than GlassSection, no header, same concentric corner treatment.
struct GlassRow<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .containerRelative)
    }
}
