import AppKit
import Charts
import SwiftUI

@main
struct PingBarApp: App {
    @StateObject private var monitor = PingMonitor()

    var body: some Scene {
        MenuBarExtra {
            PingMenu(monitor: monitor)
        } label: {
            MenuBarStatusLabel(monitor: monitor)
                .task { monitor.start() }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarStatusLabel: View {
    @ObservedObject var monitor: PingMonitor

    private func color(for level: StatusLevel) -> Color {
        switch level {
        case .green: .green
        case .yellow: .yellow
        case .red: .red
        }
    }

    var body: some View {
        labelText.fixedSize()
    }

    private var labelText: Text {
        let circle: Text = if monitor.circleStyle == .colored {
            Text(statusEmoji)
                .font(.system(size: monitor.menuBarCircleSize))
        } else {
            Text("●")
                .font(.system(size: monitor.menuBarCircleSize, weight: .bold, design: .rounded))
        }
        let time = Text(monitor.menuBarStatusText)
            .font(.system(size: monitor.menuBarTextSize, weight: .medium, design: .monospaced))

        return switch monitor.menuBarMode {
        case .circle: circle
        case .circleAndTime: circle + Text(" ") + time
        case .time: time
        }
    }

    private var statusEmoji: String {
        switch monitor.level {
        case .green: "🟢"
        case .yellow: "🟡"
        case .red: "🔴"
        }
    }
}

private struct PingMenu: View {
    private enum Page {
        case status
        case settings
    }

    private static let panelWidth = 420.0

    @ObservedObject var monitor: PingMonitor
    @State private var page = Page.status

    var body: some View {
        VStack(spacing: 0) {
            dragStrip
            Divider()
            statusView
                .opacity(page == .settings ? 0 : 1)
                .accessibilityHidden(page == .settings)
                .allowsHitTesting(page == .status)
                .overlay(alignment: .top) {
                    if page == .settings {
                        settingsView
                    }
                }
        }
        .frame(width: Self.panelWidth, alignment: .top)
        .background {
            if !monitor.panelTransparency {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .preferredColorScheme(monitor.appearance.colorScheme)
        .background(PanelWindowBehavior(appearance: monitor.appearance))
        .transaction { transaction in
            transaction.animation = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            page = .status
        }
        .onDisappear { page = .status }
        .onAppear { page = .status }
    }

    private var settingsView: some View {
        VStack(spacing: 0) {
            HStack {
                Button { page = .status } label: {
                    Label("Status", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
                Label("Settings", systemImage: "gearshape.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 42)
            Divider()
            SettingsView(monitor: monitor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var dragStrip: some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(.tertiary)
                .frame(width: 38, height: 4)
            Text("Drag to move")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .contentShape(Rectangle())
        .overlay(WindowDragRegion())
        .help("Drag to move PingBar")
    }

    private var statusView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.primary)
                    Image(systemName: "network")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(endpointName)
                            .font(.headline)
                            .lineLimit(1)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(monitor.settings.urlString, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Copy endpoint URL")
                    }
                    Text(displayURL)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Text(healthLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.12), in: Capsule())
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PING TIME")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(monitor.statusText)
                        .font(.system(size: 29, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                lastCheckCard
            }

            statistics

            latencyChart

            if monitor.consecutiveFailures > 0 {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(statusColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(monitor.consecutiveFailures) consecutive failed request\(monitor.consecutiveFailures == 1 ? "" : "s")")
                            .font(.caption.weight(.semibold))
                        if let error = monitor.lastError {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            HStack {
                Button {
                    Task { await monitor.checkNow() }
                } label: {
                    Label("Check Now", systemImage: "arrow.clockwise")
                }
                Spacer()
                Button {
                    page = .settings
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "power")
                }
                .help("Quit PingBar")
            }
        }
        .padding(14)
        .frame(width: Self.panelWidth)
    }

    private var statistics: some View {
        HStack(spacing: 7) {
            statistic("Average", value: formattedLatency(averageLatency))
            statistic("Minimum", value: formattedLatency(minimumLatency))
            statistic("Success", value: successRate)
        }
    }

    private func statistic(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var latencyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LATENCY HISTORY")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(chartWindowText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if monitor.history.isEmpty {
                Image(systemName: "waveform.path.ecg")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 110)
            } else {
                Chart(chartPoints) { point in
                    if let latency = point.latency {
                        AreaMark(
                            x: .value("Time", point.date),
                            yStart: .value("Baseline", 0),
                            yEnd: .value("Ping", latency),
                            series: .value("Run", point.segment)
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [.green.opacity(0.22), .green.opacity(0.01)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("Ping", latency),
                            series: .value("Run", point.segment)
                        )
                        .foregroundStyle(.green)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

                        if point.id == latestSuccessfulID {
                            PointMark(
                                x: .value("Time", point.date),
                                y: .value("Ping", latency)
                            )
                            .foregroundStyle(.green)
                            .symbolSize(28)
                        }
                    } else {
                        RuleMark(x: .value("Failed", point.date))
                            .foregroundStyle(.red.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    }
                }
                .chartXAxis(.hidden)
                .chartXScale(domain: chartDomain)
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine()
                        AxisValueLabel(format: Decimal.FormatStyle().precision(.fractionLength(0)))
                    }
                }
                .frame(height: 110)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private var statusColor: Color {
        switch monitor.level {
        case .green: .green
        case .yellow: .yellow
        case .red: .red
        }
    }

    private var endpointName: String {
        URL(string: monitor.settings.urlString)?.host ?? "Invalid endpoint"
    }

    private var displayURL: String {
        monitor.settings.urlString
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }

    private var healthLabel: String {
        switch monitor.level {
        case .green: return monitor.state == .waiting ? "Waiting" : "Online"
        case .yellow: return "Degraded"
        case .red: return "Offline"
        }
    }

    private var successfulLatencies: [Double] {
        monitor.history.compactMap(\.latency)
    }

    private var averageLatency: Double? {
        guard !successfulLatencies.isEmpty else { return nil }
        return successfulLatencies.reduce(0, +) / Double(successfulLatencies.count)
    }

    private var minimumLatency: Double? { successfulLatencies.min() }

    private var successRate: String {
        guard !monitor.history.isEmpty else { return "--" }
        let value = Double(successfulLatencies.count) / Double(monitor.history.count) * 100
        return String(format: "%.0f%%", value)
    }

    private func formattedLatency(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f ms", value)
    }

    private var chartDomain: ClosedRange<Date> {
        let end = Date.now
        return end.addingTimeInterval(-monitor.settings.chartWindow)...end
    }

    private var chartWindowText: String {
        let seconds = monitor.settings.chartWindow
        if seconds >= 3_600 { return "Last \(Int(seconds / 3_600))h" }
        if seconds >= 60 { return "Last \(Int(seconds / 60))m" }
        return "Last \(Int(seconds))s"
    }

    private var lastCheckCard: some View {
        HStack(spacing: 7) {
            Image(systemName: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("LAST CHECK")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(lastCheckText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .frame(width: 72, alignment: .leading)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    private var chartPoints: [ChartPoint] {
        var segment = 0
        return monitor.history.map { sample in
            let point = ChartPoint(sample: sample, segment: segment)
            if sample.latency == nil { segment += 1 }
            return point
        }
    }

    private var latestSuccessfulID: UUID? {
        monitor.history.last(where: { $0.latency != nil })?.id
    }

    private var lastCheckText: String {
        guard let date = monitor.lastCheckedAt else { return "--:--:--" }
        return Self.lastCheckFormatter.string(from: date)
    }

    private static let lastCheckFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DraggingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DraggingView: NSView {
        override var acceptsFirstResponder: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            window.performDrag(with: event)
            PanelPlacement.constrain(window)
            PanelPlacement.save(window)
        }
    }
}

private struct PanelWindowBehavior: NSViewRepresentable {
    let appearance: AppAppearance

    func makeNSView(context: Context) -> NSView {
        let view = PanelBehaviorView()
        view.apply(appearance)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? PanelBehaviorView)?.apply(appearance)
    }

    private final class PanelBehaviorView: NSView {
        private var isObservingScreenChanges = false
        private var selectedAppearance = AppAppearance.system

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.isMovable = true
            apply(selectedAppearance)

            if window != nil, !isObservingScreenChanges {
                window?.alphaValue = 0
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(screenParametersDidChange),
                    name: NSApplication.didChangeScreenParametersNotification,
                    object: nil
                )
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(revealWindow),
                    name: NSWindow.didBecomeKeyNotification,
                    object: window
                )
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(hideWindow),
                    name: NSWindow.didResignKeyNotification,
                    object: window
                )
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowDidResize),
                    name: NSWindow.didResizeNotification,
                    object: window
                )
                isObservingScreenChanges = true
                restoreWindowPosition()
                if window?.isKeyWindow == true {
                    window?.alphaValue = 1
                }
            } else if window == nil, isObservingScreenChanges {
                NotificationCenter.default.removeObserver(self)
                isObservingScreenChanges = false
            }
        }

        func apply(_ appearance: AppAppearance) {
            selectedAppearance = appearance
            window?.appearance = switch appearance {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }

        @objc private func screenParametersDidChange() {
            restoreWindowPosition()
        }

        @objc private func revealWindow() {
            restoreWindowPosition()
            window?.alphaValue = 1
        }

        @objc private func hideWindow() {
            window?.alphaValue = 0
        }

        @objc private func windowDidResize() {
            restoreWindowPosition()
        }

        @objc private func restoreWindowPosition() {
            guard let window else { return }
            if PanelPlacement.hasSavedPosition {
                PanelPlacement.restore(window)
            } else {
                PanelPlacement.constrain(window)
            }
        }
    }
}

@MainActor
private enum PanelPlacement {
    static var hasSavedPosition: Bool {
        let defaults = UserDefaults.standard
        let hasTopLeft = defaults.object(forKey: PingSettings.Keys.panelPositionX) != nil
            && defaults.object(forKey: PingSettings.Keys.panelPositionTop) != nil
        let hasLegacyOrigin = defaults.object(forKey: PingSettings.Keys.panelOriginX) != nil
            && defaults.object(forKey: PingSettings.Keys.panelOriginY) != nil
        return hasTopLeft || hasLegacyOrigin
    }

    static func save(_ window: NSWindow) {
        let defaults = UserDefaults.standard
        defaults.set(window.frame.minX, forKey: PingSettings.Keys.panelPositionX)
        defaults.set(window.frame.maxY, forKey: PingSettings.Keys.panelPositionTop)
        defaults.removeObject(forKey: PingSettings.Keys.panelOriginX)
        defaults.removeObject(forKey: PingSettings.Keys.panelOriginY)
    }

    static func restore(_ window: NSWindow) {
        guard let topLeft = savedTopLeft(for: window) else { return }
        var frame = window.frame
        frame.origin = NSPoint(x: topLeft.x, y: topLeft.y - frame.height)
        window.setFrame(constrained(frame, for: window), display: true, animate: false)
        save(window)
    }

    static func constrain(_ window: NSWindow) {
        let frame = constrained(window.frame, for: window)
        if frame != window.frame {
            window.setFrame(frame, display: true, animate: false)
        }
    }

    private static func savedTopLeft(for window: NSWindow) -> NSPoint? {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: PingSettings.Keys.panelPositionX) != nil,
           defaults.object(forKey: PingSettings.Keys.panelPositionTop) != nil {
            return NSPoint(
                x: defaults.double(forKey: PingSettings.Keys.panelPositionX),
                y: defaults.double(forKey: PingSettings.Keys.panelPositionTop)
            )
        }

        guard defaults.object(forKey: PingSettings.Keys.panelOriginX) != nil,
              defaults.object(forKey: PingSettings.Keys.panelOriginY) != nil else {
            return nil
        }
        return NSPoint(
            x: defaults.double(forKey: PingSettings.Keys.panelOriginX),
            y: defaults.double(forKey: PingSettings.Keys.panelOriginY) + window.frame.height
        )
    }

    private static func constrained(_ frame: NSRect, for window: NSWindow) -> NSRect {
        let topLeft = NSPoint(x: frame.minX, y: frame.maxY - 1)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(topLeft) })
            ?? window.screen
            ?? NSScreen.main
        guard let screen else { return frame }

        var result = frame
        let safeFrame = screen.visibleFrame
        let maximumY = min(safeFrame.maxY, screen.frame.maxY - NSStatusBar.system.thickness)
        result.origin.x = min(max(result.minX, safeFrame.minX), safeFrame.maxX - result.width)
        result.origin.y = min(max(result.minY, safeFrame.minY), maximumY - result.height)
        return result
    }
}

private struct ChartPoint: Identifiable {
    let id: UUID
    let date: Date
    let latency: Double?
    let segment: Int

    init(sample: PingSample, segment: Int) {
        id = sample.id
        date = sample.date
        latency = sample.latency
        self.segment = segment
    }
}
