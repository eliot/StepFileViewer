import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct STEPFileViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var modelStore = ModelStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(modelStore)
                .frame(minWidth: 640, minHeight: 480)
                .background(WindowConfigurator())
                .onAppear { appDelegate.modelStore = modelStore }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { modelStore.openFilePicker() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .help) { EmptyView() }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var modelStore: ModelStore?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        Task { @MainActor in
            modelStore?.load(url: url)
        }
    }
}

/// Reaches up to the hosting NSWindow and strips all chrome.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor.black
            window.isOpaque = true
            window.hasShadow = true
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
