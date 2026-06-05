import SwiftUI
import Mirror

/// Mirror tab: start/stop screen sharing, the live interactive stream, and the
/// sharing settings. Replaces needing the separate Mirror window for the common
/// case (the standalone window scene still exists for pop-out use).
struct MirrorTabView: View {
    let mirrorService: MirrorService
    let connectionService: ConnectionService

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
                streamView
            } else {
                startView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.airbridgeQuick, value: mirrorService.isStreaming)
    }

    // MARK: - Live stream

    private var streamView: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
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

                HStack(spacing: 10) {
                    statsPill
                    Button { stop() } label: {
                        Image(systemName: "stop.fill")
                            .font(.ab(.subheadline, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.red).interactive(), in: .circle)
                }
                .padding(14)
            }
        }
    }

    private var statsPill: some View {
        HStack(spacing: 8) {
            Text("\(Int(mirrorService.decodedFramesPerSecond)) FPS")
            Text("·")
            Text(String(format: "%.1f Mbps", mirrorService.incomingBitrateMbps))
        }
        .font(.ab(.caption))
        .monospacedDigit()
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .glassEffect(.regular, in: .capsule)
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

    private var settingsSection: some View {
        GlassSection(
            title: LocalizedStringKey(L10n.isPL ? "Ustawienia udostępniania" : "Sharing settings"),
            systemImage: "slider.horizontal.3"
        ) {
            infoRow(L10n.isPL ? "Rozdzielczość" : "Resolution",
                    "\(mirrorService.targetStreamWidth) × \(mirrorService.targetStreamHeight)")
            infoRow(L10n.isPL ? "Klatki" : "Frame rate",
                    "\(mirrorService.requestedFramesPerSecond) FPS")
            infoRow("Bitrate",
                    String(format: "%.1f Mbps", Double(mirrorService.requestedBitrateBps) / 1_000_000))

            Text(L10n.isPL
                ? "Edytowalne ustawienia (jakość, FPS) wkrótce."
                : "Editable settings (quality, FPS) coming soon.")
                .font(.ab(.footnote))
                .foregroundStyle(.tertiary)
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

    private func stop() {
        Task { try? await connectionService.broadcast(.mirrorStop) }
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
        let y = 1 - ((location.y - origin.y) / fitted.height)
        return CGPoint(x: x, y: y)
    }
}
