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
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
                    Text(isPL ? "Sparowano!" : "Paired!").font(.title).fontWeight(.bold)
                    Text(vm.pairedDeviceName).font(.title3).foregroundStyle(.secondary)
                    Text(isPL ? "Urządzenia są teraz połączone" : "Devices are now connected")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button(isPL ? "Gotowe" : "Done") {
                        pairingService.refreshPairedDevices()
                        isPresented = false
                    }
                    .keyboardShortcut(.defaultAction).controlSize(.large)
                case 1:
                    Spacer()
                    ProgressView().scaleEffect(2)
                    Spacer().frame(height: 24)
                    Text(isPL ? "Parowanie…" : "Pairing…").font(.title2).fontWeight(.semibold)
                    Text(isPL ? "Łączenie z telefonem" : "Connecting to phone")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                default:
                    Image(systemName: "qrcode").font(.system(size: 28)).foregroundStyle(Color.accentColor)
                    Text(L10n.pairTitle).font(.title2).fontWeight(.semibold)
                    Text(L10n.pairDesc).font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 8)
                    if let qrImage = vm.qrImage {
                        Image(nsImage: qrImage).interpolation(.none).resizable().scaledToFit()
                            .frame(width: 256, height: 256).clipShape(RoundedRectangle(cornerRadius: 8))
                    } else if let errorMessage = vm.errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.caption)
                    } else {
                        ProgressView().frame(width: 256, height: 256)
                    }
                    Text(isPL ? "Czekam na połączenie…" : "Waiting for connection…")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer().frame(height: 16)
                    Button {
                        isPresented = false
                    } label: {
                        Text(L10n.close)
                            .font(.system(size: 15))
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
        .onChange(of: connectionService.isConnected) { _, _ in
            viewModel?.onConnectionChanged()
        }
    }
}
