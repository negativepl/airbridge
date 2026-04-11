import SwiftUI
import AppKit

/// Minimalist About window shown from Apple menu → "O aplikacji AirBridge".
///
/// Replaces the default macOS `orderFrontStandardAboutPanel` (old Aqua-style
/// white panel) with a compact, native-feeling SwiftUI window: hero icon +
/// serif name + tagline, two credit rows (author, Claude), one primary GitHub
/// button, and a subtle footer with version + MIT. Sized to fit without
/// scrolling.
struct AboutWindowView: View {
    @Environment(\.dismiss) private var dismiss

    private let version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"

    var body: some View {
        VStack(spacing: 18) {
            // Icon
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.2), radius: 16, y: 6)

            // Name + version
            VStack(spacing: 4) {
                Text("AirBridge")
                    .font(.system(size: 30, weight: .regular, design: .serif))
                    .tracking(2)

                Text(L10n.isPL ? "Wersja \(version)" : "Version \(version)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            // Tagline
            Text(L10n.isPL
                 ? "Połącz telefon z komputerem Mac — lokalnie, bez chmury."
                 : "Connect your phone with your Mac — locally, no cloud.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .fixedSize(horizontal: false, vertical: true)

            // Credits
            VStack(spacing: 0) {
                creditRow(
                    image: loadBundledImage("logo_negative"),
                    fallback: "person.circle.fill",
                    caption: L10n.isPL ? "Autor" : "Author",
                    name: "Marcin Baszewski",
                    url: "https://github.com/negativepl"
                )

                Divider()
                    .padding(.horizontal, 14)

                creditRow(
                    image: loadBundledImage("logo_claude"),
                    fallback: "sparkles",
                    caption: L10n.isPL ? "Napędzane przez" : "Powered by",
                    name: "Claude Opus 4.6",
                    url: "https://anthropic.com"
                )
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 20)

            // Primary action
            Button {
                if let url = URL(string: "https://github.com/negativepl/airbridge") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label(L10n.isPL ? "Kod źródłowy na GitHub" : "Source Code on GitHub", systemImage: "curlybraces")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(.accentColor).interactive(), in: .capsule)
            .padding(.horizontal, 20)

            Spacer(minLength: 0)

            // Footer
            HStack(spacing: 6) {
                Text(L10n.isPL ? "Open source" : "Open source")
                Text("·")
                Text("MIT")
                Text("·")
                Text("© 2026 Marcin Baszewski")
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
        .padding(.top, 32)
        .padding(.bottom, 18)
        .frame(width: 360, height: 540)
    }

    // MARK: - Credit row

    private func creditRow(image: NSImage?, fallback: String, caption: String, name: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 12) {
                if let img = image {
                    Image(nsImage: img)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                } else {
                    Image(systemName: fallback)
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func loadBundledImage(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}
