import SwiftUI
import AppKit

/// Dedicated "About" tab — mirrors the Android About screen (hero logo, app
/// name, tagline, credits card, links card, license + version) so both
/// platforms feel consistent. The compact Apple-menu About window
/// (`AboutWindowView`) stays as the small popover variant.
struct AboutTabView: View {
    let updateService: UpdateService

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

    /// The project team — mirrors the Android About screen's roster: Marcin at
    /// the top, then the Claude crew with the job each model does around here.
    private var creditsSection: some View {
        GlassSection {
            creditRow(
                image: loadBundledImage("logo_negative"),
                fallback: "person.circle.fill",
                caption: L10n.isPL ? "Szef projektu" : "Project lead",
                name: "Marcin Baszewski",
                url: "https://github.com/negativepl"
            )
            ForEach(ClaudeTeam.members, id: \.name) { member in
                Divider()
                creditRow(
                    image: loadBundledImage("logo_claude"),
                    fallback: "sparkles",
                    caption: member.role,
                    name: member.name,
                    url: "https://anthropic.com"
                )
            }
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
            Divider()
            updateRow
        }
    }

    /// Unlike the other rows, this one doesn't open a URL — it triggers the
    /// shared `UpdateService` check and shows the result inline. The full
    /// changelog and "Update" install button live in the Settings tab's
    /// dedicated section; this row is a compact entry point + status readout.
    private var updateRow: some View {
        Button {
            guard case .idle = updateService.phase else {
                if case .failed = updateService.phase {
                    Task { await updateService.checkForUpdates() }
                }
                return
            }
            Task { await updateService.checkForUpdates() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.ab(.body, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
                Text(L10n.isPL ? "Sprawdź aktualizacje" : "Check for updates")
                    .font(.ab(.body))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                updateRowTrailing
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var updateRowTrailing: some View {
        switch updateService.phase {
        case .idle:
            Image(systemName: "arrow.up.right")
                .font(.ab(.caption, weight: .semibold))
                .foregroundStyle(.tertiary)

        case .checking:
            ProgressView()
                .controlSize(.small)

        case .upToDate:
            Label(L10n.isPL ? "Aktualne" : "Up to date", systemImage: "checkmark.circle.fill")
                .font(.ab(.caption, weight: .semibold))
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)

        case .available(let manifest):
            Text(L10n.isPL ? "Dostępna: \(manifest.version)" : "Available: \(manifest.version)")
                .font(.ab(.caption, weight: .semibold))
                .foregroundStyle(Color.accentColor)

        case .downloading, .installing:
            ProgressView()
                .controlSize(.small)

        case .failed:
            Label(L10n.isPL ? "Błąd" : "Failed", systemImage: "exclamationmark.triangle.fill")
                .font(.ab(.caption, weight: .semibold))
                .foregroundStyle(.red)
                .labelStyle(.titleAndIcon)
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

/// The Claude models credited in About, each with its role on the team.
/// Shared by the About tab and the compact Apple-menu About window.
enum ClaudeTeam {
    struct Member {
        let name: String
        let role: String
    }

    static var members: [Member] {
        [
            Member(name: "Claude Fable 5",
                   role: L10n.isPL ? "Menadżer projektu" : "Project manager"),
            Member(name: "Claude Opus 4.8",
                   role: L10n.isPL ? "Brygadzista" : "Foreman"),
            Member(name: "Claude Sonnet 5",
                   role: L10n.isPL ? "Programista" : "Software engineer"),
            Member(name: "Claude Haiku 4.5",
                   role: L10n.isPL ? "Stażysta — parzy kawę" : "Intern — makes the coffee")
        ]
    }
}
