import SwiftUI
import Quartz

/// Natywny podgląd pliku (QuickLook) osadzony w SwiftUI. Obsługuje zdjęcia,
/// wideo z odtwarzaniem, PDF, dokumenty itd. — wszystko czego QuickLook umie.
struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        if (nsView.previewItem as? URL) != url {
            nsView.previewItem = url as NSURL
        }
    }
}
