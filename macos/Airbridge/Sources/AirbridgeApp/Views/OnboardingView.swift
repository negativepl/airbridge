import SwiftUI
import Pairing

struct OnboardingView: View {
    let pairingService: PairingService
    let connectionService: ConnectionService
    let onComplete: () -> Void

    @State private var page = 0
    @State private var showPairing = false

    private var isPL: Bool { L10n.isPL }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcomePage.tag(0)
                featuresPage.tag(1)
                pairPage.tag(2)
            }
            .tabViewStyle(.automatic)

            // Bottom controls
            HStack {
                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? Color.accentColor : Color.primary.opacity(0.25))
                            .frame(width: i == page ? 24 : 10, height: 10)
                            .animation(.easeInOut(duration: 0.2), value: page)
                    }
                }

                Spacer()

                if page < 2 {
                    Button(isPL ? "Dalej" : "Next") {
                        withAnimation { page += 1 }
                    }
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(isPL ? "Sparuj urządzenie" : "Pair Device") {
                        showPairing = true
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)

                    Button(isPL ? "Pomiń" : "Skip") {
                        onComplete()
                    }
                    .controlSize(.large)
                }
            }
            .padding(24)
        }
        .frame(width: 520, height: 440)
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

    private var welcomePage: some View {
        VStack(spacing: 16) {
            Spacer()
            if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
               let icon = NSImage(contentsOf: iconURL) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            Text("Airbridge")
                .font(.largeTitle).fontWeight(.bold)
            Text(isPL
                ? "Twój telefon i komputer Mac, połączone jak nigdy dotąd."
                : "Your phone and Mac, finally on the same team.")
                .font(.title3).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
    }

    private var featuresPage: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(isPL ? "Co potrafi Airbridge?" : "What can Airbridge do?")
                .font(.title2).fontWeight(.bold)
            VStack(alignment: .leading, spacing: 14) {
                featureRow(icon: "doc.on.clipboard", text: isPL
                    ? "Synchronizuj schowek między telefonem a komputerem Mac"
                    : "Sync clipboard between your phone and Mac")
                featureRow(icon: "doc.fill", text: isPL
                    ? "Przesyłaj pliki i zdjęcia bezprzewodowo"
                    : "Send files and photos wirelessly")
                featureRow(icon: "message.fill", text: isPL
                    ? "Przeglądaj i wysyłaj SMS z komputera"
                    : "Browse and send SMS from your Mac")
                featureRow(icon: "lock.shield.fill", text: isPL
                    ? "Prywatnie — dane nigdy nie opuszczają Twojej sieci"
                    : "Private — data never leaves your network")
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .padding(24)
    }

    private var pairPage: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "qrcode")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text(isPL ? "Sparuj z telefonem" : "Pair with your phone")
                .font(.title2).fontWeight(.bold)
            Text(isPL
                ? "Oba urządzenia muszą być w tej samej sieci Wi-Fi.\nKliknij \"Sparuj urządzenie\" i zeskanuj kod QR telefonem."
                : "Both devices must be on the same Wi-Fi network.\nClick \"Pair Device\" and scan the QR code with your phone.")
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            Text(text)
                .font(.body)
        }
    }
}
