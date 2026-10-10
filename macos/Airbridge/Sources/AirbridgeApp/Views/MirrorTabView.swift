import SwiftUI
import Mirror

/// Mirror tab: start/stop screen sharing, the live interactive stream, and the
/// sharing settings. Replaces needing the separate Mirror window for the common
/// case (the standalone window scene still exists for pop-out use).
struct MirrorTabView: View {
    let mirrorService: MirrorService
    let connectionService: ConnectionService

    @Environment(\.dismissWindow) private var dismissWindow
    /// Modes whose "Advanced" group is open.
    @State private var advancedOpen: Set<String> = []

    var body: some View {
        Group {
            if !connectionService.isConnected {
                ContentUnavailableView {
                    Label(L10n.isPL ? "Brak połączenia" : "Not Connected", systemImage: "wifi.slash")
                } description: {
                    Text(L10n.isPL ? "Połącz się z telefonem, aby udostępniać ekran." : "Connect to your phone to share screens.")
                }
            } else if mirrorService.isStreaming {
                if mirrorService.presentedInWindow {
                    poppedOutView
                } else {
                    streamView
                }
            } else {
                startView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.airbridgeQuick, value: mirrorService.isStreaming)
    }

    private var poppedOutView: some View {
        ContentUnavailableView {
            Label(L10n.isPL ? "Udostępnianie w osobnym oknie" : "Sharing in a Separate Window",
                  systemImage: "macwindow.on.rectangle")
        } description: {
            Text(L10n.isPL ? "Ekran telefonu jest wyświetlany w osobnym oknie." : "The phone's screen is showing in its own window.")
        } actions: {
            Button(L10n.isPL ? "Pokaż tutaj" : "Show Here") { dismissWindow(id: "mirror") }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Live stream

    private var streamView: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                MirrorRendererView(streamFactory: mirrorService.makeSampleBufferStream)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                guard let p = normalizedPoint(
                                    location: value.location,
                                    in: proxy.size,
                                    aspectRatio: mirrorService.videoAspectRatio
                                ) else { return }
                                mirrorService.sendTap(xNorm: p.x, yNorm: p.y)
                            }
                    )
            }
        }
        // Controls (stats + stop) live in the window toolbar so they never
        // cover the streamed image — see MainWindow.
    }

    // MARK: - Start / settings

    /// The three modes as System Settings lays out a pane: a grouped form,
    /// one section per mode with its Start button, the one setting people
    /// understand on show and the encoder's knobs under "Advanced" (Sidecar
    /// shows none of them).
    private var startView: some View {
        Form {
            modeSection(
                slot: .forward,
                icon: "iphone.gen3.radiowaves.left.and.right",
                title: L10n.isPL ? "Ekran telefonu na Macu" : "Phone Screen on Mac",
                subtitle: L10n.isPL ? "Wyświetl ekran telefonu i steruj nim klikając." : "Show the phone's screen and control it by clicking.",
                action: { start() }
            ) {
                Picker(L10n.isPL ? "Rozdzielczość" : "Resolution", selection: scaleBinding(.forward, choices: [1.0, 0.75, 0.5])) {
                    Text(L10n.isPL ? "Pełna" : "Full").tag(1.0)
                    Text("75%").tag(0.75)
                    Text("50%").tag(0.5)
                }
            }

            modeSection(
                slot: .reverseMirror,
                icon: "macbook.and.iphone",
                title: L10n.isPL ? "Ekran Maca na telefonie" : "Mac Screen on Phone",
                subtitle: L10n.isPL ? "Lustro głównego ekranu Maca." : "Mirror this Mac's main screen.",
                action: { startReverse(mode: 0) }
            ) {
                EmptyView()
            }

            modeSection(
                slot: .reverseVirtual,
                icon: "rectangle.portrait.on.rectangle.portrait.angled",
                title: L10n.isPL ? "Telefon jako drugi monitor" : "Phone as Second Display",
                subtitle: L10n.isPL ? "Dodatkowy pulpit dopasowany do ekranu telefonu." : "An extra desktop shaped to the phone's screen.",
                action: { startReverse(mode: 1) }
            ) {
                // Named as in System Settings › Displays.
                Picker(L10n.isPL ? "Wielkość interfejsu" : "Interface Size", selection: scaleBinding(.reverseVirtual, choices: [0.8, 1.0, 1.4])) {
                    Text(L10n.isPL ? "Większy tekst" : "Larger Text").tag(0.8)
                    Text(L10n.isPL ? "Standardowa" : "Default").tag(1.0)
                    Text(L10n.isPL ? "Więcej miejsca" : "More Space").tag(1.4)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// One mode: icon, name and a line of explanation with Start on the
    /// right, its own settings below, the encoder's under "Advanced".
    private func modeSection<Settings: View>(
        slot: MirrorSlot,
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void,
        @ViewBuilder settings: () -> Settings
    ) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.isPL ? "Rozpocznij" : "Start", action: action)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 4)
            settings()
            // "Advanced" is a row of the section that reveals the encoder's
            // settings as ordinary rows below it, spaced and separated like
            // the rest of the form (a DisclosureGroup crammed them together).
            let open = advancedBinding(slot)
            Button {
                withAnimation { open.wrappedValue.toggle() }
            } label: {
                HStack {
                    Text(L10n.isPL ? "Zaawansowane" : "Advanced")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open.wrappedValue ? 90 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if open.wrappedValue {
                Picker(L10n.isPL ? "Klatki na sekundę" : "Frame Rate", selection: fpsBinding(slot)) {
                    Text("30").tag(30)
                    Text("60").tag(60)
                    // The Mac side captures at 60 Hz at most (the virtual
                    // display runs at 60 Hz), so only the phone's screen can
                    // be sent faster.
                    if slot == .forward { Text("120").tag(120) }
                }
                Picker(L10n.isPL ? "Przepływność" : "Bitrate", selection: bitrateBinding(slot)) {
                    Text(L10n.isPL ? "Automatyczna" : "Automatic").tag(0)
                    Text("8 Mb/s").tag(8_000_000)
                    Text("12 Mb/s").tag(12_000_000)
                    Text("20 Mb/s").tag(20_000_000)
                    Text("30 Mb/s").tag(30_000_000)
                    Text("40 Mb/s").tag(40_000_000)
                }
                Toggle(L10n.isPL ? "Kodek HEVC (H.265)" : "HEVC (H.265) Codec", isOn: hevcBinding(slot))
            }
        }
    }

    // MARK: - Per-slot quality bindings

    private func advancedBinding(_ slot: MirrorSlot) -> Binding<Bool> {
        let key = "\(slot)"
        return Binding(
            get: { advancedOpen.contains(key) },
            set: { open in if open { advancedOpen.insert(key) } else { advancedOpen.remove(key) } }
        )
    }

    private func fpsBinding(_ slot: MirrorSlot) -> Binding<Int> {
        Binding(
            get: { mirrorService.quality(slot).fps },
            set: { var q = mirrorService.quality(slot); q.fps = $0; mirrorService.setQuality(slot, q) }
        )
    }
    /// 0 = Auto; otherwise the manual bitrate in bps.
    private func bitrateBinding(_ slot: MirrorSlot) -> Binding<Int> {
        Binding(
            get: { let q = mirrorService.quality(slot); return q.bitrateAuto ? 0 : q.bitrateBps },
            set: { newVal in
                var q = mirrorService.quality(slot)
                if newVal == 0 { q.bitrateAuto = true }
                else { q.bitrateAuto = false; q.bitrateBps = newVal }
                mirrorService.setQuality(slot, q)
            }
        )
    }
    /// Snaps the stored scale to the nearest picker value, so a value that was
    /// not written by this picker (an older build, a hand-edited default)
    /// still selects a segment.
    private func scaleBinding(_ slot: MirrorSlot, choices: [Double]) -> Binding<Double> {
        Binding(
            get: {
                let stored = mirrorService.quality(slot).resolutionScale
                return choices.min { abs($0 - stored) < abs($1 - stored) } ?? stored
            },
            set: { var q = mirrorService.quality(slot); q.resolutionScale = $0; mirrorService.setQuality(slot, q) }
        )
    }
    private func hevcBinding(_ slot: MirrorSlot) -> Binding<Bool> {
        Binding(
            get: { mirrorService.quality(slot).useHEVC },
            set: { var q = mirrorService.quality(slot); q.useHEVC = $0; mirrorService.setQuality(slot, q) }
        )
    }

    // MARK: - Actions

    private func start() {
        guard let token = connectionService.currentPairingTokenString() else { return }
        Task { try? await connectionService.broadcast(.mirrorStartRequest(token: token)) }
    }

    private func startReverse(mode: Int) {
        guard let token = connectionService.currentPairingTokenString() else { return }
        Task { try? await connectionService.broadcast(.reverseMirrorStart(token: token, mode: mode)) }
    }

    // MARK: - Tap mapping (letterboxed aspect-fit, normalized 0..1)

    private func normalizedPoint(location: CGPoint, in size: CGSize, aspectRatio: CGFloat) -> CGPoint? {
        guard size.width > 0, size.height > 0, aspectRatio > 0 else { return nil }
        let fitted: CGSize
        if size.width / size.height > aspectRatio {
            fitted = CGSize(width: size.height * aspectRatio, height: size.height)
        } else {
            fitted = CGSize(width: size.width, height: size.width / aspectRatio)
        }
        let origin = CGPoint(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2)
        guard location.x >= origin.x, location.y >= origin.y,
              location.x <= origin.x + fitted.width, location.y <= origin.y + fitted.height else { return nil }
        let x = (location.x - origin.x) / fitted.width
        // Top-down, matching Android screen coords (0 = top). No flip.
        let y = (location.y - origin.y) / fitted.height
        return CGPoint(x: x, y: y)
    }
}
