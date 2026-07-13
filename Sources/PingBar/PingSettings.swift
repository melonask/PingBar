import Foundation

struct PingSettings: Equatable, Sendable {
    static let defaultURL = "https://fast.com"
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

    var urlString: String
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

    init(
        urlString: String = defaultURL,
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
        appearance: String = defaultAppearance
    ) {
        self.urlString = urlString
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
    }

    static func load(from defaults: UserDefaults = .standard) -> PingSettings {
        defaults.register(defaults: [
            Keys.url: defaultURL,
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
            Keys.appearance: defaultAppearance
        ])

        return PingSettings(
            urlString: defaults.string(forKey: Keys.url) ?? defaultURL,
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
            appearance: defaults.string(forKey: Keys.appearance) ?? defaultAppearance
        )
    }

    enum Keys {
        static let url = "pingURL"
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
        static let panelPositionX = "panelPositionX"
        static let panelPositionTop = "panelPositionTop"
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
