import Combine
import Foundation

@MainActor
final class PingMonitor: ObservableObject {
    enum State: Equatable {
        case waiting
        case healthy
        case failing
    }

    @Published private(set) var state = State.waiting
    @Published private(set) var latencyMilliseconds: Double?
    @Published private(set) var consecutiveFailures = 0
    @Published private(set) var lastError: String?
    @Published private(set) var history: [PingSample] = []
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var menuBarMode: MenuBarDisplayMode
    @Published private(set) var menuBarTextSize: Double
    @Published private(set) var menuBarCircleSize: Double
    @Published private(set) var circleStyle: CircleStyle
    @Published private(set) var panelTransparency: Bool
    @Published private(set) var appearance: AppAppearance
    @Published private(set) var alwaysOnTop: Bool
    @Published private(set) var publicIPLocation: PublicIPLocation?
    @Published private(set) var publicIPLookupFailed = false
    @Published private var cachedSettings: PingSettings

    private let client: any PingClient
    private let locationClient: any PublicIPLocationClient
    private let defaults: UserDefaults
    private var loopTask: Task<Void, Never>?
    private var locationTask: Task<Void, Never>?
    private var checkTask: Task<PingResponse, Error>?
    private var activeCheckID: UUID?

    init(
        client: any PingClient = RouterPingClient(),
        locationClient: any PublicIPLocationClient = IPLocationService(),
        defaults: UserDefaults = .standard
    ) {
        let settings = PingSettings.load(from: defaults)
        self.client = client
        self.locationClient = locationClient
        self.defaults = defaults
        cachedSettings = settings
        menuBarMode = MenuBarDisplayMode(rawValue: settings.menuBarMode) ?? .circleAndTime
        menuBarTextSize = settings.menuBarTextSize
        menuBarCircleSize = settings.menuBarCircleSize
        circleStyle = CircleStyle(rawValue: settings.circleStyle) ?? .colored
        panelTransparency = settings.panelTransparency
        appearance = AppAppearance(rawValue: settings.appearance) ?? .system
        alwaysOnTop = settings.alwaysOnTop
    }

    var settings: PingSettings { cachedSettings }

    var target: PingTarget {
        let whitespace = CharacterSet.whitespacesAndNewlines
        if cachedSettings.targetType == TargetType.icmp.rawValue {
            return PingTarget(type: .icmp, address: cachedSettings.pingHost.trimmingCharacters(in: whitespace))
        }
        return PingTarget(type: .http, address: cachedSettings.urlString.trimmingCharacters(in: whitespace))
    }

    var level: StatusLevel {
        if consecutiveFailures >= settings.redFailures { return .red }
        if consecutiveFailures >= settings.yellowFailures { return .yellow }
        return .green
    }

    var statusText: String {
        Self.displayLatencyText(milliseconds: latencyMilliseconds)
    }

    var menuBarStatusText: String {
        Self.compactLatencyText(milliseconds: latencyMilliseconds)
    }

    static func compactLatencyText(milliseconds: Double?) -> String {
        guard let milliseconds, milliseconds.isFinite, milliseconds >= 0 else { return " -- ms" }

        let roundedMilliseconds = milliseconds.rounded()
        if roundedMilliseconds < 1_000 {
            return String(format: "%03.0f ms", roundedMilliseconds)
        }

        let seconds = milliseconds / 1_000
        if seconds < 10 {
            return String(format: "%.2f s", seconds)
        }
        if seconds < 100 {
            return String(format: "%.1f s", seconds)
        }
        if seconds < 9_999.5 {
            let text = String(format: "%.0f s", seconds)
            return String(repeating: " ", count: 6 - text.count) + text
        }
        return "9999+s"
    }

    static func displayLatencyText(milliseconds: Double?) -> String {
        guard let milliseconds, milliseconds.isFinite, milliseconds >= 0 else { return "-- ms" }
        if milliseconds < 1 { return "<1 ms" }

        let roundedMilliseconds = milliseconds.rounded()
        if roundedMilliseconds < 1_000 {
            return String(format: "%.0f ms", roundedMilliseconds)
        }

        let seconds = milliseconds / 1_000
        if seconds < 10 { return String(format: "%.2f s", seconds) }
        if seconds < 100 { return String(format: "%.1f s", seconds) }
        return String(format: "%.0f s", seconds)
    }

    func setMenuBarMode(_ rawValue: String) {
        let mode = MenuBarDisplayMode(rawValue: rawValue) ?? .circleAndTime
        menuBarMode = mode
        defaults.set(mode.rawValue, forKey: PingSettings.Keys.menuBarMode)
    }

    func setMenuBarTextSize(_ value: Double) {
        menuBarTextSize = min(max(value.rounded(), 8), 16)
        defaults.set(menuBarTextSize, forKey: PingSettings.Keys.menuBarTextSize)
    }

    func setMenuBarCircleSize(_ value: Double) {
        menuBarCircleSize = min(max(value.rounded(), 5), 14)
        defaults.set(menuBarCircleSize, forKey: PingSettings.Keys.menuBarCircleSize)
    }

    func setCircleStyle(_ rawValue: String) {
        let style = CircleStyle(rawValue: rawValue) ?? .colored
        circleStyle = style
        defaults.set(style.rawValue, forKey: PingSettings.Keys.circleStyle)
    }

    func setPanelTransparency(_ value: Bool) {
        panelTransparency = value
        defaults.set(value, forKey: PingSettings.Keys.panelTransparency)
    }

    func setAppearance(_ rawValue: String) {
        let value = AppAppearance(rawValue: rawValue) ?? .system
        appearance = value
        defaults.set(value.rawValue, forKey: PingSettings.Keys.appearance)
    }

    func setAlwaysOnTop(_ value: Bool) {
        alwaysOnTop = value
        defaults.set(value, forKey: PingSettings.Keys.alwaysOnTop)
    }

    func refreshSettings() {
        let updatedSettings = PingSettings.load(from: defaults)
        if updatedSettings != cachedSettings {
            cachedSettings = updatedSettings
        }
    }

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.checkNow()
                let delay = max(self.settings.interval, 0.1)
                try? await Task.sleep(for: .seconds(delay))
            }
        }
        startLocationUpdates()
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        locationTask?.cancel()
        locationTask = nil
        checkTask?.cancel()
        checkTask = nil
        activeCheckID = nil
    }

    private func startLocationUpdates() {
        guard locationTask == nil else { return }
        locationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let location = try await self.locationClient.locate()
                    guard !Task.isCancelled else { return }
                    self.publicIPLocation = location
                    self.publicIPLookupFailed = false
                } catch is CancellationError {
                    return
                } catch {
                    // Keep the last known location during temporary provider
                    // or network failures; retry at a deliberately low rate.
                    self.publicIPLookupFailed = self.publicIPLocation == nil
                }
                try? await Task.sleep(for: .seconds(900))
            }
        }
    }

    func checkNow() async {
        refreshSettings()
        checkTask?.cancel()

        let target = self.target
        let settings = self.settings
        let checkID = UUID()
        activeCheckID = checkID
        let task = Task { [client, target, settings] in
            guard Self.isValidTarget(target) else {
                throw URLError(.badURL)
            }
            return try await client.ping(target: target, timeout: max(settings.timeout, 0.1))
        }
        checkTask = task

        do {
            let response = try await task.value
            guard activeCheckID == checkID, !task.isCancelled else { return }
            checkTask = nil
            activeCheckID = nil
            lastCheckedAt = .now
            if target.type == .http,
               !(settings.minimumStatus...settings.maximumStatus ~= response.statusCode) {
                recordFailure("HTTP status \(response.statusCode)")
                return
            }
            state = .healthy
            latencyMilliseconds = response.duration * 1_000
            consecutiveFailures = 0
            lastError = nil
            appendSample(latency: response.duration * 1_000)
        } catch is CancellationError {
            return
        } catch {
            guard activeCheckID == checkID else { return }
            checkTask = nil
            activeCheckID = nil
            lastCheckedAt = .now
            recordFailure(error.localizedDescription)
        }
    }

    private func recordFailure(_ message: String) {
        state = .failing
        latencyMilliseconds = nil
        consecutiveFailures += 1
        lastError = message
        appendSample(latency: nil)
    }

    private func appendSample(latency: Double?) {
        history.append(PingSample(date: .now, latency: latency))
        let cutoff = Date.now.addingTimeInterval(-max(settings.chartWindow, 60))
        history.removeAll { $0.date < cutoff }
    }

    private static func isValidTarget(_ target: PingTarget) -> Bool {
        switch target.type {
        case .http: PingSettings.isValidHTTPURL(target.address)
        case .icmp: PingSettings.isValidPingHost(target.address)
        }
    }
}

enum StatusLevel: Equatable {
    case green
    case yellow
    case red
}

struct PingSample: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let latency: Double?
}
