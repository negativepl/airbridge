import SwiftUI

/// Standard wrapper for every main screen in the app.
///
/// Structure is DELIBERATE: `ScrollView` is the **outer** view so SwiftUI can
/// automatically detect the window chrome and apply the native Liquid Glass
/// scroll edge effect (content blurs as it scrolls under the toolbar / title
/// bar). `GlassEffectContainer` wraps the inner content so per-card
/// `.glassEffect` elements still merge into one blur layer — but it no longer
/// wraps the ScrollView, which was breaking the automatic scroll edge effect.
///
/// macOS 26 applies the scroll edge blur automatically when the window has a
/// `.containerBackground(.thinMaterial)` (set in AirbridgeApp) and the
/// ScrollView is a direct descendant of the window's content column — no
/// manual `scrollEdgeEffectStyle` / `contentMargins` / `ignoresSafeArea`
/// needed.
///
/// Pass `scroll: false` for screens with their own internal scrolling
/// (GalleryView grid, MessagesView split view).
struct ScreenContainer<Content: View>: View {
    var scroll: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        if scroll {
            ScrollView {
                GlassEffectContainer(spacing: 16) {
                    VStack(spacing: 16) {
                        content
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        } else {
            GlassEffectContainer(spacing: 16) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
