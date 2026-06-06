import SwiftUI
import UniformTypeIdentifiers
import Protocol

struct FilesBrowserView: View {
    let filesBrowserService: FilesBrowserService
    let connectionService: ConnectionService

    @AppStorage("files.viewMode") private var viewModeRaw: String = FileViewMode.list.rawValue
    @State private var searchText: String = ""

    private var viewMode: FileViewMode { FileViewMode(rawValue: viewModeRaw) ?? .list }

    var body: some View {
        Group {
            if !connectionService.isConnected {
                notConnectedView
            } else {
                VStack(spacing: 0) {
                    breadcrumbBar
                    toolbarBar
                    Divider()
                    content
                }
            }
        }
        .onAppear {
            filesBrowserService.loadPersistedSort()
            if connectionService.isConnected && !filesBrowserService.hasLoadedOnce {
                filesBrowserService.open(path: "")
            }
        }
        .onChange(of: connectionService.isConnected) { _, connected in
            if connected && !filesBrowserService.hasLoadedOnce {
                filesBrowserService.open(path: "")
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private var notConnectedView: some View {
        EmptyStateContainer {
            EmptyStateView(
                systemImage: "folder",
                title: L10n.isPL ? "Pliki" : "Files",
                subtitle: L10n.isPL
                    ? "Połącz się z telefonem, aby przeglądać pliki."
                    : "Connect to your phone to browse files."
            )
        }
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 6) {
            Button { filesBrowserService.open(path: "") } label: {
                Image(systemName: "internaldrive")
                    .imageScale(.large)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var toolbarBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L10n.isPL ? "Szukaj wszędzie" : "Search everywhere", text: $searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: searchText) { _, new in
                        filesBrowserService.setSearchQuery(new)
                    }
                if !searchText.isEmpty {
                    Button { searchText = ""; filesBrowserService.setSearchQuery("") } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 280)

            Spacer()

            sortMenu

            Picker("", selection: Binding(
                get: { viewMode },
                set: { viewModeRaw = $0.rawValue }
            )) {
                Image(systemName: "list.bullet").tag(FileViewMode.list)
                Image(systemName: "square.grid.2x2").tag(FileViewMode.grid)
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    private var sortMenu: some View {
        Menu {
            Picker(L10n.isPL ? "Sortuj wg" : "Sort by",
                   selection: Binding(get: { filesBrowserService.sortBy },
                                      set: { filesBrowserService.sortBy = $0 })) {
                Text(L10n.isPL ? "Nazwa" : "Name").tag(FileSortKey.name)
                Text(L10n.isPL ? "Rozmiar" : "Size").tag(FileSortKey.size)
                Text(L10n.isPL ? "Data modyfikacji" : "Date modified").tag(FileSortKey.modified)
                Text(L10n.isPL ? "Typ" : "Type").tag(FileSortKey.type)
            }
            Divider()
            Picker(L10n.isPL ? "Kierunek" : "Order",
                   selection: Binding(get: { filesBrowserService.sortAscending },
                                      set: { filesBrowserService.sortAscending = $0 })) {
                Text(L10n.isPL ? "Rosnąco" : "Ascending").tag(true)
                Text(L10n.isPL ? "Malejąco" : "Descending").tag(false)
            }
            Divider()
            Toggle(L10n.isPL ? "Foldery na początku" : "Folders first",
                   isOn: Binding(get: { filesBrowserService.foldersFirst },
                                 set: { filesBrowserService.foldersFirst = $0 }))
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var content: some View {
        if filesBrowserService.needsPermission {
            permissionEmptyState
        } else if filesBrowserService.displayedEntries.isEmpty
                    && (filesBrowserService.isLoading || filesBrowserService.isLoadingMoreRows) {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewMode == .grid {
            gridView
        } else {
            listView
        }
    }

    private var listView: some View {
        List {
            ForEach(filesBrowserService.displayedEntries) { entry in
                FileRow(
                    entry: entry,
                    thumbnail: filesBrowserService.thumbnails[entry.relativePath],
                    stats: filesBrowserService.folderStats[entry.relativePath],
                    showPath: filesBrowserService.isSearching
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { filesBrowserService.activate(entry) }
            }
        }
        .listStyle(.inset)
        .animation(.default, value: filesBrowserService.displayedEntries.count)
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 16)], spacing: 16) {
                ForEach(filesBrowserService.displayedEntries) { entry in
                    FileGridCell(
                        entry: entry,
                        thumbnail: filesBrowserService.thumbnails[entry.relativePath],
                        showPath: filesBrowserService.isSearching
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { filesBrowserService.activate(entry) }
                }
            }
            .padding(16)
        }
        .animation(.default, value: filesBrowserService.displayedEntries.count)
    }

    private var permissionEmptyState: some View {
        EmptyStateContainer {
            VStack(spacing: 20) {
                EmptyStateView(
                    systemImage: "folder.badge.questionmark",
                    title: L10n.isPL ? "Przyznaj dostęp do plików na telefonie" : "Grant file access on your phone",
                    subtitle: L10n.isPL
                        ? "Na telefonie otwórz AirBridge → wizard uprawnień → „Pliki” i zezwól na dostęp do Pamięci wewnętrznej."
                        : "On your phone open AirBridge → permissions → \"Files\" and allow access to internal storage."
                )
                Button(L10n.isPL ? "Odśwież" : "Refresh") { filesBrowserService.reload() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.bottom, 80)
            }
        }
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
    var stats: FolderStats? = nil
    var showPath: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(showPath ? entry.relativePath : entry.name).lineLimit(1)
                if entry.isDirectory {
                    if let stats {
                        Text(Self.folderSubtitle(stats))
                            .font(.caption).foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                } else {
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
        .animation(.default, value: stats)
    }

    private static func folderSubtitle(_ s: FolderStats) -> String {
        let isPL = L10n.isPL
        var parts: [String] = []
        if s.dirCount > 0 {
            parts.append(isPL ? "\(s.dirCount) \(plural(s.dirCount, "folder", "foldery", "folderów"))"
                              : "\(s.dirCount) \(s.dirCount == 1 ? "folder" : "folders")")
        }
        parts.append(isPL ? "\(s.fileCount) \(plural(s.fileCount, "plik", "pliki", "plików"))"
                          : "\(s.fileCount) \(s.fileCount == 1 ? "file" : "files")")
        parts.append(sizeFormatter.string(fromByteCount: s.totalSize))
        return parts.joined(separator: " · ")
    }

    /// Polish plural: 1 / 2-4 (excl. teens) / rest.
    private static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if n == 1 { return one }
        if mod10 >= 2 && mod10 <= 4 && !(mod100 >= 12 && mod100 <= 14) { return few }
        return many
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

private struct FileGridCell: View {
    let entry: FileEntry
    let thumbnail: NSImage?
    var showPath: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: entry.isDirectory ? "folder.fill" : FileGridCell.symbol(for: entry.mimeType))
                        .font(.system(size: 34))
                        .foregroundStyle(entry.isDirectory ? Color.accentColor : Color.secondary)
                }
            }
            .frame(width: 96, height: 96)

            Text(showPath ? entry.relativePath : entry.name)
                .font(.caption).lineLimit(2).multilineTextAlignment(.center)
                .frame(maxWidth: 104)
        }
    }

    static func symbol(for mime: String) -> String {
        if mime.hasPrefix("image/") { return "photo" }
        if mime.hasPrefix("video/") { return "film" }
        if mime.hasPrefix("audio/") { return "music.note" }
        if mime == "application/pdf" { return "doc.richtext" }
        if mime.hasPrefix("text/") { return "doc.text" }
        return "doc"
    }
}
