import Foundation

/// Every user preference, persisted in `UserDefaults`.
///
/// `PingMonitor` owns the single live copy; views edit it through the
/// monitor so validation, persistence and side effects happen in one place.
public struct PingSettings: Equatable, Sendable {
    public static let defaultURL = "https://www.chess.com"
    private static let previousDefaultURL = "https://fast.com"
    public static let defaultPingHost = "192.168.1.1"

    public var targetType: TargetType = .http
    public var urlString: String = defaultURL
    public var pingHost: String = defaultPingHost
    public var interval: Double = 1
    public var timeout: Double = 5
    public var yellowFailures = 2
    public var redFailures = 5
    public var minimumStatus = 200
    public var maximumStatus = 399
    public var chartWindow: Double = 300
    public var locationRefresh: Double = 900
    public var menuBarMode: MenuBarDisplayMode = .circleAndTime
    public var menuBarTextSize: Double = 12
    public var menuBarCircleSize: Double = 14
    public var circleStyle: CircleStyle = .colored
    public var panelTransparency = true
    public var appearance: AppAppearance = .system
    public var alwaysOnTop = false

    public init() {}

    // MARK: - Limits

    public static let intervalRange = 0.1...86_400.0
    public static let timeoutRange = 0.1...600.0
    public static let failureThresholdRange = 1...1_000
    public static let statusCodeRange = 100...599
    public static let chartWindowRange = 60.0...86_400.0
    public static let locationRefreshRange = 60.0...3_600.0
    public static let menuBarTextSizeRange = 8.0...16.0
    public static let menuBarCircleSizeRange = 5.0...14.0

    /// Intervals offered for re-resolving the public IP address. The list is
    /// deliberately coarse: each refresh is an external lookup, so a short
    /// interval is the fastest choice rather than a free-form value.
    public static let locationRefreshOptions: [Double] = [60, 300, 900, 1_800, 3_600]

    // MARK: - Derived values

    /// The endpoint currently being monitored, with surrounding whitespace removed.
    public var target: PingTarget {
        let whitespace = CharacterSet.whitespacesAndNewlines
        return switch targetType {
        case .http: PingTarget(type: .http, address: urlString.trimmingCharacters(in: whitespace))
        case .icmp: PingTarget(type: .icmp, address: pingHost.trimmingCharacters(in: whitespace))
        }
    }

    /// A copy with every value inside its supported range.
    ///
    /// Dependent values follow the value they depend on: red always needs more
    /// failures than yellow, and the maximum accepted HTTP status can never be
    /// below the minimum. Non-finite numbers fall back to their defaults.
    public func normalized() -> PingSettings {
        let defaults = PingSettings()
        var result = self
        result.interval = Self.clamp(interval, to: Self.intervalRange, fallback: defaults.interval)
        result.timeout = Self.clamp(timeout, to: Self.timeoutRange, fallback: defaults.timeout)
        result.chartWindow = Self.clamp(chartWindow, to: Self.chartWindowRange, fallback: defaults.chartWindow)
        result.locationRefresh = Self.clamp(
            locationRefresh,
            to: Self.locationRefreshRange,
            fallback: defaults.locationRefresh
        )
        result.menuBarTextSize = Self.clamp(
            menuBarTextSize.rounded(),
            to: Self.menuBarTextSizeRange,
            fallback: defaults.menuBarTextSize
        )
        result.menuBarCircleSize = Self.clamp(
            menuBarCircleSize.rounded(),
            to: Self.menuBarCircleSizeRange,
            fallback: defaults.menuBarCircleSize
        )

        let thresholds = Self.failureThresholdRange
        result.yellowFailures = min(max(yellowFailures, thresholds.lowerBound), thresholds.upperBound - 1)
        result.redFailures = min(max(redFailures, result.yellowFailures + 1), thresholds.upperBound)

        let statuses = Self.statusCodeRange
        result.minimumStatus = min(max(minimumStatus, statuses.lowerBound), statuses.upperBound)
        result.maximumStatus = min(max(maximumStatus, result.minimumStatus), statuses.upperBound)
        return result
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    // MARK: - Persistence

    /// Reads the stored preferences. Missing or unreadable values use their
    /// defaults, and the result is always normalized.
    public static func load(from defaults: UserDefaults = .standard) -> PingSettings {
        migrateDefaultURL(in: defaults)
        let store = Store(defaults: defaults)
        var settings = PingSettings()
        settings.targetType = store.value(Keys.targetType, default: settings.targetType)
        settings.urlString = store.string(Keys.url, default: settings.urlString)
        settings.pingHost = store.string(Keys.pingHost, default: settings.pingHost)
        settings.interval = store.double(Keys.interval, default: settings.interval)
        settings.timeout = store.double(Keys.timeout, default: settings.timeout)
        settings.yellowFailures = store.integer(Keys.yellowFailures, default: settings.yellowFailures)
        settings.redFailures = store.integer(Keys.redFailures, default: settings.redFailures)
        settings.minimumStatus = store.integer(Keys.minimumStatus, default: settings.minimumStatus)
        settings.maximumStatus = store.integer(Keys.maximumStatus, default: settings.maximumStatus)
        settings.chartWindow = store.double(Keys.chartWindow, default: settings.chartWindow)
        settings.locationRefresh = store.double(Keys.locationRefresh, default: settings.locationRefresh)
        settings.menuBarMode = store.value(Keys.menuBarMode, default: settings.menuBarMode)
        settings.menuBarTextSize = store.double(Keys.menuBarTextSize, default: settings.menuBarTextSize)
        settings.menuBarCircleSize = store.double(Keys.menuBarCircleSize, default: settings.menuBarCircleSize)
        settings.circleStyle = store.value(Keys.circleStyle, default: settings.circleStyle)
        settings.panelTransparency = store.bool(Keys.panelTransparency, default: settings.panelTransparency)
        settings.appearance = store.value(Keys.appearance, default: settings.appearance)
        settings.alwaysOnTop = store.bool(Keys.alwaysOnTop, default: settings.alwaysOnTop)
        return settings.normalized()
    }

    /// Writes every preference that differs from `previous`.
    public func save(to defaults: UserDefaults, changedFrom previous: PingSettings? = nil) {
        func write<Value: Equatable>(_ keyPath: KeyPath<PingSettings, Value>, _ key: String, _ stored: (Value) -> Any) {
            let value = self[keyPath: keyPath]
            guard previous?[keyPath: keyPath] != value else { return }
            defaults.set(stored(value), forKey: key)
        }
        write(\.targetType, Keys.targetType) { $0.rawValue }
        write(\.urlString, Keys.url) { $0 }
        write(\.pingHost, Keys.pingHost) { $0 }
        write(\.interval, Keys.interval) { $0 }
        write(\.timeout, Keys.timeout) { $0 }
        write(\.yellowFailures, Keys.yellowFailures) { $0 }
        write(\.redFailures, Keys.redFailures) { $0 }
        write(\.minimumStatus, Keys.minimumStatus) { $0 }
        write(\.maximumStatus, Keys.maximumStatus) { $0 }
        write(\.chartWindow, Keys.chartWindow) { $0 }
        write(\.locationRefresh, Keys.locationRefresh) { $0 }
        write(\.menuBarMode, Keys.menuBarMode) { $0.rawValue }
        write(\.menuBarTextSize, Keys.menuBarTextSize) { $0 }
        write(\.menuBarCircleSize, Keys.menuBarCircleSize) { $0 }
        write(\.circleStyle, Keys.circleStyle) { $0.rawValue }
        write(\.panelTransparency, Keys.panelTransparency) { $0 }
        write(\.appearance, Keys.appearance) { $0.rawValue }
        write(\.alwaysOnTop, Keys.alwaysOnTop) { $0 }
    }

    /// Removes every stored preference so future launches use the built-in
    /// defaults, including any defaults changed by later releases.
    public static func removeAll(from defaults: UserDefaults) {
        for key in Keys.preferences {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Validation

    public static func isValidHTTPURL(_ string: String) -> Bool {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return false
        }
        return true
    }

    public static func isValidPingHost(_ string: String) -> Bool {
        let host = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, host.count <= 253 else { return false }
        return host.range(of: hostPattern, options: .regularExpression) != nil
    }

    public static func isValid(_ target: PingTarget) -> Bool {
        switch target.type {
        case .http: isValidHTTPURL(target.address)
        case .icmp: isValidPingHost(target.address)
        }
    }

    private static let hostPattern = #"^[A-Za-z0-9](?:[A-Za-z0-9\-._:]*[A-Za-z0-9])?(?:%[A-Za-z0-9]+)?$"#

    public static func locationRefreshTitle(for seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds)) seconds" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(Int(minutes)) min" }
        let hours = minutes / 60
        return hours == hours.rounded() ? "\(Int(hours)) hour" : String(format: "%.1f hours", hours)
    }

    private static func migrateDefaultURL(in defaults: UserDefaults) {
        guard defaults.integer(forKey: Keys.defaultURLMigrationVersion) < 1 else { return }
        if defaults.string(forKey: Keys.url) == previousDefaultURL {
            defaults.set(defaultURL, forKey: Keys.url)
        }
        defaults.set(1, forKey: Keys.defaultURLMigrationVersion)
    }

    public enum Keys {
        public static let url = "pingURL"
        public static let defaultURLMigrationVersion = "defaultURLMigrationVersion"
        public static let targetType = "targetType"
        public static let pingHost = "pingHost"
        public static let interval = "pingInterval"
        public static let timeout = "requestTimeout"
        public static let yellowFailures = "yellowFailureThreshold"
        public static let redFailures = "redFailureThreshold"
        public static let minimumStatus = "minimumSuccessStatus"
        public static let maximumStatus = "maximumSuccessStatus"
        public static let chartWindow = "chartWindowSeconds"
        public static let locationRefresh = "locationRefreshSeconds"
        public static let menuBarMode = "menuBarDisplayMode"
        public static let menuBarTextSize = "menuBarTextSize"
        public static let menuBarCircleSize = "menuBarCircleSize"
        public static let circleStyle = "menuBarCircleStyle"
        public static let panelTransparency = "panelTransparency"
        public static let appearance = "appAppearance"
        public static let alwaysOnTop = "alwaysOnTop"

        static let preferences = [
            url, targetType, pingHost, interval, timeout, yellowFailures, redFailures,
            minimumStatus, maximumStatus, chartWindow, locationRefresh, menuBarMode,
            menuBarTextSize, menuBarCircleSize, circleStyle, panelTransparency, appearance, alwaysOnTop
        ]
    }
}

/// Typed reads that fall back to a default when a key is missing.
private struct Store {
    let defaults: UserDefaults

    func string(_ key: String, default fallback: String) -> String {
        defaults.string(forKey: key) ?? fallback
    }

    func double(_ key: String, default fallback: Double) -> Double {
        defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
    }

    func integer(_ key: String, default fallback: Int) -> Int {
        defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key)
    }

    func bool(_ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    func value<Value: RawRepresentable>(_ key: String, default fallback: Value) -> Value where Value.RawValue == String {
        defaults.string(forKey: key).flatMap(Value.init(rawValue:)) ?? fallback
    }
}

public enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

public enum CircleStyle: String, CaseIterable, Identifiable, Sendable {
    case colored
    case monochrome

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .colored: "Colored"
        case .monochrome: "Monochrome"
        }
    }
}

public enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case circle
    case circleAndTime
    case time

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .circle: "Circle"
        case .circleAndTime: "Circle + Time"
        case .time: "Time"
        }
    }

    public var showsCircle: Bool { self != .time }
    public var showsTime: Bool { self != .circle }
}
