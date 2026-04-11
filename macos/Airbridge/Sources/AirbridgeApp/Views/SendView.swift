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
        Group {
            if let vm = viewModel, !vm.isConnected {
                notConnectedView
            } else {
                sendContent
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = TransferViewModel(
                    fileTransferService: fileTransferService,
                    connectionService: connectionService
                )
            }
        }
    }

    private var notConnectedView: some View {
        EmptyStateView(
            systemImage: "wifi.slash",
            title: L10n.isPL ? "Wyślij" : "Send",
            subtitle: L10n.isPL
                ? "Połącz się z telefonem, aby wysyłać pliki i zawartość schowka."
                : "Connect to your phone to send files and clipboard content."
        )
    }

    private var sendContent: some View {
        VStack(spacing: 16) {
            dropZone

            if let vm = viewModel, vm.isSending {
                GlassSection {
                    Text(vm.fileName)
                        .font(.system(size: 14))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    ProgressView(value: vm.progress)
                        .tint(.accentColor)
                    Text("\(Int(vm.progress * 100))%")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
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
    }

    private var dropZone: some View {
        ZStack {
            VStack(spacing: 14) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 44))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                    .symbolEffect(.pulse, options: .repeating, isActive: !isTargeted)
                    .symbolEffect(.bounce, value: isTargeted)
                Text(L10n.dropFilesHere)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 220)
        }
        .glassEffect(
            isTargeted
                ? .regular.tint(.accentColor).interactive()
                : .regular.interactive(),
            in: .rect(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                )
                .foregroundStyle(.secondary.opacity(isTargeted ? 0 : 0.25))
                .padding(8)
                .allowsHitTesting(false)
        )
        .contentShape(Rectangle())
        .onTapGesture { openFilePicker() }
        .animation(.airbridgeQuick, value: isTargeted)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
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
