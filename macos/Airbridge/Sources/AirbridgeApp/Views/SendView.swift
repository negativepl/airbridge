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
                    .font(.system(size: 14)).foregroundStyle(.orange).padding(.top, 8)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.3))
                VStack(spacing: 14) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 44))
                        .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                    Text(L10n.dropFilesHere)
                        .font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .frame(minHeight: 220)
            .contentShape(Rectangle())
            .onTapGesture { openFilePicker() }
            .glassEffect(isTargeted ? .regular.tint(.accentColor) : .regular, in: .rect(cornerRadius: 20))
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }

            if let vm = viewModel, vm.isSending {
                VStack(spacing: 8) {
                    Text(vm.fileName).font(.system(size: 14)).lineLimit(1)
                    ProgressView(value: vm.progress)
                    Text("\(Int(vm.progress * 100))%")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .padding(16)
                .glassEffect(in: .rect(cornerRadius: 12))
            }

            HStack(spacing: 14) {
                Button { openFilePicker() } label: {
                    Label(L10n.selectFiles, systemImage: "folder")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)

                Button { sendClipboard() } label: {
                    Label(L10n.isPL ? "Wyślij schowek" : "Send Clipboard", systemImage: "doc.on.clipboard")
                        .font(.system(size: 14))
                }
                .controlSize(.extraLarge)
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
