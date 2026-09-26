import SwiftUI
import AppKit

/// "About" as the last section of Settings (the Apple-menu About window,
/// `AboutWindowView`, stays as the compact variant). Team, links, the update
/// check with its install flow, and the version line.
struct AboutSection: View {
    let updateService: UpdateService
    /// The phone's app version, for the "update both apps" note.
    var phoneAppVersion: String? = nil

    private let version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"

    /// Diagnostics is a hidden section, unlocked the developer-options way:
    /// seven clicks on the version line. A short hint replaces the version
    /// text while counting down.
    @AppStorage(DiagnosticsUnlock.key) private var diagnosticsUnlocked = false
    @State private var versionClicks = 0
    @State private var versionHint: String?
    @State private var hintReset: Task<Void, Never>?

    var body: some View {
        GlassSection(title: LocalizedStringKey(L10n.isPL ? "O aplikacji" : "About"), systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 0) {
                creditRow(
                    image: loadBundledImage("logo_negative"),
                    fallback: "person.circle.fill",
                    caption: L10n.isPL ? "Szef projektu" : "Project lead",
                    name: "Marcin Baszewski",
                    url: "https://github.com/negativepl"
                )
                ForEach(ClaudeTeam.members, id: \.name) { member in
                    Divider().padding(.vertical, 8)
                    creditRow(
                        image: loadBundledImage("logo_claude"),
                        fallback: "sparkles",
                        caption: member.role,
                        name: member.name,
                        url: "https://anthropic.com"
                    )
                }
                Divider().padding(.vertical, 8)
                linkRow(
                    systemImage: "curlybraces",
                    title: L10n.isPL ? "Kod źródłowy" : "Source code",
                    url: "https://github.com/negativepl/airbridge"
                )
                Divider().padding(.vertical, 8)
                linkRow(
                    systemImage: "ladybug",
                    title: L10n.isPL ? "Zgłoś błąd" : "Report an issue",
                    url: "https://github.com/negativepl/airbridge/issues"
                )
                Divider().padding(.vertical, 8)
                updateRow
                updateDetails
                Divider().padding(.vertical, 8)
                footer
            }
        }
    }

    // MARK: - Updates

    /// Triggers the shared `UpdateService` check and shows the state inline;
    /// the install button and changelog unfold underneath when one is available.
    private var updateRow: some View {
        Button {
            switch updateService.phase {
            case .idle, .upToDate, .failed:
                Task { await updateService.checkForUpdates() }
            default:
                break
            }
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
            Label(L10n.isPL ? "Masz najnowszą wersję" : "Up to date", systemImage: "checkmark.circle.fill")
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
            Label(L10n.isPL ? "Spróbuj ponownie" : "Retry", systemImage: "exclamationmark.triangle.fill")
                .font(.ab(.caption, weight: .semibold))
                .foregroundStyle(.red)
                .labelStyle(.titleAndIcon)
        }
    }

    @ViewBuilder
    private var updateDetails: some View {
        switch updateService.phase {
        case .available(let manifest):
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.isPL ? "Dostępna aktualizacja: \(manifest.version)"
                                       : "Update available: \(manifest.version)")
                            .font(.ab(.body, weight: .medium))
                        Text(L10n.isPL ? "Wydano \(manifest.publishedAt)" : "Released \(manifest.publishedAt)")
                            .font(.ab(.footnote))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.isPL ? "Zaktualizuj" : "Update") {
                        Task { await updateService.downloadAndInstall() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.extraLarge)
                }
                let items = L10n.isPL ? manifest.changelog.pl : manifest.changelog.en
                if !items.isEmpty {
                    Text(L10n.isPL ? "Co nowego" : "What's new")
                        .font(.ab(.subheadline, weight: .semibold))
                    ForEach(items, id: \.self) { item in
                        Text("• \(item)")
                            .font(.ab(.body))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 12)

        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.isPL ? "Pobieranie…" : "Downloading…")
                    .font(.ab(.footnote))
                    .foregroundStyle(.secondary)
                ProgressView(value: progress)
            }
            .padding(.top, 12)

        case .installing:
            Text(L10n.isPL ? "Instalowanie…" : "Installing…")
                .font(.ab(.footnote))
                .foregroundStyle(.secondary)
                .padding(.top, 12)

        case .failed(let message):
            Text(message)
                .font(.ab(.caption))
                .foregroundStyle(.tertiary)
                .padding(.top, 8)

        default:
            if let mismatched = mismatchedVersion {
                Text(L10n.isPL
                     ? "Telefon ma wersję AirBridge \(mismatched). Zaktualizuj obie aplikacje, aby zachować zgodność."
                     : "Your phone runs AirBridge \(mismatched). Update both apps to keep them in sync.")
                    .font(.ab(.footnote))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
    }

    /// The phone's app version when it differs (ignoring a "-beta" suffix)
    /// from this Mac's own version.
    private var mismatchedVersion: String? {
        guard let remote = phoneAppVersion, !remote.isEmpty else { return nil }
        guard !version.isEmpty, versionBase(remote) != versionBase(version) else { return nil }
        return remote
    }

    /// "3.1.0-beta" and "3.1.0" are the same release for this comparison.
    private func versionBase(_ v: String) -> String {
        v.split(separator: "-").first.map(String.init) ?? v
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Text(L10n.isPL ? "Otwarte oprogramowanie" : "Open source")
            Text("·")
            Text("MIT")
            Text("·")
            Text("© 2026 Marcin Baszewski")
            Spacer(minLength: 0)
            Text(versionHint ?? (L10n.isPL ? "Wersja \(version)" : "Version \(version)"))
                .foregroundStyle(versionHint == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.accentColor))
                .contentShape(Rectangle())
                .onTapGesture { versionTapped() }
        }
        .font(.ab(.caption2))
        .foregroundStyle(.tertiary)
    }

    private func versionTapped() {
        if diagnosticsUnlocked {
            showHint(L10n.isPL ? "Diagnostyka jest już włączona" : "Diagnostics is already enabled")
            return
        }
        versionClicks += 1
        let left = DiagnosticsUnlock.taps - versionClicks
        if left <= 0 {
            diagnosticsUnlocked = true
            versionClicks = 0
            showHint(L10n.isPL ? "Diagnostyka włączona" : "Diagnostics enabled")
        } else if left <= 3 {
            showHint(L10n.isPL ? "Jeszcze \(left) \(left == 1 ? "kliknięcie" : "kliknięcia")" : "\(left) \(left == 1 ? "click" : "clicks") to go")
        }
    }

    private func showHint(_ text: String) {
        versionHint = text
        hintReset?.cancel()
        hintReset = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            versionHint = nil
        }
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
            Member(name: "Claude Fable 5.1",
                   role: L10n.isPL ? "Menadżer projektu" : "Project manager"),
            Member(name: "Claude Opus 5.5",
                   role: L10n.isPL ? "Brygadzista" : "Foreman"),
            Member(name: "Claude Sonnet 5",
                   role: L10n.isPL ? "Programista" : "Software engineer"),
            Member(name: "Claude Haiku 4.5",
                   role: L10n.isPL ? "Stażysta" : "Intern")
        ]
    }
}

/// Shared by the About section (unlock) and Settings (visibility, hide row).
enum DiagnosticsUnlock {
    static let key = "diagnostics_unlocked"
    static let taps = 7
}
