import SwiftUI
import AppKit

/// Dedicated "About" tab — mirrors the Android About screen (hero logo, app
/// name, tagline, credits card, links card, license + version) so both
/// platforms feel consistent. The compact Apple-menu About window
/// (`AboutWindowView`) stays as the small popover variant.
struct AboutTabView: View {
    private let version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"

    var body: some View {
        VStack(spacing: 16) {
            hero
            creditsSection
            linksSection
            footer
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.2), radius: 16, y: 6)

            Text("AirBridge")
                .font(.abAppName)
                .tracking(2)

            Text(L10n.isPL
                 ? "Połącz telefon z komputerem Mac — lokalnie, bez chmury."
                 : "Connect your phone with your Mac — locally, no cloud.")
                .font(.ab(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Credits

    private var creditsSection: some View {
        GlassSection {
            creditRow(
                image: loadBundledImage("logo_negative"),
                fallback: "person.circle.fill",
                caption: L10n.isPL ? "Autor" : "Created by",
                name: "Marcin Baszewski",
                url: "https://github.com/negativepl"
            )
            Divider()
            creditRow(
                image: loadBundledImage("logo_claude"),
                fallback: "sparkles",
                caption: L10n.isPL ? "Napędzane przez" : "Powered by",
                name: "Claude · Anthropic",
                url: "https://anthropic.com"
            )
        }
    }

    // MARK: - Links

    private var linksSection: some View {
        GlassSection {
            linkRow(
                systemImage: "curlybraces",
                title: L10n.isPL ? "Kod źródłowy" : "Source code",
                url: "https://github.com/negativepl/airbridge"
            )
            Divider()
            linkRow(
                systemImage: "ladybug",
                title: L10n.isPL ? "Zgłoś błąd" : "Report an issue",
                url: "https://github.com/negativepl/airbridge/issues"
            )
            Divider()
            linkRow(
                systemImage: "arrow.down.circle",
                title: L10n.isPL ? "Wydania" : "Releases",
                url: "https://github.com/negativepl/airbridge/releases"
            )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(L10n.isPL ? "Otwarte oprogramowanie" : "Open source")
                Text("·")
                Text("MIT")
                Text("·")
                Text("© 2026 Marcin Baszewski")
            }
            Text(L10n.isPL ? "Wersja \(version)" : "Version \(version)")
        }
        .font(.ab(.caption2))
        .foregroundStyle(.tertiary)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: - Rows

    private func creditRow(image: NSImage?, fallback: String, caption: String, name: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 12) {
                if let img = image {
                    Image(nsImage: img)
                        .resizable()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                } else {
                    Image(systemName: fallback)
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(caption)
                        .font(.ab(.caption2))
                        .foregroundStyle(.secondary)
                    Text(name)
                        .font(.ab(.subheadline, weight: .medium))
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.ab(.caption, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func linkRow(systemImage: String, title: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.ab(.body, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
                Text(title)
                    .font(.ab(.body))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.ab(.caption, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func loadBundledImage(_ name: String) -> NSImage? {
        guard let url = AppResources.bundle.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}
