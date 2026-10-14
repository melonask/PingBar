import AppKit
import Combine
import PingBarKit
import SwiftUI

/// Shows, hides and positions the panel.
///
/// The panel opens on the display whose menu bar was clicked, at the position
/// saved for that display. Dragging saves a new position for the display the
/// panel is dropped on. Content-driven height changes keep the top edge fixed.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let monitor: PingMonitor
    private let model = PanelModel()
    private let placementStore: PanelPlacementStore
    private let panel = StatusPanel()
    /// Top-left corner the panel is placed at; it stays put when the content
    /// height changes (for example when the failure banner appears).
    private var anchor: CGPoint?
    private var activeDrag: (mouse: CGPoint, origin: CGPoint)?
    private var isPinned: Bool
    private var outsideClickMonitor: Any?
    private var subscriptions = Set<AnyCancellable>()

    init(monitor: PingMonitor, placementStore: PanelPlacementStore = PanelPlacementStore()) {
        self.monitor = monitor
        self.placementStore = placementStore
        isPinned = monitor.settings.alwaysOnTop
        super.init()

        let actions = PanelActions(
            quit: { NSApp.terminate(nil) },
            dragBegan: { [weak self] location in self?.dragBegan(at: location) },
            dragMoved: { [weak self] location in self?.dragMoved(to: location) },
            dragEnded: { [weak self] in self?.dragEnded() }
        )
        panel.contentView = NSHostingView(rootView: PanelView(monitor: monitor, model: model, actions: actions))
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.cancel() }

        monitor.$settings
            .map(\.alwaysOnTop)
            .removeDuplicates()
            .sink { [weak self] pinned in self?.isPinned = pinned }
            .store(in: &subscriptions)

        monitor.$settings
            .map(\.appearance)
            .removeDuplicates()
            .sink { [weak self] appearance in self?.panel.appearance = appearance.nsAppearance }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.screenParametersChanged() }
            .store(in: &subscriptions)
    }

    // MARK: - Showing and hiding

    /// Opens the panel on `screen`, moves it there when it is open on another
    /// display, and closes it when it is already open on `screen`.
    func toggle(on screen: NSScreen, below itemFrame: CGRect?) {
        if panel.isVisible, currentScreen()?.displayID == screen.displayID {
            close()
        } else {
            show(on: screen, below: itemFrame)
        }
    }

    private func show(on screen: NSScreen, below itemFrame: CGRect?) {
        place(frame(on: screen, below: itemFrame))
        panel.makeKeyAndOrderFront(nil)
        startMonitoringOutsideClicks()
    }

    private func close() {
        stopMonitoringOutsideClicks()
        activeDrag = nil
        panel.orderOut(nil)
        model.reset()
    }

    /// Closes an unpinned panel when the user has moved on: another window
    /// took keyboard focus, or they clicked outside PingBar.
    private func closeIfTransient() {
        // A sheet (such as the Restore Defaults confirmation) takes key status
        // from the panel while it is still in use.
        guard panel.isVisible, !isPinned, panel.attachedSheet == nil, activeDrag == nil else { return }
        close()
    }

    /// The panel does not activate the app, so a click on the desktop or the
    /// menu bar need not change the key window. A global monitor sees exactly
    /// the clicks delivered to other apps, the same signal transient popovers
    /// and menus close on.
    private func startMonitoringOutsideClicks() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            // AppKit calls global monitors on the main thread.
            MainActor.assumeIsolated {
                self?.closeIfTransient()
            }
        }
    }

    private func stopMonitoringOutsideClicks() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }

    private func cancel() {
        if model.page == .settings {
            model.page = .status
        } else if !isPinned {
            close()
        }
    }

    // MARK: - Placement

    private func frame(on screen: NSScreen, below itemFrame: CGRect?) -> CGRect {
        let size = contentSize()
        if let offset = placementStore.offset(forDisplay: screen.displayID) {
            return PanelGeometry.frame(size: size, offset: offset, in: screen.visibleFrame)
        }
        return PanelGeometry.defaultFrame(size: size, below: itemFrame, in: screen.visibleFrame)
    }

    private func contentSize() -> CGSize {
        guard let contentView = panel.contentView else { return panel.frame.size }
        contentView.layoutSubtreeIfNeeded()
        return contentView.fittingSize
    }

    private func place(_ frame: CGRect) {
        anchor = CGPoint(x: frame.minX, y: frame.maxY)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }

    private func currentScreen() -> NSScreen? {
        let screens = NSScreen.screens
        return PanelGeometry.bestDisplayIndex(for: panel.frame, among: screens.map(\.frame)).map { screens[$0] }
    }

    /// Displays were added, removed or rearranged, or the menu bar or Dock
    /// changed size: keep a visible panel at its saved position on the display
    /// it is now on.
    private func screenParametersChanged() {
        guard panel.isVisible, activeDrag == nil, let screen = currentScreen() else { return }
        place(frame(on: screen, below: nil))
    }

    // MARK: - Dragging

    private func dragBegan(at mouse: CGPoint) {
        activeDrag = (mouse, panel.frame.origin)
        model.showMoving(dragStatus())
    }

    private func dragMoved(to mouse: CGPoint) {
        guard let activeDrag else { return }
        panel.setFrameOrigin(CGPoint(
            x: activeDrag.origin.x + mouse.x - activeDrag.mouse.x,
            y: activeDrag.origin.y + mouse.y - activeDrag.mouse.y
        ))
        model.showMoving(dragStatus())
    }

    private func dragEnded() {
        guard activeDrag != nil else { return }
        activeDrag = nil
        guard let screen = currentScreen() else { return }
        let frame = PanelGeometry.clamped(panel.frame, to: screen.visibleFrame)
        place(frame)
        placementStore.save(PanelGeometry.offset(of: frame, in: screen.visibleFrame), forDisplay: screen.displayID)
        model.showPlaced(dragStatus())
    }

    private func dragStatus() -> PanelDragStatus {
        guard let screen = currentScreen() else {
            return PanelDragStatus(displayName: "Display", offset: PanelOffset(left: panel.frame.minX, top: panel.frame.maxY))
        }
        let offset = PanelGeometry.offset(of: panel.frame, in: screen.visibleFrame)
        return PanelDragStatus(
            displayName: screen.localizedName,
            offset: PanelOffset(left: max(offset.left, 0), top: max(offset.top, 0))
        )
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        closeIfTransient()
    }

    func windowDidResize(_ notification: Notification) {
        panel.invalidateShadow()
        guard activeDrag == nil, let anchor, let screen = currentScreen() else { return }
        let size = panel.frame.size
        let anchored = CGRect(x: anchor.x, y: anchor.y - size.height, width: size.width, height: size.height)
        let target = PanelGeometry.clamped(anchored, to: screen.visibleFrame)
        if panel.frame != target {
            panel.setFrame(target, display: true)
        }
    }
}

extension NSScreen {
    /// A stable identifier for the physical display, unchanged across
    /// reconnects and restarts, unlike the session-specific display number.
    var displayID: String {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return localizedName
        }
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) else {
            return number.stringValue
        }
        return string as String
    }
}

private extension AppAppearance {
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
