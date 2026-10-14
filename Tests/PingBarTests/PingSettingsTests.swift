import Foundation
@testable import PingBarKit
import Testing

@MainActor
struct PingSettingsTests {
    @Test func normalizationKeepsDependentValuesConsistent() {
        var settings = PingSettings()
        settings.yellowFailures = 8
        settings.redFailures = 3
        settings.minimumStatus = 300
        settings.maximumStatus = 250
        settings.interval = 0
        settings.timeout = -1
        settings.chartWindow = 5
        settings.menuBarTextSize = 40
        settings.menuBarCircleSize = 6.6

        let normalized = settings.normalized()

        #expect(normalized.yellowFailures == 8)
        #expect(normalized.redFailures == 9)
        #expect(normalized.minimumStatus == 300)
        #expect(normalized.maximumStatus == 300)
        #expect(normalized.interval == 0.1)
        #expect(normalized.timeout == 0.1)
        #expect(normalized.chartWindow == 60)
        #expect(normalized.menuBarTextSize == 16)
        #expect(normalized.menuBarCircleSize == 7)
    }

    @Test func normalizationBoundsThresholdsAndStatusCodes() {
        var settings = PingSettings()
        settings.yellowFailures = 5_000
        settings.redFailures = 0
        settings.minimumStatus = 42
        settings.maximumStatus = 900
        settings.timeout = .infinity

        let normalized = settings.normalized()

        #expect(normalized.yellowFailures == 999)
        #expect(normalized.redFailures == 1_000)
        #expect(normalized.minimumStatus == 100)
        #expect(normalized.maximumStatus == 599)
        #expect(normalized.timeout == 5)
    }

    @Test func monitorNormalizesEditsBeforeSavingThem() throws {
        let defaults = try makeDefaults()
        let monitor = PingMonitor(client: StubClient(results: []), defaults: defaults)

        monitor.updateSettings { $0.redFailures = 1 }

        #expect(monitor.settings.redFailures == monitor.settings.yellowFailures + 1)
        #expect(defaults.integer(forKey: PingSettings.Keys.redFailures) == monitor.settings.redFailures)
    }

    @Test func onlyChangedValuesAreWritten() throws {
        let defaults = try makeDefaults()
        let monitor = PingMonitor(client: StubClient(results: []), defaults: defaults)

        monitor.updateSettings { $0.pingHost = "10.0.0.1" }

        #expect(defaults.string(forKey: PingSettings.Keys.pingHost) == "10.0.0.1")
        #expect(defaults.object(forKey: PingSettings.Keys.url) == nil)
        #expect(defaults.object(forKey: PingSettings.Keys.interval) == nil)
    }

    @Test func restoringDefaultsRemovesStoredPreferences() throws {
        let defaults = try makeDefaults()
        let monitor = PingMonitor(client: StubClient(results: []), defaults: defaults)
        monitor.updateSettings {
            $0.targetType = .icmp
            $0.interval = 10
            $0.alwaysOnTop = true
        }

        monitor.restoreDefaultSettings()

        #expect(monitor.settings == PingSettings())
        for key in PingSettings.Keys.preferences {
            #expect(defaults.object(forKey: key) == nil)
        }
    }

    @Test func unreadableStoredValuesFallBackToDefaults() throws {
        let defaults = try makeDefaults()
        defaults.set("carrier-pigeon", forKey: PingSettings.Keys.targetType)
        defaults.set("sideways", forKey: PingSettings.Keys.menuBarMode)
        defaults.set(0, forKey: PingSettings.Keys.interval)

        let settings = PingSettings.load(from: defaults)

        #expect(settings.targetType == .http)
        #expect(settings.menuBarMode == .circleAndTime)
        #expect(settings.interval == 0.1)
    }

    @Test func storedValuesFromEarlierVersionsStillLoad() throws {
        let defaults = try makeDefaults()
        defaults.set("icmp", forKey: "targetType")
        defaults.set("10.0.0.2", forKey: "pingHost")
        defaults.set(2.5, forKey: "pingInterval")
        defaults.set(3, forKey: "yellowFailureThreshold")
        defaults.set(7, forKey: "redFailureThreshold")
        defaults.set("time", forKey: "menuBarDisplayMode")
        defaults.set("monochrome", forKey: "menuBarCircleStyle")
        defaults.set("dark", forKey: "appAppearance")
        defaults.set(false, forKey: "panelTransparency")

        let settings = PingSettings.load(from: defaults)

        #expect(settings.target == PingTarget(type: .icmp, address: "10.0.0.2"))
        #expect(settings.interval == 2.5)
        #expect(settings.yellowFailures == 3)
        #expect(settings.redFailures == 7)
        #expect(settings.menuBarMode == .time)
        #expect(settings.circleStyle == .monochrome)
        #expect(settings.appearance == .dark)
        #expect(!settings.panelTransparency)
    }

    @Test func statusLevelFollowsThresholds() {
        var settings = PingSettings()
        settings.yellowFailures = 2
        settings.redFailures = 4

        #expect(StatusLevel(consecutiveFailures: 1, settings: settings) == .green)
        #expect(StatusLevel(consecutiveFailures: 2, settings: settings) == .yellow)
        #expect(StatusLevel(consecutiveFailures: 4, settings: settings) == .red)
    }
}
