import Combine
import Foundation

/// Runs the periodic availability checks and owns the live settings.
///
/// Results are tied to the target they were measured against: whenever the
/// target changes, in-flight work is cancelled, previous results are cleared
/// and the new target is checked straight away.
@MainActor
public final class PingMonitor: ObservableObject {
    public enum State: Equatable {
        case waiting
        case healthy
        case failing
    }

    @Published public private(set) var settings: PingSettings
    @Published public private(set) var state = State.waiting
    @Published public private(set) var latencyMilliseconds: Double?
    @Published public private(set) var consecutiveFailures = 0
    @Published public private(set) var lastError: String?
    @Published public private(set) var history: [PingSample] = []
    @Published public private(set) var lastCheckedAt: Date?
    @Published public private(set) var publicIPLocation: PublicIPLocation?
    @Published public private(set) var publicIPLookupFailed = false

    /// How long address edits settle before the new address is checked, so
    /// typing a URL does not send a request for every keystroke.
    public static let addressEditDelay = Duration.milliseconds(600)

    private let client: any PingClient
    private let locationClient: any PublicIPLocationClient
    private let defaults: UserDefaults
    private var isRunning = false
    private var checkLoop: Task<Void, Never>?
    private var locationLoop: Task<Void, Never>?
    /// Incremented whenever earlier checks become irrelevant; a check only
    /// records its outcome if the generation it started with is still current.
    private var checkGeneration = 0

    public init(
        client: any PingClient = RouterPingClient(),
        locationClient: any PublicIPLocationClient = IPLocationService(),
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.locationClient = locationClient
        self.defaults = defaults
        settings = PingSettings.load(from: defaults)
    }

    // MARK: - Derived state

    public var target: PingTarget { settings.target }

    public var level: StatusLevel {
        StatusLevel(consecutiveFailures: consecutiveFailures, settings: settings)
    }

    public var statusText: String {
        LatencyFormatter.display(milliseconds: latencyMilliseconds)
    }

    public var menuBarStatusText: String {
        LatencyFormatter.compact(milliseconds: latencyMilliseconds)
    }

    // MARK: - Settings

    /// Applies, persists and reacts to new settings. Values are normalized
    /// first, so callers can pass raw user input.
    public func updateSettings(_ newValue: PingSettings) {
        let updated = newValue.normalized()
        let previous = settings
        guard updated != previous else { return }
        settings = updated
        updated.save(to: defaults, changedFrom: previous)
        settingsDidChange(from: previous, to: updated)
    }

    public func updateSettings(_ change: (inout PingSettings) -> Void) {
        var copy = settings
        change(&copy)
        updateSettings(copy)
    }

    public func restoreDefaultSettings() {
        PingSettings.removeAll(from: defaults)
        let previous = settings
        settings = PingSettings.load(from: defaults)
        settingsDidChange(from: previous, to: settings)
    }

    private func settingsDidChange(from previous: PingSettings, to current: PingSettings) {
        if current.target != previous.target {
            resetResults()
            let typeChanged = current.targetType != previous.targetType
            restartChecks(after: typeChanged ? .zero : Self.addressEditDelay)
        } else if current.interval != previous.interval {
            restartChecks(after: .seconds(current.interval))
        }

        if current.chartWindow != previous.chartWindow {
            trimHistory()
        }

        if current.locationRefresh != previous.locationRefresh {
            restartLocationUpdates(after: publicIPLocation == nil ? .zero : .seconds(current.locationRefresh))
        }
    }

    // MARK: - Lifecycle

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        restartChecks(after: .zero)
        restartLocationUpdates(after: .zero)
    }

    public func stop() {
        isRunning = false
        checkGeneration += 1
        checkLoop?.cancel()
        checkLoop = nil
        locationLoop?.cancel()
        locationLoop = nil
    }

    private func restartChecks(after delay: Duration) {
        checkGeneration += 1
        checkLoop?.cancel()
        checkLoop = nil
        guard isRunning else { return }
        checkLoop = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                while true {
                    guard let self else { return }
                    await self.checkNow()
                    let interval = Duration.seconds(self.settings.interval)
                    try await Task.sleep(for: interval, tolerance: Self.wakeTolerance(for: interval))
                }
            } catch {
                // Cancelled: a newer loop replaced this one, or monitoring stopped.
            }
        }
    }

    private func restartLocationUpdates(after delay: Duration) {
        locationLoop?.cancel()
        locationLoop = nil
        guard isRunning else { return }
        locationLoop = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                while true {
                    guard let self else { return }
                    await self.refreshLocation()
                    let interval = Duration.seconds(self.settings.locationRefresh)
                    try await Task.sleep(for: interval, tolerance: Self.wakeTolerance(for: interval))
                }
            } catch {
                // Cancelled: the interval changed or monitoring stopped.
            }
        }
    }

    /// Lets the system coalesce periodic wake-ups with other timers: 10% of
    /// the interval, capped at 5 s, which is invisible in the chart.
    nonisolated static func wakeTolerance(for interval: Duration) -> Duration {
        min(interval / 10, .seconds(5))
    }

    // MARK: - Checks

    /// Checks the current target once and records the outcome, unless the
    /// target changed or a newer check started while this one was running.
    public func checkNow() async {
        checkGeneration += 1
        let generation = checkGeneration
        let target = settings.target
        let timeout = settings.timeout
        let range = settings.minimumStatus...settings.maximumStatus

        let outcome: Result<PingResponse, any Error>
        do {
            guard PingSettings.isValid(target) else { throw PingError.invalidTarget(target.type) }
            outcome = try await .success(client.ping(target: target, timeout: timeout))
        } catch {
            outcome = .failure(error)
        }

        guard generation == checkGeneration, !Task.isCancelled else { return }
        lastCheckedAt = .now
        switch outcome {
        case .success(let response) where target.type == .http && !range.contains(response.statusCode):
            recordFailure("HTTP status \(response.statusCode)")
        case .success(let response):
            recordSuccess(latencyMilliseconds: response.duration * 1_000)
        case .failure(let error):
            recordFailure(error.localizedDescription)
        }
    }

    private func recordSuccess(latencyMilliseconds latency: Double) {
        state = .healthy
        latencyMilliseconds = latency
        consecutiveFailures = 0
        lastError = nil
        appendSample(latency: latency)
    }

    private func recordFailure(_ message: String) {
        state = .failing
        latencyMilliseconds = nil
        consecutiveFailures += 1
        lastError = message
        appendSample(latency: nil)
    }

    private func resetResults() {
        checkGeneration += 1
        state = .waiting
        latencyMilliseconds = nil
        consecutiveFailures = 0
        lastError = nil
        history = []
        lastCheckedAt = nil
    }

    private func appendSample(latency: Double?) {
        history.append(PingSample(date: .now, latency: latency))
        trimHistory()
    }

    private func trimHistory() {
        let cutoff = Date.now.addingTimeInterval(-settings.chartWindow)
        history.removeAll { $0.date < cutoff }
    }

    // MARK: - Public IP

    private func refreshLocation() async {
        do {
            let location = try await locationClient.locate()
            guard !Task.isCancelled else { return }
            publicIPLocation = location
            publicIPLookupFailed = false
        } catch {
            guard !Task.isCancelled else { return }
            // Keep the last known location during temporary provider or
            // network failures; only report a failure when nothing is known.
            publicIPLookupFailed = publicIPLocation == nil
        }
    }
}

public enum StatusLevel: Equatable, Sendable {
    case green
    case yellow
    case red

    public init(consecutiveFailures: Int, settings: PingSettings) {
        if consecutiveFailures >= settings.redFailures {
            self = .red
        } else if consecutiveFailures >= settings.yellowFailures {
            self = .yellow
        } else {
            self = .green
        }
    }
}

public struct PingSample: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let date: Date
    public let latency: Double?

    public init(date: Date, latency: Double?) {
        self.date = date
        self.latency = latency
    }
}

/// Formats latency for the dashboard and the fixed-width menu-bar label.
public enum LatencyFormatter {
    /// Always six characters wide so the menu-bar item never changes width.
    public static func compact(milliseconds: Double?) -> String {
        guard let milliseconds, milliseconds.isFinite, milliseconds >= 0 else { return " -- ms" }

        let roundedMilliseconds = milliseconds.rounded()
        if roundedMilliseconds < 1_000 {
            return String(format: "%03.0f ms", roundedMilliseconds)
        }

        let seconds = milliseconds / 1_000
        if seconds < 10 { return String(format: "%.2f s", seconds) }
        if seconds < 100 { return String(format: "%.1f s", seconds) }
        if seconds < 9_999.5 {
            let text = String(format: "%.0f s", seconds)
            return String(repeating: " ", count: 6 - text.count) + text
        }
        return "9999+s"
    }

    public static func display(milliseconds: Double?) -> String {
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
}
