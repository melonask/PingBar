import Foundation

struct PingSettings: Equatable, Sendable {
    static let defaultURL = "https://www.chess.com"
    private static let previousDefaultURL = "https://fast.com"
    static let defaultTargetType = TargetType.http.rawValue
    static let defaultPingHost = "192.168.1.1"
    static let defaultInterval = 1.0
    static let defaultTimeout = 5.0
    static let defaultYellowFailures = 2
    static let defaultRedFailures = 5
    static let defaultMinimumStatus = 200
    static let defaultMaximumStatus = 399
    static let defaultChartWindow = 300.0
    static let defaultMenuBarMode = MenuBarDisplayMode.circleAndTime.rawValue
    static let defaultMenuBarTextSize = 9.0
    static let defaultMenuBarCircleSize = 7.0
    static let defaultCircleStyle = CircleStyle.colored.rawValue
    static let defaultPanelTransparency = true
    static let defaultAppearance = AppAppearance.system.rawValue
    static let defaultAlwaysOnTop = false

    var urlString: String
    var targetType: String
    var pingHost: String
    var interval: Double
    var timeout: Double
    var yellowFailures: Int
    var redFailures: Int
    var minimumStatus: Int
    var maximumStatus: Int
    var chartWindow: Double
    var menuBarMode: String
    var menuBarTextSize: Double
    var menuBarCircleSize: Double
    var circleStyle: String
    var panelTransparency: Bool
    var appearance: String
    var alwaysOnTop: Bool

    init(
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

    static func load(from defaults: UserDefaults = .standard) -> PingSettings {
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

    static func isValidHTTPURL(_ string: String) -> Bool {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return false
        }
        return true
    }

    static func isValidPingHost(_ string: String) -> Bool {
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

    enum Keys {
        static let url = "pingURL"
        static let defaultURLMigrationVersion = "defaultURLMigrationVersion"
        static let targetType = "targetType"
        static let pingHost = "pingHost"
        static let interval = "pingInterval"
        static let timeout = "requestTimeout"
        static let yellowFailures = "yellowFailureThreshold"
        static let redFailures = "redFailureThreshold"
        static let minimumStatus = "minimumSuccessStatus"
        static let maximumStatus = "maximumSuccessStatus"
        static let chartWindow = "chartWindowSeconds"
        static let menuBarMode = "menuBarDisplayMode"
        static let menuBarTextSize = "menuBarTextSize"
        static let menuBarCircleSize = "menuBarCircleSize"
        static let circleStyle = "menuBarCircleStyle"
        static let panelTransparency = "panelTransparency"
        static let appearance = "appAppearance"
        static let alwaysOnTop = "alwaysOnTop"
        static let panelPositionX = "panelPositionX"
        static let panelPositionTop = "panelPositionTop"
        static let panelScreenID = "panelScreenID"
        static let panelScreenX = "panelScreenX"
        static let panelScreenTop = "panelScreenTop"
        static let panelOriginX = "panelOriginX"
        static let panelOriginY = "panelOriginY"
    }
}

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum CircleStyle: String, CaseIterable, Identifiable, Sendable {
    case colored
    case monochrome

    var id: String { rawValue }

    var title: String {
        switch self {
        case .colored: "Colored"
        case .monochrome: "Monochrome"
        }
    }
}

enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case circle
    case circleAndTime
    case time

    var id: String { rawValue }

    var title: String {
        switch self {
        case .circle: "Circle"
        case .circleAndTime: "Circle + Time"
        case .time: "Time"
        }
    }
}
