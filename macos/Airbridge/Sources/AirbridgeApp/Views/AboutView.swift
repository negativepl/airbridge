import SwiftUI
import AppKit

struct AboutView: View {
    var body: some View {
        GlassSection(padding: 28) {
            VStack(spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 120, height: 120)

                Text("Airbridge")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .tracking(1)

                Text(L10n.isPL
                    ? "Połącz telefon z komputerem Mac.\nSynchronizuj schowek, przesyłaj pliki — wszystko lokalnie, bez chmury."
                    : "Connect your phone with your Mac.\nSync clipboard, transfer files — all local, no cloud.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                // Credits
                VStack(spacing: 16) {
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
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Marcin Baszewski")
                                .font(.body).fontWeight(.semibold)
                        }
                        Spacer()
                        linkButton(url: "https://github.com/negativepl")
                    }

                    Divider()

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
                                .font(.body).fontWeight(.semibold)
                            Text("Anthropic")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .padding(16)
                .frame(maxWidth: 440)
                .glassEffect(.regular, in: .rect(cornerRadius: 16, style: .continuous))

                // Links
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
                .padding(4)
                .frame(maxWidth: 440)
                .glassEffect(.regular, in: .rect(cornerRadius: 16, style: .continuous))

                Text(L10n.isPL ? "Airbridge jest open source" : "Airbridge is open source")
                    .font(.caption).foregroundStyle(.secondary)
                Text(L10n.isPL ? "Licencja MIT" : "MIT License")
                    .font(.caption).foregroundStyle(.tertiary)

                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func linkButton(url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            Image(systemName: "arrow.up.right")
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
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
                Text(title).font(.body)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption).foregroundStyle(.secondary)
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
