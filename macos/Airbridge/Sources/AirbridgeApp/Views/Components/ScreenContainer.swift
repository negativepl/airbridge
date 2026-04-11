import SwiftUI

/// Standard wrapper for every main screen in the app.
///
/// Provides:
/// - `GlassEffectContainer` — one shared blur layer so all inner `.glassEffect`
///   elements merge visually (this is the cornerstone of Liquid Glass use)
/// - `ScrollView` with `.scrollEdgeEffect(.soft)` at top and bottom so content
///   softly fades at scroll edges (Apple standard in Settings.app)
/// - 24pt padding around the content
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
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
            } else {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
