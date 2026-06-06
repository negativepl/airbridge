import SwiftUI
import Pairing
import UserNotifications
import CoreGraphics
import ApplicationServices

struct OnboardingView: View {
    let pairingService: PairingService
    let connectionService: ConnectionService
    let hotkeyService: GlobalHotkeyService
    let notificationService: NotificationService
    let onComplete: () -> Void

    private enum Direction { case forward, backward }
    @State private var page = 0
    @State private var direction: Direction = .forward
    @State private var showPairing = false
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var screenRecordingGranted = CGPreflightScreenCaptureAccess()
    @State private var notificationsAuthorized = false
    @State private var accessibilityPollTimer: Timer?

    private var isPL: Bool { L10n.isPL }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch page {
                case 0: welcomePage.transition(.asymmetric(
                    insertion: .move(edge: .leading),
                    removal: .move(edge: .leading)
                ))
                case 1: howItWorksPage.transition(.asymmetric(
                    insertion: .move(edge: direction == .forward ? .trailing : .leading),
                    removal: .move(edge: direction == .forward ? .leading : .trailing)
                ))
                case 2: permissionsPage.transition(.asymmetric(
                    insertion: .move(edge: direction == .forward ? .trailing : .leading),
                    removal: .move(edge: direction == .forward ? .leading : .trailing)
                ))
                default: connectPage.transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .trailing)
                ))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showPairing) {
            PairingView(
                pairingService: pairingService,
                connectionService: connectionService,
                isPresented: $showPairing
            )
            .onChange(of: connectionService.isConnected) { _, connected in
                if connected {
                    showPairing = false
                    onComplete()
                }
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 20) {
            if page > 0 {
                Button {
                    direction = .backward
                    withAnimation(.airbridgeQuick) { page -= 1 }
                } label: {
                    Text(isPL ? "Wstecz" : "Back")
                        .font(.ab(.callout))
                        .frame(minWidth: 96, minHeight: 40)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
            } else {
                Color.clear.frame(width: 96, height: 40)
            }

            Spacer()

            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Color.accentColor : Color.primary.opacity(0.25))
                        .frame(width: i == page ? 28 : 10, height: 10)
                        .animation(.airbridgeQuick, value: page)
                }
            }

            Spacer()

            if page < 3 {
                Button {
                    direction = .forward
                    withAnimation(.airbridgeQuick) { page += 1 }
                } label: {
                    Text(isPL ? "Dalej" : "Next")
                        .font(.ab(.callout, weight: .semibold))
                        .frame(minWidth: 96, minHeight: 40)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(.accentColor).interactive(), in: .capsule)
                .keyboardShortcut(.defaultAction)
            } else {
                HStack(spacing: 12) {
                    Button {
                        onComplete()
                    } label: {
                        Text(isPL ? "Pomiń" : "Skip")
                            .font(.ab(.callout))
                            .frame(minWidth: 96, minHeight: 40)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)

                    Button {
                        showPairing = true
                    } label: {
                        Text(isPL ? "Sparuj urządzenie" : "Pair Device")
                            .font(.ab(.callout, weight: .semibold))
                            .frame(minWidth: 180, minHeight: 40)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.accentColor).interactive(), in: .capsule)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 24)
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 40) {
            Spacer(minLength: 40)

            if let iconURL = AppResources.bundle.url(forResource: "AppIcon", withExtension: "icns"),
               let icon = NSImage(contentsOf: iconURL) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 130, height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
                    .symbolEffect(.bounce, value: page)
            }

            VStack(spacing: 14) {
                Text("AirBridge")
                    .font(.abHeroName)
                    .tracking(3)

                Text(isPL
                    ? "Twój telefon i komputer Mac, połączone jak nigdy dotąd."
                    : "Your phone and Mac, finally on the same team.")
                    .font(.ab(.title2))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 20) {
                featureRow(
                    icon: "doc.on.clipboard",
                    text: isPL
                        ? "Synchronizuj schowek między telefonem, a Makiem"
                        : "Sync the clipboard between your phone and Mac"
                )
                featureRow(
                    icon: "photo.on.rectangle",
                    text: isPL
                        ? "Przeglądaj i przesyłaj pliki oraz zdjęcia, bez chmury"
                        : "Browse and transfer files and photos — no cloud"
                )
                featureRow(
                    icon: "rectangle.on.rectangle",
                    text: isPL
                        ? "Pokaż ekran telefonu na Macu — i odwrotnie"
                        : "Mirror your phone screen on your Mac — and back"
                )
                featureRow(
                    icon: "bell.badge",
                    text: isPL
                        ? "Powiadomienia z telefonu na Macu"
                        : "Your phone notifications on your Mac"
                )
                featureRow(
                    icon: "sparkles",
                    text: isPL
                        ? "…i wiele więcej"
                        : "…and much more"
                )
            }
            .frame(maxWidth: 560, alignment: .leading)

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Page 2: How it works

    private var howItWorksPage: some View {
        VStack(spacing: 40) {
            Spacer(minLength: 40)

            Image(systemName: "wifi")
                .font(.system(size: 96, weight: .light))
                .foregroundStyle(.primary)
                .symbolEffect(.bounce, value: page)
                .padding(.bottom, 8)

            VStack(spacing: 14) {
                Text(isPL ? "Jak to działa?" : "How it works")
                    .font(.abPageTitle)

                Text(isPL
                    ? "Trzy rzeczy, które warto wiedzieć:"
                    : "Three things you should know:")
                    .font(.ab(.title2))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 26) {
                numberedRow(
                    number: "1",
                    text: isPL
                        ? "Telefon i komputer Mac muszą być w tej samej sieci Wi-Fi"
                        : "Both devices need to be on the same WiFi network"
                )
                numberedRow(
                    number: "2",
                    text: isPL
                        ? "Komputer Mac zostanie wykryty automatycznie — bez konfiguracji"
                        : "AirBridge finds your Mac automatically — no IP addresses, no configuration"
                )
                numberedRow(
                    number: "3",
                    text: isPL
                        ? "Schowek synchronizuje się automatycznie, a pliki przesyłasz jednym kliknięciem"
                        : "Runs quietly in the background — clipboard syncs automatically"
                )
            }
            .frame(maxWidth: 620, alignment: .leading)

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Page 3: Permissions

    private var permissionsPage: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 56)).foregroundStyle(.tint)
                .symbolEffect(.bounce, value: page)
            Text(isPL ? "Uprawnienia" : "Permissions")
                .font(.ab(.title2)).fontWeight(.bold)
            Text(isPL ? "Wszystkie opcjonalne poza siecią — możesz pominąć i wrócić w Ustawieniach."
                      : "All optional except network — you can skip and return in Settings.")
                .font(.ab(.subheadline)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            permissionRow(
                title: isPL ? "Powiadomienia" : "Notifications",
                why: isPL ? "Powiadomienia z telefonu na Macu" : "Phone notifications on your Mac",
                granted: notificationsAuthorized,
                grant: {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
                        refreshNotificationStatus()
                    }
                })
            permissionRow(
                title: isPL ? "Dostępność" : "Accessibility",
                why: isPL ? "Skrót Quick Drop i sterowanie telefonem" : "Quick Drop shortcut & controlling your phone",
                granted: accessibilityGranted,
                grant: {
                    hotkeyService.requestAccessibilityAndStart()
                    startAccessibilityPolling()
                })
            permissionRow(
                title: isPL ? "Nagrywanie ekranu" : "Screen recording",
                why: isPL ? "Pokazywanie ekranu Maca na telefonie" : "Show your Mac's screen on your phone",
                granted: screenRecordingGranted,
                grant: {
                    _ = CGRequestScreenCaptureAccess()
                    screenRecordingGranted = CGPreflightScreenCaptureAccess()
                })
            permissionRow(
                title: isPL ? "Sieć lokalna" : "Local network",
                why: isPL ? "Wykrywanie telefonu w Wi-Fi (systemowo przy 1. połączeniu)" : "Discover your phone on Wi-Fi (granted on first connect)",
                granted: true,
                grant: nil)
        }
        .padding(.horizontal, 48)
        .onAppear {
            accessibilityGranted = AXIsProcessTrusted()
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
            refreshNotificationStatus()
        }
    }

    @ViewBuilder
    private func permissionRow(title: String, why: String, granted: Bool, grant: (() -> Void)?) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ab(.body)).fontWeight(.medium)
                Text(why).font(.ab(.caption)).foregroundStyle(.secondary)
            }
            Spacer()
            StatusIndicator(state: granted ? .connected : .error, size: 12)
            if !granted, let grant {
                Button(isPL ? "Przyznaj" : "Grant", action: grant)
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let authorized = settings.authorizationStatus == .authorized
            DispatchQueue.main.async {
                notificationsAuthorized = authorized
            }
        }
    }

    private func startAccessibilityPolling() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            if AXIsProcessTrusted() {
                accessibilityGranted = true
                accessibilityPollTimer?.invalidate()
                accessibilityPollTimer = nil
            }
        }
    }

    // MARK: - Page 4: Connect

    private var connectPage: some View {
        VStack(spacing: 32) {
            Spacer(minLength: 40)

            Image(systemName: "qrcode")
                .font(.system(size: 112, weight: .light))
                .foregroundStyle(.primary)
                .symbolEffect(.bounce, value: page)
                .padding(.bottom, 8)

            Text(isPL ? "Sparuj z telefonem" : "Pair with your phone")
                .font(.abPageTitle)

            VStack(spacing: 14) {
                Text(isPL
                    ? "Otwórz AirBridge na telefonie i zeskanuj kod QR."
                    : "Open AirBridge on your phone and scan the QR code.")
                    .font(.ab(.title2))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(isPL
                    ? "Oba urządzenia muszą być w tej samej sieci Wi-Fi."
                    : "Both devices must be on the same Wi-Fi network.")
                    .font(.ab(.callout))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 580)

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Components

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 18) {
            Image(systemName: icon)
                .font(.ab(.title2))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .glassEffect(.regular.tint(.accentColor), in: .rect(cornerRadius: 12, style: .continuous))
            Text(text)
                .font(.ab(.headline))
                .fixedSize(horizontal: false, vertical: true)
        }
    }


    private func numberedRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Text(number)
                .font(.ab(.title3, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .glassEffect(.regular.tint(.accentColor), in: .circle)
            Text(text)
                .font(.ab(.headline))
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
