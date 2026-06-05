import SwiftUI
import UniformTypeIdentifiers
import Protocol

struct FilesBrowserView: View {
    let filesBrowserService: FilesBrowserService
    let connectionService: ConnectionService

    var body: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            Divider()
            content
        }
        .onAppear { filesBrowserService.open(path: "") }
        .onChange(of: connectionService.isConnected) { _, connected in
            if connected { filesBrowserService.open(path: "") }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 6) {
            Button { filesBrowserService.open(path: "") } label: {
                Image(systemName: "internaldrive")
            }
            .buttonStyle(.borderless)

            ForEach(Array(filesBrowserService.breadcrumbs.enumerated()), id: \.offset) { index, segment in
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                Button(segment) {
                    let path = filesBrowserService.breadcrumbs.prefix(index + 1).joined(separator: "/")
                    filesBrowserService.open(path: path)
                }
                .buttonStyle(.borderless)
            }
            Spacer()
            if filesBrowserService.isLoading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if filesBrowserService.needsPermission {
            permissionEmptyState
        } else {
            List(filesBrowserService.entries) { entry in
                FileRow(entry: entry, thumbnail: filesBrowserService.thumbnails[entry.relativePath])
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { filesBrowserService.activate(entry) }
                    .onAppear { filesBrowserService.requestThumbnail(entry) }
            }
            .listStyle(.inset)
        }
    }

    private var permissionEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark").font(.system(size: 48)).foregroundStyle(.secondary)
            Text(L10n.isPL ? "Przyznaj dostęp do plików na telefonie" : "Grant file access on your phone")
                .font(.headline)
            Text(L10n.isPL
                 ? "Na telefonie otwórz AirBridge → wizard uprawnień → „Pliki” i zezwól na dostęp do Pamięci wewnętrznej."
                 : "On your phone open AirBridge → permissions → \"Files\" and allow access to internal storage.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
            Button(L10n.isPL ? "Odśwież" : "Refresh") { filesBrowserService.reload() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !filesBrowserService.needsPermission else { return false }
        let lock = NSLock()
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            guard provider.canLoadObject(ofClass: URL.self) else { continue }
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { filesBrowserService.upload(urls: urls) }
        }
        return true
    }
}

private struct FileRow: View {
    let entry: FileEntry
    let thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).lineLimit(1)
                if !entry.isDirectory {
                    Text(Self.sizeFormatter.string(fromByteCount: entry.size))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if entry.isDirectory {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var icon: some View {
        if let thumbnail {
            Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                .frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: entry.isDirectory ? "folder.fill" : Self.symbol(for: entry.mimeType))
                .frame(width: 28, height: 28)
                .foregroundStyle(entry.isDirectory ? Color.accentColor : Color.secondary)
        }
    }

    private static func symbol(for mime: String) -> String {
        if mime.hasPrefix("image/") { return "photo" }
        if mime.hasPrefix("video/") { return "film" }
        if mime.hasPrefix("audio/") { return "music.note" }
        if mime == "application/pdf" { return "doc.richtext" }
        if mime.hasPrefix("text/") { return "doc.text" }
        return "doc"
    }

    private static let sizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter(); f.countStyle = .file; return f
    }()
}
