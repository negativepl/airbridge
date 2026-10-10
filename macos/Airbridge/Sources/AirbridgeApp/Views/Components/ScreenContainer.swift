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
        // The minimum belongs to the detail column: a minimum on the whole
        // TabView went to the detail column alone, and in a window narrower
        // than sidebar + minimum the sidebar slid three quarters of the way
        // open and then snapped. The window's own minimum is set in MainWindow.
        content_
            .frame(minWidth: ScreenMetrics.minDetailWidth, minHeight: 600)
    }

    @ViewBuilder private var content_: some View {
        if scroll {
            ScrollView {
                VStack(spacing: 10) {
                    content
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

enum ScreenMetrics {
    /// Room the sidebar takes while it is shown (the system default width).
    static let sidebarWidth: CGFloat = 210
    /// Messages needs its 320 pt list beside a conversation that still has
    /// room for bubbles; squeezed below this the panes started to jitter.
    static let minDetailWidth: CGFloat = 820
}
