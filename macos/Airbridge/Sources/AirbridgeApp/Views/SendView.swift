import SwiftUI
import UniformTypeIdentifiers
import Protocol

struct SendView: View {
    let fileTransferService: FileTransferService
    let connectionService: ConnectionService
    let clipboardService: ClipboardService

    @State private var viewModel: TransferViewModel?
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 20) {
            if let vm = viewModel, !vm.isConnected {
                Label(L10n.isPL ? "Połącz się z urządzeniem aby wysłać" : "Connect to a device to send", systemImage: "wifi.slash")
                    .font(.subheadline).foregroundStyle(.orange).padding(.top, 8)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                    )
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 40))
                        .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                    Text(L10n.dropFilesHere)
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .frame(minHeight: 200)
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }

            if let vm = viewModel, vm.isSending {
                VStack(spacing: 6) {
                    Text(vm.fileName).font(.subheadline).lineLimit(1)
                    ProgressView(value: vm.progress)
                    Text("\(Int(vm.progress * 100))%")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button { openFilePicker() } label: {
                    Label(L10n.selectFiles, systemImage: "folder")
                }
                .controlSize(.large)

                Button { sendClipboard() } label: {
                    Label(L10n.isPL ? "Wyślij schowek" : "Send Clipboard", systemImage: "doc.on.clipboard")
                }
                .controlSize(.large)
                .disabled(viewModel.map { !$0.isConnected } ?? true)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if viewModel == nil {
                viewModel = TransferViewModel(
                    fileTransferService: fileTransferService,
                    connectionService: connectionService
                )
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let vm = viewModel, vm.isConnected else { return false }
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                let files = Self.resolveFiles(from: url)
                Task { @MainActor in
                    for file in files { viewModel?.sendFile(url: file) }
                }
            }
        }
        return true
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            let files = panel.urls.flatMap { Self.resolveFiles(from: $0) }
            for url in files { viewModel?.sendFile(url: url) }
        }
    }

    private static func resolveFiles(from url: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue { return [url] }
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var result: [URL] = []
        for case let fileURL as URL in enumerator {
            if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                result.append(fileURL)
            }
        }
        return result
    }

    private func sendClipboard() {
        clipboardService.sendCurrentClipboard()
    }
}
