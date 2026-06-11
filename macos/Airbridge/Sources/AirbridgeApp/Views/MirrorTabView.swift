import SwiftUI
import Mirror

/// Mirror tab: start/stop screen sharing, the live interactive stream, and the
/// sharing settings. Replaces needing the separate Mirror window for the common
/// case (the standalone window scene still exists for pop-out use).
struct MirrorTabView: View {
    let mirrorService: MirrorService
    let connectionService: ConnectionService

    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if !connectionService.isConnected {
                EmptyStateContainer {
                    EmptyStateView(
                        systemImage: "iphone.gen3.radiowaves.left.and.right",
                        title: L10n.isPL ? "Udostępnianie ekranu" : "Screen Sharing",
                        subtitle: L10n.isPL
                            ? "Połącz się z telefonem, aby udostępnić jego ekran."
                            : "Connect to your phone to mirror its screen."
                    )
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
        EmptyStateContainer {
            EmptyStateView(
                systemImage: "rectangle.on.rectangle",
                title: L10n.isPL ? "Udostępnianie w osobnym oknie" : "Sharing in a separate window",
                subtitle: L10n.isPL
                    ? "Stream odtwarza się w wydzielonym oknie."
                    : "The stream is playing in its own window."
            ) {
                Button(L10n.isPL ? "Pokaż tutaj" : "Show here") {
                    dismissWindow(id: "mirror")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
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

    private var startView: some View {
        ScrollView {
            VStack(spacing: 16) {
                mirrorOptionCard(
                    slot: .forward,
                    icon: "iphone.gen3.radiowaves.left.and.right",
                    title: L10n.isPL ? "Udostępnianie ekranu" : "Screen Sharing",
                    subtitle: L10n.isPL
                        ? "Udostępnij ekran telefonu i steruj nim klikając."
                        : "Mirror your phone screen and control it by clicking.",
                    showResolution: true,
                    action: { start() }
                )

                mirrorOptionCard(
                    slot: .reverseMirror,
                    icon: "macbook.and.iphone",
                    title: L10n.isPL ? "Mój ekran na telefonie" : "My Screen on Phone",
                    subtitle: L10n.isPL
                        ? "Lustro głównego ekranu Maca."
                        : "Mirror this Mac's main screen.",
                    showResolution: false,
                    action: { startReverse(mode: 0) }
                )

                mirrorOptionCard(
                    slot: .reverseVirtual,
                    icon: "rectangle.portrait.on.rectangle.portrait.angled",
                    title: L10n.isPL ? "Telefon jako drugi monitor" : "Phone as Second Display",
                    subtitle: L10n.isPL
                        ? "Dodatkowy pulpit dopasowany do ekranu telefonu — pełny ekran, bez pasów."
                        : "An extra desktop shaped to the phone — full screen, no bars.",
                    showUIScale: true,
                    action: { startReverse(mode: 1) }
                )
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// One launch option in the Mirror tab — icon, CTA, and its own quality
    /// settings (each mode keeps independent settings).
    private func mirrorOptionCard(
        slot: MirrorSlot,
        icon: String,
        title: String,
        subtitle: String,
        showResolution: Bool = false,
        showUIScale: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        GlassSection {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 26))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.ab(.headline, weight: .semibold))
                        Text(subtitle)
                            .font(.ab(.subheadline))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button(L10n.isPL ? "Rozpocznij" : "Start", action: action)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.extraLarge)
                }

                Divider().opacity(0.4)

                qualityControls(slot: slot, showResolution: showResolution, showUIScale: showUIScale)
            }
        }
    }

    @ViewBuilder
    private func qualityControls(slot: MirrorSlot, showResolution: Bool, showUIScale: Bool) -> some View {
        VStack(spacing: 10) {
            settingRow(L10n.isPL ? "Klatki" : "Frame rate") {
                Picker("", selection: fpsBinding(slot)) {
                    Text("30 FPS").tag(30)
                    Text("60 FPS").tag(60)
                    Text("120 FPS").tag(120)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            if showResolution {
                settingRow(L10n.isPL ? "Rozdzielczość" : "Resolution") {
                    Picker("", selection: scaleBinding(slot)) {
                        Text(L10n.isPL ? "Pełna" : "Full").tag(1.0)
                        Text("75%").tag(0.75)
                        Text("50%").tag(0.5)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }

            if showUIScale {
                settingRow(L10n.isPL ? "Skala UI" : "UI scale") {
                    Picker("", selection: scaleBinding(slot)) {
                        Text(L10n.isPL ? "Większe UI" : "Bigger UI").tag(0.8)
                        Text(L10n.isPL ? "Standard" : "Standard").tag(1.0)
                        Text(L10n.isPL ? "Więcej miejsca" : "More space").tag(1.4)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }

            settingRow("Bitrate") {
                Picker("", selection: bitrateBinding(slot)) {
                    Text("Auto").tag(0)
                    Text("8 Mbps").tag(8_000_000)
                    Text("12 Mbps").tag(12_000_000)
                    Text("20 Mbps").tag(20_000_000)
                    Text("30 Mbps").tag(30_000_000)
                    Text("40 Mbps").tag(40_000_000)
                }
                .pickerStyle(.menu)
                .fixedSize()
            }

            settingRow(L10n.isPL ? "HEVC (H.265)" : "HEVC (H.265)") {
                Toggle("", isOn: hevcBinding(slot))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
        }
    }

    // MARK: - Per-slot quality bindings

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
    private func scaleBinding(_ slot: MirrorSlot) -> Binding<Double> {
        Binding(
            get: { mirrorService.quality(slot).resolutionScale },
            set: { var q = mirrorService.quality(slot); q.resolutionScale = $0; mirrorService.setQuality(slot, q) }
        )
    }
    private func hevcBinding(_ slot: MirrorSlot) -> Binding<Bool> {
        Binding(
            get: { mirrorService.quality(slot).useHEVC },
            set: { var q = mirrorService.quality(slot); q.useHEVC = $0; mirrorService.setQuality(slot, q) }
        )
    }

    private func settingRow<Control: View>(_ label: String, @ViewBuilder _ control: () -> Control) -> some View {
        HStack {
            Text(label).font(.ab(.body)).foregroundStyle(.secondary)
            Spacer()
            control().labelsHidden()
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.ab(.body)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.ab(.body)).monospacedDigit()
        }
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
