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
    /// viewer is a layer over the grid that zooms from the tile's frame.
    @State private var openPhoto: String?
    /// The open photo is zooming back into the grid: the title and toolbar
    /// are the grid's again from the moment the close starts, as in Photos.
    @State private var closing = false
    /// The photo has landed on its tile (near the end of the zoom back), so
    /// its selection outline shows; never over the photo still in flight.
    @State private var landed = true
    @State private var selection: String?
    /// "11.06–09.09.2025": the dates of the photos in view, under the title.
    @State private var visibleRange = ""
    /// Where the scroll is, written on every scrolled frame. A plain reference
    /// (not observed) so scrolling never re-renders the gallery; read when a
    /// zoom or a close needs it.
    @State private var scrollProbe = ScrollProbe()
    @State private var photoPendingDeletion: GalleryPhotoMeta?
    /// Scroll the grid to a photo (a fresh value each time, so a repeat counts).
    @State private var scrollRequest: ScrollRequest?
    /// Zoom level as a column count, like Photos: resizing the window scales
    /// the tiles and never reflows the grid (a minimum tile size changed the
    /// column count as the window moved, and every row jumped).
    @AppStorage("gallery.columns") private var savedColumns: Int = 5
    /// What the grid draws. An @AppStorage write reaches the view outside the
    /// animation transaction, so the zoom never animated while the grid read
    /// the stored value directly.
    @State private var columns: Int = 5
    private static let columnRange = 2...9   // as Photos

    var body: some View {
        ZStack {
            content
                .allowsHitTesting(openPhoto == nil)
            if let id = openPhoto, let photo = galleryService.photos.first(where: { $0.id == id }) {
                PhotoViewer(
                    photo: photo,
                    galleryService: galleryService,
                    sourceFrame: { [scrollProbe] id in scrollProbe.tileFrames[id] },
                    onStep: { step(from: id, by: $0) },
                    prepareClose: { id in
                        // Bring the tile on screen so the photo can zoom back into it.
                        selection = id
                        closing = true
                        scrollRequest = ScrollRequest(id: id)
                    },
                    onLanding: { landed = true },
                    onClosed: { openPhoto = nil; closing = false },
                    onDelete: { photoPendingDeletion = photo }
                )
                .zIndex(1)
            }
        }
        .onAppear {
            columns = min(max(savedColumns, Self.columnRange.lowerBound), Self.columnRange.upperBound)
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
                if openPhoto == photo.id { openPhoto = nil }
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: columns),
                    alignment: .leading,
                    spacing: 2
                ) {
                    ForEach(galleryService.photos) { photo in
                        GalleryTile(photo: photo, galleryService: galleryService,
                                    isSelected: selection == photo.id && (openPhoto != photo.id || landed),
                                    isOpen: openPhoto == photo.id, probe: scrollProbe)
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

                // Fixed-height footer: the spinner only fades, so the content
                // height doesn't change under the scroll's rubber band (which
                // shook the grid at the bottom).
                ProgressView()
                    .controlSize(.small)
                    .opacity(galleryService.isLoading ? 1 : 0)
                    .frame(height: 44)
            }
            // One continuous grid, as Photos' library: the dates of the photos in
            // view go under the title instead of day headers splitting the grid.
            .onScrollTargetVisibilityChange(idType: String.self) { visibleIDs in
                scrollProbe.visibleIDs = visibleIDs
                if let first = visibleIDs.first { preloadThumbnails(around: first, screens: 2, visible: visibleIDs.count) }
                scrollProbe.centerPhoto = visibleIDs.isEmpty ? nil : visibleIDs[visibleIDs.count / 2]
                let range = dateRange(of: visibleIDs)
                if range != visibleRange { visibleRange = range }
            }
            .onChange(of: scrollRequest) { _, request in
                guard let request else { return }
                proxy.scrollTo(request.id, anchor: request.anchor)
            }
        }
        // Open photo: "28 czerwca 2025 o 17:11:27" over "23 z 147", as Photos.
        .navigationTitle(viewerDate.map { $0.formatted(date: .long, time: .standard) }
                         ?? (L10n.isPL ? "Galeria" : "Gallery"))
        .navigationSubtitle(closing ? visibleRange : (openPhotoPosition ?? visibleRange))
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.return) {
            guard let selection else { return .ignored }
            open(selection)
            return .handled
        }
        .toolbar {
            if openPhoto == nil || closing { gridToolbar }
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

    /// The viewer zooms itself out of the tile (see PhotoViewer).
    private func open(_ id: String) {
        selection = id
        landed = false
        openPhoto = id
    }

    /// The open photo's date while the viewer is up (not while it closes).
    private var viewerDate: Date? { closing ? nil : openPhotoDate }

    /// "23 z 147": the open photo's place in the phone's library.
    private var openPhotoPosition: String? {
        guard let id = openPhoto, let index = galleryService.photos.firstIndex(where: { $0.id == id }) else { return nil }
        let total = max(galleryService.totalCount, galleryService.photos.count)
        return L10n.isPL ? "\(index + 1) z \(total)" : "\(index + 1) of \(total)"
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
    /// Zoom switches the layout at once, keeping the photo in the middle in the
    /// middle. Not animated: it is repeated often and bound to ⌘+/⌘−, and every
    /// animated variant of a lazy grid relayout misdrew tiles (2026-10-10).
    private func zoom(by direction: Int) {
        let next = min(max(columns - direction, Self.columnRange.lowerBound), Self.columnRange.upperBound)
        guard next != columns else { return }
        let pivot = scrollProbe.centerPhoto
        if let pivot {
            let ratio = CGFloat(columns) / CGFloat(next)
            let visibleNext = Int((CGFloat(max(scrollProbe.visibleIDs.count, 1)) / (ratio * ratio)).rounded(.up))
            preloadThumbnails(around: pivot, screens: 1, visible: max(visibleNext, scrollProbe.visibleIDs.count))
        }
        columns = next
        if let pivot { scrollRequest = ScrollRequest(id: pivot) }
        savedColumns = next
    }

    /// Requests the thumbnails `screens` screenfuls before and after a photo,
    /// so tiles are filled before they scroll (or zoom) into view. Already
    /// loaded or requested ones cost a dictionary lookup.
    private func preloadThumbnails(around id: String, screens: Int, visible: Int) {
        let photos = galleryService.photos
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        let reach = visible * (screens + 1)
        let range = max(0, index - reach)..<min(photos.count, index + reach)
        for photo in photos[range] { galleryService.requestThumbnail(photoId: photo.id) }
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
    /// The photo is open in the viewer (or zooming in or out of it): its
    /// image is there, not here, and so is the selection outline.
    let isOpen: Bool
    /// Receives the tile's frame, where the viewer's zoom starts and ends.
    let probe: ScrollProbe

    /// Observed on its own: another photo's thumbnail arriving doesn't redraw
    /// this tile.
    private var thumbnail: Thumbnail { galleryService.thumbnail(for: photo.id) }

    var body: some View {
        // Color.clear sets the square at the column's width; the image fills an
        // overlay and is clipped, so a tile never pushes the grid apart.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if !isOpen {
                    if let image = thumbnail.image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle().fill(.quaternary)
                    }
                }
            }
            .clipped()
            .overlay {
                if isSelected {
                    Rectangle().strokeBorder(.tint, lineWidth: 3)
                }
            }
            .contentShape(Rectangle())
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                probe.tileFrames[photo.id] = frame
            }
            .onAppear {
                if thumbnail.image == nil {
                    galleryService.requestThumbnail(photoId: photo.id)
                }
            }
    }
}

// MARK: - Photo viewer

/// One photo in place of the grid, as Photos opens it: it zooms out of its
/// tile, the date is the title, actions sit in the toolbar and details in an
/// inspector. ←/→ step through the library, Esc zooms back into the grid.
///
/// The zoom animates one frame, from the tile's square to the fitted photo
/// (and back), with the image aspect-filled and clipped to it, so it starts
/// as the tile's crop and ends as the whole photo. The grid dims under the
/// window background meanwhile. A short spring without bounce: Photos is
/// quick, and the spring can be retargeted mid-flight.
private struct PhotoViewer: View {
    let photo: GalleryPhotoMeta
    let galleryService: GalleryService
    let sourceFrame: (String) -> CGRect?
    let onStep: (Int) -> Void
    let prepareClose: (String) -> Void
    let onLanding: () -> Void
    let onClosed: () -> Void
    let onDelete: () -> Void

    /// The zooming image's frame in window coordinates; nil once settled.
    @State private var hero: CGRect?
    /// Opacity of the window background over the grid.
    @State private var backdrop: Double = 0
    /// The viewer's own frame in window coordinates.
    @State private var area: CGRect = .zero
    @State private var zoomedIn = false
    @State private var closing = false

    private static let zoom = Animation.spring(duration: 0.3, bounce: 0)
    private static let inset: CGFloat = 16

    init(photo: GalleryPhotoMeta, galleryService: GalleryService,
         sourceFrame: @escaping (String) -> CGRect?, onStep: @escaping (Int) -> Void,
         prepareClose: @escaping (String) -> Void, onLanding: @escaping () -> Void,
         onClosed: @escaping () -> Void,
         onDelete: @escaping () -> Void) {
        self.photo = photo
        self.galleryService = galleryService
        self.sourceFrame = sourceFrame
        self.onStep = onStep
        self.prepareClose = prepareClose
        self.onLanding = onLanding
        self.onClosed = onClosed
        self.onDelete = onDelete
        // First frame drawn exactly over the tile, so nothing flashes before
        // the zoom starts.
        _hero = State(initialValue: sourceFrame(photo.id))
    }

    @State private var rotation: Angle = .zero
    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var downloaded = false
    @AppStorage("gallery.showInfo") private var showInfo = false
    @FocusState private var focused: Bool

    private var taken: Date { Date(timeIntervalSince1970: TimeInterval(photo.dateTaken) / 1000) }

    private var image: NSImage? {
        galleryService.previewImages[photo.id] ?? galleryService.thumbnail(for: photo.id).image
    }

    var body: some View {
        ZStack {
            // Under the toolbar too: otherwise its scroll edge effect keeps
            // showing the blurred grid above the open photo.
            Color(nsColor: .windowBackgroundColor)
                .opacity(backdrop)
                .ignoresSafeArea()
            if let hero, let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: hero.width, height: hero.height)
                    .clipped()
                    .position(x: hero.midX - area.minX, y: hero.midY - area.minY)
            } else {
                // Without a tile to zoom from (or to) the photo fades with the backdrop.
                photoLayer.opacity(backdrop)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            area = frame
            if !zoomedIn { zoomedIn = true; zoomIn() }
        }
        .toolbar { if !closing { toolbar } }
        .inspector(isPresented: $showInfo) {
            info.inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.leftArrow) { onStep(-1); return .handled }
        .onKeyPress(.rightArrow) { onStep(1); return .handled }
        .onKeyPress(.escape) { zoomOut(); return .handled }
        .onChange(of: photo.id) { _, _ in
            rotation = .zero
            downloaded = false
            resetZoom(animated: false)
        }
    }

    private var photoLayer: some View {
        Group {
            if let image = galleryService.previewImages[photo.id] ?? galleryService.thumbnail(for: photo.id).image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
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
        .padding(Self.inset)
        .task(id: photo.id) {
            galleryService.requestPreview(photoId: photo.id, maxSize: 1920)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: zoomOut) {
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

    // MARK: - Zoom in and out of the tile

    /// Where the settled photo sits: aspect-fitted inside the padded area,
    /// exactly where photoLayer lays it out, so the hand-over is seamless.
    private func fittedFrame() -> CGRect {
        let bounds = area.insetBy(dx: Self.inset, dy: Self.inset)
        let size = image?.size ?? CGSize(width: photo.width, height: photo.height)
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }

    private func zoomIn() {
        guard hero != nil else {
            withAnimation(Self.zoom) { backdrop = 1 }
            return
        }
        // Let the tile-sized first frame land before animating away from it.
        DispatchQueue.main.async {
            // .removed: the default (.logicallyComplete) fires while the spring
            // is still settling, and the hand-over then jumped a few pixels.
            withAnimation(Self.zoom, completionCriteria: .removed) {
                hero = fittedFrame()
                backdrop = 1
            } completion: {
                if !closing { hero = nil }
            }
        }
    }

    private func zoomOut() {
        guard !closing else { return }
        closing = true
        rotation = .zero
        resetZoom(animated: false)
        prepareClose(photo.id)
        // Swap the settled photo for the zooming frame at the same place, give
        // the grid a pass to scroll the tile into view, then zoom into it.
        hero = fittedFrame()
        DispatchQueue.main.async {
            let target = sourceFrame(photo.id)
            // Hand back to the tile as soon as the photo has logically landed
            // on it: the viewer sits above the grid, so until it goes the
            // tile's selection outline is hidden under the landing photo.
            withAnimation(Self.zoom, completionCriteria: .logicallyComplete) {
                if let target { hero = target } else { hero = nil }
                backdrop = 0
            } completion: {
                onLanding()
                onClosed()
            }
        }
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

/// Scroll state kept out of SwiftUI's observation (see `scrollProbe`).
private final class ScrollProbe {
    var centerPhoto: String?
    var visibleIDs: [String] = []
    /// Where each tile on screen is, in window coordinates. The tiles and the
    /// viewer measure in .global: a named space on the ZStack resolved
    /// differently for the two (off by the sidebar and the toolbar).
    var tileFrames: [String: CGRect] = [:]
}

private struct ScrollRequest: Equatable {
    let id: String
    var anchor: UnitPoint = .center
    let token = UUID()
}
