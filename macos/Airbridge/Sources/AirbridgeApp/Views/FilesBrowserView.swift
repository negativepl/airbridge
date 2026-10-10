import SwiftUI
import UniformTypeIdentifiers
import Protocol
import os
import QuickLook

/// The phone's files, laid out like the Finder: a sortable list (a system
/// Table) or an icon view, Back/Forward in the toolbar, the path bar at the
/// bottom and Quick Look for previews.
struct FilesBrowserView: View {
    let filesBrowserService: FilesBrowserService
    let connectionService: ConnectionService

    @AppStorage("files.viewMode") private var viewModeRaw: String = FileViewMode.list.rawValue
    @State private var searchText: String = ""
    @State private var selection: Set<FileEntry.ID> = []
    @State private var sortOrder: [KeyPathComparator<FileEntry>] = [KeyPathComparator(\.name)]
    /// Which columns show, their order and widths — the header's right-click
    /// menu, as the Finder's; kept with the window.
    @SceneStorage("files.columns") private var columnCustomization = TableColumnCustomization<FileEntry>()
    @State private var entriesPendingDeletion: [FileEntry] = []
    /// A file drag is over the window: the folder takes the drop.
    @State private var isDropTargeted = false

    private var viewMode: FileViewMode { FileViewMode(rawValue: viewModeRaw) ?? .list }
    private var service: FilesBrowserService { filesBrowserService }

    var body: some View {
        withAlerts(withLifecycle(browser))
    }

    private var browser: some View {
        Group {
            if !connectionService.isConnected {
                ContentUnavailableView {
                    Label(L10n.isPL ? "Brak połączenia" : "Not Connected", systemImage: "wifi.slash")
                } description: {
                    Text(L10n.isPL ? "Połącz się z telefonem, aby przeglądać pliki." : "Connect to your phone to browse files.")
                }
            } else {
                VStack(spacing: 0) {
                    content
                        .overlay { dropOutline }
                    Divider()
                    pathBar
                }
                .searchable(
                    text: $searchText,
                    placement: .toolbar,
                    prompt: L10n.isPL ? "Szukaj wszędzie" : "Search everywhere"
                )
            }
        }
    }

    private func withLifecycle(_ view: some View) -> some View {
        view
            .navigationTitle(service.breadcrumbs.last ?? (L10n.isPL ? "Pliki" : "Files"))
            .toolbar { toolbar }
            .onChange(of: searchText) { _, new in
                service.setSearchQuery(new)
            }
            .onAppear {
                service.loadPersistedSort()
                sortOrder = [Self.comparator(for: service.sortBy, ascending: service.sortAscending)]
                if connectionService.isConnected && !service.hasLoadedOnce {
                    service.open(path: "")
                }
            }
            .onChange(of: connectionService.isConnected) { _, connected in
                if connected && !service.hasLoadedOnce { service.open(path: "") }
            }
            .onChange(of: connectionService.activeDeviceId) { _, _ in
                // Switched phones — paths differ per device, so reopen the new root.
                if connectionService.isConnected { service.open(path: "") }
            }
            .onChange(of: service.searchQuery) { _, q in
                if q.isEmpty && !searchText.isEmpty { searchText = "" }
            }
            .onChange(of: service.currentPath) { _, _ in selection = [] }
            // Sorting happens on the phone: a column click asks for the listing
            // in the new order.
            .onChange(of: sortOrder) { _, order in applySort(order) }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
            }
            // Quick Look, as the Finder's space bar: the panel opens once the file
            // has come over from the phone.
            .quickLookPreview(quickLookItem)
    }

    private var quickLookItem: Binding<URL?> {
        Binding<URL?>(
            get: { service.isPreviewPresented ? service.previewURL : nil },
            set: { url in if url == nil { service.dismissPreview() } }
        )
    }

    private func withAlerts(_ view: some View) -> some View {
        view
            .alert(
                deletionTitle,
                isPresented: Binding(get: { !entriesPendingDeletion.isEmpty },
                                     set: { if !$0 { entriesPendingDeletion = [] } })
            ) {
                Button(L10n.isPL ? "Usuń" : "Delete", role: .destructive) {
                    entriesPendingDeletion.forEach { service.delete($0) }
                    entriesPendingDeletion = []
                }
                Button(L10n.isPL ? "Anuluj" : "Cancel", role: .cancel) { entriesPendingDeletion = [] }
            } message: {
                Text(L10n.isPL ? "Tej operacji nie można cofnąć." : "This cannot be undone.")
            }
            .alert(
                L10n.isPL ? "Nie udało się usunąć" : "Delete Failed",
                isPresented: Binding(get: { service.deleteError != nil }, set: { if !$0 { service.deleteError = nil } })
            ) {
                Button("OK", role: .cancel) { service.deleteError = nil }
            } message: {
                Text(L10n.isPL ? "Nie można było usunąć tego elementu. Spróbuj ponownie."
                               : "This item could not be deleted. Please try again.")
            }
            .alert(
                L10n.isPL ? "Nie udało się otworzyć pliku" : "Could Not Open the File",
                isPresented: Binding(get: { service.isPreviewPresented && service.previewFailed },
                                     set: { if !$0 { service.dismissPreview() } })
            ) {
                Button("OK", role: .cancel) { service.dismissPreview() }
            } message: {
                Text(L10n.isPL ? "Nie udało się pobrać pliku z telefonu do podglądu."
                               : "The file could not be fetched from the phone for preview.")
            }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { service.goBack() } label: {
                Label(L10n.isPL ? "Wstecz" : "Back", systemImage: "chevron.backward")
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(service.backStack.isEmpty)
            Button { service.goForward() } label: {
                Label(L10n.isPL ? "Dalej" : "Forward", systemImage: "chevron.forward")
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(service.forwardStack.isEmpty)
        }
        ToolbarItem(placement: .primaryAction) {
            Picker(L10n.isPL ? "Widok" : "View", selection: $viewModeRaw) {
                Label(L10n.isPL ? "Lista" : "List", systemImage: "list.bullet").tag(FileViewMode.list.rawValue)
                Label(L10n.isPL ? "Ikony" : "Icons", systemImage: "square.grid.2x2").tag(FileViewMode.grid.rawValue)
            }
            .pickerStyle(.segmented)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { service.reload() } label: {
                Label(L10n.isPL ? "Odśwież" : "Refresh", systemImage: "arrow.clockwise")
            }
        }
    }

    // MARK: - Content

    private enum ContentKind: Hashable { case permission, loading, failed, empty, icons, list }

    private var contentKind: ContentKind {
        let s = service
        if s.needsPermission { return .permission }
        // The first page shows all at once when every folder in it has its
        // size and count, not row by row as the phone answers for each.
        if (s.displayedEntries.isEmpty && s.isLoading) || (s.currentPage == 0 && s.isLoadingMoreRows) { return .loading }
        if s.loadFailed && s.displayedEntries.isEmpty { return .failed }
        if s.displayedEntries.isEmpty && s.hasLoadedOnce { return .empty }
        return viewMode == .grid ? .icons : .list
    }

    /// The listing comes fresh from the phone; a small spinner shows at once
    /// while it does (in the path bar when the folder is already on screen).
    private var content: some View {
        Group {
            switch contentKind {
            case .permission:
                ContentUnavailableView {
                    Label(L10n.isPL ? "Przyznaj dostęp do plików na telefonie" : "Grant File Access on Your Phone",
                          systemImage: "folder.badge.questionmark")
                } description: {
                    Text(L10n.isPL
                         ? "Na telefonie otwórz AirBridge → uprawnienia → „Pliki” i zezwól na dostęp do pamięci wewnętrznej."
                         : "On your phone open AirBridge → permissions → \"Files\" and allow access to internal storage.")
                } actions: {
                    Button(L10n.isPL ? "Odśwież" : "Refresh") { service.reload() }
                }
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                ContentUnavailableView {
                    Label(L10n.isPL ? "Nie udało się załadować plików" : "Could Not Load Files",
                          systemImage: "exclamationmark.triangle")
                } description: {
                    Text(L10n.isPL ? "Telefon nie odpowiedział. Spróbuj ponownie." : "The phone did not respond. Please try again.")
                } actions: {
                    Button(L10n.isPL ? "Spróbuj ponownie" : "Try Again") { service.reload() }
                }
            case .empty:
                if service.isSearching {
                    ContentUnavailableView.search(text: service.searchQuery)
                } else {
                    ContentUnavailableView(
                        L10n.isPL ? "Ten folder jest pusty" : "This Folder Is Empty",
                        systemImage: "folder",
                        description: Text(L10n.isPL ? "Przeciągnij tu pliki, aby wysłać je do tego folderu."
                                                    : "Drag files here to send them to this folder."))
                }
            case .icons:
                iconView
            case .list:
                listView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { $0.animation = nil }
    }

    // MARK: - List (Table)

    private var listView: some View {
        Table(service.displayedEntries, selection: $selection, sortOrder: $sortOrder,
              columnCustomization: $columnCustomization) {
            TableColumn(L10n.isPL ? "Nazwa" : "Name", value: \.name) { entry in
                HStack(spacing: 6) {
                    FileIcon(entry: entry, thumbnail: service.thumbnails[entry.relativePath], size: 18)
                    Text(service.isSearching ? entry.relativePath : entry.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .onAppear { loadMoreIfLast(entry) }
            }
            .width(min: 200, ideal: 320)
            .customizationID("name")
            .disabledCustomizationBehavior(.visibility)
            TableColumn(L10n.isPL ? "Data modyfikacji" : "Date Modified", value: \.modified) { entry in
                Text(Self.date(entry.modified)).foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 170)
            .customizationID("modified")
            TableColumn(L10n.isPL ? "Rozmiar" : "Size", value: \.size) { entry in
                Text(sizeText(entry))
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)
            .customizationID("size")
            TableColumn(L10n.isPL ? "Rodzaj" : "Kind", value: \.mimeType) { entry in
                Text(kindText(entry)).foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 130)
            .customizationID("kind")
            TableColumn(L10n.isPL ? "Zawartość" : "Contents") { entry in
                Text(contentsText(entry))
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100)
            .customizationID("contents")
        }
        .contextMenu(forSelectionType: FileEntry.ID.self) { ids in
            contextMenu(for: entries(ids))
        } primaryAction: { ids in
            // Double-click or Return, as the Finder.
            if let entry = entries(ids).first { service.activate(entry) }
        }
        .onKeyPress(.space) { previewSelection() }
    }

    // MARK: - Icons

    private var iconView: some View {
        ScrollView {
            // Top-aligned rows: a two-line name grows down, the icons stay level.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 128), spacing: 8, alignment: .top)],
                      spacing: 16) {
                ForEach(service.displayedEntries) { entry in
                    FileIconItem(entry: entry,
                                 thumbnail: service.thumbnails[entry.relativePath],
                                 name: service.isSearching ? entry.relativePath : entry.name,
                                 isSelected: selection.contains(entry.id))
                        .onTapGesture {
                            selection = [entry.id]
                            if NSApp.currentEvent?.clickCount == 2 { service.activate(entry) }
                        }
                        .contextMenu { contextMenu(for: [entry]) }
                        .onAppear { loadMoreIfLast(entry) }
                }
            }
            .padding(16)
        }
        .contentShape(Rectangle())
        .onTapGesture { selection = [] }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) { previewSelection() }
        .onKeyPress(.return) {
            guard let entry = entries(selection).first else { return .ignored }
            service.activate(entry)
            return .handled
        }
    }

    // MARK: - Path bar

    /// The Finder's path bar: clickable segments from the phone's root, and
    /// the download of a file being opened in Quick Look.
    private var pathBar: some View {
        HStack(spacing: 4) {
            Button { service.open(path: "") } label: {
                Label(L10n.isPL ? "Telefon" : "Phone", systemImage: "smartphone")
            }
            .buttonStyle(.borderless)

            ForEach(Array(service.breadcrumbs.enumerated()), id: \.offset) { index, segment in
                Image(systemName: "chevron.compact.right")
                    .foregroundStyle(.tertiary)
                Button {
                    service.open(path: service.breadcrumbs.prefix(index + 1).joined(separator: "/"))
                } label: {
                    Label(segment, systemImage: "folder.fill")
                }
                .buttonStyle(.borderless)
            }

            Spacer()

            // Refreshing a folder that is already on screen.
            if service.isLoading && contentKind != .loading {
                ProgressView().controlSize(.small)
            }

            if service.isPreviewPresented && service.previewURL == nil && !service.previewFailed {
                Text(service.previewName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                ProgressView(value: service.previewProgress)
                    .controlSize(.small)
                    .frame(width: 100)
            }
        }
        .font(.callout)
        .lineLimit(1)
        // Fixed height: the download progress must not make the bar grow.
        .frame(height: 22)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }

    /// The whole folder takes a drop; an accent outline marks it, as the
    /// Finder outlines a window about to take one.
    @ViewBuilder
    private var dropOutline: some View {
        if isDropTargeted && !service.needsPermission {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.tint, lineWidth: 3)
                .padding(6)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private func contextMenu(for entries: [FileEntry]) -> some View {
        if entries.count == 1, let entry = entries.first {
            Button(L10n.isPL ? "Otwórz" : "Open") { service.activate(entry) }
        }
        let files = entries.filter { !$0.isDirectory }
        if !files.isEmpty {
            Button(L10n.isPL ? "Pobierz" : "Download") { files.forEach { service.download($0) } }
        }
        if !entries.isEmpty {
            Divider()
            Button(L10n.isPL ? "Usuń…" : "Delete…", role: .destructive) { entriesPendingDeletion = entries }
        }
    }

    private func entries(_ ids: Set<FileEntry.ID>) -> [FileEntry] {
        service.displayedEntries.filter { ids.contains($0.id) }
    }

    private func previewSelection() -> KeyPress.Result {
        guard let entry = entries(selection).first(where: { !$0.isDirectory }) else { return .ignored }
        service.preview(entry)
        return .handled
    }

    private func loadMoreIfLast(_ entry: FileEntry) {
        if entry.id == service.displayedEntries.last?.id { service.loadNextPage() }
    }

    private var deletionTitle: String {
        guard let first = entriesPendingDeletion.first else { return "" }
        if entriesPendingDeletion.count > 1 {
            return L10n.isPL ? "Usunąć \(entriesPendingDeletion.count) elementy?" : "Delete \(entriesPendingDeletion.count) items?"
        }
        return L10n.isPL ? "Usunąć \u{201E}\(first.name)\u{201D}?" : "Delete \"\(first.name)\"?"
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !service.needsPermission else { return false }
        // Sendable lock-guarded accumulator: provider completions fire on
        // arbitrary queues, so the collected URLs need synchronized shared state
        // that is safe to capture in the @Sendable completion closures.
        let collected = OSAllocatedUnfairLock<[URL]>(initialState: [])
        let group = DispatchGroup()
        for provider in providers {
            guard provider.canLoadObject(ofClass: URL.self) else { continue }
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { collected.withLock { $0.append(url) } }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let urls = collected.withLock { $0 }
            if !urls.isEmpty { service.upload(urls: urls) }
        }
        return true
    }

    // MARK: - Formatting

    private func sizeText(_ entry: FileEntry) -> String {
        if entry.isDirectory {
            guard let stats = service.folderStats[entry.relativePath] else { return "—" }
            return Self.sizeFormatter.string(fromByteCount: stats.totalSize)
        }
        return Self.sizeFormatter.string(fromByteCount: entry.size)
    }

    /// "0 bajtów", not the formatter's worded "Zero KB".
    private static let sizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f
    }()

    /// "Folder", or the file type's system name ("Obraz JPEG").
    private func kindText(_ entry: FileEntry) -> String {
        if entry.isDirectory { return "Folder" }
        if let known = Self.kindNames[entry.mimeType] { return known }
        let name = UTType(mimeType: entry.mimeType)?.localizedDescription ?? entry.mimeType
        Self.kindNames[entry.mimeType] = name
        return name
    }

    /// Row text is rebuilt on every selection change; the type lookup and
    /// the date formatting are kept so a fast click run stays instant.
    @MainActor private static var kindNames: [String: String] = [:]
    @MainActor private static var dates: [Int64: String] = [:]

    /// A folder's item count ("12 elementów"); empty for files.
    private func contentsText(_ entry: FileEntry) -> String {
        guard entry.isDirectory, let stats = service.folderStats[entry.relativePath] else { return "" }
        return Self.itemCount(stats.dirCount + stats.fileCount)
    }

    private static func itemCount(_ n: Int) -> String {
        guard L10n.isPL else { return n == 1 ? "1 item" : "\(n) items" }
        let mod10 = n % 10, mod100 = n % 100
        if n == 1 { return "1 element" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "\(n) elementy" }
        return "\(n) elementów"
    }

    private static func date(_ millis: Int64) -> String {
        if let known = dates[millis] { return known }
        let text = Date(timeIntervalSince1970: TimeInterval(millis) / 1000).formatted(date: .abbreviated, time: .shortened)
        dates[millis] = text
        return text
    }

    // MARK: - Sorting

    private static func comparator(for key: FileSortKey, ascending: Bool) -> KeyPathComparator<FileEntry> {
        let order: SortOrder = ascending ? .forward : .reverse
        switch key {
        case .name: return KeyPathComparator(\.name, order: order)
        case .size: return KeyPathComparator(\.size, order: order)
        case .modified: return KeyPathComparator(\.modified, order: order)
        case .type: return KeyPathComparator(\.mimeType, order: order)
        }
    }

    private func applySort(_ order: [KeyPathComparator<FileEntry>]) {
        guard let first = order.first, let key = Self.sortKey(for: first) else { return }
        service.sortAscending = first.order == .forward
        service.sortBy = key
    }

    private static func sortKey(for comparator: KeyPathComparator<FileEntry>) -> FileSortKey? {
        let keyPath: PartialKeyPath<FileEntry> = comparator.keyPath
        let keys: [(PartialKeyPath<FileEntry>, FileSortKey)] = [
            (\FileEntry.name, .name), (\FileEntry.size, .size),
            (\FileEntry.modified, .modified), (\FileEntry.mimeType, .type),
        ]
        return keys.first { $0.0 == keyPath }?.1
    }
}

/// SF Symbol for a MIME type.
private func fileSymbol(for mime: String) -> String {
    if mime.hasPrefix("image/") { return "photo" }
    if mime.hasPrefix("video/") { return "film" }
    if mime.hasPrefix("audio/") { return "music.note" }
    if mime == "application/pdf" { return "doc.richtext" }
    if mime.hasPrefix("text/") { return "doc.text" }
    return "doc"
}

/// A file's icon: its thumbnail when the phone sent one, otherwise the
/// folder or file-type symbol.
private struct FileIcon: View {
    let entry: FileEntry
    let thumbnail: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: entry.isDirectory ? "folder.fill" : fileSymbol(for: entry.mimeType))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(entry.isDirectory ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .padding(size * 0.08)
            }
        }
        .frame(width: size, height: size)
    }
}

/// An item of the icon view, as the Finder draws one: the icon on a soft
/// highlight and the name in an accent capsule when selected.
private struct FileIconItem: View {
    let entry: FileEntry
    let thumbnail: NSImage?
    let name: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            FileIcon(entry: entry, thumbnail: thumbnail, size: 64)
                .padding(6)
                .background(isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                            in: .rect(cornerRadius: 8, style: .continuous))
            Text(name)
                .font(.callout)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear),
                            in: .rect(cornerRadius: 4, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .help(name)
    }
}
