import SwiftUI

public struct SettingsView: View {
    @ObservedObject var monitor: PingMonitor
    @State private var showingRestoreConfirmation = false

    /// Edits go straight through the monitor, which normalizes, persists and
    /// applies them, so this view never holds a second copy of the settings.
    private var settings: Binding<PingSettings> {
        Binding(
            get: { monitor.settings },
            set: { monitor.updateSettings($0) }
        )
    }

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
                        Picker("Check type", selection: settings.targetType) {
                            ForEach(TargetType.allCases) { type in
                                Text(type.title).tag(type)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }
                    Divider()
                    if monitor.settings.targetType == .icmp {
                        HStack(spacing: 8) {
                            Image(systemName: "network")
                                .foregroundStyle(.secondary)
                            TextField("Device address", text: settings.pingHost, prompt: Text(PingSettings.defaultPingHost))
                                .textFieldStyle(.roundedBorder)
                        }
                        Label(pingHostValidationText, systemImage: isValidPingHost ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(isValidPingHost ? .green : .red)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "link")
                                .foregroundStyle(.secondary)
                            TextField("Website URL", text: settings.urlString, prompt: Text(PingSettings.defaultURL))
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
                        if monitor.settings.menuBarMode.showsCircle {
                            Divider()
                            HStack {
                                Text("Circle style")
                                Spacer()
                                Picker("Circle style", selection: settings.circleStyle) {
                                    ForEach(CircleStyle.allCases) { style in
                                        Text(style.title).tag(style)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(width: 170)
                            }
                            Divider()
                            valueRow("Circle size", value: settings.menuBarCircleSize, unit: "pt")
                        }
                        if monitor.settings.menuBarMode.showsTime {
                            Divider()
                            valueRow("Time size", value: settings.menuBarTextSize, unit: "pt")
                        }
                    }
                #endif

                settingCard("Panel", systemImage: "rectangle.on.rectangle") {
                    HStack {
                        Text("Appearance")
                        Spacer()
                        Picker("Appearance", selection: settings.appearance) {
                            ForEach(AppAppearance.allCases) { appearance in
                                Text(appearance.title).tag(appearance)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }
                    #if os(macOS)
                        Divider()
                        Toggle("Transparent background", isOn: settings.panelTransparency)
                        Text("Use the macOS translucent material on both Status and Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Divider()
                        Toggle("Always on top", isOn: settings.alwaysOnTop)
                        Text("Keep the panel visible above all other windows while open.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    #endif
                }

                settingCard("Monitoring", systemImage: "clock") {
                    valueRow("Check interval", value: settings.interval, unit: "seconds")
                    Divider()
                    valueRow("Request timeout", value: settings.timeout, unit: "seconds")
                    Divider()
                    valueRow("Chart window", value: settings.chartWindow, unit: "seconds")
                    Text("Checks run automatically; history keeps only the selected time window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Divider()
                    HStack {
                        Text("Recheck public IP")
                        Spacer()
                        Picker("Recheck public IP", selection: settings.locationRefresh) {
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
                    thresholdRow(color: .yellow, title: "Show yellow", value: settings.yellowFailures)
                    Divider()
                    thresholdRow(color: .red, title: "Show red", value: settings.redFailures)
                    Text("The counter resets immediately after a successful request.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if monitor.settings.targetType == .http {
                    settingCard("HTTP Response Range", systemImage: "checkmark.circle") {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Minimum")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Minimum", value: settings.minimumStatus, format: .number)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Image(systemName: "ellipsis")
                                .foregroundStyle(.tertiary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Maximum")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Maximum", value: settings.maximumStatus, format: .number)
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
            Button("Restore Defaults", role: .destructive, action: monitor.restoreDefaultSettings)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This resets the target, timing, thresholds, menu-bar display, and panel appearance.")
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
            Stepper(value: value, in: PingSettings.failureThresholdRange) {
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
        let current = monitor.settings.locationRefresh
        return PingSettings.locationRefreshOptions.contains(current)
            ? PingSettings.locationRefreshOptions
            : (PingSettings.locationRefreshOptions + [current]).sorted()
    }

    private var isValidURL: Bool { PingSettings.isValidHTTPURL(monitor.settings.urlString) }

    private var urlValidationText: String {
        isValidURL ? "Ready to monitor" : "Enter a complete HTTP or HTTPS URL"
    }

    private var isValidPingHost: Bool { PingSettings.isValidPingHost(monitor.settings.pingHost) }

    private var pingHostValidationText: String {
        isValidPingHost ? "Ready to ping" : "Enter an IP address or hostname"
    }

    private func modeButton(_ mode: MenuBarDisplayMode) -> some View {
        let isSelected = monitor.settings.menuBarMode == mode
        return Button {
            monitor.updateSettings { $0.menuBarMode = mode }
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    if mode.showsCircle {
                        statusCircle
                    }
                    if mode.showsTime {
                        Text("024 ms")
                            .fontDesign(.monospaced)
                    }
                }
                .font(.system(size: monitor.settings.menuBarTextSize, weight: .medium))
                .frame(height: max(monitor.settings.menuBarTextSize, monitor.settings.menuBarCircleSize) + 4)

                HStack(spacing: 4) {
                    Text(mode.title)
                        .font(.caption2.weight(.medium))
                    if isSelected {
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
            Color.primary.opacity(isSelected ? 0.08 : 0),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.primary.opacity(0.35) : Color.secondary.opacity(0.18))
        }
    }

    private var menuBarPreview: some View {
        HStack(spacing: 5) {
            if monitor.settings.menuBarMode.showsCircle {
                statusCircle
            }
            if monitor.settings.menuBarMode.showsTime {
                Text(monitor.menuBarStatusText)
                    .font(.system(size: monitor.settings.menuBarTextSize, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder private var statusCircle: some View {
        switch monitor.settings.circleStyle {
        case .colored:
            Text("🟢")
                .font(.system(size: monitor.settings.menuBarCircleSize))
        case .monochrome:
            Text("●")
                .font(.system(size: monitor.settings.menuBarCircleSize, weight: .bold, design: .rounded))
        }
    }
}
