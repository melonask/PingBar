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
        menuBarCircleSize: Double = defaultMenuBarCircleSize
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
            Keys.menuBarCircleSize: defaultMenuBarCircleSize
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
            menuBarCircleSize: defaults.double(forKey: Keys.menuBarCircleSize)
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
