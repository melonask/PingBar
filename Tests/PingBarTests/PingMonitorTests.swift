import Foundation
@testable import PingBarKit
import Testing

@MainActor
struct PingMonitorTests {
    @Test func defaultEndpointIsChessDotCom() throws {
        let defaults = try makeDefaults()

        #expect(PingSettings.load(from: defaults).urlString == "https://www.chess.com")
    }

    @Test func previousDefaultEndpointMigratesButCustomEndpointDoesNot() throws {
        let oldDefaults = try makeDefaults()
        oldDefaults.set("https://fast.com", forKey: PingSettings.Keys.url)
        #expect(PingSettings.load(from: oldDefaults).urlString == "https://www.chess.com")
        #expect(oldDefaults.string(forKey: PingSettings.Keys.url) == "https://www.chess.com")

        let customDefaults = try makeDefaults()
        customDefaults.set("https://example.com/health", forKey: PingSettings.Keys.url)
        #expect(PingSettings.load(from: customDefaults).urlString == "https://example.com/health")
    }

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
        #expect(monitor.statusText == "24 ms")
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

    @Test func dashboardLatencyAvoidsFalsePrecision() {
        #expect(PingMonitor.displayLatencyText(milliseconds: nil) == "-- ms")
        #expect(PingMonitor.displayLatencyText(milliseconds: 0.42) == "<1 ms")
        #expect(PingMonitor.displayLatencyText(milliseconds: 24.33) == "24 ms")
        #expect(PingMonitor.displayLatencyText(milliseconds: 902.032) == "902 ms")
        #expect(PingMonitor.displayLatencyText(milliseconds: 999.6) == "1.00 s")
        #expect(PingMonitor.displayLatencyText(milliseconds: 12_345) == "12.3 s")
    }

    @Test func thresholdsControlYellowAndRedLevels() async throws {
        let defaults = try makeDefaults()
        defaults.set(2, forKey: PingSettings.Keys.yellowFailures)
        defaults.set(4, forKey: PingSettings.Keys.redFailures)
        let monitor = PingMonitor(
            client: StubClient(results: Array(
                repeating: .failure(URLError(.cannotConnectToHost)),
                count: 4
            )),
            defaults: defaults
        )

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

    @Test func supersededCheckCannotOverwriteNewerResult() async throws {
        let defaults = try makeDefaults()
        let client = DelayedClient(responses: [
            (delay: .milliseconds(100), response: PingResponse(statusCode: 200, duration: 0.5)),
            (delay: .zero, response: PingResponse(statusCode: 200, duration: 0.02))
        ])
        let monitor = PingMonitor(client: client, defaults: defaults)

        let olderCheck = Task { await monitor.checkNow() }
        try await Task.sleep(for: .milliseconds(10))
        await monitor.checkNow()
        await olderCheck.value

        #expect(monitor.latencyMilliseconds == 20)
        #expect(monitor.history.count == 1)
    }

    @Test func menuBarAppearanceUpdatesImmediatelyAndPersists() throws {
        let defaults = try makeDefaults()
        let monitor = PingMonitor(client: StubClient(results: []), defaults: defaults)

        monitor.setMenuBarMode(MenuBarDisplayMode.time.rawValue)
        monitor.setMenuBarTextSize(13)
        monitor.setMenuBarCircleSize(11)
        monitor.setCircleStyle(CircleStyle.monochrome.rawValue)
        monitor.setPanelTransparency(false)
        monitor.setAppearance(AppAppearance.dark.rawValue)

        #expect(monitor.menuBarMode == .time)
        #expect(monitor.menuBarTextSize == 13)
        #expect(monitor.menuBarCircleSize == 11)
        #expect(monitor.circleStyle == .monochrome)
        #expect(!monitor.panelTransparency)
        #expect(monitor.appearance == .dark)
        #expect(defaults.string(forKey: PingSettings.Keys.menuBarMode) == MenuBarDisplayMode.time.rawValue)
        #expect(defaults.string(forKey: PingSettings.Keys.circleStyle) == CircleStyle.monochrome.rawValue)
        #expect(!defaults.bool(forKey: PingSettings.Keys.panelTransparency))
        #expect(defaults.string(forKey: PingSettings.Keys.appearance) == AppAppearance.dark.rawValue)
    }

    @Test func panelTransparencyDefaultsToEnabled() throws {
        let defaults = try makeDefaults()
        let monitor = PingMonitor(client: StubClient(results: []), defaults: defaults)

        #expect(monitor.panelTransparency)
        #expect(monitor.settings.panelTransparency)
        #expect(monitor.appearance == .system)
    }

    @Test func alwaysOnTopDefaultsToDisabledAndPersists() throws {
        let defaults = try makeDefaults()
        let monitor = PingMonitor(client: StubClient(results: []), defaults: defaults)

        #expect(!monitor.alwaysOnTop)

        monitor.setAlwaysOnTop(true)

        #expect(monitor.alwaysOnTop)
        #expect(defaults.bool(forKey: PingSettings.Keys.alwaysOnTop))
    }

    @Test func icmpPingRecordsLatencyWithoutStatusRangeCheck() async throws {
        let defaults = try makeDefaults()
        defaults.set(TargetType.icmp.rawValue, forKey: PingSettings.Keys.targetType)
        defaults.set("192.168.1.1", forKey: PingSettings.Keys.pingHost)
        let monitor = PingMonitor(client: StubClient(results: [
            .success(PingResponse(statusCode: 0, duration: 0.005))
        ]), defaults: defaults)

        await monitor.checkNow()

        #expect(monitor.state == .healthy)
        #expect(monitor.latencyMilliseconds == 5.0)
        #expect(monitor.consecutiveFailures == 0)
        #expect(monitor.lastError == nil)
    }

    @Test func icmpTargetRoutedToPingClient() async throws {
        let defaults = try makeDefaults()
        defaults.set(TargetType.icmp.rawValue, forKey: PingSettings.Keys.targetType)
        defaults.set("192.168.1.1", forKey: PingSettings.Keys.pingHost)
        let client = StubClient(results: [.success(PingResponse(statusCode: 0, duration: 0.003))])
        let monitor = PingMonitor(client: client, defaults: defaults)

        await monitor.checkNow()

        let targets = await client.receivedTargets
        #expect(targets == [PingTarget(type: .icmp, address: "192.168.1.1")])
    }

    @Test func icmpLatencyParsing() {
        let successfulOutput = """
        PING 192.168.1.1 (192.168.1.1): 56 data bytes
        64 bytes from 192.168.1.1: icmp_seq=0 ttl=64 time=1.234 ms

        --- 192.168.1.1 ping statistics ---
        1 packets transmitted, 1 packets received, 0.0% packet loss
        round-trip min/avg/max/stddev = 1.234/1.234/1.234/0.000 ms
        """
        #expect(ICMPPingClient.latencyMilliseconds(from: successfulOutput) == 1.234)
        #expect(ICMPPingClient.latencyMilliseconds(
            from: "64 bytes from 192.168.1.1: icmp_seq=0 ttl=64 time<1 ms"
        ) == 0.5)
        #expect(ICMPPingClient.latencyMilliseconds(from: "Request timeout for icmp_seq 0") == nil)
    }

    @Test func icmpUnreachableSummaryUsesLastOutputLine() {
        let output = """
        PING 192.168.1.99 (192.168.1.99): 56 data bytes

        --- 192.168.1.99 ping statistics ---
        1 packets transmitted, 0 packets received, 100.0% packet loss
        """
        #expect(ICMPPingClient.summary(of: output) == "1 packets transmitted, 0 packets received, 100.0% packet loss")
        #expect(ICMPPingClient.summary(of: "   \n  ") == nil)
    }

    @Test func targetValidation() {
        #expect(PingSettings.isValidHTTPURL("https://www.chess.com"))
        #expect(PingSettings.isValidHTTPURL("http://192.168.1.1:8080/health"))
        #expect(!PingSettings.isValidHTTPURL("192.168.1.1"))
        #expect(!PingSettings.isValidHTTPURL(""))

        #expect(PingSettings.isValidPingHost("192.168.1.1"))
        #expect(PingSettings.isValidPingHost("router.local"))
        #expect(PingSettings.isValidPingHost("fe80::1%en0"))
        #expect(!PingSettings.isValidPingHost(""))
        #expect(!PingSettings.isValidPingHost("bad host"))
        #expect(!PingSettings.isValidPingHost("https://example.com"))
    }

    @Test func routerDispatchesToMatchingClient() async throws {
        let http = SpyClient()
        let icmp = SpyClient()
        let router = RouterPingClient(http: http, icmp: icmp)

        _ = try await router.ping(target: PingTarget(type: .http, address: "https://a.example"), timeout: 1)
        _ = try await router.ping(target: PingTarget(type: .icmp, address: "192.168.1.1"), timeout: 1)

        #expect(await http.callCount == 1)
        #expect(await icmp.callCount == 1)
    }

    @Test func icmpClientPingsLocalhostEndToEnd() async throws {
        let client = ICMPPingClient()
        let response = try await client.ping(
            target: PingTarget(type: .icmp, address: "127.0.0.1"),
            timeout: 3
        )

        #expect(response.duration > 0)
        #expect(response.duration < 3)
    }

    @Test func httpClientRejectsIcmpTarget() async {
        let client = HTTPPingClient()
        await #expect(throws: PingError.self) {
            try await client.ping(
                target: PingTarget(type: .icmp, address: "127.0.0.1"),
                timeout: 1
            )
        }
    }

    @Test func publicIPProvidersParseLocations() throws {
        let ipWhoIs = Data(#"{"success":true,"ip":"203.0.113.4","latitude":"51.5","longitude":-0.12}"#.utf8)
        let first = try IPLocationService.parse(ipWhoIs, providerName: "ipwho.is")
        #expect(first == PublicIPLocation(address: "203.0.113.4", latitude: 51.5, longitude: -0.12))

        let ipInfo = Data(#"{"ip":"2001:db8::1","loc":"37.77,-122.42"}"#.utf8)
        let second = try IPLocationService.parse(ipInfo, providerName: "ipinfo.io")
        #expect(second == PublicIPLocation(address: "2001:db8::1", latitude: 37.77, longitude: -122.42))
    }

    @Test func publicIPProviderRejectsInvalidCoordinates() {
        let response = Data(#"{"success":true,"ip":"203.0.113.4","latitude":120,"longitude":0}"#.utf8)
        #expect(throws: Error.self) {
            try IPLocationService.parse(response, providerName: "ipwho.is")
        }
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
    private(set) var receivedTargets: [PingTarget] = []

    init(results: [Result<PingResponse, Error>]) {
        self.results = results
    }

    func ping(target: PingTarget, timeout: TimeInterval) async throws -> PingResponse {
        receivedTargets.append(target)
        guard !results.isEmpty else { throw URLError(.unknown) }
        return try results.removeFirst().get()
    }
}

private actor SpyClient: PingClient {
    private var count = 0

    var callCount: Int { count }

    func ping(target: PingTarget, timeout: TimeInterval) async throws -> PingResponse {
        count += 1
        return PingResponse(statusCode: 200, duration: 0.01)
    }
}

private actor DelayedClient: PingClient {
    private var responses: [(delay: Duration, response: PingResponse)]

    init(responses: [(delay: Duration, response: PingResponse)]) {
        self.responses = responses
    }

    func ping(target: PingTarget, timeout: TimeInterval) async throws -> PingResponse {
        guard !responses.isEmpty else { throw URLError(.unknown) }
        let next = responses.removeFirst()
        do {
            try await Task.sleep(for: next.delay)
        } catch is CancellationError {
            // Simulates a dependency that cannot abort its in-flight work.
        }
        return next.response
    }
}
