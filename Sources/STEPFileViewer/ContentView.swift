import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: ModelStore
    @State private var isDropTargeted = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            SceneViewport(store: store)
                .ignoresSafeArea()

            // Empty-state hint
            if store.fileName == nil && store.errorMessage == nil {
                EmptyStateHint()
                    .allowsHitTesting(false)
            }

            // Drop overlay
            if isDropTargeted {
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 2)
                    .background(Color.white.opacity(0.05))
                    .allowsHitTesting(false)
            }

            // Error banner
            if let error = store.errorMessage {
                ErrorBanner(message: error)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)
            }

            // Statistics HUD (bottom-right)
            StatisticsHUD(stats: store.statistics, fileName: store.fileName)
                .padding(14)
                .allowsHitTesting(false)
        }
        .background(Color.black)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in store.load(url: url) }
        }
        return true
    }
}

private struct EmptyStateHint: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("STEP File Viewer")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            Text("Drop a 3D file here, or press ⌘O")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
            Text("STL · OBJ · PLY · USDZ · 3MF · STEP")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ErrorBanner: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.red.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
    }
}
