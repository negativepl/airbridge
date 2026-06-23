import SwiftUI

/// Opaque content-card surface.
///
/// Liquid Glass is reserved for the *chrome / control* layer — toolbar,
/// sidebar, floating buttons and pills — per Apple's Liquid Glass HIG, which
/// cautions against putting glass on content or stacking glass on glass. Doing
/// the latter made content cards refract the desktop through their edges and
/// pick up reflections from neighbouring glass (e.g. the green connection dot).
/// Content cards therefore use a solid grouped material instead.
extension View {
    func contentCard(cornerRadius: CGFloat = 18) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(shape.fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(shape.strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }
}

/// Standard titled content card for grouped content.
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
        .contentCard(cornerRadius: cornerRadius)
    }
}

/// Compact unnamed content row for lists (history, conversations, gallery tiles).
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
            .contentCard(cornerRadius: cornerRadius)
    }
}
