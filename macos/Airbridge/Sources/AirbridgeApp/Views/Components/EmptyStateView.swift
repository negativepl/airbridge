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
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let subtitle: String
    var pulseIcon: Bool = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
                .modifier(PulseIfActive(active: pulseIcon))

            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
