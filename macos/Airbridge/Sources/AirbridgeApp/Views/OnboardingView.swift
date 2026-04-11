import SwiftUI
import Pairing

struct OnboardingView: View {
    let pairingService: PairingService
    let connectionService: ConnectionService
    let onComplete: () -> Void

    private enum Direction { case forward, backward }
    @State private var page = 0
    @State private var direction: Direction = .forward
    @State private var showPairing = false

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
                default: connectPage.transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .trailing)
                ))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // Bottom bar
            GlassEffectContainer(spacing: 14) {
                HStack(spacing: 20) {
                    if page > 0 {
                        Button {
                            direction = .backward
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                page -= 1
                            }
                        } label: {
                            Text(isPL ? "Wstecz" : "Back")
                                .font(.system(size: 15))
                                .frame(minWidth: 80, minHeight: 36)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { i in
                            Capsule()
                                .fill(i == page ? Color.accentColor : Color.primary.opacity(0.25))
                                .frame(width: i == page ? 28 : 10, height: 10)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: page)
                        }
                    }

                    Spacer()

                    if page < 2 {
                        Button {
                            direction = .forward
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                page += 1
                            }
                        } label: {
                            Text(isPL ? "Dalej" : "Next")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(minWidth: 80, minHeight: 36)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(.accentColor).interactive(), in: .capsule)
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Button {
                            onComplete()
                        } label: {
                            Text(isPL ? "Pomiń" : "Skip")
                                .font(.system(size: 15))
                                .frame(minWidth: 80, minHeight: 36)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .capsule)

                        Button {
                            showPairing = true
                        } label: {
                            Text(isPL ? "Sparuj urządzenie" : "Pair Device")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(minWidth: 180, minHeight: 36)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(.accentColor).interactive(), in: .capsule)
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 18)
            }
        }
        .frame(width: 640, height: 560)
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

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        ScrollView {
            VStack(spacing: 24) {
                GlassSection {
                    VStack(spacing: 20) {
                        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
                           let icon = NSImage(contentsOf: iconURL) {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 140, height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 30))
                                .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
                                .symbolEffect(.bounce, value: page)
                        }

                        Text("Airbridge")
                            .font(.system(size: 36, weight: .bold))

                        Text(isPL
                            ? "Twój telefon i komputer Mac, połączone jak nigdy dotąd."
                            : "Your phone and Mac, finally on the same team.")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }

                GlassSection {
                    VStack(alignment: .leading, spacing: 18) {
                        featureRow(
                            icon: "doc.on.clipboard",
                            text: isPL
                                ? "Synchronizuj schowek między telefonem a komputerem Mac"
                                : "Instantly copy text between your phone and Mac"
                        )
                        featureRow(
                            icon: "doc.fill",
                            text: isPL
                                ? "Przesyłaj zdjęcia i pliki bezprzewodowo, bez chmury"
                                : "Send photos and files — no cables, no cloud"
                        )
                        featureRow(
                            icon: "lock.shield.fill",
                            text: isPL
                                ? "Wszystko zostaje w Twojej sieci — pełna prywatność"
                                : "Private — your data never leaves your home network"
                        )
                    }
                }
            }
            .padding(24)
        }
    }

    // MARK: - Page 2: How it works

    private var howItWorksPage: some View {
        ScrollView {
            VStack(spacing: 24) {
                GlassSection {
                    VStack(spacing: 16) {
                        Image(systemName: "wifi")
                            .font(.system(size: 56))
                            .foregroundStyle(.primary)
                            .symbolEffect(.bounce, value: page)

                        Text(isPL ? "Jak to działa?" : "How it works")
                            .font(.system(size: 32, weight: .bold))

                        Text(isPL
                            ? "Trzy rzeczy, które warto wiedzieć:"
                            : "Three things you should know:")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }

                GlassSection {
                    VStack(alignment: .leading, spacing: 22) {
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
                                : "Airbridge finds your Mac automatically — no IP addresses, no configuration"
                        )
                        numberedRow(
                            number: "3",
                            text: isPL
                                ? "Schowek synchronizuje się automatycznie, a pliki przesyłasz jednym kliknięciem"
                                : "Runs quietly in the background — clipboard syncs automatically"
                        )
                    }
                }
            }
            .padding(24)
        }
    }

    // MARK: - Page 3: Connect

    private var connectPage: some View {
        ScrollView {
            VStack(spacing: 24) {
                GlassSection {
                    VStack(spacing: 16) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 56))
                            .foregroundStyle(.primary)
                            .symbolEffect(.bounce, value: page)

                        Text(isPL ? "Sparuj z telefonem" : "Pair with your phone")
                            .font(.system(size: 32, weight: .bold))

                        Text(isPL
                            ? "Otwórz Airbridge na telefonie i zeskanuj kod QR."
                            : "Open Airbridge on your phone and scan the QR code.")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Text(isPL
                            ? "Oba urządzenia muszą być w tej samej sieci Wi-Fi."
                            : "Both devices must be on the same Wi-Fi network.")
                            .font(.system(size: 15))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
    }

    // MARK: - Components

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .glassEffect(.regular.tint(.accentColor), in: .rect(cornerRadius: 10))
            Text(text)
                .font(.system(size: 15))
        }
    }

    private func numberedRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .glassEffect(.regular.tint(.accentColor), in: .circle)
            Text(text)
                .font(.system(size: 15))
                .padding(.top, 5)
        }
    }
}
