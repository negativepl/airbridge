import SwiftUI
import AppKit

// MARK: - TransferPopupView

struct TransferPopupView: View {
    let fileTransferService: FileTransferService
    @AppStorage("islandWidth") private var islandWidth: Double = 756
    @AppStorage("islandHeight") private var islandHeight: Double = 130
    @AppStorage("islandCornerRadius") private var islandCornerRadius: Double = 24

    private let accentLight = Color.accentColor.opacity(0.8)
    private let accentDark = Color.accentColor

    @State private var showComplete = false

    private var speedLabel: String { L10n.isPL ? "Prędkość" : "Speed" }
    private var etaLabel: String { L10n.isPL ? "Pozostało" : "Remaining" }

    private var speedText: String {
        let speed = fileTransferService.transferSpeed
        if speed > 1024 * 1024 {
            return String(format: "%@: %.1f MB/s", speedLabel, speed / (1024 * 1024))
        } else if speed > 1024 {
            return String(format: "%@: %.0f KB/s", speedLabel, speed / 1024)
        }
        return ""
    }

    private var etaText: String {
        let eta = fileTransferService.transferEta
        if eta > 60 {
            return "\(etaLabel): \(eta / 60) min \(eta % 60) s"
        } else if eta > 3 {
            return "\(etaLabel): \(eta) s"
        } else if fileTransferService.fileTransferProgress > 0 && fileTransferService.fileTransferProgress < 1.0 {
            return L10n.isPL ? "\(etaLabel): kilka sekund…" : "\(etaLabel): a few seconds…"
        }
        return ""
    }

    var body: some View {
        ZStack {
            if showComplete {
                HStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.green)
                    Text(L10n.isPL ? "Plik odebrany!" : "File received!")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.top, 10)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                HStack(spacing: 16) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundColor(accentLight)
                        .padding(.leading, 24)

                    VStack(alignment: .leading, spacing: 6) {
                        MarqueeText(
                            text: fileTransferService.fileTransferFileName.isEmpty
                                ? "file" : fileTransferService.fileTransferFileName
                        )

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3.5)
                                    .fill(Color.white.opacity(0.12))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3.5)
                                    .fill(
                                        LinearGradient(
                                            colors: [accentDark, accentLight],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geometry.size.width * max(0.01, fileTransferService.fileTransferProgress), height: 6)
                                    .animation(.easeInOut(duration: 0.3), value: fileTransferService.fileTransferProgress)
                            }
                        }
                        .frame(height: 6)

                        HStack(spacing: 4) {
                            Text(speedText.isEmpty ? " " : speedText)
                                .font(.system(size: 13, weight: .medium))
                                .monospacedDigit()
                                .foregroundColor(.white.opacity(0.45))
                            Spacer()
                            Text(etaText.isEmpty ? " " : etaText)
                                .font(.system(size: 13, weight: .medium))
                                .monospacedDigit()
                                .foregroundColor(.white.opacity(0.45))
                        }
                        .frame(height: 16)
                    }

                    Text("\(Int(fileTransferService.fileTransferProgress * 100))%")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .frame(width: 80, alignment: .center)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: Int(fileTransferService.fileTransferProgress * 100))
                        .padding(.trailing, 24)
                }
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: showComplete)
        .onChange(of: fileTransferService.isReceivingFile) { _, receiving in
            if !receiving {
                withAnimation { showComplete = true }
            } else {
                showComplete = false
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 10)
        .frame(width: islandWidth, height: islandHeight, alignment: .center)
        .clipShape(BottomRoundedShape(radius: islandCornerRadius))
        .background(
            BottomRoundedShape(radius: islandCornerRadius)
                .fill(Color.black)
        )
    }
}

// MARK: - MarqueeText

struct MarqueeText: View {
    let text: String
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animating = false

    private var needsScroll: Bool { textWidth > containerWidth && containerWidth > 0 }
    private var scrollDistance: CGFloat { textWidth - containerWidth + 20 }

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
                .fixedSize()
                .background(GeometryReader { textGeo in
                    Color.clear.onAppear {
                        textWidth = textGeo.size.width
                        containerWidth = geo.size.width
                        startAnimation()
                    }
                })
                .offset(x: offset)
        }
        .frame(height: 20)
        .clipped()
        .onChange(of: text) { _, _ in
            offset = 0
            animating = false
            textWidth = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                startAnimation()
            }
        }
    }

    private func startAnimation() {
        guard needsScroll, !animating else { return }
        animating = true
        animate()
    }

    private func animate() {
        guard animating, needsScroll else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
            guard animating else { return }
            withAnimation(.linear(duration: Double(scrollDistance) / 30.0)) {
                offset = -scrollDistance
            }
            let scrollDuration = Double(scrollDistance) / 30.0
            DispatchQueue.main.asyncAfter(deadline: .now() + scrollDuration + 1.0) { [self] in
                guard animating else { return }
                withAnimation(.linear(duration: Double(scrollDistance) / 30.0)) {
                    offset = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + scrollDuration + 1.0) { [self] in
                    animate()
                }
            }
        }
    }
}

// MARK: - BottomRoundedShape

struct BottomRoundedShape: Shape {
    var radius: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - TransferPopup (singleton)

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

        let startY = y + height + 10
        window.setFrame(NSRect(x: x, y: startY, width: width, height: height), display: true)
        window.orderFrontRegardless()

        let duration = 0.35
        let startTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0/60.0, repeats: true) { timer in
            let elapsed = CACurrentMediaTime() - startTime
            let t = min(elapsed / duration, 1.0)
            let eased = 1.0 - pow(1.0 - t, 3.0)
            let currentY = startY + (y - startY) * eased
            window.setFrameOrigin(NSPoint(x: x, y: currentY))
            if t >= 1.0 {
                timer.invalidate()
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }
        RunLoop.main.add(timer, forMode: .common)

        self.panel = window
    }

    func hide() {
        guard isVisible, let panel else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, let panel = self.panel else { return }
            let frame = panel.frame
            let targetY = frame.origin.y + frame.height + 10
            let startY = frame.origin.y
            let duration = 0.3
            let startTime = CACurrentMediaTime()

            let timer = Timer(timeInterval: 1.0/60.0, repeats: true) { [weak self] timer in
                let elapsed = CACurrentMediaTime() - startTime
                let t = min(elapsed / duration, 1.0)
                let eased = t * t * t
                let currentY = startY + (targetY - startY) * eased
                panel.setFrameOrigin(NSPoint(x: frame.origin.x, y: currentY))
                if t >= 1.0 {
                    timer.invalidate()
                    panel.orderOut(nil)
                    self?.panel = nil
                    self?.isVisible = false
                }
            }
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func computeLayout(screen: NSScreen) -> (x: Double, y: Double, width: Double, height: Double) {
        let defaults = UserDefaults.standard
        let offsetFromTop = defaults.object(forKey: "islandOffsetY") as? Double ?? 0
        let islandWidth = defaults.object(forKey: "islandWidth") as? Double ?? 756
        let height = defaults.object(forKey: "islandHeight") as? Double ?? 130

        let screenFrame = screen.frame
        let x = screenFrame.midX - islandWidth / 2
        let y = screenFrame.maxY - offsetFromTop - height

        return (x, y, islandWidth, height)
    }
}
