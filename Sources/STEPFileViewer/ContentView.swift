import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: ModelStore
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            SceneViewport(store: store)
                .ignoresSafeArea()

            // Empty-state hint
            if store.fileName == nil && store.errorMessage == nil && !store.isLoading {
                EmptyStateHint()
                    .allowsHitTesting(false)
            }

            // Loading spinner
            if store.isLoading {
                LoadingOverlay()
                    .allowsHitTesting(false)
            }

            // Drop overlay
            if isDropTargeted {
                Rectangle()
                    .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 2)
                    .background(Color.accentColor.opacity(0.08))
                    .allowsHitTesting(false)
            }

            // Error banner
            if let error = store.errorMessage {
                ErrorBanner(message: error)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .topLeading)
                    .allowsHitTesting(false)
            }

            // Statistics HUD + wireframe toggle (bottom-right)
            if store.statistics.hasGeometry {
                StatisticsHUD(stats: store.statistics, wireframe: $store.wireframe)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .bottomTrailing)
            }

            // Object color picker (top-right)
            ColorPicker("Object color", selection: $store.objectColor,
                        supportsOpacity: false)
                .labelsHidden()
                .controlSize(.large)
                .help("Object color")
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .topTrailing)
        }
        .background(VisualEffectView())
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
                .foregroundStyle(.primary)
            Text("Drop a 3D file here, or press ⌘O")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("STL · OBJ · PLY · USDZ · 3MF · STEP")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LoadingOverlay: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading…")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(26)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Frosted translucent backing that lets the desktop blur through, giving the
/// light "Quick Look" appearance.
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .aqua)
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
