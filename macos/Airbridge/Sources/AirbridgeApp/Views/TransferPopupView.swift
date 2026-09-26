import SwiftUI
import AppKit
import Observation
import UniformTypeIdentifiers

// MARK: - Popup presentation state
// Tiny @Observable holding the popup's "is visually presented" flag.
// Driven by `TransferPopup` (the window manager) and observed by
// `TransferPopupView` to drive scale/opacity transitions in SwiftUI.
// This lets the appear/disappear animation happen in SwiftUI (with native
// spring) instead of via NSWindow frame animation, which means the window
// itself stays anchored at the top of the screen — only the content scales.

@Observable
@MainActor
final class TransferPopupPresentation {
    var isPresented: Bool = false
}

// MARK: - Blur transition
// `AnyTransition` that blurs content as it enters/leaves. Paired with a
// non-bouncy `easeInOut` (no scale, no spring overshoot) it gives the state
// cross-fade a soft, liquid-glass feel without the island pulsing.

private struct BlurTransitionModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

extension AnyTransition {
    static func blurTransition(radius: CGFloat) -> AnyTransition {
        .modifier(
            active: BlurTransitionModifier(radius: radius),
            identity: BlurTransitionModifier(radius: 0)
        )
    }
}

// MARK: - NSScreen notch helper

extension NSScreen {
    /// Height of the camera notch on MacBook Pro 14"/16" displays. Returns 0
    /// on displays without a notch. Used to push popup content below the
    /// notch cutout so centered text/icons don't get visually clipped.
    var notchInset: CGFloat {
        if #available(macOS 12.0, *) {
            return safeAreaInsets.top
        }
        return 0
    }
}

// MARK: - TransferPopupView

struct TransferPopupView: View {
    let connectionService: ConnectionService
    let fileTransferService: FileTransferService
    /// Source of the "content arrived from the phone" receipt state.
    let clipboardService: ClipboardService
    /// Top inset for the notch on MacBook Pro 14"/16". Content is pushed down
    /// by this amount so it sits below the notch cutout.
    let notchInset: CGFloat
    /// Drives the appear/disappear scale+opacity animation. Mutated by
    /// TransferPopup (the window manager) inside `withAnimation` blocks.
    let presentation: TransferPopupPresentation
    @AppStorage("islandWidth") private var islandWidth: Double = 560
    @AppStorage("islandHeight") private var islandHeight: Double = 130

    @State private var showComplete = false
    @State private var isTargeted = false

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
        if fileTransferService.isFailed {
            return .failed(filename: fileTransferService.fileTransferFileName)
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
        // Actively transferring as long as progress is non-zero. We treat
        // 1.0 as still .transferring until `showComplete` flips — otherwise
        // the brief moment when progress hits 1.0 (before the .onChange
        // handler fires) computes to .idle and flashes the drop zone.
        let progress = fileTransferService.fileTransferProgress
        if progress > 0 {
            return .transferring(
                filename: fileTransferService.fileTransferFileName.isEmpty ? "file" : fileTransferService.fileTransferFileName,
                progress: progress,
                isReceiving: fileTransferService.isReceivingFile
            )
        }
        // Accepted, but the upload has not sent its first byte yet. Without
        // this the popup would fall through to the idle drop zone and flash
        // "Drop file here" at someone who just accepted a file.
        if fileTransferService.isAwaitingAcceptedTransfer {
            return .transferring(
                filename: fileTransferService.fileTransferFileName,
                progress: 0,
                isReceiving: true
            )
        }
        // Clipboard receipt — a transfer in flight still owns the popup, but
        // an arriving link outranks both the headphone question and idle.
        if let preview = clipboardService.incomingPreview {
            return .clipboardReceived(preview: preview, isLink: clipboardService.incomingURL != nil)
        }
        // Ask-first headphone prompt — below every transfer state (those
        // take priority over the question) but above idle.
        if connectionService.headphonePromptVisible {
            return .headphonePrompt
        }
        // Nothing active → idle drop zone
        return .idle(connected: connectionService.isConnected)
    }

    private func tint(for state: TransferPopupState) -> Color {
        switch state {
        case .idle: return .accentColor
        case .incoming, .waiting, .transferring, .headphonePrompt: return .accentColor
        case .clipboardReceived: return .accentColor
        case .complete: return .green
        case .rejected, .failed: return .red
        }
    }

    /// Three-color palette per state for the aurora-style background.
    /// SwiftUI interpolates each color independently when the state
    /// changes, so transitions blend the three colors smoothly.
    private func palette(for state: TransferPopupState) -> GradientPalette {
        switch state {
        case .idle, .incoming, .waiting, .transferring, .headphonePrompt:
            return GradientPalette(primary: .blue, secondary: .cyan, tertiary: .purple)
        case .clipboardReceived:
            return GradientPalette(primary: .green, secondary: .mint, tertiary: .teal)
        case .complete:
            return GradientPalette(primary: .green, secondary: .mint, tertiary: .teal)
        case .rejected, .failed:
            return GradientPalette(primary: .red, secondary: .orange, tertiary: .pink)
        }
    }

    private func intensity(for state: TransferPopupState) -> Double {
        switch state {
        case .idle(let connected): return connected ? (isTargeted ? 1.0 : 0.7) : 0.0
        case .incoming: return 0.9
        case .waiting: return 0.75
        case .transferring: return 1.0
        case .complete: return 0.95
        case .rejected: return 0.85
        case .failed: return 0.85
        case .headphonePrompt: return 0.9
        case .clipboardReceived: return 0.9
        }
    }

    /// Progress value for the current transfer (0 when not transferring).
    private var transferProgress: Double {
        if case .transferring(_, let p, _) = state { return p }
        return 0
    }

    private var isIdleConnected: Bool {
        if case .idle(let connected) = state { return connected }
        return false
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard connectionService.isConnected else { return false }
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                fileTransferService.sendFile(url: url)
            }
        }
        return true
    }

    /// Stable identity for the state TYPE — changes only when the popup
    /// switches kinds (idle→waiting→transferring→etc.). Does NOT change
    /// when `fileTransferProgress` updates, so progress ticks don't cause
    /// the view to re-mount and kill the transition.
    private var stateKind: Int {
        switch state {
        case .idle: return 0
        case .incoming: return 1
        case .waiting: return 2
        case .transferring: return 3
        case .complete: return 4
        case .rejected: return 5
        case .headphonePrompt: return 6
        case .failed: return 7
        case .clipboardReceived: return 8
        }
    }

    /// Content view for the current state. Extracted as a `@ViewBuilder`
    /// so `.id(stateKind)` can be applied to the whole result — that's
    /// what lets SwiftUI treat each state as a distinct view and actually
    /// fire the `.transition(...)` on add/remove.
    @ViewBuilder
    private func contentForState(_ state: TransferPopupState) -> some View {
        switch state {
        case .idle(let connected):
            idleView(connected: connected)
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
        case .failed(let name):
            failedView(name: name)
        case .headphonePrompt:
            headphonePromptView()
        case .clipboardReceived(let preview, let isLink):
            clipboardReceivedView(preview: preview, isLink: isLink)
        }
    }

    /// Outer island shape: square top corners (flush with the screen edge /
    /// notch), rounded bottom corners.
    static let islandShape = UnevenRoundedRectangle(
        topLeadingRadius: 0,
        bottomLeadingRadius: 24,
        bottomTrailingRadius: 24,
        topTrailingRadius: 0,
        style: .continuous
    )

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            ZStack {
                // Layer 1: solid black outer shell. Square TOP corners hang
                // flush with the screen edge / notch so it blends seamlessly;
                // only the bottom corners are rounded.
                Self.islandShape
                    .fill(Color.black)

                // Layer 2: aurora — multi-blob drifting gradient
                TransferStateEffects(
                    palette: palette(for: state),
                    intensity: intensity(for: state),
                    notchInset: notchInset,
                    transferProgress: transferProgress
                )
                .clipShape(Self.islandShape)
                .allowsHitTesting(false)

                // Layer 3: inner pill — glass material hosting the content.
                // `.id(stateKind)` + `.transition(...)` so SwiftUI mounts/
                // unmounts per state, firing the morph.
                ZStack {
                    contentForState(state)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(stateKind)
                        .transition(Self.stateTransition)
                }
                .padding(14)
                .glassEffect(
                    isTargeted && isIdleConnected
                        ? .regular.tint(.accentColor).interactive()
                        : .regular.interactive(),
                    in: .rect(cornerRadius: 18, style: .continuous)
                )
                .padding(EdgeInsets(top: 18 + notchInset, leading: 18, bottom: 18, trailing: 18))
            }
            .frame(width: islandWidth, height: islandHeight + notchInset)
            // Black overscan glued to the island's top edge, extending upward
            // off-screen. The island top can sit a hair below the physical
            // screen top (safe-area rounding), leaving a constant sliver of
            // desktop above it that becomes visible when the aurora dims during
            // a state change. This fills that sliver with black. It's part of
            // the island view, so it scales/fades WITH it on hide — no static
            // square left behind.
            .background(alignment: .top) {
                Color.black
                    .frame(width: islandWidth, height: 120)
                    .offset(y: -120)
            }
            .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        }
        // Wyspa ma zawsze czarną skorupę (jak notch), więc jej wnętrze musi
        // renderować się w ciemnym schemacie niezależnie od motywu systemu —
        // inaczej na jasnym motywie glass robi się mleczny, a tekst czarny.
        .environment(\.colorScheme, .dark)
        // No shell "bump" on state change — scaling the whole island (even
        // anchored top) momentarily moved its edges and flashed a sliver of
        // desktop above the notch. The per-state content morph (blur + scale,
        // inside the glass) is the only feedback now, so the shell stays put.
        .offset(y: presentation.isPresented ? 0 : -22)
        .blur(radius: presentation.isPresented ? 0 : 8)
        .opacity(presentation.isPresented ? 1.0 : 0.0)
        .padding(.horizontal, Self.windowPadding)
        .padding(.top, Self.windowPadding)
        // TOP-align (not center) so the island's top edge stays pinned to the
        // screen edge / notch. Centering let any sub-1.0 bump overshoot shrink
        // the island and drop its top, exposing a sliver above it. The extra
        // vertical room now spills to the bottom instead.
        .frame(
            width: islandWidth + Self.windowPadding * 2,
            height: islandHeight + notchInset + Self.windowPadding * 2,
            alignment: .top
        )
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        // Animate only between state KINDS — progress ticks keep the same
        // stateKind, so they don't re-trigger the cross-fade or re-mount.
        .animation(.easeInOut(duration: 0.28), value: stateKind)
        .onAppear {
            // Popup just became visible — kick off the spring-in animation
            // from inside the view (this is the canonical SwiftUI pattern;
            // doing it externally via withAnimation in show() races with the
            // first render and the interpolation gets skipped).
            withAnimation(.spring(response: 0.72, dampingFraction: 0.84)) {
                presentation.isPresented = true
            }
            // Idle auto-hide countdown (also for a clipboard receipt)
            if state.autoHides {
                TransferPopup.shared.resetIdleAutoHideTimer()
            } else {
                TransferPopup.shared.cancelIdleAutoHide()
            }
        }
        .onChange(of: state) { _, newState in
            // Any activity (incoming offer, waiting, transferring, etc.)
            // cancels the idle auto-hide. Returning to idle, or showing a
            // clipboard receipt, (re)starts it — a receipt never holds the island.
            if newState.autoHides {
                if isTargeted {
                    TransferPopup.shared.cancelIdleAutoHide()
                } else {
                    TransferPopup.shared.resetIdleAutoHideTimer()
                }
            } else {
                TransferPopup.shared.cancelIdleAutoHide()
            }
        }
        .onChange(of: isTargeted) { _, targeted in
            // While a file is hovering over the drop zone, suppress the
            // idle auto-hide — the user is clearly trying to drop.
            // When the drag leaves, restart the countdown (if still idle).
            if targeted {
                TransferPopup.shared.cancelIdleAutoHide()
            } else if state.autoHides {
                TransferPopup.shared.resetIdleAutoHideTimer()
            }
        }
        .onChange(of: fileTransferService.fileTransferProgress) { _, new in
            if new >= 1.0 {
                // Let the bar visibly reach 100% before morphing to complete.
                // Small/fast files used to jump to "complete" with the bar
                // stuck at a partial value because progress hit 1.0 and the
                // state flipped in the same instant.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    if fileTransferService.fileTransferProgress >= 1.0 {
                        showComplete = true
                    }
                }
            } else if new == 0 {
                showComplete = false
            }
        }
    }

    static let windowPadding: CGFloat = 40

    /// Transition used between all popup state views. Opacity + blur only —
    /// NO scale. A center scale (even subtle) combined with the bouncy
    /// `airbridgeStateMorph` overshoot read as the whole island "growing and
    /// shrinking", which nudged the top edge and flashed desktop above the
    /// notch. Content now just materializes from blur.
    // Scale is SAFE here because it's on the CONTENT transition (inside the
    // inset, clipped glass pill) — it never touches the island shell or its
    // top edge. The pulsing/top-gap before came from scaling the whole island
    // (entrance 0.62 + bump) plus a bouncy spring that overshot past 1.0. With
    // a non-bouncy `easeInOut` the content just settles up to 1.0 — gives the
    // animation body without any overshoot.
    static let stateTransition: AnyTransition = .opacity
        .combined(with: .blurTransition(radius: 18))
        .combined(with: .scale(scale: 0.94, anchor: .center))

    // MARK: - Subviews per state

    @ViewBuilder
    private func idleView(connected: Bool) -> some View {
        if connected {
            HStack(spacing: 14) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                    .symbolEffect(.pulse, options: .repeating, isActive: !isTargeted)
                    .symbolEffect(.bounce, value: isTargeted)

                Text(L10n.dropFileHere)
                    .font(.ab(.title3, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()
            }
        } else {
            HStack(spacing: 14) {
                Spacer()
                Image(systemName: "wifi.slash")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(L10n.noDeviceConnected)
                    .font(.ab(.title3, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func incomingView(name: String, size: Int64) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.primary)
                .symbolEffect(.bounce, value: name)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.isPL ? "Przychodzący plik" : "Incoming file")
                    .font(.ab(.footnote, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.ab(.callout, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(formatBytes(size))
                    .font(.ab(.footnote))
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
                    .font(.ab(.callout, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(name)
                    .font(.ab(.subheadline))
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
                    .font(.ab(.footnote, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(name)
                    .font(.ab(.callout, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                ProgressView(value: min(max(progress, 0), 1))
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .animation(.easeOut(duration: 0.3), value: progress)

                HStack {
                    Text(speedText)
                        .font(.ab(.footnote, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    Spacer()
                    Text(etaText)
                        .font(.ab(.footnote, weight: .medium))
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
                .font(.ab(.title3, weight: .bold))
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
                    .font(.ab(.headline, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(name)
                    .font(.ab(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
    }

    private func failedView(name: String) -> some View {
        HStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.primary)
                .symbolEffect(.bounce, value: name)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.isPL ? "Przesyłanie nie powiodło się" : "Transfer failed")
                    .font(.ab(.headline, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(name)
                    .font(.ab(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
    }

    /// Ask-first: playback started on this Mac while the phone holds idle
    /// headphones. One click confirms — nothing moves until then.
    private func headphonePromptView() -> some View {
        HStack(spacing: 16) {
            Image(systemName: "headphones")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.primary)
                .symbolEffect(.bounce)

            Text(L10n.isPL ? "Przełączyć słuchawki na Maka?" : "Switch the headphones to this Mac?")
                .font(.ab(.callout, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            HStack(spacing: 8) {
                Button(L10n.isPL ? "Nie teraz" : "Not now") {
                    connectionService.dismissHeadphonePrompt()
                }
                .controlSize(.large)

                Button(L10n.isPL ? "Przełącz" : "Switch") {
                    connectionService.confirmHeadphoneSwitch()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    /// Receipt for content synced from the phone: it is already on the
    /// pasteboard, this only makes that visible. A plain web link also gets
    /// a one-click Open.
    private func clipboardReceivedView(preview: String, isLink: Bool) -> some View {
        HStack(spacing: 16) {
            Image(systemName: isLink ? "link" : "doc.on.clipboard.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.primary)
                .symbolEffect(.bounce, value: preview)

            VStack(alignment: .leading, spacing: 4) {
                Text(isLink ? L10n.clipboardReceivedLinkTitle : L10n.clipboardReceivedTitle)
                    .font(.ab(.footnote, weight: .medium))
                    .foregroundStyle(.secondary)
                if let url = clipboardService.incomingURL {
                    // Domain leads — it is what tells you where the link goes.
                    // The path/query is a supporting detail, not the headline.
                    Text(ClipboardService.linkHost(url))
                        .font(.ab(.callout, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let detail = ClipboardService.linkDetail(url) {
                        Text(detail)
                            .font(.ab(.footnote))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                } else {
                    Text(preview)
                        .font(.ab(.callout, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            if isLink {
                Button(L10n.clipboardOpenLink) {
                    clipboardService.openIncomingURL()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Button {
                dismissClipboardReceipt()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)
            .help(L10n.close)
            .accessibilityLabel(L10n.close)
        }
        // The whole receipt is a target: a click anywhere puts it away, the
        // panel is non-activating so Escape only works while the app is frontmost.
        .contentShape(Rectangle())
        .onTapGesture { dismissClipboardReceipt() }
    }

    private func dismissClipboardReceipt() {
        clipboardService.dismissIncomingPreview()
        TransferPopup.shared.hide(delay: 0)
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
        } else if eta > 0 {
            return "\(label): \(eta) s"
        } else if fileTransferService.fileTransferProgress > 0 && fileTransferService.fileTransferProgress < 1.0 {
            return L10n.isPL ? "\(label): obliczanie…" : "\(label): calculating…"
        }
        return " "
    }

    private func formatBytes(_ size: Int64) -> String {
        if size > 1024 * 1024 { return String(format: "%.1f MB", Double(size) / (1024.0 * 1024.0)) }
        if size > 1024 { return String(format: "%.0f KB", Double(size) / 1024.0) }
        return "\(size) B"
    }
}

// MARK: - TransferStateEffects
// One radial glow anchored at the BOTTOM edge of the pill, its color
// driven by the popup's state tint. Uses a native SwiftUI `Rectangle`
// with `RadialGradient` fill (NOT `Canvas`) so that SwiftUI's built-in
// animation system can smoothly interpolate the gradient's colors when
// the popup state changes — this is what makes the color transitions
// actually smooth instead of hard-cutting. Canvas is a black box to
// SwiftUI's animation engine; native shape fills are not.
//
// Continuous drift and breathing pulse come from two independent
// @State doubles animated via `withAnimation(...repeatForever...)`,
// which coexist with the state-driven color/intensity animation.

// Three-color palette for the aurora-style background blobs. Each state
// of the popup gets a different palette so the gradient color smoothly
// shifts between accent (blue/cyan/indigo), complete (green/mint/teal),
// and rejected (red/orange/pink) — and the SHAPE of the gradient stays
// alive at all times via independently-drifting blobs.
struct GradientPalette: Equatable {
    let primary: Color
    let secondary: Color
    let tertiary: Color
}

private struct TransferStateEffects: View {
    let palette: GradientPalette
    let intensity: Double
    let notchInset: CGFloat
    let transferProgress: Double

    @State private var revealed: Bool = false
    @State private var animPrimary: Color = .blue
    @State private var animSecondary: Color = .cyan
    @State private var animTertiary: Color = .purple
    @State private var animIntensity: Double = 0.5
    /// Smoothly-animated mirror of transferProgress. All energy
    /// parameters (speed, amplitude, pulse) read this so idle↔transfer
    /// transitions are seamless — same blobs, different energy.
    @State private var animTP: Double = 0

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let tp = animTP
            let twoPi = 2.0 * .pi

            // ── Ambient energy: constant and calm. Progress does NOT speed
            // the drift up (fast wobble + high-rate pulsing read as flicker);
            // instead progress drives a soft left-to-right light fill below.
            let st = t * 0.55                        // slow, constant drift
            let yAmp = 1.0
            let breathe = 1.0 + sin(t * twoPi * 0.35) * 0.08   // gentle 0.35 Hz
            let glow = animIntensity * breathe
            let blurR = 22.0

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let topMaskCutoff = max(0.04, (notchInset + 12) / h)

                ZStack {
                    // Three wide, slow glows anchored at the bottom — ambient
                    // light, not visible moving shapes.
                    blob(color: animPrimary, opacity: glow,
                         cx: 0.25 + sin(st * twoPi / 9.0) * 0.10,
                         cy: 0.98 + cos(st * twoPi / 11.0) * 0.06 * yAmp,
                         radius: w * 0.34)

                    blob(color: animSecondary, opacity: glow,
                         cx: 0.75 + cos(st * twoPi / 12.0) * 0.10,
                         cy: 1.02 + sin(st * twoPi / 10.0) * 0.05 * yAmp,
                         radius: w * 0.36)

                    blob(color: animTertiary, opacity: glow * 0.85,
                         cx: 0.50 + sin(st * twoPi / 14.0) * 0.12,
                         cy: 0.95 + cos(st * twoPi / 9.5) * 0.07 * yAmp,
                         radius: w * 0.30)

                    // Progress as light: a soft fill that grows left→right with
                    // the transfer, so "how far along" is legible at a glance.
                    if tp > 0.005 {
                        RoundedRectangle(cornerRadius: h * 0.5, style: .continuous)
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: animPrimary.opacity(glow * 0.85), location: 0),
                                        .init(color: animPrimary.opacity(glow * 0.55), location: 0.8),
                                        .init(color: .clear, location: 1.0),
                                    ],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: max(w * 0.12, w * tp), height: h * 0.5)
                            .position(x: max(w * 0.12, w * tp) / 2, y: h * 0.95)
                    }
                }
                .compositingGroup()
                .blur(radius: blurR)
                .scaleEffect(x: 1.0, y: revealed ? 1.0 : 0.0, anchor: .bottom)
                .opacity(revealed ? 1.0 : 0.0)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: topMaskCutoff),
                            .init(color: .black.opacity(0.3), location: topMaskCutoff + 0.25),
                            .init(color: .black.opacity(0.7), location: 0.6),
                            .init(color: .black, location: 0.75),
                            .init(color: .black, location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .onAppear {
            animPrimary = palette.primary
            animSecondary = palette.secondary
            animTertiary = palette.tertiary
            animIntensity = intensity
            animTP = transferProgress
            withAnimation(.spring(response: 0.7, dampingFraction: 0.78).delay(0.08)) {
                revealed = true
            }
        }
        .onChange(of: palette.primary) { _, new in
            withAnimation(.easeInOut(duration: 0.7)) { animPrimary = new }
        }
        .onChange(of: palette.secondary) { _, new in
            withAnimation(.easeInOut(duration: 0.7)) { animSecondary = new }
        }
        .onChange(of: palette.tertiary) { _, new in
            withAnimation(.easeInOut(duration: 0.7)) { animTertiary = new }
        }
        .onChange(of: intensity) { _, new in
            withAnimation(.easeInOut(duration: 0.6)) { animIntensity = new }
        }
        .onChange(of: transferProgress) { _, new in
            withAnimation(.easeInOut(duration: 0.5)) { animTP = new }
        }
    }

    private func blob(
        color: Color, opacity: Double,
        cx: Double, cy: Double, radius: CGFloat
    ) -> some View {
        RadialGradient(
            colors: [color.opacity(opacity), .clear],
            center: UnitPoint(x: cx, y: cy),
            startRadius: 0,
            endRadius: radius
        )
        .blendMode(.plusLighter)
    }
}

// MARK: - TransferPopup singleton
// Unified popup — handles both the Quick Drop (idle) drop zone and all
// in-flight transfer states in a single NSWindow. A `configure()` call at
// app startup wires both services so `show()`/`toggle()`/`hide()` can be
// called from anywhere without passing services each time.

@MainActor
final class TransferPopup {

    static let shared = TransferPopup()

    private var panel: NSWindow?
    private var isVisible = false
    private weak var connectionService: ConnectionService?
    private weak var fileTransferService: FileTransferService?
    private weak var clipboardService: ClipboardService?
    private var idleAutoHideTimer: Timer?
    private let idleAutoHideDelay: TimeInterval = 5.0
    private var escapeMonitor: Any?
    /// Drives the SwiftUI scale+opacity present/dismiss animation. Lives on
    /// `TransferPopup` so it persists across show/hide; the same instance
    /// is handed to the `TransferPopupView` so the spring animation runs
    /// inside SwiftUI (anchored at top of pill — window stays put).
    private let presentation = TransferPopupPresentation()
    // animationTimer is gone — replaced by SwiftUI's withAnimation+spring
    // running inside the popup view itself.

    private init() {}

    var isShowing: Bool { isVisible }

    func configure(
        connectionService: ConnectionService,
        fileTransferService: FileTransferService,
        clipboardService: ClipboardService
    ) {
        self.connectionService = connectionService
        self.fileTransferService = fileTransferService
        self.clipboardService = clipboardService
    }

    /// Toggle for the global shortcut — shows in idle state, hides if visible.
    func toggle() {
        if isVisible {
            hide(delay: 0)
        } else {
            show()
        }
    }

    /// Show the popup. Safe to call repeatedly — subsequent calls while
    /// already visible are a no-op (SwiftUI handles state transitions
    /// internally from the observed services).
    func show() {
        if isVisible { return }
        guard let connectionService, let fileTransferService, let clipboardService else { return }
        isVisible = true

        guard let screen = NSScreen.main else { return }
        let notchInset = screen.notchInset
        let (x, y, width, height) = computeLayout(screen: screen)

        let view = TransferPopupView(
            connectionService: connectionService,
            fileTransferService: fileTransferService,
            clipboardService: clipboardService,
            notchInset: notchInset,
            presentation: presentation
        )
        let hostingView = NSHostingView(rootView: view)

        // A non-activating panel: clicking its buttons (Accept/Reject) must NOT
        // activate the app, otherwise the SwiftUI WindowGroup restores the main
        // window on top. The whole flow stays inside the popup.
        let window = NSPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = true
        window.contentView = hostingView
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.popUpMenuWindow)))
        window.hasShadow = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.acceptsMouseMovedEvents = true
        window.ignoresMouseEvents = false

        // Register drag types on the window's content view so drops land here
        hostingView.registerForDraggedTypes([.fileURL])

        // The window goes up immediately at full target frame (no NSWindow
        // animation). The visual appear animation happens entirely inside
        // SwiftUI via `presentation.isPresented` driving scale+opacity with
        // anchor `.top` — so the popup grows downward from the notch and
        // never detaches from the top edge of the screen.
        // Reset to false so the view mounts in the "before" state and the
        // .onAppear withAnimation can interpolate up to true.
        presentation.isPresented = false
        window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        window.alphaValue = 1
        window.orderFrontRegardless()
        window.makeKey()

        self.panel = window
        // The view's .onAppear will trigger withAnimation { isPresented = true }
        // — that's where the spring animation actually fires.

        // Escape key to dismiss from idle state
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.hide(delay: 0)
                return nil
            }
            return event
        }

        // Auto-hide when idle for too long
        resetIdleAutoHideTimer()
    }

    /// Reset the idle auto-hide countdown. Called while the popup is in the
    /// idle state; transfer states suppress auto-hide via cancelIdleAutoHide().
    func resetIdleAutoHideTimer() {
        idleAutoHideTimer?.invalidate()
        idleAutoHideTimer = Timer.scheduledTimer(withTimeInterval: idleAutoHideDelay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.hide(delay: 0)
            }
        }
    }

    func cancelIdleAutoHide() {
        idleAutoHideTimer?.invalidate()
        idleAutoHideTimer = nil
    }

    func hide(delay: TimeInterval = 2.5) {
        guard isVisible, panel != nil else { return }

        idleAutoHideTimer?.invalidate()
        idleAutoHideTimer = nil

        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let panel = self.panel else { return }
            // Hide animation runs entirely in SwiftUI: scale + opacity reverse
            // back to 0 with a spring (slight anticipation via the spring's
            // overshoot in the opposite direction). On completion the window
            // is orderOut'd. The window itself never moves.
            withAnimation(.spring(response: 0.52, dampingFraction: 0.88)) {
                self.presentation.isPresented = false
            } completion: {
                panel.orderOut(nil)
                self.panel = nil
                self.isVisible = false
                // The receipt lives exactly as long as the popup that shows
                // it — otherwise a stale preview would re-appear the next
                // time the popup opens for something else.
                self.clipboardService?.dismissIncomingPreview()
            }
        }
    }

    private func computeLayout(screen: NSScreen) -> (x: Double, y: Double, width: Double, height: Double) {
        let defaults = UserDefaults.standard
        let offsetFromTop = defaults.object(forKey: "islandOffsetY") as? Double ?? 0
        let islandWidth = defaults.object(forKey: "islandWidth") as? Double ?? 560
        let islandHeight = defaults.object(forKey: "islandHeight") as? Double ?? 130

        // Extend the visible pill height by the notch inset so content can be
        // pushed below the notch cutout. The top of the pill sits under the
        // notch (invisible) and the pill visually "grows out of" the notch.
        let notchInset = screen.notchInset
        let pillHeight = islandHeight + notchInset

        // Window is larger than the visible glass pill so the drop shadow
        // can render without being clipped at the window edges. The SwiftUI
        // body pads by `windowPadding` on each side to center the pill.
        let padding = TransferPopupView.windowPadding
        let width = islandWidth + padding * 2
        let height = pillHeight + padding * 2

        let screenFrame = screen.frame
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - offsetFromTop - pillHeight - padding

        return (x, y, width, height)
    }
}
