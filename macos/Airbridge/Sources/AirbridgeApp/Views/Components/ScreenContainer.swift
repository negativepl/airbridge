import SwiftUI

/// Standard wrapper for every main screen in the app.
///
/// Just a plain `ScrollView` so macOS 26 can apply its automatic Liquid Glass
/// scroll edge effect (content blurs natively as it scrolls under the window
/// toolbar). Per Apple's Landmarks sample guidance, `GlassEffectContainer` is
/// for floating navigation-layer controls only — never for content / ScrollView
/// wrappers, because it interferes with the chrome-layer sampling the scroll
/// edge effect depends on.
///
/// Requirements for the automatic blur to fire (set outside this file):
/// - `Window` scene has NO custom `.windowStyle(.hiddenTitleBar)` and NO
///   `.containerBackground(.thinMaterial, for: .window)` — those kill the top
///   safe area and override the system Liquid Glass window material.
/// - The `TabView` has a `.toolbar { }` block with at least one `ToolbarItem`,
///   which installs the window toolbar area that becomes the top safe area.
///
/// Pass `scroll: false` for screens with their own internal scrolling
/// (GalleryView grid, MessagesView split view).
struct ScreenContainer<Content: View>: View {
    var scroll: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
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
