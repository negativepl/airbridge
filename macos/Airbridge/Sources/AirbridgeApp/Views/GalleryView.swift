import SwiftUI
import Protocol

/// The phone's photos, laid out like Photos on the Mac: one dense square grid,
/// and a photo that zooms out of its tile into the window with its actions in
/// the toolbar and its details in an inspector.
struct GalleryView: View {
    let galleryService: GalleryService
    let connectionService: ConnectionService

    /// The photo shown over the grid. Not a NavigationStack push: the zoom
    /// out of the tile (`navigationTransition(.zoom)`) is iOS-only, so the
    /// viewer is a layer over the grid sharing a matched geometry with it.
    @State private var openPhoto: String?
    @Namespace private var zoomSpace
    @State private var selection: String?
    /// "11.06–09.09.2025": the dates of the photos in view, under the title.
    @State private var visibleRange = ""
    /// Old ÷ new column count of the zoom in flight (>1 zooming in).
    @State private var zoomRatio: CGFloat = 1
    /// Middle of the visible part of the grid; the zoom scales about it.
    @State private var zoomAnchor: UnitPoint = .center
    /// Photo at the centre of the scroll view, kept in place while zooming.
    @State private var centerPhoto: String?
    @State private var photoPendingDeletion: GalleryPhotoMeta?
    /// Zoom level as a column count, like Photos: resizing the window scales
    /// the tiles and never reflows the grid (a minimum tile size changed the
    /// column count as the window moved, and every row jumped).
    @AppStorage("gallery.columns") private var savedColumns: Int = 5
    /// What the grid draws. An @AppStorage write reaches the view outside the
    /// animation transaction, so the zoom never animated while the grid read
    /// the stored value directly.
    @State private var columns: Int = 5
    private static let columnRange = 2...12

    var body: some View {
        ZStack {
            content
                .opacity(openPhoto == nil ? 1 : 0)
                .allowsHitTesting(openPhoto == nil)
            if let id = openPhoto, let photo = galleryService.photos.first(where: { $0.id == id }) {
                PhotoViewer(
                    photo: photo,
                    galleryService: galleryService,
                    zoomSpace: zoomSpace,
                    onStep: { step(from: id, by: $0) },
                    onClose: { close() },
                    onDelete: { photoPendingDeletion = photo }
                )
                .zIndex(1)
            }
        }
        .onAppear {
            columns = savedColumns
            if connectionService.isConnected && galleryService.photos.isEmpty {
                galleryService.loadPhotos()
            }
        }
        .onChange(of: connectionService.isConnected) { _, connected in
            if connected && galleryService.photos.isEmpty {
                galleryService.loadPhotos()
            }
        }
        .onChange(of: connectionService.activeDeviceId) { _, _ in
            // Switched to a different phone — reload its gallery.
            openPhoto = nil
            if connectionService.isConnected { galleryService.clearAndReload() }
        }
        .alert(
            photoPendingDeletion.map { L10n.isPL ? "Usunąć „\($0.filename)” z telefonu?" : "Delete \"\($0.filename)\" from the phone?" } ?? "",
            isPresented: Binding(get: { photoPendingDeletion != nil }, set: { if !$0 { photoPendingDeletion = nil } }),
            presenting: photoPendingDeletion
        ) { photo in
            Button(L10n.isPL ? "Usuń" : "Delete", role: .destructive) {
                galleryService.deletePhoto(photoId: photo.id)
                if openPhoto == photo.id { close() }
                photoPendingDeletion = nil
            }
            Button(L10n.isPL ? "Anuluj" : "Cancel", role: .cancel) { photoPendingDeletion = nil }
        } message: { _ in
            Text(L10n.isPL
                 ? "Zdjęcie zostanie usunięte z biblioteki telefonu. Tej operacji nie można cofnąć."
                 : "The photo will be removed from the phone's library. This cannot be undone.")
        }
        .alert(
            L10n.isPL ? "Nie udało się usunąć zdjęcia" : "Could Not Delete Photo",
            isPresented: Binding(get: { galleryService.deleteError != nil }, set: { if !$0 { galleryService.deleteError = nil } })
        ) {
            Button("OK") { galleryService.deleteError = nil }
        } message: {
            Text(galleryService.deleteError == "declined"
                 ? (L10n.isPL ? "Usunięcie zostało odrzucone na telefonie." : "The deletion was declined on the phone.")
                 : (L10n.isPL ? "Telefon nie mógł usunąć tego zdjęcia." : "The phone could not delete this photo."))
        }
    }

    @ViewBuilder
    private var content: some View {
        if !connectionService.isConnected {
            ContentUnavailableView {
                Label(L10n.isPL ? "Brak połączenia" : "Not Connected", systemImage: "wifi.slash")
            } description: {
                Text(L10n.isPL ? "Połącz się z telefonem, aby przeglądać zdjęcia." : "Connect to your phone to browse photos.")
            }
        } else if galleryService.photos.isEmpty && galleryService.isLoading {
            ProgressView(L10n.isPL ? "Ładowanie zdjęć…" : "Loading Photos…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if galleryService.photos.isEmpty && galleryService.loadFailed {
            ContentUnavailableView {
                Label(L10n.isPL ? "Nie udało się załadować zdjęć" : "Could Not Load Photos",
                      systemImage: "exclamationmark.triangle")
            } description: {
                Text(L10n.isPL ? "Telefon nie odpowiedział. Spróbuj ponownie." : "The phone did not respond. Please try again.")
            } actions: {
                Button(L10n.isPL ? "Spróbuj ponownie" : "Try Again") { galleryService.clearAndReload() }
            }
        } else if galleryService.photos.isEmpty {
            ContentUnavailableView(L10n.isPL ? "Brak zdjęć" : "No Photos",
                                   systemImage: "photo.on.rectangle",
                                   description: Text(L10n.isPL ? "Na telefonie nie ma zdjęć." : "There are no photos on the phone."))
        } else {
            grid
        }
    }

    // MARK: - Grid

    private var grid: some View {
        ScrollView {
            // Zoom as Photos does it: the grid is magnified (or shrunk) about
            // the middle of the view while the new layout fades in from the
            // inverse scale. Tiles don't travel between rows. The ZStack keeps
            // the outgoing and incoming grids on top of each other.
            ZStack(alignment: .top) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: columns),
                    alignment: .leading,
                    spacing: 2
                ) {
                    ForEach(galleryService.photos) { photo in
                        GalleryTile(photo: photo, galleryService: galleryService,
                                    isSelected: selection == photo.id,
                                    isOpen: openPhoto == photo.id, zoomSpace: zoomSpace)
                            .onTapGesture {
                                selection = photo.id
                                // Double-click opens, like Photos; reading the
                                // click count keeps the single click instant.
                                if NSApp.currentEvent?.clickCount == 2 { open(photo.id) }
                            }
                            .contextMenu { contextMenu(photo) }
                            .onAppear { prefetchIfNear(photo) }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 2)
                .id(columns)
                .transition(.asymmetric(
                    insertion: .scale(scale: 1 / zoomRatio, anchor: zoomAnchor).combined(with: .opacity),
                    removal: .scale(scale: zoomRatio, anchor: zoomAnchor).combined(with: .opacity)
                ))
            }

            // Fixed-height footer: the spinner only fades, so the content
            // height doesn't change under the scroll's rubber band (which
            // shook the grid at the bottom).
            ProgressView()
                .controlSize(.small)
                .opacity(galleryService.isLoading ? 1 : 0)
                .frame(height: 44)
        }
        .scrollPosition(id: $centerPhoto, anchor: .center)
        .onScrollGeometryChange(for: UnitPoint.self) { geo in
            // The middle of the visible part, in the grid's own unit space.
            let height = max(geo.contentSize.height, 1)
            return UnitPoint(x: 0.5, y: (geo.contentOffset.y + geo.containerSize.height / 2) / height)
        } action: { _, anchor in
            zoomAnchor = anchor
        }
        // One continuous grid, as Photos' library: the dates of the photos in
        // view go under the title instead of day headers splitting the grid.
        .onScrollTargetVisibilityChange(idType: String.self) { visibleIDs in
            visibleRange = dateRange(of: visibleIDs)
        }
        .navigationTitle(openPhotoDate.map { $0.formatted(.dateTime.day().month(.wide).year()) }
                         ?? (L10n.isPL ? "Galeria" : "Gallery"))
        .navigationSubtitle(openPhotoDate.map { $0.formatted(date: .omitted, time: .shortened) } ?? visibleRange)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.return) {
            guard let selection else { return .ignored }
            open(selection)
            return .handled
        }
        .toolbar {
            if openPhoto == nil { gridToolbar }
        }
    }

    @ToolbarContentBuilder
    private var gridToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                zoom(by: -1)
            } label: {
                Label(L10n.isPL ? "Pomniejsz" : "Zoom Out", systemImage: "minus.magnifyingglass")
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(columns >= Self.columnRange.upperBound)
            Button {
                zoom(by: 1)
            } label: {
                Label(L10n.isPL ? "Powiększ" : "Zoom In", systemImage: "plus.magnifyingglass")
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(columns <= Self.columnRange.lowerBound)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                galleryService.clearAndReload()
            } label: {
                Label(L10n.isPL ? "Odśwież" : "Refresh", systemImage: "arrow.clockwise")
            }
        }
    }

    @ViewBuilder
    private func contextMenu(_ photo: GalleryPhotoMeta) -> some View {
        Button(L10n.isPL ? "Otwórz" : "Open") { open(photo.id) }
        Button(L10n.isPL ? "Pobierz" : "Download") { galleryService.downloadPhoto(photoId: photo.id) }
        Divider()
        Button(L10n.isPL ? "Usuń z telefonu…" : "Delete from Phone…", role: .destructive) {
            photoPendingDeletion = photo
        }
    }

    /// Asks for the next page while there are still ~40 photos to go, so it
    /// usually lands before the scroll reaches the bottom.
    private func prefetchIfNear(_ photo: GalleryPhotoMeta) {
        let photos = galleryService.photos
        guard let i = photos.lastIndex(where: { $0.id == photo.id }), i >= photos.count - 40 else { return }
        galleryService.loadNextPage()
    }

    private func open(_ id: String) {
        selection = id
        withAnimation(.smooth(duration: 0.4)) { openPhoto = id }
    }

    /// Back to the grid, scrolled so the photo's tile is on screen for the
    /// zoom back into it.
    private func close() {
        guard let id = openPhoto else { return }
        selection = id
        centerPhoto = id
        withAnimation(.smooth(duration: 0.4)) { openPhoto = nil }
    }

    private var openPhotoDate: Date? {
        guard let id = openPhoto, let photo = galleryService.photos.first(where: { $0.id == id }) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(photo.dateTaken) / 1000)
    }

    /// Previous/next photo in the viewer; loads the next page at the end.
    private func step(from id: String, by delta: Int) {
        let photos = galleryService.photos
        guard let i = photos.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        if j >= photos.count - 3 { galleryService.loadNextPage() }
        guard photos.indices.contains(j) else { return }
        selection = photos[j].id
        openPhoto = photos[j].id
    }

    /// Zooming in shows fewer, larger tiles.
    /// Cross-zoom between the two layouts (see the grid); the scroll position
    /// keeps the photo at the centre where it was.
    private func zoom(by direction: Int) {
        let next = min(max(columns - direction, Self.columnRange.lowerBound), Self.columnRange.upperBound)
        guard next != columns else { return }
        zoomRatio = CGFloat(columns) / CGFloat(next)
        withAnimation(.smooth(duration: 0.35)) { columns = next }
        savedColumns = next
    }

    private func dateRange(of ids: [String]) -> String {
        let wanted = Set(ids)
        let dates = galleryService.photos.lazy
            .filter { wanted.contains($0.id) }
            .map { Date(timeIntervalSince1970: TimeInterval($0.dateTaken) / 1000) }
        guard let first = dates.min(), let last = dates.max() else { return "" }
        return Self.rangeFormatter.string(from: first, to: last)
    }

    private static let rangeFormatter: DateIntervalFormatter = {
        let f = DateIntervalFormatter()
        f.dateTemplate = "ddMMyyyy"
        return f
    }()
}

/// Square grid tile: the thumbnail fills and is cropped; the selection is the
/// accent outline Photos draws.
private struct GalleryTile: View {
    let photo: GalleryPhotoMeta
    let galleryService: GalleryService
    let isSelected: Bool
    /// The photo is open in the viewer: its image is there, not here.
    let isOpen: Bool
    let zoomSpace: Namespace.ID

    var body: some View {
        // Color.clear sets the square at the column's width; the image fills an
        // overlay and is clipped, so a tile never pushes the grid apart.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                // The zoom's source is the visible square, not the image: an
                // aspect-filled image's own frame overhangs the tile (a tall
                // screenshot reaches far above and below it).
                if !isOpen {
                    Color.clear
                        .overlay {
                            if let image = galleryService.thumbnailImages[photo.id] {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Rectangle().fill(.quaternary)
                            }
                        }
                        .clipped()
                        .matchedGeometryEffect(id: photo.id, in: zoomSpace)
                }
            }
            .overlay {
                if isSelected {
                    Rectangle().strokeBorder(.tint, lineWidth: 3)
                }
            }
            .contentShape(Rectangle())
            .onAppear {
                if galleryService.thumbnailImages[photo.id] == nil {
                    galleryService.requestThumbnail(photoId: photo.id)
                }
            }
    }
}

// MARK: - Photo viewer

/// One photo in place of the grid, as Photos opens it: the system back button,
/// the date as the title, actions in the toolbar and details in an inspector.
/// ←/→ step through the library, Esc returns to the grid.
private struct PhotoViewer: View {
    let photo: GalleryPhotoMeta
    let galleryService: GalleryService
    let zoomSpace: Namespace.ID
    let onStep: (Int) -> Void
    let onClose: () -> Void
    let onDelete: () -> Void

    @State private var rotation: Angle = .zero
    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var downloaded = false
    @AppStorage("gallery.showInfo") private var showInfo = false
    @FocusState private var focused: Bool

    private var taken: Date { Date(timeIntervalSince1970: TimeInterval(photo.dateTaken) / 1000) }

    var body: some View {
        photoLayer
            .toolbar { toolbar }
            .inspector(isPresented: $showInfo) {
                info.inspectorColumnWidth(min: 240, ideal: 280, max: 360)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onAppear { focused = true }
            .onKeyPress(.leftArrow) { onStep(-1); return .handled }
            .onKeyPress(.rightArrow) { onStep(1); return .handled }
            .onKeyPress(.escape) { onClose(); return .handled }
            .onChange(of: photo.id) { _, _ in
                rotation = .zero
                downloaded = false
                resetZoom(animated: false)
            }
    }

    private var photoLayer: some View {
        Group {
            if let image = galleryService.previewImages[photo.id] ?? galleryService.thumbnailImages[photo.id] {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .matchedGeometryEffect(id: photo.id, in: zoomSpace)
                    .rotationEffect(rotation)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(zoomGesture)
                    .simultaneousGesture(panGesture)
                    .onTapGesture(count: 2) { toggleZoom() }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .task(id: photo.id) {
            galleryService.requestPreview(photoId: photo.id, maxSize: 1920)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: onClose) {
                Label(L10n.isPL ? "Wstecz" : "Back", systemImage: "chevron.backward")
            }
            .help(L10n.isPL ? "Wróć do zdjęć" : "Back to photos")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                withAnimation { rotation -= .degrees(90) }
            } label: {
                Label(L10n.isPL ? "Obróć" : "Rotate", systemImage: "rotate.left")
            }
            .keyboardShortcut("r", modifiers: .command)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                galleryService.downloadPhoto(photoId: photo.id)
                downloaded = true
            } label: {
                Label(downloaded ? (L10n.isPL ? "Pobrano" : "Downloaded") : (L10n.isPL ? "Pobierz" : "Download"),
                      systemImage: downloaded ? "checkmark.circle" : "arrow.down.circle")
                    .contentTransition(.symbolEffect(.replace))
            }
            .help(L10n.isPL ? "Pobierz oryginał do folderu Pobrane" : "Download the original to Downloads")
        }
        ToolbarItem(placement: .primaryAction) {
            Button(role: .destructive, action: onDelete) {
                Label(L10n.isPL ? "Usuń z telefonu" : "Delete from Phone", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showInfo.toggle()
            } label: {
                Label(L10n.isPL ? "Informacje" : "Info", systemImage: "info.circle")
            }
            .keyboardShortcut("i", modifiers: .command)
        }
    }

    private var info: some View {
        Form {
            Section {
                LabeledContent(L10n.isPL ? "Nazwa" : "Name") {
                    Text(photo.filename).textSelection(.enabled)
                }
                LabeledContent(L10n.isPL ? "Data" : "Date",
                               value: taken.formatted(date: .long, time: .shortened))
            }
            Section {
                LabeledContent(L10n.isPL ? "Wymiary" : "Dimensions", value: "\(photo.width) × \(photo.height)")
                LabeledContent(L10n.isPL ? "Rozmiar" : "Size",
                               value: ByteCountFormatter.string(fromByteCount: photo.size, countStyle: .file))
                LabeledContent(L10n.isPL ? "Format" : "Format",
                               value: photo.mimeType.replacingOccurrences(of: "image/", with: "").uppercased())
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Zoom and pan

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = max(0.8, min(6, committedScale * value.magnification))
            }
            .onEnded { _ in
                if scale < 1 { resetZoom(animated: true) } else { committedScale = scale }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(width: committedOffset.width + value.translation.width,
                                height: committedOffset.height + value.translation.height)
            }
            .onEnded { _ in committedOffset = offset }
    }

    private func toggleZoom() {
        if scale > 1 {
            resetZoom(animated: true)
        } else {
            withAnimation { scale = 2; committedScale = 2 }
        }
    }

    private func resetZoom(animated: Bool) {
        let reset = {
            scale = 1; committedScale = 1
            offset = .zero; committedOffset = .zero
        }
        if animated { withAnimation { reset() } } else { reset() }
    }
}
