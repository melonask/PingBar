import Foundation

public struct PingSettings: Equatable, Sendable {
    public static let defaultURL = "https://www.chess.com"
    private static let previousDefaultURL = "https://fast.com"
    public static let defaultTargetType = TargetType.http.rawValue
    public static let defaultPingHost = "192.168.1.1"
    public static let defaultInterval = 1.0
    public static let defaultTimeout = 5.0
    public static let defaultYellowFailures = 2
    public static let defaultRedFailures = 5
    public static let defaultMinimumStatus = 200
    public static let defaultMaximumStatus = 399
    public static let defaultChartWindow = 300.0
    public static let defaultMenuBarMode = MenuBarDisplayMode.circleAndTime.rawValue
    public static let defaultMenuBarTextSize = 9.0
    public static let defaultMenuBarCircleSize = 7.0
    public static let defaultCircleStyle = CircleStyle.colored.rawValue
    public static let defaultPanelTransparency = true
    public static let defaultAppearance = AppAppearance.system.rawValue
    public static let defaultAlwaysOnTop = false

    public var urlString: String
    public var targetType: String
    public var pingHost: String
    public var interval: Double
    public var timeout: Double
    public var yellowFailures: Int
    public var redFailures: Int
    public var minimumStatus: Int
    public var maximumStatus: Int
    public var chartWindow: Double
    public var menuBarMode: String
    public var menuBarTextSize: Double
    public var menuBarCircleSize: Double
    public var circleStyle: String
    public var panelTransparency: Bool
    public var appearance: String
    public var alwaysOnTop: Bool

    public init(
        urlString: String = defaultURL,
        targetType: String = defaultTargetType,
        pingHost: String = defaultPingHost,
        interval: Double = defaultInterval,
        timeout: Double = defaultTimeout,
        yellowFailures: Int = defaultYellowFailures,
        redFailures: Int = defaultRedFailures,
        minimumStatus: Int = defaultMinimumStatus,
        maximumStatus: Int = defaultMaximumStatus,
        chartWindow: Double = defaultChartWindow,
        menuBarMode: String = defaultMenuBarMode,
        menuBarTextSize: Double = defaultMenuBarTextSize,
        menuBarCircleSize: Double = defaultMenuBarCircleSize,
        circleStyle: String = defaultCircleStyle,
        panelTransparency: Bool = defaultPanelTransparency,
        appearance: String = defaultAppearance,
        alwaysOnTop: Bool = defaultAlwaysOnTop
    ) {
        self.urlString = urlString
        self.targetType = targetType
        self.pingHost = pingHost
        self.interval = interval
        self.timeout = timeout
        self.yellowFailures = yellowFailures
        self.redFailures = redFailures
        self.minimumStatus = minimumStatus
        self.maximumStatus = maximumStatus
        self.chartWindow = chartWindow
        self.menuBarMode = menuBarMode
        self.menuBarTextSize = menuBarTextSize
        self.menuBarCircleSize = menuBarCircleSize
        self.circleStyle = circleStyle
        self.panelTransparency = panelTransparency
        self.appearance = appearance
        self.alwaysOnTop = alwaysOnTop
    }

    public static func load(from defaults: UserDefaults = .standard) -> PingSettings {
        migrateDefaultURL(in: defaults)
        defaults.register(defaults: [
            Keys.url: defaultURL,
            Keys.targetType: defaultTargetType,
            Keys.pingHost: defaultPingHost,
            Keys.interval: defaultInterval,
            Keys.timeout: defaultTimeout,
            Keys.yellowFailures: defaultYellowFailures,
            Keys.redFailures: defaultRedFailures,
            Keys.minimumStatus: defaultMinimumStatus,
            Keys.maximumStatus: defaultMaximumStatus,
            Keys.chartWindow: defaultChartWindow,
            Keys.menuBarMode: defaultMenuBarMode,
            Keys.menuBarTextSize: defaultMenuBarTextSize,
            Keys.menuBarCircleSize: defaultMenuBarCircleSize,
            Keys.circleStyle: defaultCircleStyle,
            Keys.panelTransparency: defaultPanelTransparency,
            Keys.appearance: defaultAppearance,
            Keys.alwaysOnTop: defaultAlwaysOnTop
        ])

        return PingSettings(
            urlString: defaults.string(forKey: Keys.url) ?? defaultURL,
            targetType: defaults.string(forKey: Keys.targetType) ?? defaultTargetType,
            pingHost: defaults.string(forKey: Keys.pingHost) ?? defaultPingHost,
            interval: defaults.double(forKey: Keys.interval),
            timeout: defaults.double(forKey: Keys.timeout),
            yellowFailures: defaults.integer(forKey: Keys.yellowFailures),
            redFailures: defaults.integer(forKey: Keys.redFailures),
            minimumStatus: defaults.integer(forKey: Keys.minimumStatus),
            maximumStatus: defaults.integer(forKey: Keys.maximumStatus),
            chartWindow: defaults.double(forKey: Keys.chartWindow),
            menuBarMode: defaults.string(forKey: Keys.menuBarMode) ?? defaultMenuBarMode,
            menuBarTextSize: defaults.double(forKey: Keys.menuBarTextSize),
            menuBarCircleSize: defaults.double(forKey: Keys.menuBarCircleSize),
            circleStyle: defaults.string(forKey: Keys.circleStyle) ?? defaultCircleStyle,
            panelTransparency: defaults.bool(forKey: Keys.panelTransparency),
            appearance: defaults.string(forKey: Keys.appearance) ?? defaultAppearance,
            alwaysOnTop: defaults.bool(forKey: Keys.alwaysOnTop)
        )
    }

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
        return host.range(of: Self.hostPattern, options: .regularExpression) != nil
    }

    private static let hostPattern = #"^[A-Za-z0-9](?:[A-Za-z0-9\-._:]*[A-Za-z0-9])?(?:%[A-Za-z0-9]+)?$"#

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
        public static let menuBarMode = "menuBarDisplayMode"
        public static let menuBarTextSize = "menuBarTextSize"
        public static let menuBarCircleSize = "menuBarCircleSize"
        public static let circleStyle = "menuBarCircleStyle"
        public static let panelTransparency = "panelTransparency"
        public static let appearance = "appAppearance"
        public static let alwaysOnTop = "alwaysOnTop"
        public static let panelPositionX = "panelPositionX"
        public static let panelPositionTop = "panelPositionTop"
        public static let panelScreenID = "panelScreenID"
        public static let panelScreenX = "panelScreenX"
        public static let panelScreenTop = "panelScreenTop"
        public static let panelOriginX = "panelOriginX"
        public static let panelOriginY = "panelOriginY"
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
}
