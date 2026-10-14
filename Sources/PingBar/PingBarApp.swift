import AppKit
import PingBarKit

@main
@MainActor
enum PingBarApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

/// Owns the monitor, the menu-bar item and the panel for the app's lifetime.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = PingMonitor()
    private var panelController: PanelController?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Info.plist already sets LSUIElement; this also covers `swift run`.
        NSApp.setActivationPolicy(.accessory)

        let panelController = PanelController(monitor: monitor)
        let statusItemController = StatusItemController(monitor: monitor) { click in
            panelController.toggle(on: click.screen, below: click.itemFrame)
        }
        panelController.isOnStatusItem = { [weak statusItemController] point in
            statusItemController?.contains(point) ?? false
        }
        self.statusItemController = statusItemController
        self.panelController = panelController
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }
}
