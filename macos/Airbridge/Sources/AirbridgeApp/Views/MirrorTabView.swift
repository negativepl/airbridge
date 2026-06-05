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
                        title: "Mirror",
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
            VStack(spacing: 16) {
                EmptyStateView(
                    systemImage: "rectangle.on.rectangle",
                    title: L10n.isPL ? "Mirror w osobnym oknie" : "Mirroring in a separate window",
                    subtitle: L10n.isPL
                        ? "Stream odtwarza się w wydzielonym oknie."
                        : "The stream is playing in its own window."
                )
                Button(L10n.isPL ? "Pokaż tutaj" : "Show here") {
                    dismissWindow(id: "mirror")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 80)
            }
        }
    }

    // MARK: - Live stream

    private var streamView: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                MirrorRendererView(stream: mirrorService.sampleBufferStream)
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
                GlassSection {
                    HStack(spacing: 14) {
                        Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                            .font(.system(size: 26))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 36, height: 36)
                            .symbolEffect(.pulse, options: .repeating)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.isPL ? "Mirror telefonu" : "Mirror Phone")
                                .font(.ab(.headline, weight: .semibold))
                            Text(L10n.isPL
                                ? "Udostępnij ekran telefonu i steruj nim klikając."
                                : "Mirror your phone screen and control it by clicking.")
                                .font(.ab(.subheadline))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(L10n.isPL ? "Rozpocznij" : "Start") { start() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.extraLarge)
                    }
                }

                settingsSection
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var fpsBinding: Binding<Int> {
        Binding(get: { mirrorService.requestedFramesPerSecond },
                set: { mirrorService.requestedFramesPerSecond = $0 })
    }
    /// 0 = Auto; otherwise the manual bitrate in bps.
    private var bitrateBinding: Binding<Int> {
        Binding(
            get: { mirrorService.bitrateAuto ? 0 : mirrorService.requestedBitrateBps },
            set: { newVal in
                if newVal == 0 {
                    mirrorService.bitrateAuto = true
                } else {
                    mirrorService.bitrateAuto = false
                    mirrorService.requestedBitrateBps = newVal
                }
            }
        )
    }
    private var scaleBinding: Binding<Double> {
        Binding(get: { mirrorService.resolutionScale },
                set: { mirrorService.resolutionScale = $0 })
    }

    private var settingsSection: some View {
        GlassSection(
            title: LocalizedStringKey(L10n.isPL ? "Ustawienia udostępniania" : "Sharing settings"),
            systemImage: "slider.horizontal.3"
        ) {
            settingRow(L10n.isPL ? "Klatki" : "Frame rate") {
                Picker("", selection: fpsBinding) {
                    Text("30 FPS").tag(30)
                    Text("60 FPS").tag(60)
                    Text("120 FPS").tag(120)
                }
                .pickerStyle(.segmented)
            }

            settingRow(L10n.isPL ? "Rozdzielczość" : "Resolution") {
                Picker("", selection: scaleBinding) {
                    Text(L10n.isPL ? "Pełna" : "Full").tag(1.0)
                    Text("75%").tag(0.75)
                    Text("50%").tag(0.5)
                }
                .pickerStyle(.segmented)
            }

            settingRow("Bitrate") {
                Picker("", selection: bitrateBinding) {
                    Text(L10n.isPL ? "Auto" : "Auto").tag(0)
                    Text("8 Mbps").tag(8_000_000)
                    Text("12 Mbps").tag(12_000_000)
                    Text("20 Mbps").tag(20_000_000)
                    Text("30 Mbps").tag(30_000_000)
                    Text("40 Mbps").tag(40_000_000)
                }
                .pickerStyle(.menu)
                .fixedSize()
            }

            if mirrorService.isStreaming {
                infoRow(L10n.isPL ? "Aktualnie" : "Current",
                        "\(mirrorService.targetStreamWidth) × \(mirrorService.targetStreamHeight)")
            }

            Text(L10n.isPL
                ? "Zmiany działają od następnego startu mirrora. Niższa rozdzielczość/bitrate = gładziej i mniej latencji; wyższe = ostrzej."
                : "Changes apply on the next mirror start. Lower resolution/bitrate = smoother and lower latency; higher = sharper.")
                .font(.ab(.footnote))
                .foregroundStyle(.tertiary)
        }
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
