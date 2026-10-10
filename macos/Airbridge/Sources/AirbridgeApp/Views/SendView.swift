import SwiftUI
import UniformTypeIdentifiers
import Protocol

struct SendView: View {
    let fileTransferService: FileTransferService
    let connectionService: ConnectionService
    let clipboardService: ClipboardService

    @State private var viewModel: TransferViewModel?
    @State private var isTargeted = false

    /// Like the AirDrop window: the whole tab takes the drop, with the target
    /// phone and the two ways to send in a system empty-state view; while a
    /// file goes out the same place shows its progress.
    var body: some View {
        Group {
            if let vm = viewModel, !vm.isConnected {
                ContentUnavailableView {
                    Label(L10n.isPL ? "Brak połączenia" : "Not Connected", systemImage: "wifi.slash")
                } description: {
                    Text(L10n.isPL
                         ? "Połącz się z telefonem, aby wysyłać pliki i zawartość schowka."
                         : "Connect to your phone to send files and clipboard content.")
                }
            } else if let vm = viewModel, vm.isSending {
                ContentUnavailableView {
                    Label(L10n.isPL ? "Wysyłanie" : "Sending", systemImage: "arrow.up.doc")
                } description: {
                    Text(vm.fileName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } actions: {
                    ProgressView(value: vm.progress) {
                        EmptyView()
                    } currentValueLabel: {
                        Text(vm.progress, format: .percent.precision(.fractionLength(0)))
                            .contentTransition(.numericText())
                    }
                    .frame(width: 280)
                }
            } else {
                ContentUnavailableView {
                    Label(targetTitle, systemImage: "arrow.up.doc")
                        .symbolEffect(.bounce, value: isTargeted)
                } description: {
                    Text(L10n.isPL
                         ? "Przeciągnij pliki lub foldery do tego okna albo wybierz je z dysku."
                         : "Drag files or folders into this window, or choose them from disk.")
                } actions: {
                    Button(L10n.selectFiles) { openFilePicker() }
                        .buttonStyle(.borderedProminent)
                    Button(L10n.isPL ? "Wyślij schowek" : "Send Clipboard") { sendClipboard() }
                }
                // macOS 26 draws large controls as capsules; the standalone
                // actions of an empty state are large, like Photos' "Import".
                .controlSize(.large)
                .buttonBorderShape(.capsule)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Drop highlight: an accent outline around the whole drop area, as
        // Finder outlines a folder window that is about to take a drop.
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.tint, lineWidth: 3)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
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

    /// "Wyślij do Galaxy Z Fold7" — the phone the files will go to.
    private var targetTitle: String {
        let device = connectionService.activeDevice
        let name = device?.deviceInfo?.name.isEmpty == false ? device?.deviceInfo?.name : device?.name
        guard let name else { return L10n.isPL ? "Wyślij do telefonu" : "Send to Phone" }
        return L10n.isPL ? "Wyślij do \(name)" : "Send to \(name)"
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let vm = viewModel, vm.isConnected else { return false }
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    let files = Self.resolveFiles(from: url)
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
