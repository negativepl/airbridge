import SwiftUI
import AppKit

// MARK: - TransferPopupView

struct TransferPopupView: View {
    let fileTransferService: FileTransferService
    @AppStorage("islandWidth") private var islandWidth: Double = 560
    @AppStorage("islandHeight") private var islandHeight: Double = 130

    @Namespace private var glassNS
    @State private var showComplete = false

    private var state: TransferPopupState {
        if fileTransferService.hasIncomingOffer {
            return .incoming(
                filename: fileTransferService.fileTransferFileName,
                sizeBytes: fileTransferService.incomingOfferFileSize
            )
        }
        if fileTransferService.isRejected {
            return .rejected(filename: fileTransferService.fileTransferFileName)
        }
        if fileTransferService.isWaitingForAccept {
            return .waiting(filename: fileTransferService.fileTransferFileName)
        }
        if showComplete {
            return .complete(
                filename: fileTransferService.fileTransferFileName,
                isReceiving: fileTransferService.isReceivingFile
            )
        }
        return .transferring(
            filename: fileTransferService.fileTransferFileName.isEmpty ? "file" : fileTransferService.fileTransferFileName,
            progress: fileTransferService.fileTransferProgress,
            isReceiving: fileTransferService.isReceivingFile
        )
    }

    private func tint(for state: TransferPopupState) -> Color {
        switch state {
        case .incoming, .waiting, .transferring: return .accentColor
        case .complete: return .green
        case .rejected: return .red
        }
    }

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            Group {
                switch state {
                case .incoming(let name, let size):
                    incomingView(name: name, size: size)
                case .waiting(let name):
                    waitingView(name: name)
                case .transferring(let name, let progress, let receiving):
                    transferringView(name: name, progress: progress, isReceiving: receiving)
                case .complete(_, let receiving):
                    completeView(isReceiving: receiving)
                case .rejected(let name):
                    rejectedView(name: name)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(width: islandWidth, height: islandHeight)
            .glassEffect(
                .regular.tint(tint(for: state)),
                in: .rect(cornerRadius: 28, style: .continuous)
            )
            .glassEffectID("popup", in: glassNS)
            .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        }
        .padding(Self.windowPadding)
        .frame(
            width: islandWidth + Self.windowPadding * 2,
            height: islandHeight + Self.windowPadding * 2
        )
        .animation(.airbridgeSmooth, value: state)
        .onChange(of: fileTransferService.fileTransferProgress) { _, new in
            if new >= 1.0 {
                withAnimation(.airbridgeSmooth) { showComplete = true }
            } else if new == 0 {
                showComplete = false
            }
        }
    }

    static let windowPadding: CGFloat = 40

    // MARK: - Subviews per state

    private func incomingView(name: String, size: Int64) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.primary)
                .symbolEffect(.bounce, value: name)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.isPL ? "Przychodzący plik" : "Incoming file")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(formatBytes(size))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            HStack(spacing: 8) {
                Button(L10n.isPL ? "Odrzuć" : "Reject") {
                    fileTransferService.rejectIncomingOffer()
                }
                .controlSize(.large)

                Button(L10n.isPL ? "Akceptuj" : "Accept") {
                    fileTransferService.acceptIncomingOffer()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private func waitingView(name: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "hourglass")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.primary)
                .symbolEffect(.pulse, options: .repeating)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.isPL ? "Czekam na akceptację..." : "Waiting for acceptance...")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(name)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(L10n.isPL ? "Anuluj" : "Cancel") {
                fileTransferService.cancelPendingTransfer()
            }
            .controlSize(.large)
        }
    }

    private func transferringView(name: String, progress: Double, isReceiving: Bool) -> some View {
        HStack(spacing: 16) {
            Image(systemName: isReceiving ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.primary)
                .symbolEffect(.variableColor, options: .repeating)

            VStack(alignment: .leading, spacing: 6) {
                Text(isReceiving
                    ? (L10n.isPL ? "Odbieram" : "Receiving")
                    : (L10n.isPL ? "Wysyłam" : "Sending"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)

                HStack {
                    Text(speedText)
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    Spacer()
                    Text(etaText)
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }

            Text("\(Int(progress * 100))%")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(width: 72, alignment: .trailing)
                .contentTransition(.numericText())
        }
    }

    private func completeView(isReceiving: Bool) -> some View {
        HStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.primary)
                .symbolEffect(.bounce, value: isReceiving)
            Text(isReceiving
                ? (L10n.isPL ? "Plik odebrany!" : "File received!")
                : (L10n.isPL ? "Plik wysłany!" : "File sent!"))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    private func rejectedView(name: String) -> some View {
        HStack(spacing: 16) {
            Spacer()
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.primary)
                .symbolEffect(.bounce, value: name)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.isPL ? "Przesyłanie odrzucone" : "Transfer rejected")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(name)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private var speedText: String {
        let speed = fileTransferService.transferSpeed
        let label = L10n.isPL ? "Prędkość" : "Speed"
        if speed > 1024 * 1024 {
            return String(format: "%@: %.1f MB/s", label, speed / (1024 * 1024))
        } else if speed > 1024 {
            return String(format: "%@: %.0f KB/s", label, speed / 1024)
        }
        return " "
    }

    private var etaText: String {
        let eta = fileTransferService.transferEta
        let label = L10n.isPL ? "Pozostało" : "Remaining"
        if eta > 60 {
            return "\(label): \(eta / 60) min \(eta % 60) s"
        } else if eta > 3 {
            return "\(label): \(eta) s"
        } else if fileTransferService.fileTransferProgress > 0 && fileTransferService.fileTransferProgress < 1.0 {
            return L10n.isPL ? "\(label): kilka sekund…" : "\(label): a few seconds…"
        }
        return " "
    }

    private func formatBytes(_ size: Int64) -> String {
        if size > 1024 * 1024 { return String(format: "%.1f MB", Double(size) / (1024.0 * 1024.0)) }
        if size > 1024 { return String(format: "%.0f KB", Double(size) / 1024.0) }
        return "\(size) B"
    }
}

// MARK: - TransferPopup singleton
// (Window management — see Task 18 for the slim rewrite)

@MainActor
final class TransferPopup {

    static let shared = TransferPopup()

    private var panel: NSWindow?
    private var isVisible = false

    private init() {}

    func show(fileTransferService: FileTransferService) {
        if isVisible { return }
        isVisible = true

        let view = TransferPopupView(fileTransferService: fileTransferService)
        let hostingView = NSHostingView(rootView: view)

        guard let screen = NSScreen.main else { return }
        let (x, y, width, height) = computeLayout(screen: screen)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.level = .screenSaver
        window.hasShadow = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // Slide in using NSAnimationContext instead of manual Timer
        let startY = y + height + 10
        window.setFrame(NSRect(x: x, y: startY, width: width, height: height), display: true)
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            window.animator().setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }

        self.panel = window
    }

    func hide(delay: TimeInterval = 2.5) {
        guard isVisible, let panel else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let panel = self.panel else { return }
            let frame = panel.frame
            let targetY = frame.origin.y + frame.height + 10

            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.30
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                ctx.allowsImplicitAnimation = true
                panel.animator().setFrameOrigin(NSPoint(x: frame.origin.x, y: targetY))
            }, completionHandler: {
                panel.orderOut(nil)
                self.panel = nil
                self.isVisible = false
            })
        }
    }

    private func computeLayout(screen: NSScreen) -> (x: Double, y: Double, width: Double, height: Double) {
        let defaults = UserDefaults.standard
        let offsetFromTop = defaults.object(forKey: "islandOffsetY") as? Double ?? 0
        let islandWidth = defaults.object(forKey: "islandWidth") as? Double ?? 560
        let islandHeight = defaults.object(forKey: "islandHeight") as? Double ?? 130

        // Window is larger than the visible glass pill so the drop shadow
        // can render without being clipped at the window edges. The SwiftUI
        // body pads by `windowPadding` on each side to center the pill.
        let padding = TransferPopupView.windowPadding
        let width = islandWidth + padding * 2
        let height = islandHeight + padding * 2

        let screenFrame = screen.frame
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - offsetFromTop - islandHeight - padding

        return (x, y, width, height)
    }
}
