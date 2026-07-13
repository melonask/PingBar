import Foundation
import Testing
@testable import PingBar

@MainActor
struct PingMonitorTests {
    @Test func successfulPingRecordsLatencyAndResetsFailures() async throws {
        let defaults = try makeDefaults()
        let monitor = PingMonitor(client: StubClient(results: [
            .failure(URLError(.timedOut)),
            .success(PingResponse(statusCode: 204, duration: 0.02433))
        ]), defaults: defaults)

        await monitor.checkNow()
        #expect(monitor.consecutiveFailures == 1)
        await monitor.checkNow()

        #expect(monitor.state == .healthy)
        #expect(monitor.consecutiveFailures == 0)
        #expect(monitor.statusText == "24.330 ms")
        #expect(monitor.menuBarStatusText == "024 ms")
        #expect(monitor.level == .green)
    }

    @Test func compactLatencyUsesStableSixCharacterValues() {
        let values: [(Double?, String)] = [
            (nil, " -- ms"),
            (12.3456, "012 ms"),
            (123.456, "123 ms"),
            (123.556, "124 ms"),
            (999.6, "1.00 s"),
            (12_345, "12.3 s"),
            (123_456, " 123 s"),
            (10_000_000, "9999+s")
        ]

        for (milliseconds, expected) in values {
            let text = PingMonitor.compactLatencyText(milliseconds: milliseconds)
            #expect(text == expected)
            #expect(text.count == 6)
        }
    }

    @Test func thresholdsControlYellowAndRedLevels() async throws {
        let defaults = try makeDefaults()
        defaults.set(2, forKey: PingSettings.Keys.yellowFailures)
        defaults.set(4, forKey: PingSettings.Keys.redFailures)
        let monitor = PingMonitor(client: StubClient(results: Array(repeating: .failure(URLError(.cannotConnectToHost)), count: 4)), defaults: defaults)

        await monitor.checkNow()
        #expect(monitor.level == .green)
        await monitor.checkNow()
        #expect(monitor.level == .yellow)
        await monitor.checkNow()
        await monitor.checkNow()
        #expect(monitor.level == .red)
        #expect(monitor.consecutiveFailures == 4)
    }

    @Test func rejectedHTTPStatusCountsAsFailure() async throws {
        let defaults = try makeDefaults()
        let monitor = PingMonitor(client: StubClient(results: [.success(PingResponse(statusCode: 500, duration: 0.01))]), defaults: defaults)

        await monitor.checkNow()

        #expect(monitor.state == .failing)
        #expect(monitor.lastError == "HTTP status 500")
    }

    @Test func menuBarAppearanceUpdatesImmediatelyAndPersists() throws {
        let defaults = try makeDefaults()
        let monitor = PingMonitor(client: StubClient(results: []), defaults: defaults)

        monitor.setMenuBarMode(MenuBarDisplayMode.time.rawValue)
        monitor.setMenuBarTextSize(13)
        monitor.setMenuBarCircleSize(11)
        monitor.setCircleStyle(CircleStyle.monochrome.rawValue)
        monitor.setPanelTransparency(false)

        #expect(monitor.menuBarMode == .time)
        #expect(monitor.menuBarTextSize == 13)
        #expect(monitor.menuBarCircleSize == 11)
        #expect(monitor.circleStyle == .monochrome)
        #expect(!monitor.panelTransparency)
        #expect(defaults.string(forKey: PingSettings.Keys.menuBarMode) == MenuBarDisplayMode.time.rawValue)
        #expect(defaults.string(forKey: PingSettings.Keys.circleStyle) == CircleStyle.monochrome.rawValue)
        #expect(!defaults.bool(forKey: PingSettings.Keys.panelTransparency))
    }

    @Test func panelTransparencyDefaultsToEnabled() throws {
        let defaults = try makeDefaults()
        let monitor = PingMonitor(client: StubClient(results: []), defaults: defaults)

        #expect(monitor.panelTransparency)
        #expect(monitor.settings.panelTransparency)
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "PingBarTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

private actor StubClient: PingClient {
    private var results: [Result<PingResponse, Error>]

    init(results: [Result<PingResponse, Error>]) {
        self.results = results
    }

    func ping(url: URL, timeout: TimeInterval) async throws -> PingResponse {
        guard !results.isEmpty else { throw URLError(.unknown) }
        return try results.removeFirst().get()
    }
}
