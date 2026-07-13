import SwiftUI

struct SettingsView: View {
    @ObservedObject var monitor: PingMonitor
    @AppStorage(PingSettings.Keys.url) private var url = PingSettings.defaultURL
    @AppStorage(PingSettings.Keys.interval) private var interval = PingSettings.defaultInterval
    @AppStorage(PingSettings.Keys.timeout) private var timeout = PingSettings.defaultTimeout
    @AppStorage(PingSettings.Keys.yellowFailures) private var yellowFailures = PingSettings.defaultYellowFailures
    @AppStorage(PingSettings.Keys.redFailures) private var redFailures = PingSettings.defaultRedFailures
    @AppStorage(PingSettings.Keys.minimumStatus) private var minimumStatus = PingSettings.defaultMinimumStatus
    @AppStorage(PingSettings.Keys.maximumStatus) private var maximumStatus = PingSettings.defaultMaximumStatus
    @AppStorage(PingSettings.Keys.chartWindow) private var chartWindow = PingSettings.defaultChartWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11)
                            .fill(.primary)
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ping Settings")
                            .font(.title2.weight(.semibold))
                        Text("Saved automatically and applied to the next check.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                settingCard("Endpoint", systemImage: "network") {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                        TextField("Website URL", text: $url, prompt: Text("https://fast.com"))
                            .textFieldStyle(.roundedBorder)
                    }
                    Label(urlValidationText, systemImage: isValidURL ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(isValidURL ? .green : .red)
                }

                settingCard("Menu Bar", systemImage: "menubar.rectangle") {
                    HStack {
                        Text("Preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        menuBarPreview
                    }
                    .padding(9)
                    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                    HStack(spacing: 8) {
                        ForEach(MenuBarDisplayMode.allCases) { mode in
                            modeButton(mode)
                        }
                    }
                    Text("Choose exactly what PingBar keeps visible in the system menu bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if monitor.menuBarMode != .time {
                        Divider()
                        HStack {
                            Text("Circle style")
                            Spacer()
                            Picker("Circle style", selection: circleStyleBinding) {
                                ForEach(CircleStyle.allCases) { style in
                                    Text(style.title).tag(style.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 170)
                        }
                        Divider()
                        valueRow("Circle size", value: menuBarCircleSizeBinding, unit: "pt")
                    }
                    if monitor.menuBarMode != .circle {
                        Divider()
                        valueRow("Time size", value: menuBarTextSizeBinding, unit: "pt")
                    }
                }

                settingCard("Timing", systemImage: "clock") {
                    valueRow("Check interval", value: $interval, unit: "seconds")
                    Divider()
                    valueRow("Request timeout", value: $timeout, unit: "seconds")
                }

                settingCard("Failure Colors", systemImage: "circle.inset.filled") {
                    thresholdRow(color: .yellow, title: "Show yellow", value: $yellowFailures)
                    Divider()
                    thresholdRow(color: .red, title: "Show red", value: $redFailures)
                    Text("The counter resets immediately after a successful request.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                settingCard("Successful HTTP Responses", systemImage: "checkmark.circle") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Minimum")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Minimum", value: $minimumStatus, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.tertiary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Maximum")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Maximum", value: $maximumStatus, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    Text("Responses outside this inclusive range count as failures.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                settingCard("Chart", systemImage: "chart.xyaxis.line") {
                    valueRow("Time window", value: $chartWindow, unit: "seconds")
                    Text("The chart shows checks from the most recent time window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label("All changes are saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Restore Defaults", action: restoreDefaults)
                }
            }
            .padding(16)
        }
        .scrollIndicators(.never)
        .onChange(of: yellowFailures) { _, value in
            if redFailures <= value { redFailures = value + 1 }
        }
        .onChange(of: interval) { _, value in interval = max(value, 0.1) }
        .onChange(of: timeout) { _, value in timeout = max(value, 0.1) }
        .onChange(of: chartWindow) { _, value in chartWindow = min(max(value, 60), 86_400) }
        .onChange(of: minimumStatus) { _, value in
            minimumStatus = min(max(value, 100), 599)
            if maximumStatus < minimumStatus { maximumStatus = minimumStatus }
        }
        .onChange(of: maximumStatus) { _, value in
            maximumStatus = min(max(value, minimumStatus), 599)
        }
    }

    private func settingCard<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 24, height: 24)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    Text(title)
                        .font(.headline)
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private func valueRow(_ title: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(1...2)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
        }
    }

    private func thresholdRow(color: Color, title: String, value: Binding<Int>) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(title)
            Spacer()
            Stepper(value: value, in: 1...1000) {
                Text("after \(value.wrappedValue)")
                    .monospacedDigit()
                    .frame(width: 66, alignment: .trailing)
            }
            Text("failures")
                .foregroundStyle(.secondary)
        }
    }

    private func restoreDefaults() {
        url = PingSettings.defaultURL
        interval = PingSettings.defaultInterval
        timeout = PingSettings.defaultTimeout
        yellowFailures = PingSettings.defaultYellowFailures
        redFailures = PingSettings.defaultRedFailures
        minimumStatus = PingSettings.defaultMinimumStatus
        maximumStatus = PingSettings.defaultMaximumStatus
        chartWindow = PingSettings.defaultChartWindow
        monitor.setMenuBarMode(PingSettings.defaultMenuBarMode)
        monitor.setMenuBarTextSize(PingSettings.defaultMenuBarTextSize)
        monitor.setMenuBarCircleSize(PingSettings.defaultMenuBarCircleSize)
        monitor.setCircleStyle(PingSettings.defaultCircleStyle)
    }

    private var isValidURL: Bool {
        guard let value = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = value.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              value.host != nil else {
            return false
        }
        return true
    }

    private var urlValidationText: String {
        isValidURL ? "Ready to monitor" : "Enter a complete HTTP or HTTPS URL"
    }

    private func modeButton(_ mode: MenuBarDisplayMode) -> some View {
        Button {
            monitor.setMenuBarMode(mode.rawValue)
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    if mode != .time {
                        if monitor.circleStyle == .colored {
                            Text("🟢")
                                .font(.system(size: monitor.menuBarCircleSize))
                        } else {
                            Text("●")
                                .font(.system(size: monitor.menuBarCircleSize, weight: .bold, design: .rounded))
                        }
                    }
                    if mode != .circle {
                        Text("024 ms")
                            .fontDesign(.monospaced)
                    }
                }
                .font(.system(size: monitor.menuBarTextSize, weight: .medium))
                .frame(height: max(monitor.menuBarTextSize, monitor.menuBarCircleSize) + 4)

                HStack(spacing: 4) {
                    Text(mode.title)
                        .font(.caption2.weight(.medium))
                    if monitor.menuBarMode == mode {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(
            Color.primary.opacity(monitor.menuBarMode == mode ? 0.08 : 0),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(monitor.menuBarMode == mode ? Color.primary.opacity(0.35) : Color.secondary.opacity(0.18))
        }
    }

    private var menuBarPreview: some View {
        HStack(spacing: 5) {
            if monitor.menuBarMode != .time {
                if monitor.circleStyle == .colored {
                    Text("🟢")
                        .font(.system(size: monitor.menuBarCircleSize))
                } else {
                    Text("●")
                        .font(.system(size: monitor.menuBarCircleSize, weight: .bold, design: .rounded))
                }
            }
            if monitor.menuBarMode != .circle {
                Text(monitor.menuBarStatusText)
                    .font(.system(size: monitor.menuBarTextSize, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private var menuBarTextSizeBinding: Binding<Double> {
        Binding(
            get: { monitor.menuBarTextSize },
            set: { monitor.setMenuBarTextSize($0) }
        )
    }

    private var menuBarCircleSizeBinding: Binding<Double> {
        Binding(
            get: { monitor.menuBarCircleSize },
            set: { monitor.setMenuBarCircleSize($0) }
        )
    }

    private var circleStyleBinding: Binding<String> {
        Binding(
            get: { monitor.circleStyle.rawValue },
            set: { monitor.setCircleStyle($0) }
        )
    }
}
