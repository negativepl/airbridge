import SwiftUI
import UniformTypeIdentifiers
import Protocol

struct FilesBrowserView: View {
    let filesBrowserService: FilesBrowserService
    let connectionService: ConnectionService

    @AppStorage("files.viewMode") private var viewModeRaw: String = FileViewMode.list.rawValue
    @State private var searchText: String = ""
    @State private var entryPendingDeletion: FileEntry?

    private var viewMode: FileViewMode { FileViewMode(rawValue: viewModeRaw) ?? .list }

    private var deletionAlertTitle: String {
        guard let e = entryPendingDeletion else { return "" }
        if L10n.isPL {
            // Cudzysłowy „ " jako \u — literalne typograficzne znaki łamią parser tuż przed znakiem `?`.
            return "Usunąć \u{201E}\(e.name)\u{201D}?"
        } else {
            return "Delete \"\(e.name)\"?"
        }
    }

    var body: some View {
        Group {
            if !connectionService.isConnected {
                notConnectedView
            } else {
                VStack(spacing: 0) {
                    content
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
        .onChange(of: searchText) { _, new in
            filesBrowserService.setSearchQuery(new)
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
        .onChange(of: filesBrowserService.searchQuery) { _, q in
            if q.isEmpty && !searchText.isEmpty { searchText = "" }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .alert(
            deletionAlertTitle,
            isPresented: Binding(
                get: { entryPendingDeletion != nil },
                set: { if !$0 { entryPendingDeletion = nil } }
            ),
            presenting: entryPendingDeletion
        ) { entry in
            Button(L10n.isPL ? "Usuń" : "Delete", role: .destructive) {
                filesBrowserService.delete(entry)
                entryPendingDeletion = nil
            }
            Button(L10n.isPL ? "Anuluj" : "Cancel", role: .cancel) {
                entryPendingDeletion = nil
            }
        } message: { _ in
            Text(L10n.isPL ? "Tej operacji nie można cofnąć." : "This cannot be undone.")
        }
        .alert(
            L10n.isPL ? "Nie udało się usunąć" : "Delete failed",
            isPresented: Binding(
                get: { filesBrowserService.deleteError != nil },
                set: { if !$0 { filesBrowserService.deleteError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { filesBrowserService.deleteError = nil }
        } message: {
            Text(L10n.isPL
                 ? "Nie można było usunąć tego elementu. Spróbuj ponownie."
                 : "This item could not be deleted. Please try again.")
        }
        .sheet(isPresented: Binding(
            get: { filesBrowserService.isPreviewPresented },
            set: { if !$0 { filesBrowserService.dismissPreview() } }
        )) {
            FilePreviewSheet(service: filesBrowserService)
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

    /// Ścieżka jak pasek dolny Findera — kompaktowa, na materiale paska,
    /// klikalne segmenty.
    private var pathBar: some View {
        HStack(spacing: 4) {
            Button {
                filesBrowserService.open(path: "")
            } label: {
                Label(L10n.isPL ? "Telefon" : "Phone", systemImage: "smartphone")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)

            ForEach(Array(filesBrowserService.breadcrumbs.enumerated()), id: \.offset) { index, segment in
                Image(systemName: "chevron.compact.right")
                    .foregroundStyle(.tertiary)
                Button {
                    let path = filesBrowserService.breadcrumbs.prefix(index + 1).joined(separator: "/")
                    filesBrowserService.open(path: path)
                } label: {
                    if index == filesBrowserService.breadcrumbs.count - 1 {
                        Label(segment, systemImage: "folder.fill")
                    } else {
                        Text(segment)
                    }
                }
                .buttonStyle(.borderless)
            }

            Spacer()
        }
        .font(.ab(.caption))
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
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
            ForEach(entryGroups) { group in
                Section {
                    ForEach(group.entries) { entry in listRow(entry) }
                } header: {
                    if !group.title.isEmpty { Text(group.title) }
                }
            }
        }
        .listStyle(.inset)
        .animation(.default, value: filesBrowserService.displayedEntries.count)
    }

    @ViewBuilder
    private func listRow(_ entry: FileEntry) -> some View {
        FileRow(
            entry: entry,
            thumbnail: filesBrowserService.thumbnails[entry.relativePath],
            stats: filesBrowserService.folderStats[entry.relativePath],
            showPath: filesBrowserService.isSearching
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { filesBrowserService.activate(entry) }
        .contextMenu { contextMenuItems(entry) }
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 14)],
                alignment: .leading,
                spacing: 16,
                pinnedViews: [.sectionHeaders]
            ) {
                ForEach(entryGroups) { group in
                    Section {
                        ForEach(group.entries) { entry in gridCell(entry) }
                    } header: {
                        if !group.title.isEmpty {
                            DateSectionHeader(title: group.title)
                        }
                    }
                }
            }
            .padding(16)
        }
        .animation(.default, value: filesBrowserService.displayedEntries.count)
    }

    @ViewBuilder
    private func gridCell(_ entry: FileEntry) -> some View {
        FileGridCell(
            entry: entry,
            thumbnail: filesBrowserService.thumbnails[entry.relativePath],
            showPath: filesBrowserService.isSearching
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { filesBrowserService.activate(entry) }
        .contextMenu { contextMenuItems(entry) }
    }

    @ViewBuilder
    private func contextMenuItems(_ entry: FileEntry) -> some View {
        if !entry.isDirectory {
            Button { filesBrowserService.preview(entry) } label: {
                Label(L10n.isPL ? "Otwórz" : "Open", systemImage: "eye")
            }
            Button { filesBrowserService.download(entry) } label: {
                Label(L10n.isPL ? "Pobierz" : "Download", systemImage: "arrow.down.circle")
            }
            Divider()
        }
        Button(role: .destructive) { entryPendingDeletion = entry } label: {
            Label(L10n.isPL ? "Usuń" : "Delete", systemImage: "trash")
        }
    }

    /// Grupuje wpisy: foldery w sekcji „Foldery", pliki wg dnia modyfikacji
    /// (najnowsze u góry). W trybie wyszukiwania jedna sekcja bez nagłówka.
    /// Wspólne dla widoku siatki i listy.
    private var entryGroups: [FileDateGroup] {
        let entries = filesBrowserService.displayedEntries
        if filesBrowserService.isSearching {
            return entries.isEmpty ? [] : [FileDateGroup(id: "__search", title: "", entries: entries)]
        }
        var groups: [FileDateGroup] = []
        let dirs = entries.filter { $0.isDirectory }
        if !dirs.isEmpty {
            groups.append(FileDateGroup(id: "__folders", title: L10n.isPL ? "Foldery" : "Folders", entries: dirs))
        }
        let cal = Calendar.current
        var dayOrder: [Date] = []
        var byDay: [Date: [FileEntry]] = [:]
        for f in entries where !f.isDirectory {
            let day = cal.startOfDay(for: Date(timeIntervalSince1970: Double(f.modified) / 1000))
            if byDay[day] == nil { dayOrder.append(day) }
            byDay[day, default: []].append(f)
        }
        for day in dayOrder.sorted(by: >) {
            groups.append(FileDateGroup(
                id: Self.dayKeyFormatter.string(from: day),
                title: Self.sectionTitle(for: day),
                entries: byDay[day] ?? []
            ))
        }
        return groups
    }

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private static let sectionDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isPL ? "pl_PL" : "en_US")
        f.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return f
    }()

    /// Nagłówek dnia: „Dziś" / „Wczoraj" / pełna data.
    private static func sectionTitle(for day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return L10n.isPL ? "Dziś" : "Today" }
        if cal.isDateInYesterday(day) { return L10n.isPL ? "Wczoraj" : "Yesterday" }
        return sectionDateFormatter.string(from: day)
    }

    private var permissionEmptyState: some View {
        EmptyStateContainer {
            EmptyStateView(
                systemImage: "folder.badge.questionmark",
                title: L10n.isPL ? "Przyznaj dostęp do plików na telefonie" : "Grant file access on your phone",
                subtitle: L10n.isPL
                    ? "Na telefonie otwórz AirBridge → wizard uprawnień → „Pliki” i zezwól na dostęp do Pamięci wewnętrznej."
                    : "On your phone open AirBridge → permissions → \"Files\" and allow access to internal storage."
            ) {
                Button(L10n.isPL ? "Odśwież" : "Refresh") { filesBrowserService.reload() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
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

/// Okno podglądu pliku (QuickLook). Pokazuje spinner w trakcie pobierania,
/// potem podgląd; „Pobierz" zapisuje już-pobrane bajty do Downloads.
private struct FilePreviewSheet: View {
    let service: FilesBrowserService

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(service.previewName)
                    .font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                if service.previewURL != nil {
                    Button { service.saveCurrentPreviewToDownloads() } label: {
                        Label(L10n.isPL ? "Pobierz" : "Download", systemImage: "arrow.down.circle")
                    }
                }
                Button(L10n.isPL ? "Zamknij" : "Close") { service.dismissPreview() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            content
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    @ViewBuilder
    private var content: some View {
        if let url = service.previewURL {
            QuickLookPreview(url: url)
        } else if service.previewFailed {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 34)).foregroundStyle(.secondary)
                Text(L10n.isPL ? "Nie udało się pobrać pliku do podglądu."
                               : "Couldn't load the file for preview.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                if service.previewProgress > 0 {
                    ProgressView(value: service.previewProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 240)
                    Text("\(Int(service.previewProgress * 100))%")
                        .font(.caption).foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    ProgressView()
                    Text(L10n.isPL ? "Pobieram…" : "Loading…").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Sekcja siatki: foldery lub pliki z danego dnia. `title` puste = bez nagłówka.
private struct FileDateGroup: Identifiable {
    let id: String
    let title: String
    let entries: [FileEntry]
}

/// SF Symbol dla danego typu MIME (wspólne dla wiersza i kafelka siatki).
private func fileSymbol(for mime: String) -> String {
    if mime.hasPrefix("image/") { return "photo" }
    if mime.hasPrefix("video/") { return "film" }
    if mime.hasPrefix("audio/") { return "music.note" }
    if mime == "application/pdf" { return "doc.richtext" }
    if mime.hasPrefix("text/") { return "doc.text" }
    return "doc"
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
            Image(systemName: entry.isDirectory ? "folder.fill" : fileSymbol(for: entry.mimeType))
                .frame(width: 28, height: 28)
                .foregroundStyle(entry.isDirectory ? Color.accentColor : Color.secondary)
        }
    }

    private static let sizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter(); f.countStyle = .file; return f
    }()
}

/// Wspólny formatter rozmiaru pliku (kafelek + wiersz). Używany tylko z głównego wątku (SwiftUI).
private nonisolated(unsafe) let fileSizeFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter(); f.countStyle = .file; return f
}()

/// Sticky nagłówek sekcji daty w siatce („Dziś", „Wczoraj", pełna data).
private struct DateSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.ab(.subheadline, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .background(.bar, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct FileGridCell: View {
    let entry: FileEntry
    let thumbnail: NSImage?
    var showPath: Bool = false

    private var isVideo: Bool { entry.mimeType.hasPrefix("video/") }
    private var isMedia: Bool { isVideo || entry.mimeType.hasPrefix("image/") }
    private var displayName: String { showPath ? entry.relativePath : entry.name }

    var body: some View {
        VStack(spacing: 6) {
            tile
            VStack(spacing: 1) {
                Text(displayName)
                    .font(.caption).lineLimit(1).truncationMode(.middle)
                if !entry.isDirectory {
                    Text(fileSizeFormatter.string(fromByteCount: entry.size))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .help(displayName)
        }
    }

    private var tile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.quaternary)
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
            } else if entry.isDirectory {
                Image(systemName: "folder.fill")
                    .font(.system(size: 40)).foregroundStyle(Color.accentColor)
            } else if isMedia {
                ProgressView().controlSize(.small)   // szkielet, zanim miniaturka dojdzie
            } else {
                Image(systemName: fileSymbol(for: entry.mimeType))
                    .font(.system(size: 38)).foregroundStyle(.secondary)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .overlay(alignment: .center) {
            if isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(9)
                    .background(.black.opacity(0.5), in: Circle())
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }
}
