#if os(macOS)

    import CoreGraphics
    import Foundation

    /// Where the panel sits on a display: the distance of its top-left corner
    /// from the top-left corner of the display's visible frame (below the menu
    /// bar, beside the Dock), in points.
    public struct PanelOffset: Codable, Equatable, Sendable {
        public var left: Double
        public var top: Double

        public init(left: Double, top: Double) {
            self.left = left
            self.top = top
        }
    }

    /// Pure geometry for placing the panel in AppKit's bottom-left-origin
    /// screen coordinates.
    public enum PanelGeometry {
        /// Gap between the menu bar and a panel opened at its default position.
        public static let menuBarGap: CGFloat = 6

        public static func offset(of frame: CGRect, in visibleFrame: CGRect) -> PanelOffset {
            PanelOffset(
                left: (frame.minX - visibleFrame.minX).rounded(),
                top: (visibleFrame.maxY - frame.maxY).rounded()
            )
        }

        /// The frame at `offset`, kept entirely inside `visibleFrame`.
        public static func frame(size: CGSize, offset: PanelOffset, in visibleFrame: CGRect) -> CGRect {
            let frame = CGRect(
                x: visibleFrame.minX + offset.left,
                y: visibleFrame.maxY - offset.top - size.height,
                width: size.width,
                height: size.height
            )
            return clamped(frame, to: visibleFrame)
        }

        /// The first-launch position: just below the status item, horizontally
        /// centred on it, or the top-right corner when it is on another display.
        public static func defaultFrame(size: CGSize, below anchor: CGRect?, in visibleFrame: CGRect) -> CGRect {
            let midX = anchor.map(\.midX) ?? (visibleFrame.maxX - size.width / 2)
            let frame = CGRect(
                x: midX - size.width / 2,
                y: visibleFrame.maxY - menuBarGap - size.height,
                width: size.width,
                height: size.height
            )
            return clamped(frame, to: visibleFrame)
        }

        /// Moves `frame` the least distance needed to fit inside `visibleFrame`.
        /// When it is taller than the display, its top edge stays visible.
        public static func clamped(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
            var result = frame
            result.origin.x = min(max(frame.minX, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - frame.width))
            result.origin.y = max(min(frame.minY, visibleFrame.maxY - frame.height), visibleFrame.minY)
            if result.maxY > visibleFrame.maxY {
                result.origin.y = visibleFrame.maxY - frame.height
            }
            return result
        }

        /// Index of the display showing most of `frame`, or the nearest display
        /// when the frame is not on any of them.
        public static func bestDisplayIndex(for frame: CGRect, among displays: [CGRect]) -> Int? {
            let overlaps = displays.enumerated().map { index, display in
                let overlap = frame.intersection(display)
                return (index, overlap.isNull ? 0 : overlap.width * overlap.height)
            }
            if let best = overlaps.max(by: { $0.1 < $1.1 }), best.1 > 0 {
                return best.0
            }
            return displays.indices.min { first, second in
                distanceSquared(frame, displays[first]) < distanceSquared(frame, displays[second])
            }
        }

        private static func distanceSquared(_ first: CGRect, _ second: CGRect) -> Double {
            let x = first.midX - second.midX
            let y = first.midY - second.midY
            return x * x + y * y
        }
    }

    /// Remembers the panel position separately for every display, so each
    /// display keeps its own placement when displays are connected or removed.
    public struct PanelPlacementStore {
        private struct Stored: Codable {
            var offsets: [String: PanelOffset] = [:]
            var lastDisplayID: String?
        }

        enum Keys {
            static let placement = "panelPlacement"
            // Written by 1.4.0 and earlier: a single offset from the top-left
            // of the visible frame of the display the panel was last on.
            static let legacyScreenX = "panelScreenX"
            static let legacyScreenTop = "panelScreenTop"
            static let legacy = [
                "panelPositionX", "panelPositionTop", "panelScreenID",
                legacyScreenX, legacyScreenTop, "panelOriginX", "panelOriginY"
            ]
        }

        private let defaults: UserDefaults

        public init(defaults: UserDefaults = .standard) {
            self.defaults = defaults
        }

        /// The offset saved for `displayID`. A display the panel has never been
        /// placed on borrows the most recent placement, so a newly connected
        /// display opens the panel where the user last put it.
        public func offset(forDisplay displayID: String) -> PanelOffset? {
            let stored = load()
            if let offset = stored.offsets[displayID] {
                return offset
            }
            if let lastID = stored.lastDisplayID, let offset = stored.offsets[lastID] {
                return offset
            }
            return legacyOffset()
        }

        public func save(_ offset: PanelOffset, forDisplay displayID: String) {
            var stored = load()
            stored.offsets[displayID] = offset
            stored.lastDisplayID = displayID
            guard let data = try? JSONEncoder().encode(stored) else { return }
            defaults.set(data, forKey: Keys.placement)
            for key in Keys.legacy {
                defaults.removeObject(forKey: key)
            }
        }

        private func load() -> Stored {
            guard let data = defaults.data(forKey: Keys.placement),
                  let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
                return Stored()
            }
            return stored
        }

        private func legacyOffset() -> PanelOffset? {
            guard defaults.object(forKey: Keys.legacyScreenX) != nil,
                  defaults.object(forKey: Keys.legacyScreenTop) != nil else {
                return nil
            }
            return PanelOffset(
                left: defaults.double(forKey: Keys.legacyScreenX),
                top: defaults.double(forKey: Keys.legacyScreenTop)
            )
        }
    }

#endif
