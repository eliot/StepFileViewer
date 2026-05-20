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
                .navigationTitle(modelStore.fileName ?? "STEP File Viewer")
                .background(WindowConfigurator())
                .onAppear { appDelegate.modelStore = modelStore }
        }
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

/// Reaches up to the hosting NSWindow to keep the translucent backing while
/// using a standard title bar.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            // Standard title bar with all window buttons; the window is moved
            // by its title bar, NOT by background drag — otherwise clicks in
            // the viewport would drag the window instead of orbiting.
            window.isMovableByWindowBackground = false
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            // Force a light appearance so the frosted background reads as white
            // regardless of the system's dark/light mode.
            window.appearance = NSAppearance(named: .aqua)
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
