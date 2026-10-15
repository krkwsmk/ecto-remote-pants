import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        installHeaderDoubleClickMonitor()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = nil
        AppModel.shared.shutdownForTermination()
    }

    /// A double-click on the custom header band zooms (maximizes) the window.
    /// Done with a local event monitor because, with a hidden title bar and a
    /// custom SwiftUI header, neither the native title-bar handler nor SwiftUI
    /// gestures reliably receive the double-click. The monitor sees the event
    /// before any view or the window-drag machinery, so it is deterministic.
    private func installHeaderDoubleClickMonitor() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            guard event.clickCount == 2,
                  let window = event.window ?? NSApp.keyWindow,
                  !window.isSheet,
                  window.styleMask.contains(.resizable),
                  let content = window.contentView else { return event }
            // Header band lives at the very top of the content view.
            let headerHeight: CGFloat = 54
            let point = event.locationInWindow
            if point.y >= content.bounds.height - headerHeight {
                window.zoom(nil)
                return nil // consume: don't also start a drag/selection
            }
            return event
        }
    }
}

@main
struct EctoRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("Ecto Remote") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 940, minHeight: 620)
                .background(Theme.bg)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
