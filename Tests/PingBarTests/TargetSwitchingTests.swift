import Foundation
@testable import PingBarKit
import Testing

@MainActor
struct TargetSwitchingTests {
    @Test func switchingTypeClearsResultsOfThePreviousTarget() async throws {
        let defaults = try makeDefaults()
        let monitor = PingMonitor(
            client: StubClient(results: [.failure(URLError(.timedOut)), .failure(URLError(.timedOut))]),
            locationClient: UnavailableLocation(),
            defaults: defaults
        )
        await monitor.checkNow()
        await monitor.checkNow()
        #expect(monitor.consecutiveFailures == 2)
        #expect(monitor.history.count == 2)

        monitor.updateSettings { $0.targetType = .icmp }

        #expect(monitor.target == PingTarget(type: .icmp, address: PingSettings.defaultPingHost))
        #expect(monitor.state == .waiting)
        #expect(monitor.consecutiveFailures == 0)
        #expect(monitor.lastError == nil)
        #expect(monitor.latencyMilliseconds == nil)
        #expect(monitor.history.isEmpty)
        #expect(defaults.string(forKey: PingSettings.Keys.targetType) == TargetType.icmp.rawValue)
    }

    @Test func inFlightResultForThePreviousTargetIsDiscarded() async throws {
        let defaults = try makeDefaults()
        let client = DelayedClient(responses: [
            (delay: .milliseconds(150), response: PingResponse(statusCode: 200, duration: 0.5))
        ])
        let monitor = PingMonitor(client: client, locationClient: UnavailableLocation(), defaults: defaults)

        let httpCheck = Task { await monitor.checkNow() }
        try await Task.sleep(for: .milliseconds(20))
        monitor.updateSettings { $0.targetType = .icmp }
        await httpCheck.value

        #expect(monitor.state == .waiting)
        #expect(monitor.latencyMilliseconds == nil)
        #expect(monitor.history.isEmpty)
    }

    @Test func runningMonitorChecksTheNewTargetImmediately() async throws {
        let defaults = try makeDefaults()
        // A long interval proves the new target is checked because of the
        // switch, not because the next scheduled check came around.
        defaults.set(60.0, forKey: PingSettings.Keys.interval)
        let client = StubClient(results: [
            .success(PingResponse(statusCode: 200, duration: 0.05)),
            .success(PingResponse(statusCode: 0, duration: 0.002)),
            .success(PingResponse(statusCode: 200, duration: 0.04))
        ])
        let monitor = PingMonitor(client: client, locationClient: UnavailableLocation(), defaults: defaults)
        monitor.start()
        defer { monitor.stop() }

        try await waitUntil { await client.receivedTargets.count == 1 }
        #expect(await client.receivedTargets.last?.type == .http)

        monitor.updateSettings { $0.targetType = .icmp }
        try await waitUntil { monitor.state == .healthy }
        #expect(await client.receivedTargets.last == PingTarget(type: .icmp, address: PingSettings.defaultPingHost))
        #expect(monitor.latencyMilliseconds == 2)
        #expect(monitor.history.count == 1)

        monitor.updateSettings { $0.targetType = .http }
        #expect(monitor.state == .waiting)
        try await waitUntil { monitor.state == .healthy }
        #expect(await client.receivedTargets.last == PingTarget(type: .http, address: PingSettings.defaultURL))
        #expect(monitor.latencyMilliseconds == 40)
        #expect(monitor.history.count == 1)
    }

    @Test func editingTheAddressRestartsWithTheNewAddress() async throws {
        let defaults = try makeDefaults()
        defaults.set(60.0, forKey: PingSettings.Keys.interval)
        let client = StubClient(results: Array(repeating: .success(PingResponse(statusCode: 200, duration: 0.01)), count: 3))
        let monitor = PingMonitor(client: client, locationClient: UnavailableLocation(), defaults: defaults)
        monitor.start()
        defer { monitor.stop() }
        try await waitUntil { await client.receivedTargets.count == 1 }

        monitor.updateSettings { $0.urlString = "https://example.com/health " }

        #expect(monitor.history.isEmpty)
        try await waitUntil { await client.receivedTargets.count == 2 }
        #expect(await client.receivedTargets.last == PingTarget(type: .http, address: "https://example.com/health"))
    }

    @Test func invalidTargetReportsAReadableError() async throws {
        let defaults = try makeDefaults()
        let client = StubClient(results: [])
        let monitor = PingMonitor(client: client, locationClient: UnavailableLocation(), defaults: defaults)

        monitor.updateSettings {
            $0.targetType = .icmp
            $0.pingHost = "bad host"
        }
        await monitor.checkNow()

        #expect(monitor.state == .failing)
        #expect(monitor.lastError == "Enter an IP address or hostname")
        #expect(await client.receivedTargets.isEmpty)
    }

    @Test func icmpIgnoresTheHTTPStatusRange() async throws {
        let defaults = try makeDefaults()
        defaults.set(TargetType.icmp.rawValue, forKey: PingSettings.Keys.targetType)
        let monitor = PingMonitor(
            client: StubClient(results: [.success(PingResponse(statusCode: 0, duration: 0.004))]),
            locationClient: UnavailableLocation(),
            defaults: defaults
        )

        await monitor.checkNow()

        #expect(monitor.state == .healthy)
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        _ condition: @MainActor () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while await !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Condition not met within \(timeout)")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

struct UnavailableLocation: PublicIPLocationClient {
    func locate() async throws -> PublicIPLocation {
        throw URLError(.notConnectedToInternet)
    }
}
