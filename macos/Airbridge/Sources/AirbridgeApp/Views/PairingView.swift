import SwiftUI
import Pairing

struct PairingView: View {
    let pairingService: PairingService
    let connectionService: ConnectionService
    @Binding var isPresented: Bool

    @State private var viewModel: PairingViewModel?

    private var isPL: Bool { L10n.isPL }

    var body: some View {
        VStack(spacing: 20) {
            if let vm = viewModel {
                switch vm.phase {
                case 2:
                    GlassSection {
                        VStack(spacing: 16) {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.green)
                                .symbolEffect(.bounce, options: .nonRepeating, value: vm.phase)
                            Text(isPL ? "Sparowano!" : "Paired!")
                                .font(.title).fontWeight(.bold)
                            Text(vm.pairedDeviceName)
                                .font(.title3).foregroundStyle(.secondary)
                            Text(isPL ? "Urządzenia są teraz połączone" : "Devices are now connected")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            Button(isPL ? "Gotowe" : "Done") {
                                pairingService.refreshPairedDevices()
                                isPresented = false
                            }
                            .keyboardShortcut(.defaultAction).controlSize(.large)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                default:
                    GlassSection(title: LocalizedStringKey(isPL ? "Zeskanuj kod QR" : "Scan this QR code"), systemImage: "qrcode") {
                        VStack(spacing: 12) {
                            Text(L10n.pairTitle).font(.title2).fontWeight(.semibold)
                            Text(L10n.pairDesc).font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            if let qrImage = vm.qrImage {
                                Image(nsImage: qrImage).interpolation(.none).resizable().scaledToFit()
                                    .frame(width: 256, height: 256).clipShape(RoundedRectangle(cornerRadius: 8))
                                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                            } else if let errorMessage = vm.errorMessage {
                                Text(errorMessage).foregroundStyle(.red).font(.caption)
                            } else {
                                ProgressView().frame(width: 256, height: 256)
                            }
                            Text(isPL ? "Czekam na połączenie…" : "Waiting for connection…")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .transition(.scale(scale: 0.95).combined(with: .opacity))

                    Spacer().frame(height: 8)

                    Button {
                        isPresented = false
                    } label: {
                        Text(L10n.close)
                            .font(.ab(.callout))
                            .frame(minWidth: 100, minHeight: 36)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(32)
        .frame(width: 420, height: 540)
        .presentationBackground(.thinMaterial)
        // The QR card and the "Paired!" card swap with a spring, not a cut.
        .animation(.spring(duration: 0.45, bounce: 0.15), value: viewModel?.phase)
        .animation(.easeOut(duration: 0.3), value: viewModel?.qrImage != nil)
        .onAppear {
            if viewModel == nil {
                let vm = PairingViewModel(
                    pairingService: pairingService,
                    connectionService: connectionService
                )
                vm.generateQR()
                viewModel = vm
            }
        }
        .onChange(of: connectionService.pairedSignal) { _, _ in
            viewModel?.onPaired()
        }
    }
}
