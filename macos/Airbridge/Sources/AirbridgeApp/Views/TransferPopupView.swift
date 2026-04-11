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
// Custom `AnyTransition` that applies a SwiftUI `.blur(radius:)` modifier
// during insertion/removal. Used to make state transitions in the popup
// feel fluid and liquid-glass-y instead of hard-cutting.

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
    /// Top inset for the notch on MacBook Pro 14"/16". Content is pushed down
    /// by this amount so it sits below the notch cutout.
    let notchInset: CGFloat
    /// Drives the appear/disappear scale+opacity animation. Mutated by
    /// TransferPopup (the window manager) inside `withAnimation` blocks.
    let presentation: TransferPopupPresentation
    @AppStorage("islandWidth") private var islandWidth: Double = 560
    @AppStorage("islandHeight") private var islandHeight: Double = 130

    @Namespace private var glassNS
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
        // Nothing active → idle drop zone
        return .idle(connected: connectionService.isConnected)
    }

    private func tint(for state: TransferPopupState) -> Color {
        switch state {
        case .idle: return .accentColor
        case .incoming, .waiting, .transferring: return .accentColor
        case .complete: return .green
        case .rejected: return .red
        }
    }

    /// Three-color palette per state for the aurora-style background.
    /// SwiftUI interpolates each color independently when the state
    /// changes, so transitions blend the three colors smoothly.
    private func palette(for state: TransferPopupState) -> GradientPalette {
        switch state {
        case .idle, .incoming, .waiting, .transferring:
            return GradientPalette(primary: .blue, secondary: .cyan, tertiary: .purple)
        case .complete:
            return GradientPalette(primary: .green, secondary: .mint, tertiary: .teal)
        case .rejected:
            return GradientPalette(primary: .red, secondary: .orange, tertiary: .pink)
        }
    }

    private func intensity(for state: TransferPopupState) -> Double {
        switch state {
        case .idle(let connected): return connected ? (isTargeted ? 0.95 : 0.55) : 0.0
        case .incoming: return 0.75
        case .waiting: return 0.6
        case .transferring: return 0.85
        case .complete: return 0.8
        case .rejected: return 0.7
        }
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
        }
    }

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            ZStack {
                // Layer 1: solid black outer pill — blends with the notch
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black)

                // Layer 2: aurora — multi-blob drifting gradient
                TransferStateEffects(
                    palette: palette(for: state),
                    intensity: intensity(for: state),
                    notchInset: notchInset
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .allowsHitTesting(false)

                // Layer 3: inner pill — glass material + content together.
                // The OUTER ZStack is stable (no identity change) and is what
                // hosts the glass material. Inside it, contentForState gets
                // `.id(stateKind)` + `.transition(...)` so SwiftUI properly
                // mounts/unmounts the content per state, firing transitions.
                // This way the glass pill stays put visually, while text and
                // buttons inside it morph cleanly on every state change.
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
            .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        }
        .padding(Self.windowPadding)
        .frame(
            width: islandWidth + Self.windowPadding * 2,
            height: islandHeight + notchInset + Self.windowPadding * 2
        )
        // Apply scale + opacity OUTSIDE the GlassEffectContainer so the
        // glass material AND its content (text/icons/buttons) all scale
        // together as one unit. Putting it inside causes the glass to
        // render in a separate layer that the text doesn't follow.
        .scaleEffect(presentation.isPresented ? 1.0 : 0.55, anchor: .top)
        .opacity(presentation.isPresented ? 1.0 : 0.0)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        // Animation drives transitions between state KINDS only — not on
        // every progress tick (stateKind is stable within a given state
        // like .transferring, so progress updates don't re-trigger the
        // view-morph animation or re-mount the content).
        .animation(.airbridgeStateMorph, value: stateKind)
        .onAppear {
            // Popup just became visible — kick off the spring-in animation
            // from inside the view (this is the canonical SwiftUI pattern;
            // doing it externally via withAnimation in show() races with the
            // first render and the interpolation gets skipped).
            withAnimation(.spring(response: 0.5, dampingFraction: 0.68)) {
                presentation.isPresented = true
            }
            // Idle auto-hide countdown
            if case .idle = state {
                TransferPopup.shared.resetIdleAutoHideTimer()
            } else {
                TransferPopup.shared.cancelIdleAutoHide()
            }
        }
        .onChange(of: state) { _, newState in
            // Any activity (incoming offer, waiting, transferring, etc.)
            // cancels the idle auto-hide. Returning to idle restarts it.
            if case .idle = newState {
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
            } else if case .idle = state {
                TransferPopup.shared.resetIdleAutoHideTimer()
            }
        }
        .onChange(of: fileTransferService.fileTransferProgress) { _, new in
            if new >= 1.0 {
                withAnimation(.airbridgeSmooth) { showComplete = true }
            } else if new == 0 {
                showComplete = false
            }
        }
    }

    static let windowPadding: CGFloat = 40

    /// Transition used between all popup state views. Opacity + strong blur
    /// + a very subtle (96%) scale from center. Combined with the bouncy
    /// `airbridgeStateMorph` animation this gives each new state a gentle
    /// "lands in place" feel — content materializes from blur, scales up a
    /// hair past 1.0 then settles back. No directional slide.
    static let stateTransition: AnyTransition = .opacity
        .combined(with: .blurTransition(radius: 30))
        .combined(with: .scale(scale: 0.96, anchor: .center))

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
                    .font(.system(size: 18, weight: .semibold))
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
                    .font(.system(size: 18, weight: .semibold))
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

    /// Reveal animation — starts at false (gradient compressed at bottom),
    /// animates to true on appear so the aurora "rises" from the bottom
    /// edge into its full extent.
    @State private var revealed: Bool = false
    /// Animated copies of the palette colors. Updated via `withAnimation`
    /// in `.onChange` so SwiftUI can smoothly interpolate them as the
    /// popup state changes — TimelineView reads these animated values on
    /// every frame, so the color crossfade is sampled per frame.
    @State private var animPrimary: Color = .blue
    @State private var animSecondary: Color = .cyan
    @State private var animTertiary: Color = .purple
    @State private var animIntensity: Double = 0.5

    var body: some View {
        // TimelineView(.animation) re-renders the body at the screen refresh
        // rate (60+Hz). On every tick we read `t` and recompute blob centers
        // from `sin(t/period)` — that's what produces actually visible
        // motion. The earlier `withAnimation { phase = 1 } + sin(phase*2π)`
        // approach was a no-op because SwiftUI only interpolates the FINAL
        // value of an animatable modifier, and sin(0)=sin(2π)=0 — start and
        // end were the same point so SwiftUI animated zero motion.
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let topMaskCutoff = max(0.04, (notchInset + 12) / h)
                let twoPi = 2.0 * .pi

                ZStack {
                    // Five small color blobs sweeping wide orbits at coprime
                    // periods. Each X and Y axis has its own period so blobs
                    // never trace a simple circle — they ribbon around like
                    // aurora curtains.

                    blob(
                        color: animPrimary,
                        opacity: animIntensity,
                        cx: 0.22 + sin(t * twoPi / 3.0) * 0.38,
                        cy: 0.78 + cos(t * twoPi / 2.6) * 0.20,
                        radius: w * 0.22
                    )

                    blob(
                        color: animSecondary,
                        opacity: animIntensity * 0.95,
                        cx: 0.78 + cos(t * twoPi / 4.0) * 0.38,
                        cy: 0.82 + sin(t * twoPi / 3.5) * 0.18,
                        radius: w * 0.24
                    )

                    blob(
                        color: animTertiary,
                        opacity: animIntensity * 0.85,
                        cx: 0.50 + sin(t * twoPi / 5.0) * 0.40,
                        cy: 0.65 + cos(t * twoPi / 3.8) * 0.22,
                        radius: w * 0.20
                    )

                    blob(
                        color: animPrimary,
                        opacity: animIntensity * 0.7,
                        cx: 0.62 + cos(t * twoPi / 6.0) * 0.34,
                        cy: 0.88 + sin(t * twoPi / 4.5) * 0.12,
                        radius: w * 0.18
                    )

                    blob(
                        color: animSecondary,
                        opacity: animIntensity * 0.7,
                        cx: 0.38 + sin(t * twoPi / 7.0) * 0.34,
                        cy: 0.70 + cos(t * twoPi / 5.2) * 0.22,
                        radius: w * 0.19
                    )
                }
                .compositingGroup()
                .blur(radius: 16)
                // RISE FROM BOTTOM on appear: scale Y 0→1 anchored at the
                // bottom edge — aurora visually fills upward into the pill.
                .scaleEffect(x: 1.0, y: revealed ? 1.0 : 0.0, anchor: .bottom)
                .opacity(revealed ? 1.0 : 0.0)
                // Mask: pure black above the notch line.
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: topMaskCutoff),
                            .init(color: .black.opacity(0.6), location: topMaskCutoff + 0.18),
                            .init(color: .black, location: 0.55),
                            .init(color: .black, location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .onAppear {
            // Initialize animated color/intensity to current props
            animPrimary = palette.primary
            animSecondary = palette.secondary
            animTertiary = palette.tertiary
            animIntensity = intensity
            // Reveal — aurora rises from the bottom edge with a soft
            // spring slightly delayed so it follows the popup's appear
            // animation, like a wave filling in after the pill drops.
            withAnimation(.spring(response: 0.7, dampingFraction: 0.78).delay(0.08)) {
                revealed = true
            }
        }
        // Smooth color crossfades when state changes — Color is Animatable,
        // SwiftUI interpolates @State Color via withAnimation. TimelineView
        // reads the in-flight interpolated value on each frame.
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
    }

    /// Single radial-gradient blob at a unit-point center. Pulled out so
    /// the body stays readable.
    private func blob(
        color: Color,
        opacity: Double,
        cx: Double,
        cy: Double,
        radius: CGFloat
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

    func configure(connectionService: ConnectionService, fileTransferService: FileTransferService) {
        self.connectionService = connectionService
        self.fileTransferService = fileTransferService
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
        guard let connectionService, let fileTransferService else { return }
        isVisible = true

        guard let screen = NSScreen.main else { return }
        let notchInset = screen.notchInset
        let (x, y, width, height) = computeLayout(screen: screen)

        let view = TransferPopupView(
            connectionService: connectionService,
            fileTransferService: fileTransferService,
            notchInset: notchInset,
            presentation: presentation
        )
        let hostingView = NSHostingView(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
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
        guard isVisible, let panel else { return }

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
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                self.presentation.isPresented = false
            } completion: {
                panel.orderOut(nil)
                self.panel = nil
                self.isVisible = false
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
