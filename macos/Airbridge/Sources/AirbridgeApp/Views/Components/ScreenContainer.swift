import SwiftUI

/// Standard wrapper for every main screen in the app.
///
/// Minimal by design: just `GlassEffectContainer` (so per-card `.glassEffect`
/// elements share one blur layer) and a plain `ScrollView` with content.
///
/// The macOS 26 Liquid Glass scroll-under-toolbar blur effect is **automatic**
/// on Apple's native chrome — we don't touch scrollEdgeEffectStyle, safe areas,
/// or content margins. The window's `.containerBackground(.thinMaterial)` +
/// standard toolbar is enough for the system to apply the native blur.
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
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
