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
    /// True while the island is on its way out. The geometry differs from
    /// arrival: it is sucked into the notch (genie) rather than shrinking back
    /// the way it came.
    var isExiting: Bool = false
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
    /// Rejection/failure shake trigger. The motion starts from 0 (no jump on
    /// the first frame): a fast push out, then an underdamped spring back to
    /// centre that does the oscillating and the decay.
    @State private var shakeTrigger = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The island morphs: each state gets its own size, the settings hold
    /// the fully expanded one. Compact for a notice, full for anything with
    /// buttons or a progress bar. The window is always laid out for the
    /// expanded size; the shell animates inside it, pinned to the top.
    private func size(for state: TransferPopupState) -> CGSize {
        let w = islandWidth, h = islandHeight
        switch state {
        case .idle(let connected):
            return connected ? CGSize(width: w * 0.70, height: h * 0.86) : CGSize(width: w * 0.66, height: h * 0.80)
        case .incoming, .transferring:
            return CGSize(width: w, height: h)
        case .waiting:
            return CGSize(width: w * 0.88, height: h * 0.90)
        case .complete:
            return CGSize(width: w * 0.66, height: h * 0.80)
        case .rejected, .failed:
            return CGSize(width: w * 0.88, height: h * 0.90)
        case .headphonePrompt:
            return CGSize(width: w, height: h * 0.90)
        case .clipboardReceived:
            return CGSize(width: w * 0.94, height: h)
        }
    }

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
        let islandSize = size(for: state)
        GlassEffectContainer(spacing: 0) {
            ZStack {
                // Layer 1: solid black outer shell. Square TOP corners hang
                // flush with the screen edge / notch so it blends seamlessly;
                // only the bottom corners are rounded.
                Self.islandShape
                    .fill(Color.black)

                // Layer 2: aurora — drifting light at the bottom, and the
                // shell's edge picking that light up (plus the progress comet).
                TransferStateEffects(
                    palette: palette(for: state),
                    intensity: intensity(for: state),
                    notchInset: notchInset,
                    transferProgress: transferProgress,
                    reduceMotion: reduceMotion
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
                        .transition(reduceMotion ? .opacity : Self.stateTransition)
                }
                .padding(12)
                // The pill clips its content: while the shell shrinks, the
                // leaving content stays inside the glass instead of spilling
                // past its edge.
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
                .glassEffect(
                    isTargeted && isIdleConnected
                        ? .regular.tint(.accentColor).interactive()
                        : .regular.interactive(),
                    in: .rect(cornerRadius: 18, style: .continuous)
                )
                .padding(EdgeInsets(top: 16 + notchInset, leading: 16, bottom: 16, trailing: 16))
            }
            // The shell morphs between the per-state sizes with a spring
            // (interruptible: a state change mid-morph retargets, no restart).
            .frame(width: islandSize.width, height: islandSize.height + notchInset)
            // Black overscan glued to the island's top edge, extending upward
            // off-screen, so no sliver of desktop ever shows above the shell.
            // It scales/fades WITH the island on hide.
            .background(alignment: .top) {
                Color.black
                    .frame(width: islandSize.width, height: 120)
                    .offset(y: -120)
            }
            .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        }
        // Rejection / failure shake: sideways only. No rotation — Liquid
        // Glass renders mirrored artefacts when rotated, and a tilt pushed
        // the shell past the panel's edge where it got clipped. The swing is
        // sized to stay inside the panel's side padding.
        .keyframeAnimator(initialValue: CGFloat(0), trigger: shakeTrigger) { content, x in
            content.offset(x: reduceMotion ? 0 : x)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(14, duration: 0.06)
                // The keyframe must outlast the spring's settle, or the last
                // swing is cut off mid-air: ~1 s for this damping.
                SpringKeyframe(0, duration: 1.1, spring: Spring(response: 0.4, dampingRatio: 0.26))
            }
        }
        // Wyspa ma zawsze czarną skorupę (jak notch), więc jej wnętrze musi
        // renderować się w ciemnym schemacie niezależnie od motywu systemu —
        // inaczej na jasnym motywie glass robi się mleczny, a tekst czarny.
        .environment(\.colorScheme, .dark)
        // Entrance: the shell grows out of the notch — scale anchored at the
        // TOP, so the bounce lands on the bottom and the sides while the top
        // edge never moves (no gap above it). No vertical offset here on
        // purpose: an offset overshoot would pull the top edge off the screen
        // edge. Blur and opacity ride along.
        // Two springs, two axes: height bounces more and settles later than
        // width, so the shell lands like something with give in it instead
        // of a uniform zoom. Opacity and blur clear quickly and without
        // bounce, so they never smear the overshoot.
        .modifier(IslandEntrance(presented: presentation.isPresented || reduceMotion, exiting: presentation.isExiting && !reduceMotion))
        .opacity(presentation.isPresented ? 1.0 : 0.0)
        // Arrival: opacity clears fast. Exit: it holds while the shell is being
        // drawn into the notch and only goes at the very end (genie).
        .animation(
            reduceMotion ? .easeOut(duration: 0.2)
                : (presentation.isExiting ? .easeIn(duration: 0.34).delay(0.06) : .easeOut(duration: 0.22)),
            value: presentation.isPresented
        )
        .padding(.horizontal, Self.windowPadding)
        .padding(.top, Self.windowPadding)
        // TOP-align (not center) so the island's top edge stays pinned to the
        // screen edge / notch; the extra room spills to the bottom and sides.
        .frame(
            width: islandWidth + Self.windowPadding * 2,
            height: islandHeight + notchInset + Self.windowPadding * 2,
            alignment: .top
        )
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        // The one animation for a state change: shell size, content swap.
        // Keyed on the state KIND so progress ticks never restart it.
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.44, dampingFraction: 0.84), value: stateKind)
        .onAppear {
            // Popup just became visible — kick off the spring-in animation
            // from inside the view (this is the canonical SwiftUI pattern;
            // doing it externally via withAnimation in show() races with the
            // first render and the interpolation gets skipped).
            // The per-property animations live on the modifiers
            // (IslandEntrance, opacity); this just flips the flag.
            presentation.isPresented = true
            // Idle auto-hide countdown (also for a clipboard receipt)
            if state.autoHides {
                TransferPopup.shared.resetIdleAutoHideTimer()
            } else {
                TransferPopup.shared.cancelIdleAutoHide()
            }
        }
        .onChange(of: state) { _, newState in
            switch newState {
            case .rejected, .failed:
                shakeTrigger += 1
            default: break
            }
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
                // Just long enough for the bar to land on 100% (its own
                // animation is 0.2 s); any longer reads as a stall before the
                // dim of the swap.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 220_000_000)
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

    /// Content swap between states. Asymmetric on purpose: the new content
    /// materialises with a soft spring (blur + a hair of scale, inside the
    /// clipped glass pill so the shell never bumps), the old one leaves fast.
    /// Slow where the user reads, fast where the system moves on.
    /// One animation drives both the shell morph and this swap (see the
    /// `.animation(value: stateKind)` on the body): per-transition animations
    /// left both sides frozen mid-flight when states changed in quick
    /// succession (offer → transfer), so the asymmetry lives in the values.
    /// The block itself only crossfades through a light blur: the visible
    /// motion belongs to its parts (StaggerIn), so it must not compete.
    static let stateTransition: AnyTransition = .asymmetric(
        insertion: .opacity.combined(with: .blurTransition(radius: 8)),
        removal: .opacity
            .combined(with: .blurTransition(radius: 6))
            .combined(with: .scale(scale: 0.97, anchor: .center))
    )

    // MARK: - Subviews per state
    //
    // Every state is the same row: a state glyph in a fixed 40 pt column, a
    // text stack, and the controls pinned to the trailing edge as round icon
    // buttons (✓ accept / confirm, ✕ reject / cancel / close, ↗ open). Same
    // places in every state, so the eye never has to search.

    @ViewBuilder
    private func islandRow<Glyph: View, Texts: View, Controls: View>(
        @ViewBuilder glyph: () -> Glyph,
        @ViewBuilder texts: () -> Texts,
        @ViewBuilder controls: () -> Controls
    ) -> some View {
        HStack(spacing: 16) {
            glyph()
                .frame(width: 40, alignment: .center)
                .staggerIn(0)
            texts()
                .staggerIn(1)
            Spacer(minLength: 12)
            HStack(spacing: 10) { controls() }
                .staggerIn(2)
        }
    }

    private func glyph(_ systemName: String, size: CGFloat = 28, color: Color = .primary) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(color)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.ab(.footnote, weight: .medium)).foregroundStyle(.secondary)
    }

    private func headline(_ text: String, lines: Int = 1) -> some View {
        Text(text)
            .font(.ab(.callout, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(lines)
            .truncationMode(.middle)
    }

    @ViewBuilder
    private func idleView(connected: Bool) -> some View {
        if connected {
            islandRow {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                    .symbolEffect(.pulse, options: .repeating, isActive: !isTargeted)
                    .symbolEffect(.bounce, value: isTargeted)
            } texts: {
                Text(L10n.dropFileHere)
                    .font(.ab(.title3, weight: .semibold))
                    .foregroundStyle(.primary)
            } controls: {
                // Put the drop zone away now instead of waiting out the countdown.
                IslandIconButton(systemName: "xmark", label: L10n.close) {
                    TransferPopup.shared.hide(delay: 0)
                }
            }
        } else {
            islandRow {
                glyph("wifi.slash", color: .secondary)
            } texts: {
                Text(L10n.noDeviceConnected)
                    .font(.ab(.title3, weight: .semibold))
                    .foregroundStyle(.secondary)
            } controls: {
                IslandIconButton(systemName: "xmark", label: L10n.close) {
                    TransferPopup.shared.hide(delay: 0)
                }
            }
        }
    }

    private func incomingView(name: String, size: Int64) -> some View {
        islandRow {
            glyph("arrow.down.doc.fill").symbolEffect(.bounce, value: name)
        } texts: {
            VStack(alignment: .leading, spacing: 3) {
                caption(L10n.isPL ? "Przychodzący plik" : "Incoming file")
                headline(name)
                Text(formatBytes(size))
                    .font(.ab(.footnote))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        } controls: {
            IslandIconButton(systemName: "xmark", label: L10n.isPL ? "Odrzuć" : "Reject") {
                fileTransferService.rejectIncomingOffer()
            }
            IslandIconButton(systemName: "checkmark", label: L10n.isPL ? "Akceptuj" : "Accept", prominent: true) {
                fileTransferService.acceptIncomingOffer()
            }
        }
    }

    private func waitingView(name: String) -> some View {
        islandRow {
            glyph("hourglass").symbolEffect(.pulse, options: .repeating)
        } texts: {
            VStack(alignment: .leading, spacing: 3) {
                caption(L10n.isPL ? "Czekam na akceptację…" : "Waiting for acceptance…")
                headline(name)
            }
        } controls: {
            IslandIconButton(systemName: "xmark", label: L10n.isPL ? "Anuluj" : "Cancel") {
                fileTransferService.cancelPendingTransfer()
            }
        }
    }

    private func transferringView(name: String, progress: Double, isReceiving: Bool) -> some View {
        // No progress bar: the edge comet and the aurora fill already show how
        // far along it is; the number gives the precision.
        islandRow {
            glyph(isReceiving ? "arrow.down.circle.fill" : "arrow.up.circle.fill", size: 26)
                .symbolEffect(.variableColor, options: .repeating)
        } texts: {
            VStack(alignment: .leading, spacing: 3) {
                caption(isReceiving ? (L10n.isPL ? "Odbieram" : "Receiving") : (L10n.isPL ? "Wysyłam" : "Sending"))
                headline(name)
                HStack(spacing: 12) {
                    Text(speedText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(etaText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(.ab(.footnote, weight: .medium))
                .foregroundStyle(.secondary)
            }
        } controls: {
            Text("\(Int(progress * 100))%")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(width: 76, alignment: .trailing)
                .contentTransition(.numericText())
        }
    }

    private func completeView(isReceiving: Bool) -> some View {
        islandRow {
            glyph("checkmark.circle.fill").symbolEffect(.bounce, value: isReceiving)
        } texts: {
            VStack(alignment: .leading, spacing: 3) {
                Text(isReceiving
                    ? (L10n.isPL ? "Plik odebrany" : "File received")
                    : (L10n.isPL ? "Plik wysłany" : "File sent"))
                    .font(.ab(.title3, weight: .bold))
                    .foregroundStyle(.primary)
                if isReceiving, let url = fileTransferService.lastReceivedFileURL {
                    Text(url.lastPathComponent)
                        .font(.ab(.footnote))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        } controls: {
            // Open the file that just arrived (its default app, or Finder when
            // nothing on this Mac claims the type). Holds the island while shown.
            if isReceiving, fileTransferService.lastReceivedFileURL != nil {
                IslandIconButton(systemName: "arrow.up.forward.app", label: L10n.isPL ? "Otwórz" : "Open", prominent: true) {
                    fileTransferService.openLastReceivedFile()
                    TransferPopup.shared.hide(delay: 0)
                }
            }
        }
    }

    private func rejectedView(name: String) -> some View {
        islandRow {
            glyph("xmark.circle.fill").symbolEffect(.bounce, value: name)
        } texts: {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.isPL ? "Przesyłanie odrzucone" : "Transfer rejected")
                    .font(.ab(.headline, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(name).font(.ab(.subheadline)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        } controls: {
            EmptyView()
        }
    }

    private func failedView(name: String) -> some View {
        islandRow {
            glyph("exclamationmark.triangle.fill").symbolEffect(.bounce, value: name)
        } texts: {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.isPL ? "Przesyłanie nie powiodło się" : "Transfer failed")
                    .font(.ab(.headline, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(name).font(.ab(.subheadline)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        } controls: {
            EmptyView()
        }
    }

    /// Ask-first: playback started on this Mac while the phone holds idle
    /// headphones. One click confirms — nothing moves until then.
    private func headphonePromptView() -> some View {
        islandRow {
            glyph("headphones").symbolEffect(.bounce)
        } texts: {
            VStack(alignment: .leading, spacing: 3) {
                caption(L10n.isPL ? "Słuchawki" : "Headphones")
                headline(L10n.isPL ? "Przełączyć na Maka?" : "Switch to this Mac?")
            }
        } controls: {
            IslandIconButton(systemName: "xmark", label: L10n.isPL ? "Nie teraz" : "Not now") {
                connectionService.dismissHeadphonePrompt()
            }
            IslandIconButton(systemName: "checkmark", label: L10n.isPL ? "Przełącz" : "Switch", prominent: true) {
                connectionService.confirmHeadphoneSwitch()
            }
        }
    }

    /// Receipt for content synced from the phone: it is already on the
    /// pasteboard, this only makes that visible (so no "copy" — there is
    /// nothing left to copy). A plain web link also gets a one-click Open.
    private func clipboardReceivedView(preview: String, isLink: Bool) -> some View {
        islandRow {
            glyph(isLink ? "link" : "doc.on.clipboard.fill").symbolEffect(.bounce, value: preview)
        } texts: {
            VStack(alignment: .leading, spacing: 3) {
                caption(isLink ? L10n.clipboardReceivedLinkTitle : L10n.clipboardReceivedTitle)
                if let url = clipboardService.incomingURL {
                    // Domain leads — it is what tells you where the link goes.
                    headline(ClipboardService.linkHost(url))
                    if let detail = ClipboardService.linkDetail(url) {
                        Text(detail).font(.ab(.footnote)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    }
                } else {
                    headline(preview, lines: 2)
                }
            }
        } controls: {
            IslandIconButton(systemName: "xmark", label: L10n.close) {
                dismissClipboardReceipt()
            }
            if isLink {
                IslandIconButton(systemName: "arrow.up.right", label: L10n.clipboardOpenLink, prominent: true) {
                    clipboardService.openIncomingURL()
                }
            }
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

// MARK: - IslandIconButton
// The island's one control: a 36 pt round glass button with a symbol. The
// prominent one (accept / confirm / open) is tinted with the accent; the
// plain one (reject / cancel / close) is clear glass. Press feedback is a
// 0.94 scale, 120 ms — the interface heard you.

private struct IslandIconButton: View {
    let systemName: String
    let label: String
    var prominent: Bool = false
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(prominent ? .regular.tint(Color.accentColor).interactive() : .regular.interactive(), in: .circle)
        .scaleEffect(pressed ? 0.94 : 1)
        .animation(.easeOut(duration: 0.12), value: pressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - StaggerIn
// Parts of a state's content arrive one after another (icon, then text,
// then controls), each rising a few points out of a light blur, so a state
// change reads as one choreographed moment rather than a block crossfade.
// Instant under reduced motion.

private struct StaggerIn: ViewModifier {
    /// 0 = the lead (icon): pops in from 60% with a bounce.
    /// 1 = text: rises 14 pt with a hair of scale.
    /// 2 = controls: rise 10 pt, settle last.
    let order: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var delay: Double { 0.05 + Double(order) * 0.06 }
    private var startScale: CGFloat { order == 0 ? 0.6 : 0.94 }
    private var startOffset: CGFloat { order == 0 ? 0 : (order == 1 ? 14 : 10) }
    private var spring: Animation {
        order == 0 ? .spring(duration: 0.5, bounce: 0.35) : .spring(duration: 0.45, bounce: 0.18)
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : startScale)
            .offset(y: shown ? 0 : startOffset)
            .blur(radius: shown ? 0 : 6)
            .onAppear {
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(spring.delay(delay)) { shown = true }
                }
            }
    }
}

private extension View {
    func staggerIn(_ order: Int) -> some View {
        modifier(StaggerIn(order: order))
    }
}

// MARK: - IslandEntrance
// Entrance/exit geometry of the shell. Scale anchored at the TOP so the top
// edge never leaves the screen edge: all the overshoot lands on the bottom
// and the sides. Height and width get their own springs (different bounce,
// different settle) so the arrival has give; leaving uses no bounce.

private struct IslandEntrance: ViewModifier {
    let presented: Bool
    /// Genie exit: the shell is drawn into the notch — width collapses to
    /// about the notch's width first, height follows, all anchored at the
    /// top centre so it converges on the notch itself.
    let exiting: Bool

    private var hiddenScaleX: CGFloat { exiting ? 0.34 : 0.88 }
    private var hiddenScaleY: CGFloat { exiting ? 0.10 : 0.62 }

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 1.0, y: presented ? 1.0 : hiddenScaleY, anchor: .top)
            .animation(
                presented ? .spring(duration: 0.62, bounce: 0.38)
                    : (exiting ? .spring(duration: 0.42, bounce: 0) : .spring(duration: 0.3, bounce: 0)),
                value: presented
            )
            .scaleEffect(x: presented ? 1.0 : hiddenScaleX, y: 1.0, anchor: .top)
            .animation(
                presented ? .spring(duration: 0.5, bounce: 0.22)
                    : (exiting ? .spring(duration: 0.32, bounce: 0) : .spring(duration: 0.3, bounce: 0)),
                value: presented
            )
            .blur(radius: presented ? 0 : (exiting ? 14 : 10))
            .animation(presented ? .easeOut(duration: 0.22) : .easeIn(duration: 0.3), value: presented)
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
    var reduceMotion: Bool = false

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
            let st = reduceMotion ? 0.0 : t * 0.55   // slow, constant drift (none under reduced motion)
            let yAmp = 1.0
            let breathe = reduceMotion ? 1.0 : 1.0 + sin(t * twoPi * 0.35) * 0.08   // gentle 0.35 Hz
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
                .overlay {
                    edgeLight(width: w, height: h, glow: glow, progress: tp)
                        .opacity(revealed ? 1 : 0)
                }
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

    /// The shell's edge, lit by the aurora: a faint hairline all round, the
    /// palette colour strongest along the bottom where the light pools, a soft
    /// bloom behind it, and during a transfer a bright comet on the bottom
    /// edge sitting exactly where the progress fill ends.
    private func edgeLight(width w: CGFloat, height h: CGFloat, glow: Double, progress tp: Double) -> some View {
        let shape = TransferPopupView.islandShape
        let bottomHalf = LinearGradient(
            stops: [.init(color: .clear, location: 0.35), .init(color: .black, location: 0.8)],
            startPoint: .top, endPoint: .bottom
        )
        return ZStack {
            // Hairline: the shell has an edge even with the light off.
            shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1)

            // Colour picked up from the light below.
            shape.strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.15),
                        .init(color: animSecondary.opacity(0.45 * glow), location: 0.6),
                        .init(color: animPrimary.opacity(0.95 * glow), location: 1.0),
                    ],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: 1.5
            )

            // Bloom of that edge, bottom only.
            shape.strokeBorder(animPrimary.opacity(0.7 * glow), lineWidth: 3)
                .blur(radius: 7)
                .mask(bottomHalf)

            // Progress comet: a bright head on the bottom edge at the fill's end.
            if tp > 0.005 {
                let head = min(max(tp, 0.06), 0.98)
                let comet = LinearGradient(
                    stops: [
                        .init(color: .clear, location: max(0, head - 0.16)),
                        .init(color: animSecondary.opacity(0.9), location: max(0, head - 0.03)),
                        .init(color: .white.opacity(0.95), location: head),
                        .init(color: .clear, location: min(1, head + 0.02)),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                shape.strokeBorder(comet, lineWidth: 2.5)
                    .mask(bottomHalf)
                shape.strokeBorder(comet, lineWidth: 6)
                    .blur(radius: 6)
                    .mask(bottomHalf)
            }
        }
        .frame(width: w, height: h)
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
        presentation.isExiting = false
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
            // Exit is faster than entrance: the system is moving on, not arriving.
            // Exit: the modifiers' own animations key on this flag (scale
            // springs without bounce on the way out, opacity eases out).
            // Genie: the modifiers read `isExiting` to pick the into-the-notch
            // geometry and their own timings; this transaction just flips it.
            self.presentation.isExiting = true
            withAnimation(.spring(duration: 0.42, bounce: 0)) {
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
