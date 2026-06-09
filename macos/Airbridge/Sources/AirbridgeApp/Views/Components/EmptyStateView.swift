import SwiftUI

/// Unified empty / disconnected / not-found state shown centered on the
/// whole available area. Used everywhere the app needs to tell the user
/// "nothing to show here, and here's why" — disconnected device, empty
/// history, no photos, no messages selected, etc.
///
/// Sizes are fixed so every empty state in the app looks identical:
/// - icon: 40pt, tertiary foreground
/// - title: 20pt semibold, secondary foreground
/// - subtitle: 14pt, tertiary foreground, center-aligned, multi-line
/// - 14pt vertical spacing
///
/// Pass `pulseIcon: true` to make the icon slowly pulse via symbolEffect
/// (for idle states like "no activity yet").
struct EmptyStateView<Actions: View>: View {
    let systemImage: String
    let title: String
    let subtitle: String
    var pulseIcon: Bool = false
    @ViewBuilder var actions: Actions

    init(
        systemImage: String,
        title: String,
        subtitle: String,
        pulseIcon: Bool = false,
        @ViewBuilder actions: () -> Actions
    ) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.pulseIcon = pulseIcon
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
                .modifier(PulseIfActive(active: pulseIcon))

            Text(title)
                .font(.ab(.title2, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(subtitle)
                .font(.ab(.body))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Akcje (np. Odśwież) wchodzą w wyśrodkowany blok jak w natywnym
            // ContentUnavailableView — bez ręcznych paddingów rozjeżdżających
            // pion tytułu między zakładkami.
            actions
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(systemImage: String, title: String, subtitle: String, pulseIcon: Bool = false) {
        self.init(
            systemImage: systemImage,
            title: title,
            subtitle: subtitle,
            pulseIcon: pulseIcon
        ) { EmptyView() }
    }
}

/// Wraps centered empty / disconnected / loading content in a ScrollView that
/// always fills the viewport. On `scroll: false` tabs a plain centered VStack
/// collapses the window's top safe area (the toolbar / Liquid Glass scroll edge
/// area), which makes the sidebar jump upward when switching to an empty state.
/// A ScrollView keeps that safe area installed; `minHeight: geo.height` keeps
/// the content vertically centered as if it weren't scrolling.
struct EmptyStateContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
        }
    }
}

private struct PulseIfActive: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.symbolEffect(.pulse, options: .repeating)
        } else {
            content
        }
    }
}
