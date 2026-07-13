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

    private let client: any PingClient
    private let defaults: UserDefaults
    private var loopTask: Task<Void, Never>?
    private var checkTask: Task<PingResponse, Error>?

    init(client: any PingClient = HTTPPingClient(), defaults: UserDefaults = .standard) {
        let settings = PingSettings.load(from: defaults)
        self.client = client
        self.defaults = defaults
        menuBarMode = MenuBarDisplayMode(rawValue: settings.menuBarMode) ?? .circleAndTime
        menuBarTextSize = settings.menuBarTextSize
        menuBarCircleSize = settings.menuBarCircleSize
        circleStyle = CircleStyle(rawValue: settings.circleStyle) ?? .colored
    }

    var settings: PingSettings { PingSettings.load(from: defaults) }

    var level: StatusLevel {
        if consecutiveFailures >= settings.redFailures { return .red }
        if consecutiveFailures >= settings.yellowFailures { return .yellow }
        return .green
    }

    var statusText: String {
        guard let latencyMilliseconds else { return "-- ms" }
        return String(format: "%.3f ms", latencyMilliseconds)
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
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        checkTask?.cancel()
        checkTask = nil
    }

    func checkNow() async {
        checkTask?.cancel()
        let task = Task { [client, settings] in
            guard let url = Self.validURL(from: settings.urlString) else {
                throw URLError(.badURL)
            }
            return try await client.ping(url: url, timeout: max(settings.timeout, 0.1))
        }
        checkTask = task

        do {
            let response = try await task.value
            lastCheckedAt = .now
            guard settings.minimumStatus...settings.maximumStatus ~= response.statusCode else {
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

    private static func validURL(from string: String) -> URL? {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
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
