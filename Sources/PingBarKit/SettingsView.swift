import SwiftUI

public struct SettingsView: View {
    @ObservedObject var monitor: PingMonitor
    @State private var showingRestoreConfirmation = false
    @AppStorage(PingSettings.Keys.url) private var url = PingSettings.defaultURL
    @AppStorage(PingSettings.Keys.targetType) private var targetType = PingSettings.defaultTargetType
    @AppStorage(PingSettings.Keys.pingHost) private var pingHost = PingSettings.defaultPingHost
    @AppStorage(PingSettings.Keys.interval) private var interval = PingSettings.defaultInterval
    @AppStorage(PingSettings.Keys.timeout) private var timeout = PingSettings.defaultTimeout
    @AppStorage(PingSettings.Keys.yellowFailures) private var yellowFailures = PingSettings.defaultYellowFailures
    @AppStorage(PingSettings.Keys.redFailures) private var redFailures = PingSettings.defaultRedFailures
    @AppStorage(PingSettings.Keys.minimumStatus) private var minimumStatus = PingSettings.defaultMinimumStatus
    @AppStorage(PingSettings.Keys.maximumStatus) private var maximumStatus = PingSettings.defaultMaximumStatus
    @AppStorage(PingSettings.Keys.chartWindow) private var chartWindow = PingSettings.defaultChartWindow
    @AppStorage(PingSettings.Keys.locationRefresh) private var locationRefresh = PingSettings.defaultLocationRefresh

    public init(monitor: PingMonitor) {
        self.monitor = monitor
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Settings")
                            .font(.title2.weight(.semibold))
                        Text("Tune monitoring and appearance.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("Auto-saved", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.green.opacity(0.1), in: Capsule())
                }

                settingCard("Target", systemImage: "scope") {
                    HStack {
                        Text("Check type")
                        Spacer()
                        Picker("Check type", selection: $targetType) {
                            ForEach(TargetType.allCases) { type in
                                Text(type.title).tag(type.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }
                    Divider()
                    if targetType == TargetType.icmp.rawValue {
                        HStack(spacing: 8) {
                            Image(systemName: "network")
                                .foregroundStyle(.secondary)
                            TextField("Device address", text: $pingHost, prompt: Text(PingSettings.defaultPingHost))
                                .textFieldStyle(.roundedBorder)
                        }
                        Label(pingHostValidationText, systemImage: isValidPingHost ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(isValidPingHost ? .green : .red)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "link")
                                .foregroundStyle(.secondary)
                            TextField("Website URL", text: $url, prompt: Text(PingSettings.defaultURL))
                                .textFieldStyle(.roundedBorder)
                        }
                        Label(urlValidationText, systemImage: isValidURL ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(isValidURL ? .green : .red)
                    }
                    Text("HTTP monitors a website; Ping measures round trips to a device such as a router or another computer on your network.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                #if os(macOS)
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
                #endif

                settingCard("Panel", systemImage: "rectangle.on.rectangle") {
                    HStack {
                        Text("Appearance")
                        Spacer()
                        Picker("Appearance", selection: appearanceBinding) {
                            ForEach(AppAppearance.allCases) { appearance in
                                Text(appearance.title).tag(appearance.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }
                    #if os(macOS)
                        Divider()
                        Toggle("Transparent background", isOn: panelTransparencyBinding)
                        Text("Use the macOS translucent material on both Status and Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Divider()
                        Toggle("Always on top", isOn: alwaysOnTopBinding)
                        Text("Keep the panel visible above all other windows while open.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    #endif
                }

                settingCard("Monitoring", systemImage: "clock") {
                    valueRow("Check interval", value: $interval, unit: "seconds")
                    Divider()
                    valueRow("Request timeout", value: $timeout, unit: "seconds")
                    Divider()
                    valueRow("Chart window", value: $chartWindow, unit: "seconds")
                    Text("Checks run automatically; history keeps only the selected time window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Divider()
                    HStack {
                        Text("Recheck public IP")
                        Spacer()
                        Picker("Recheck public IP", selection: $locationRefresh) {
                            ForEach(locationRefreshChoices, id: \.self) { seconds in
                                Text(PingSettings.locationRefreshTitle(for: seconds)).tag(seconds)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 130)
                    }
                    Text("How often the public IP address and its map location are refreshed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                settingCard("Connection Health", systemImage: "circle.inset.filled") {
                    thresholdRow(color: .yellow, title: "Show yellow", value: $yellowFailures)
                    Divider()
                    thresholdRow(color: .red, title: "Show red", value: $redFailures)
                    Text("The counter resets immediately after a successful request.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if targetType == TargetType.http.rawValue {
                    settingCard("HTTP Response Range", systemImage: "checkmark.circle") {
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
                }

                HStack {
                    Text("Restore every preference to its original value.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Defaults…") {
                        showingRestoreConfirmation = true
                    }
                }
            }
            .padding(16)
        }
        .scrollIndicators(.visible)
        .confirmationDialog(
            "Restore all settings?",
            isPresented: $showingRestoreConfirmation
        ) {
            Button("Restore Defaults", role: .destructive, action: restoreDefaults)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This resets the target, timing, thresholds, menu-bar display, and panel appearance.")
        }
        .onChange(of: yellowFailures) { _, value in
            if redFailures <= value { redFailures = value + 1 }
        }
        .onChange(of: targetType) { monitor.refreshSettings() }
        .onChange(of: url) { monitor.refreshSettings() }
        .onChange(of: pingHost) { monitor.refreshSettings() }
        .onChange(of: interval) { _, value in interval = max(value, 0.1) }
        .onChange(of: timeout) { _, value in timeout = max(value, 0.1) }
        .onChange(of: chartWindow) { _, value in chartWindow = min(max(value, 60), 86_400) }
        .onChange(of: locationRefresh) { _, value in
            locationRefresh = min(
                max(value, PingSettings.minimumLocationRefresh),
                PingSettings.maximumLocationRefresh
            )
            monitor.refreshSettings()
        }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22, height: 22)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                Text(title)
                    .font(.headline)
            }
            Divider()
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 0.7)
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
            Stepper(value: value, in: 1...1_000) {
                Text("after \(value.wrappedValue)")
                    .monospacedDigit()
                    .frame(width: 66, alignment: .trailing)
            }
            Text("failures")
                .foregroundStyle(.secondary)
        }
    }

    /// The stored interval is normally one of the offered choices. If it is
    /// not (an older or hand-edited value), it is shown alongside them so the
    /// picker always has a selection instead of appearing blank.
    private var locationRefreshChoices: [Double] {
        PingSettings.locationRefreshOptions.contains(locationRefresh)
            ? PingSettings.locationRefreshOptions
            : (PingSettings.locationRefreshOptions + [locationRefresh]).sorted()
    }

    private func restoreDefaults() {
        url = PingSettings.defaultURL
        targetType = PingSettings.defaultTargetType
        pingHost = PingSettings.defaultPingHost
        interval = PingSettings.defaultInterval
        timeout = PingSettings.defaultTimeout
        yellowFailures = PingSettings.defaultYellowFailures
        redFailures = PingSettings.defaultRedFailures
        minimumStatus = PingSettings.defaultMinimumStatus
        maximumStatus = PingSettings.defaultMaximumStatus
        chartWindow = PingSettings.defaultChartWindow
        locationRefresh = PingSettings.defaultLocationRefresh
        monitor.setMenuBarMode(PingSettings.defaultMenuBarMode)
        monitor.setMenuBarTextSize(PingSettings.defaultMenuBarTextSize)
        monitor.setMenuBarCircleSize(PingSettings.defaultMenuBarCircleSize)
        monitor.setCircleStyle(PingSettings.defaultCircleStyle)
        monitor.setPanelTransparency(PingSettings.defaultPanelTransparency)
        monitor.setAppearance(PingSettings.defaultAppearance)
        monitor.setAlwaysOnTop(PingSettings.defaultAlwaysOnTop)
        monitor.refreshSettings()
    }

    private var isValidURL: Bool { PingSettings.isValidHTTPURL(url) }

    private var urlValidationText: String {
        isValidURL ? "Ready to monitor" : "Enter a complete HTTP or HTTPS URL"
    }

    private var isValidPingHost: Bool { PingSettings.isValidPingHost(pingHost) }

    private var pingHostValidationText: String {
        isValidPingHost ? "Ready to ping" : "Enter an IP address or hostname"
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

    private var panelTransparencyBinding: Binding<Bool> {
        Binding(
            get: { monitor.panelTransparency },
            set: { monitor.setPanelTransparency($0) }
        )
    }

    private var alwaysOnTopBinding: Binding<Bool> {
        Binding(
            get: { monitor.alwaysOnTop },
            set: { monitor.setAlwaysOnTop($0) }
        )
    }

    private var appearanceBinding: Binding<String> {
        Binding(
            get: { monitor.appearance.rawValue },
            set: { monitor.setAppearance($0) }
        )
    }
}
