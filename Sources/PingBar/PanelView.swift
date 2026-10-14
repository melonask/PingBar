import AppKit
import PingBarKit
import SwiftUI

/// UI state for the panel that outlives a single open/close cycle.
@MainActor
final class PanelModel: ObservableObject {
    enum Page {
        case status
        case settings
    }

    @Published var page = Page.status
    @Published private(set) var dragStatus: PanelDragStatus?
    @Published private(set) var isDragging = false
    private var clearStatusTask: Task<Void, Never>?

    func showMoving(_ status: PanelDragStatus) {
        clearStatusTask?.cancel()
        dragStatus = status
        isDragging = true
    }

    /// Shows where the panel was dropped for a moment, then the hint again.
    func showPlaced(_ status: PanelDragStatus) {
        dragStatus = status
        isDragging = false
        clearStatusTask?.cancel()
        clearStatusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.dragStatus = nil
        }
    }

    /// Every opening starts on the status page.
    func reset() {
        clearStatusTask?.cancel()
        page = .status
        dragStatus = nil
        isDragging = false
    }
}

struct PanelDragStatus: Equatable {
    let displayName: String
    let offset: PanelOffset
}

struct PanelActions {
    let quit: () -> Void
    /// Mouse locations are in AppKit screen coordinates.
    let dragBegan: (CGPoint) -> Void
    let dragMoved: (CGPoint) -> Void
    let dragEnded: () -> Void
}

struct PanelView: View {
    static let width = 420.0
    static let cornerRadius = 12.0

    @ObservedObject var monitor: PingMonitor
    @ObservedObject var model: PanelModel
    let actions: PanelActions

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            // The status page sets the panel height on both pages, so switching
            // pages never moves or resizes the panel; settings scroll inside it.
            PingDashboardView(monitor: monitor)
                .frame(width: Self.width)
                .opacity(model.page == .settings ? 0 : 1)
                .accessibilityHidden(model.page == .settings)
                .allowsHitTesting(model.page == .status)
                .overlay(alignment: .top) {
                    if model.page == .settings {
                        SettingsView(monitor: monitor)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
        }
        .frame(width: Self.width, alignment: .top)
        .background {
            if !monitor.settings.panelTransparency {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .background(VisualEffectBackground(cornerRadius: Self.cornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            leadingButton
                .padding(.leading, 10)
                .frame(width: 62, alignment: .leading)

            dragHandle

            settingsToggle
            alwaysOnTopToggle
                .padding(.trailing, 10)
        }
        .frame(height: 40)
    }

    /// Quits from the status page. On the settings page the same spot closes
    /// Settings instead, so it is never mistaken for quitting the app.
    @ViewBuilder private var leadingButton: some View {
        switch model.page {
        case .status:
            headerButton(systemImage: "power", isActive: false) {
                actions.quit()
            }
            .help("Quit PingBar")
            .accessibilityLabel("Quit PingBar")
        case .settings:
            headerButton(systemImage: "xmark", isActive: false) {
                model.page = .status
            }
            .background(.quaternary, in: Circle())
            .help("Close Settings (Esc)")
            .accessibilityLabel("Close Settings")
        }
    }

    private var settingsToggle: some View {
        let isOpen = model.page == .settings
        return headerButton(systemImage: isOpen ? "gearshape.fill" : "gearshape", isActive: isOpen) {
            model.page = isOpen ? .status : .settings
        }
        .help(isOpen ? "Back to Status (⌘,)" : "Settings (⌘,)")
        .accessibilityLabel(isOpen ? "Back to Status" : "Settings")
        .keyboardShortcut(",", modifiers: .command)
    }

    private var alwaysOnTopToggle: some View {
        let isPinned = monitor.settings.alwaysOnTop
        return headerButton(systemImage: isPinned ? "pin.fill" : "pin", isActive: isPinned) {
            monitor.updateSettings { $0.alwaysOnTop.toggle() }
        }
        .help(isPinned ? "Disable always on top" : "Keep the panel above all windows")
        .accessibilityLabel("Always on top")
        .accessibilityValue(isPinned ? "On" : "Off")
    }

    private func headerButton(systemImage: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
        .background(
            isActive ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7)
        )
    }

    // MARK: - Drag handle

    private var dragHandle: some View {
        HStack(spacing: 7) {
            Image(systemName: model.isDragging ? "arrow.up.and.down.and.arrow.left.and.right" : "line.3.horizontal")
                .font(.system(size: 10, weight: .semibold))
            Text(dragHandleText)
                .font(.system(size: 9, weight: model.isDragging ? .semibold : .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(model.isDragging ? Color.accentColor : Color.secondary)
        .padding(.horizontal, 10)
        .background(
            model.isDragging ? Color.accentColor.opacity(0.1) : Color.clear,
            in: Capsule()
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .overlay {
            WindowDragHandle(
                onBegan: actions.dragBegan,
                onMoved: actions.dragMoved,
                onEnded: actions.dragEnded
            )
        }
        .help("Drag to move PingBar")
        .accessibilityLabel(dragHandleText)
    }

    private var dragHandleText: String {
        guard let status = model.dragStatus else { return "Drag to move" }
        let action = model.isDragging ? "Moving" : "Placed"
        return "\(action) · \(status.displayName) · x \(Int(status.offset.left))  y \(Int(status.offset.top))"
    }
}

/// Reports the mouse-down, drag and mouse-up of a panel move. The controller
/// moves the panel itself, so it knows exactly when a move starts and ends.
private struct WindowDragHandle: NSViewRepresentable {
    let onBegan: (CGPoint) -> Void
    let onMoved: (CGPoint) -> Void
    let onEnded: () -> Void

    func makeNSView(context: Context) -> HandleView {
        HandleView()
    }

    func updateNSView(_ view: HandleView, context: Context) {
        view.onBegan = onBegan
        view.onMoved = onMoved
        view.onEnded = onEnded
    }

    final class HandleView: NSView {
        var onBegan: (CGPoint) -> Void = { _ in }
        var onMoved: (CGPoint) -> Void = { _ in }
        var onEnded: () -> Void = {}
        private var isTracking = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: isTracking ? .closedHand : .openHand)
        }

        override func mouseDown(with event: NSEvent) {
            isTracking = true
            window?.invalidateCursorRects(for: self)
            NSCursor.closedHand.set()
            onBegan(Self.screenLocation(of: event))
        }

        override func mouseDragged(with event: NSEvent) {
            guard isTracking else { return }
            onMoved(Self.screenLocation(of: event))
        }

        override func mouseUp(with event: NSEvent) {
            guard isTracking else { return }
            isTracking = false
            window?.invalidateCursorRects(for: self)
            onEnded()
        }

        /// Where the event happened, independent of the window, which moves
        /// during the drag. Using each event's own location (rather than the
        /// pointer position when the event is handled) keeps the panel exactly
        /// under the pointer even when events are processed late.
        private static func screenLocation(of event: NSEvent) -> CGPoint {
            guard let location = event.cgEvent?.location,
                  let primaryHeight = NSScreen.screens.first?.frame.maxY else {
                return NSEvent.mouseLocation
            }
            // Quartz event coordinates start at the top-left of the primary display.
            return CGPoint(x: location.x, y: primaryHeight - location.y)
        }
    }
}

/// The translucent panel material behind the content.
private struct VisualEffectBackground: NSViewRepresentable {
    let cornerRadius: Double

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.roundedMask(radius: cornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}

    /// A stretchable rounded-rectangle mask, the documented way to give a
    /// visual effect view rounded corners.
    private static func roundedMask(radius: Double) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
