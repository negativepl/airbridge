import SwiftUI

struct MenuBarView: View {
    let connectionService: ConnectionService
    let clipboardService: ClipboardService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(connectionService.isConnected ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                    if connectionService.isConnected {
                        Text("\(L10n.connectedToDevice) \(connectionService.connectedDeviceName)")
                            .font(.subheadline)
                    } else {
                        Text(L10n.notConnected).font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                Divider()

                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label(L10n.openAirbridge, systemImage: "macwindow")
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))

                Button {
                    clipboardService.stopMonitoring()
                    connectionService.stopServer()
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label(L10n.quit, systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
            }
            .padding(16)
        }
        .frame(width: 260)
    }
}
