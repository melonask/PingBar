import AppKit

/// The borderless floating panel that hosts the status and settings pages.
///
/// Like Spotlight, it becomes key so the settings fields accept typing without
/// activating the app, so the frontmost app keeps its menus and focus. It is
/// only moved through `PanelController`, never by AppKit, so every position
/// change is one the controller knows about.
final class StatusPanel: NSPanel {
    /// Called for Escape (`cancelOperation`) when no control handled it.
    var onCancel: (() -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
