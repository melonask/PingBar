import AppKit
import Combine
import PingBarKit

/// The menu-bar item: shows the status circle and latency, and reports
/// clicks together with the display they happened on.
@MainActor
final class StatusItemController: NSObject {
    struct Click {
        /// The display whose menu bar was clicked.
        let screen: NSScreen
        /// The item's frame in screen coordinates, used for default placement.
        let itemFrame: CGRect?
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let onClick: (Click) -> Void
    private var labelSubscription: AnyCancellable?

    init(monitor: PingMonitor, onClick: @escaping (Click) -> Void) {
        self.onClick = onClick
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.imagePosition = .noImage
        }

        // Each publisher emits the incoming value, so the label is built from
        // the values passed in rather than read back from the monitor.
        labelSubscription = Publishers.CombineLatest3(
            monitor.$latencyMilliseconds,
            monitor.$consecutiveFailures,
            monitor.$settings
        )
        .sink { [weak self] latency, failures, settings in
            self?.updateLabel(
                latency: latency,
                level: StatusLevel(consecutiveFailures: failures, settings: settings),
                settings: settings
            )
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? sender.window?.screen
            ?? NSScreen.main
        guard let screen else { return }

        let itemFrame = sender.window.map { $0.convertToScreen(sender.convert(sender.bounds, to: nil)) }
        // Only anchor below the item when it is on the clicked display.
        let anchor = itemFrame.flatMap { screen.frame.intersects($0) ? $0 : nil }
        onClick(Click(screen: screen, itemFrame: anchor))
    }

    /// Whether `point` (in screen coordinates) lies on the menu-bar item.
    func contains(_ point: CGPoint) -> Bool {
        guard let button = statusItem.button, let window = button.window else { return false }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return NSMouseInRect(point, frame, false)
    }

    private func updateLabel(latency: Double?, level: StatusLevel, settings: PingSettings) {
        guard let button = statusItem.button else { return }
        let latencyText = LatencyFormatter.compact(milliseconds: latency)
        button.attributedTitle = StatusItemLabel.title(latencyText: latencyText, level: level, settings: settings)
        button.setAccessibilityLabel("PingBar, \(level.accessibilityDescription), \(LatencyFormatter.display(milliseconds: latency))")
    }
}

/// Builds the menu-bar text: an optional status circle and fixed-width latency.
enum StatusItemLabel {
    static func title(latencyText: String, level: StatusLevel, settings: PingSettings) -> NSAttributedString {
        let title = NSMutableAttributedString()
        let mode = settings.menuBarMode
        if mode.showsCircle {
            title.append(circle(level: level, settings: settings))
        }
        if mode.showsCircle, mode.showsTime {
            title.append(NSAttributedString(string: " ", attributes: [.font: timeFont(settings)]))
        }
        if mode.showsTime {
            title.append(NSAttributedString(string: latencyText, attributes: [
                .font: timeFont(settings),
                .foregroundColor: NSColor.labelColor
            ]))
        }
        return title
    }

    private static func circle(level: StatusLevel, settings: PingSettings) -> NSAttributedString {
        let size = settings.menuBarCircleSize
        switch settings.circleStyle {
        case .colored:
            return NSAttributedString(string: level.emoji, attributes: [.font: NSFont.systemFont(ofSize: size)])
        case .monochrome:
            let bold = NSFont.systemFont(ofSize: size, weight: .bold)
            let rounded = bold.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? bold
            return NSAttributedString(string: "●", attributes: [
                .font: rounded,
                .foregroundColor: NSColor.labelColor
            ])
        }
    }

    private static func timeFont(_ settings: PingSettings) -> NSFont {
        .monospacedSystemFont(ofSize: settings.menuBarTextSize, weight: .medium)
    }
}

private extension StatusLevel {
    var emoji: String {
        switch self {
        case .green: "🟢"
        case .yellow: "🟡"
        case .red: "🔴"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .green: "online"
        case .yellow: "degraded"
        case .red: "offline"
        }
    }
}
