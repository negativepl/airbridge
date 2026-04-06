import SwiftUI
import AppKit

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 32)

                // App icon
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 120, height: 120)

                Spacer().frame(height: 16)

                Text("Airbridge")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .tracking(1)

                Spacer().frame(height: 12)

                Text(L10n.isPL
                    ? "Połącz telefon z komputerem Mac.\nSynchronizuj schowek, przesyłaj pliki — wszystko lokalnie, bez chmury."
                    : "Connect your phone with your Mac.\nSync clipboard, transfer files — all local, no cloud.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer().frame(height: 28)

                // Credits card
                GroupBox {
                    VStack(spacing: 16) {
                        // Author
                        HStack(spacing: 12) {
                            if let img = loadBundledImage("logo_negative") {
                                Image(nsImage: img)
                                    .resizable()
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.isPL ? "Autor" : "Author")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Marcin Baszewski")
                                    .font(.body)
                                    .fontWeight(.semibold)
                            }

                            Spacer()

                            linkButton(url: "https://github.com/negativepl")
                        }

                        Divider()

                        // AI
                        HStack(spacing: 12) {
                            if let img = loadBundledImage("logo_claude") {
                                Image(nsImage: img)
                                    .resizable()
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "brain")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Powered by Claude Opus 4.6")
                                    .font(.body)
                                    .fontWeight(.semibold)
                                Text("Anthropic")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                    }
                    .padding(4)
                } label: {
                    Label(L10n.isPL ? "Twórcy" : "Credits", systemImage: "heart")
                }
                .frame(maxWidth: 440)
                .padding(.horizontal, 24)

                Spacer().frame(height: 16)

                // Links card
                GroupBox {
                    VStack(spacing: 0) {
                        linkRow(
                            icon: "curlybraces",
                            title: L10n.isPL ? "Kod źródłowy na GitHub" : "Source code on GitHub",
                            url: "https://github.com/negativepl/airbridge"
                        )

                        Divider().padding(.horizontal, 4)

                        linkRow(
                            icon: "ladybug",
                            title: L10n.isPL ? "Zgłoś problem" : "Report an issue",
                            url: "https://github.com/negativepl/airbridge/issues"
                        )
                    }
                } label: {
                    Label(L10n.isPL ? "Linki" : "Links", systemImage: "link")
                }
                .frame(maxWidth: 440)
                .padding(.horizontal, 24)

                Spacer().frame(height: 20)

                // License
                Text(L10n.isPL ? "Airbridge jest open source" : "Airbridge is open source")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L10n.isPL ? "Licencja MIT" : "MIT License")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer().frame(height: 8)

                Text("v1.0.0")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 32)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func linkButton(url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            Image(systemName: "arrow.up.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func linkRow(icon: String, title: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)

                Text(title)
                    .font(.body)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadBundledImage(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}
