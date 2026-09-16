import AppKit
import PingBarKit
import SwiftUI

@main
struct PingBarApp: App {
    @StateObject private var monitor = PingMonitor()

    var body: some Scene {
        MenuBarExtra {
            PingMenu(monitor: monitor)
        } label: {
            MenuBarStatusLabel(monitor: monitor)
                .task { monitor.start() }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarStatusLabel: View {
    @ObservedObject var monitor: PingMonitor

    var body: some View {
        labelText.fixedSize()
    }

    private var labelText: Text {
        let circle = if monitor.circleStyle == .colored {
            Text(statusEmoji)
                .font(.system(size: monitor.menuBarCircleSize))
        } else {
            Text("●")
                .font(.system(size: monitor.menuBarCircleSize, weight: .bold, design: .rounded))
        }
        let time = Text(monitor.menuBarStatusText)
            .font(.system(size: monitor.menuBarTextSize, weight: .medium, design: .monospaced))

        return switch monitor.menuBarMode {
        case .circle: circle
        case .circleAndTime: circle + Text(" ") + time
        case .time: time
        }
    }

    private var statusEmoji: String {
        switch monitor.level {
        case .green: "🟢"
        case .yellow: "🟡"
        case .red: "🔴"
        }
    }
}

private struct PingMenu: View {
    private enum Page {
        case status
        case settings
    }

    private static let panelWidth = 420.0

    @ObservedObject var monitor: PingMonitor
    @State private var page = Page.status
    @State private var dragFeedback: PanelDragFeedback?
    @State private var isDraggingPanel = false
    @State private var feedbackResetTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            dragStrip
            Divider()
            statusView
                .opacity(page == .settings ? 0 : 1)
                .accessibilityHidden(page == .settings)
                .allowsHitTesting(page == .status)
                .overlay(alignment: .top) {
                    if page == .settings {
                        settingsView
                    }
                }
        }
        .frame(width: Self.panelWidth, alignment: .top)
        .background {
            if !monitor.panelTransparency {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .preferredColorScheme(monitor.appearance.colorScheme)
        .background(PanelWindowBehavior(appearance: monitor.appearance, alwaysOnTop: monitor.alwaysOnTop))
        .transaction { transaction in
            transaction.animation = nil
        }
        .onDisappear { page = .status }
        .onAppear { page = .status }
    }

    private var settingsView: some View {
        SettingsView(monitor: monitor)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var dragStrip: some View {
        HStack(spacing: 0) {
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Quit PingBar")
            .accessibilityLabel("Quit PingBar")
            .padding(.leading, 10)
            .frame(width: 62, alignment: .leading)

            HStack(spacing: 7) {
                Image(systemName: isDraggingPanel ? "arrow.up.and.down.and.arrow.left.and.right" : "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                Text(dragStripText)
                    .font(.system(size: 9, weight: isDraggingPanel ? .semibold : .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isDraggingPanel ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 10)
            .background(
                isDraggingPanel ? Color.accentColor.opacity(0.1) : Color.clear,
                in: Capsule()
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay {
                WindowDragRegion(
                    onChanged: { feedback in
                        feedbackResetTask?.cancel()
                        dragFeedback = feedback
                        isDraggingPanel = true
                    },
                    onEnded: { feedback in
                        dragFeedback = feedback
                        isDraggingPanel = false
                        scheduleFeedbackReset()
                    }
                )
            }
            .help("Drag to move PingBar")
            .accessibilityLabel(dragStripText)

            settingsToggle
            alwaysOnTopToggle
                .padding(.trailing, 10)
        }
        .frame(height: 40)
    }

    private var settingsToggle: some View {
        Button {
            page = page == .settings ? .status : .settings
        } label: {
            Image(systemName: page == .settings ? "gearshape.fill" : "gearshape")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(page == .settings ? Color.accentColor : Color.secondary)
        .background(
            page == .settings ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7)
        )
        .help(page == .settings ? "Back to Status (⌘,)" : "Settings (⌘,)")
        .accessibilityLabel(page == .settings ? "Back to Status" : "Settings")
        .keyboardShortcut(",", modifiers: .command)
    }

    private var dragStripText: String {
        guard let dragFeedback else { return "Drag to move" }
        let action = isDraggingPanel ? "Moving" : "Placed"
        return "\(action) · \(dragFeedback.screenName) · x \(Int(dragFeedback.x))  y \(Int(dragFeedback.y))"
    }

    private func scheduleFeedbackReset() {
        feedbackResetTask?.cancel()
        feedbackResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            dragFeedback = nil
        }
    }

    private var statusView: some View {
        PingDashboardView(monitor: monitor)
            .frame(width: Self.panelWidth)
    }

    private var alwaysOnTopToggle: some View {
        Button {
            monitor.setAlwaysOnTop(!monitor.alwaysOnTop)
        } label: {
            Image(systemName: monitor.alwaysOnTop ? "pin.fill" : "pin")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(monitor.alwaysOnTop ? Color.accentColor : Color.secondary)
        .background(
            monitor.alwaysOnTop ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7)
        )
        .help(monitor.alwaysOnTop ? "Disable always on top" : "Keep the panel above all windows")
        .accessibilityLabel("Always on top")
    }
}

private struct WindowDragRegion: NSViewRepresentable {
    let onChanged: (PanelDragFeedback) -> Void
    let onEnded: (PanelDragFeedback) -> Void

    func makeNSView(context: Context) -> NSView {
        DraggingView(onChanged: onChanged, onEnded: onEnded)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? DraggingView else { return }
        view.onChanged = onChanged
        view.onEnded = onEnded
    }

    private final class DraggingView: NSView {
        var onChanged: (PanelDragFeedback) -> Void
        var onEnded: (PanelDragFeedback) -> Void

        init(
            onChanged: @escaping (PanelDragFeedback) -> Void,
            onEnded: @escaping (PanelDragFeedback) -> Void
        ) {
            self.onChanged = onChanged
            self.onEnded = onEnded
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override var acceptsFirstResponder: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            PanelPlacement.isUserDragging = true
            let center = NotificationCenter.default
            let observer = center.addObserver(
                forName: NSWindow.didMoveNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                guard let self, let window else { return }
                MainActor.assumeIsolated {
                    self.onChanged(PanelPlacement.feedback(for: window.frame, window: window))
                }
            }
            onChanged(PanelPlacement.feedback(for: window.frame, window: window))
            NSCursor.closedHand.push()
            defer {
                NSCursor.pop()
                center.removeObserver(observer)
                PanelPlacement.isUserDragging = false
                PanelPlacement.constrain(window)
                PanelPlacement.save(window)
                onEnded(PanelPlacement.feedback(for: window.frame, window: window))
            }
            window.performDrag(with: event)
        }
    }
}

private struct PanelWindowBehavior: NSViewRepresentable {
    let appearance: AppAppearance
    let alwaysOnTop: Bool

    func makeNSView(context: Context) -> NSView {
        let view = PanelBehaviorView()
        view.apply(appearance: appearance, alwaysOnTop: alwaysOnTop)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? PanelBehaviorView)?.apply(appearance: appearance, alwaysOnTop: alwaysOnTop)
    }

    private final class PanelBehaviorView: NSView {
        private var isObservingScreenChanges = false
        private var selectedAppearance = AppAppearance.system
        private var selectedAlwaysOnTop = false
        private var naturalLevel: NSWindow.Level?
        private var restoreTask: Task<Void, Never>?
        private var reshowTask: Task<Void, Never>?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.isMovable = true
            window?.isMovableByWindowBackground = true
            if naturalLevel == nil {
                naturalLevel = window?.level
            }
            apply(appearance: selectedAppearance, alwaysOnTop: selectedAlwaysOnTop)

            if window != nil, !isObservingScreenChanges {
                window?.alphaValue = 0
                let center = NotificationCenter.default
                center.addObserver(
                    self,
                    selector: #selector(screenParametersDidChange),
                    name: NSApplication.didChangeScreenParametersNotification,
                    object: nil
                )
                center.addObserver(
                    self,
                    selector: #selector(revealWindow),
                    name: NSWindow.didBecomeKeyNotification,
                    object: window
                )
                center.addObserver(
                    self,
                    selector: #selector(hideWindow),
                    name: NSWindow.didResignKeyNotification,
                    object: window
                )
                center.addObserver(
                    self,
                    selector: #selector(windowDidResize),
                    name: NSWindow.didResizeNotification,
                    object: window
                )
                center.addObserver(
                    self,
                    selector: #selector(windowDidMove),
                    name: NSWindow.didMoveNotification,
                    object: window
                )
                center.addObserver(
                    self,
                    selector: #selector(windowOcclusionDidChange),
                    name: NSWindow.didChangeOcclusionStateNotification,
                    object: window
                )
                isObservingScreenChanges = true
                restoreWindowConfiguration()
                scheduleConfigurationRestore()
                if window?.isKeyWindow == true {
                    window?.alphaValue = 1
                }
            } else if window == nil, isObservingScreenChanges {
                restoreTask?.cancel()
                restoreTask = nil
                reshowTask?.cancel()
                reshowTask = nil
                NotificationCenter.default.removeObserver(self)
                isObservingScreenChanges = false
                naturalLevel = nil
            }
        }

        func apply(appearance: AppAppearance, alwaysOnTop: Bool) {
            selectedAppearance = appearance
            selectedAlwaysOnTop = alwaysOnTop
            window?.appearance = switch appearance {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
            applyWindowLevel()
        }

        @objc private func screenParametersDidChange() {
            scheduleConfigurationRestore()
        }

        @objc private func revealWindow() {
            restoreWindowConfiguration()
            window?.alphaValue = 1
            scheduleConfigurationRestore()
        }

        @objc private func hideWindow() {
            guard !selectedAlwaysOnTop else {
                reshowIfNeeded()
                return
            }
            window?.alphaValue = 0
        }

        @objc private func windowOcclusionDidChange() {
            guard selectedAlwaysOnTop, let window, !window.isVisible else { return }
            window.orderFrontRegardless()
            restoreWindowConfiguration()
            window.alphaValue = 1
        }

        private func reshowIfNeeded() {
            reshowTask?.cancel()
            reshowTask = Task { @MainActor [weak self] in
                // MenuBarExtra toggles its window when the status item is
                // clicked. Reassert pinned visibility over its closing pass,
                // without the previous noticeable 200 ms disappearance.
                for delay in [0, 20, 80] {
                    if delay > 0 {
                        try? await Task.sleep(for: .milliseconds(delay))
                    } else {
                        await Task.yield()
                    }
                    guard !Task.isCancelled,
                          let self,
                          let window = self.window,
                          self.selectedAlwaysOnTop else { return }
                    if !window.isVisible {
                        window.orderFrontRegardless()
                    }
                    self.restoreWindowConfiguration()
                    window.alphaValue = 1
                }
            }
        }

        @objc private func windowDidResize() {
            scheduleConfigurationRestore()
        }

        @objc private func windowDidMove() {
            guard let window, !PanelPlacement.isRestoring else { return }
            let isBackgroundDrag = NSEvent.pressedMouseButtons & 1 == 1
                && window.frame.contains(NSEvent.mouseLocation)
            if PanelPlacement.isUserDragging || isBackgroundDrag {
                restoreTask?.cancel()
                PanelPlacement.save(window)
            } else if window.isVisible {
                scheduleConfigurationRestore()
            }
        }

        private func scheduleConfigurationRestore() {
            restoreTask?.cancel()
            restoreTask = Task { @MainActor [weak self] in
                // MenuBarExtra can apply its anchor frame after didBecomeKey.
                // Restore over the next few run-loop passes so the saved frame
                // wins on the first opening, not only the second one.
                for delay in [0, 20, 80] {
                    if delay > 0 {
                        try? await Task.sleep(for: .milliseconds(delay))
                    } else {
                        await Task.yield()
                    }
                    guard !Task.isCancelled, let self, self.window?.isVisible == true else { return }
                    self.restoreWindowConfiguration()
                }
            }
        }

        private func restoreWindowConfiguration() {
            guard let window, !PanelPlacement.isUserDragging else { return }
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.removeAllAnimations()
            if PanelPlacement.hasSavedPosition {
                PanelPlacement.restore(window)
            } else {
                PanelPlacement.constrain(window)
            }
            applyWindowLevel()
        }

        private func applyWindowLevel() {
            guard let window, let naturalLevel else { return }
            let pinnedLevel = NSWindow.Level(
                rawValue: max(naturalLevel.rawValue, NSWindow.Level.floating.rawValue)
            )
            let desiredLevel = selectedAlwaysOnTop ? pinnedLevel : naturalLevel
            if window.level != desiredLevel {
                window.level = desiredLevel
            }
        }
    }
}

@MainActor
private enum PanelPlacement {
    static var isUserDragging = false
    static var isRestoring = false

    static var hasSavedPosition: Bool {
        let defaults = UserDefaults.standard
        let hasTopLeft = defaults.object(forKey: PingSettings.Keys.panelPositionX) != nil
            && defaults.object(forKey: PingSettings.Keys.panelPositionTop) != nil
        let hasLegacyOrigin = defaults.object(forKey: PingSettings.Keys.panelOriginX) != nil
            && defaults.object(forKey: PingSettings.Keys.panelOriginY) != nil
        return hasTopLeft || hasLegacyOrigin
    }

    static func save(_ window: NSWindow) {
        guard !isRestoring else { return }
        let defaults = UserDefaults.standard
        defaults.set(window.frame.minX, forKey: PingSettings.Keys.panelPositionX)
        defaults.set(window.frame.maxY, forKey: PingSettings.Keys.panelPositionTop)
        defaults.removeObject(forKey: PingSettings.Keys.panelOriginX)
        defaults.removeObject(forKey: PingSettings.Keys.panelOriginY)

        if let screen = bestScreen(for: window.frame, preferred: window.screen) {
            defaults.set(screenIdentifier(screen), forKey: PingSettings.Keys.panelScreenID)
            defaults.set(window.frame.minX - screen.visibleFrame.minX, forKey: PingSettings.Keys.panelScreenX)
            defaults.set(screen.visibleFrame.maxY - window.frame.maxY, forKey: PingSettings.Keys.panelScreenTop)
        }
    }

    static func restore(_ window: NSWindow) {
        guard let topLeft = savedTopLeft(for: window) else { return }
        var frame = window.frame
        frame.origin = NSPoint(x: topLeft.x, y: topLeft.y - frame.height)
        let target = constrained(frame, for: window)
        if target != window.frame {
            isRestoring = true
            defer { isRestoring = false }
            window.setFrame(target, display: true, animate: false)
        }
    }

    static func constrain(_ window: NSWindow) {
        let frame = constrained(window.frame, for: window)
        if frame != window.frame {
            isRestoring = true
            defer { isRestoring = false }
            window.setFrame(frame, display: true, animate: false)
        }
    }

    static func feedback(for frame: NSRect, window: NSWindow) -> PanelDragFeedback {
        guard let screen = bestScreen(for: frame, preferred: window.screen) else {
            return PanelDragFeedback(screenName: "Display", x: frame.minX.rounded(), y: frame.minY.rounded())
        }
        return PanelDragFeedback(
            screenName: screen.localizedName,
            x: max(frame.minX - screen.visibleFrame.minX, 0).rounded(),
            y: max(screen.visibleFrame.maxY - frame.maxY, 0).rounded()
        )
    }

    private static func savedTopLeft(for window: NSWindow) -> NSPoint? {
        let defaults = UserDefaults.standard
        if let identifier = defaults.string(forKey: PingSettings.Keys.panelScreenID),
           defaults.object(forKey: PingSettings.Keys.panelScreenX) != nil,
           defaults.object(forKey: PingSettings.Keys.panelScreenTop) != nil,
           let screen = NSScreen.screens.first(where: { screenIdentifier($0) == identifier }) {
            return NSPoint(
                x: screen.visibleFrame.minX + defaults.double(forKey: PingSettings.Keys.panelScreenX),
                y: screen.visibleFrame.maxY - defaults.double(forKey: PingSettings.Keys.panelScreenTop)
            )
        }

        if defaults.object(forKey: PingSettings.Keys.panelPositionX) != nil,
           defaults.object(forKey: PingSettings.Keys.panelPositionTop) != nil {
            return NSPoint(
                x: defaults.double(forKey: PingSettings.Keys.panelPositionX),
                y: defaults.double(forKey: PingSettings.Keys.panelPositionTop)
            )
        }

        guard defaults.object(forKey: PingSettings.Keys.panelOriginX) != nil,
              defaults.object(forKey: PingSettings.Keys.panelOriginY) != nil else {
            return nil
        }
        return NSPoint(
            x: defaults.double(forKey: PingSettings.Keys.panelOriginX),
            y: defaults.double(forKey: PingSettings.Keys.panelOriginY) + window.frame.height
        )
    }

    private static func constrained(_ frame: NSRect, for window: NSWindow) -> NSRect {
        let screen = bestScreen(for: frame, preferred: window.screen)
        guard let screen else { return frame }

        var result = frame
        let safeFrame = screen.visibleFrame
        result.origin.x = clamped(
            result.minX,
            lower: safeFrame.minX,
            upper: max(safeFrame.minX, safeFrame.maxX - result.width)
        )
        result.origin.y = clamped(
            result.minY,
            lower: safeFrame.minY,
            upper: max(safeFrame.minY, safeFrame.maxY - result.height)
        )
        return result
    }

    private static func bestScreen(for frame: NSRect, preferred: NSScreen?) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return preferred ?? NSScreen.main }

        let intersections = screens.map { screen in
            (screen, frame.intersection(screen.frame).area)
        }
        if let best = intersections.max(by: { $0.1 < $1.1 }), best.1 > 0 {
            return best.0
        }

        return preferred ?? screens.min(by: {
            distanceSquared(from: frame.center, to: $0.frame.center)
                < distanceSquared(from: frame.center, to: $1.frame.center)
        })
    }

    private static func screenIdentifier(_ screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        return screen.localizedName
    }

    private static func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }

    private static func distanceSquared(from first: NSPoint, to second: NSPoint) -> CGFloat {
        let x = first.x - second.x
        let y = first.y - second.y
        return x * x + y * y
    }
}

private struct PanelDragFeedback: Equatable {
    let screenName: String
    let x: CGFloat
    let y: CGFloat
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
    var center: NSPoint { NSPoint(x: midX, y: midY) }
}
