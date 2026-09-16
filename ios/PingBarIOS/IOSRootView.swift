import PingBarKit
import SwiftUI

struct IOSRootView: View {
    @ObservedObject var monitor: PingMonitor

    var body: some View {
        TabView {
            NavigationStack {
                ScrollView {
                    PingDashboardView(monitor: monitor)
                }
                .navigationTitle("PingBar")
            }
            .tabItem {
                Label("Status", systemImage: "waveform.path.ecg")
            }

            SettingsView(monitor: monitor)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .preferredColorScheme(monitor.appearance.colorScheme)
    }
}
