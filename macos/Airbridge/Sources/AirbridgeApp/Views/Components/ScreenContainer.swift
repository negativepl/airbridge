import SwiftUI

/// Standard wrapper for every main screen in the app.
///
/// Provides:
/// - `GlassEffectContainer` — shared blur layer so all inner `.glassEffect`
///   elements merge visually (the cornerstone of Liquid Glass use).
/// - `ScrollView` that extends past the top/bottom safe area (so content can
///   physically scroll under the transparent window toolbar), with
///   `.scrollEdgeEffectStyle(.soft)` providing the Liquid Glass blur fade at
///   those edges, and `.contentMargins(for: .scrollContent)` keeping the
///   first/last item out of the traffic-lights / tab-bar zone.
/// - 24pt horizontal padding around the content via contentMargins.
///
/// Pass `scroll: false` for screens with their own internal scrolling
/// (GalleryView grid, MessagesView split view).
struct ScreenContainer<Content: View>: View {
    var scroll: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            if scroll {
                ScrollView {
                    VStack(spacing: 16) {
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .contentMargins(.horizontal, 24, for: .scrollContent)
                .contentMargins(.top, 28, for: .scrollContent)
                .contentMargins(.bottom, 24, for: .scrollContent)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                .ignoresSafeArea(edges: [.top, .bottom])
            } else {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
