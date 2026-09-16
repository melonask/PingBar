import PingBarKit
import SwiftUI

@main
struct PingBarIOSApp: App {
    @StateObject private var monitor = PingMonitor()

    var body: some Scene {
        WindowGroup {
            IOSRootView(monitor: monitor)
                .task { monitor.start() }
        }
    }
}
