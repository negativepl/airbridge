import SwiftUI

/// Standard titled glass card for grouped content.
///
/// Uses an explicit 18pt continuous corner radius. We tried `.containerRelative`
/// for concentric corners, but in macOS 26 `TabView.sidebarAdaptable` content
/// has no enclosing rounded container, so `containerRelative` fell back to 0
/// and every card rendered as a hard rectangle.
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
    var cornerRadius: CGFloat = 18
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
        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Compact unnamed glass row for lists (history, conversations, gallery tiles).
///
/// Smaller padding and a tighter 12pt continuous corner.
struct GlassRow<Content: View>: View {
    var padding: CGFloat = 12
    var cornerRadius: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))
    }
}
