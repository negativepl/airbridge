import SwiftUI
import Mirror

struct MirrorWindow: View {
    let mirrorService: MirrorService

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MirrorRendererView(stream: mirrorService.sampleBufferStream)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Stop") {
                    Task { await mirrorService.stop() }
                }
            }
        }
        .navigationTitle("AirBridge Mirror")
    }
}
