import SwiftUI

/// Shape drawn for each land cell of the dotted world grid.
public enum MicroWorldMapLandShape: String, CaseIterable, Identifiable, Sendable {
    case circle
    case hexagon

    public var id: String { rawValue }
}

/// Fixed, lightweight world grid derived from DotMap's Miller projection with
/// a diagonal grid at 24 rows. A compact bit mask avoids bundling and parsing
/// the full GeoJSON dataset for a map that never changes configuration.
public struct MicroWorldMap: View {
    public let location: PublicIPLocation?
    public let lookupFailed: Bool
    private let scale: CGFloat
    private let dotShape: MicroWorldMapLandShape

    /// - Parameters:
    ///   - scale: Multiplier applied to the compact 116×54 menu-bar footprint.
    ///     The iOS dashboard uses a larger map than the macOS panel.
    ///   - dotShape: Shape used for each land cell of the dotted world grid.
    public init(
        location: PublicIPLocation?,
        lookupFailed: Bool,
        scale: CGFloat = 1,
        dotShape: MicroWorldMapLandShape = .circle
    ) {
        self.location = location
        self.lookupFailed = lookupFailed
        self.scale = scale
        self.dotShape = dotShape
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: location == nil || reduceMotion)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                let layout = MapLayout(size: size)
                drawLand(in: &context, layout: layout)
                if let location {
                    drawLocation(location, at: timeline.date, in: &context, layout: layout)
                }
            }
        }
        .frame(width: 116 * scale, height: 54 * scale)
        .padding(.horizontal, 7 * scale)
        .padding(.vertical, 4 * scale)
        .overlay {
            if location == nil {
                if lookupFailed {
                    Image(systemName: "location.slash")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .help(accessibilityText)
    }

    private func drawLand(in context: inout GraphicsContext, layout: MapLayout) {
        // Dot size is a ratio of the lattice spacing, so the map keeps the same
        // density at any scale. A fixed floor would leave the 3× iOS map with
        // menu-bar-sized dots and wide gaps between them.
        let radius = layout.scale * Self.dotRadiusRatio
        var path = Path()
        for (row, mask) in Self.rowMasks.enumerated() {
            let offset = row.isMultiple(of: 2) ? 0.5 : 0
            for column in 0..<Self.columnCount where mask & (1 << UInt64(column)) != 0 {
                let point = layout.point(x: Double(column) + offset, y: Double(row) * Self.rowStep)
                switch dotShape {
                case .circle:
                    path.addEllipse(in: CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    ))
                case .hexagon:
                    // The lattice is already hexagonal (√3/2 row step with a
                    // half-column offset), so pointy-top hexagons tile it with
                    // no seams as the radius approaches 1/√3 of the spacing.
                    path.addPath(Self.hexagon(
                        center: point,
                        radius: layout.scale * Self.hexagonRadiusRatio
                    ))
                }
            }
        }
        context.fill(path, with: .color(.secondary.opacity(0.5)))
    }

    private static func hexagon(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        for corner in 0..<6 {
            let angle = (Double(corner) * 60 - 90) * .pi / 180
            let point = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            if corner == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }

    private func drawLocation(
        _ location: PublicIPLocation,
        at date: Date,
        in context: inout GraphicsContext,
        layout: MapLayout
    ) {
        let mapPoint = Self.mapPoint(latitude: location.latitude, longitude: location.longitude)
        let point = layout.point(x: mapPoint.x, y: mapPoint.y)
        let phase = reduceMotion ? 0 : date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
        let haloRadius = 3 + phase * 5
        let haloOpacity = reduceMotion ? 0.35 : 0.55 * (1 - phase)

        let halo = Path(ellipseIn: CGRect(
            x: point.x - haloRadius,
            y: point.y - haloRadius,
            width: haloRadius * 2,
            height: haloRadius * 2
        ))
        context.stroke(halo, with: .color(.green.opacity(haloOpacity)), lineWidth: 1)

        let markerRadius = 2.2
        let marker = Path(ellipseIn: CGRect(
            x: point.x - markerRadius,
            y: point.y - markerRadius,
            width: markerRadius * 2,
            height: markerRadius * 2
        ))
        context.fill(marker, with: .color(.green))
        context.addFilter(.shadow(color: .green.opacity(0.8), radius: 2))
        context.stroke(marker, with: .color(.white.opacity(0.85)), lineWidth: 0.7)
    }

    private var accessibilityText: String {
        guard let location else {
            return lookupFailed ? "Public IP location unavailable" : "Locating public IP address"
        }
        return "Public IP \(location.address), approximately \(location.latitude), \(location.longitude)"
    }

    private struct MapLayout {
        let scale: CGFloat
        let xOffset: CGFloat
        let yOffset: CGFloat

        init(size: CGSize) {
            let insetSize = CGSize(width: max(size.width - 8, 0), height: max(size.height - 8, 0))
            scale = min(insetSize.width / SelfMap.width, insetSize.height / SelfMap.height)
            xOffset = (size.width - SelfMap.width * scale) / 2
            yOffset = (size.height - SelfMap.height * scale) / 2
        }

        func point(x: Double, y: Double) -> CGPoint {
            CGPoint(x: xOffset + x * scale, y: yOffset + y * scale)
        }

        private enum SelfMap {
            static let width: CGFloat = 54
            static let height: CGFloat = 24
        }
    }

    private static func mapPoint(latitude: Double, longitude: Double) -> CGPoint {
        let latitude = min(max(latitude, -56), 71)
        let longitude = min(max(longitude, -168), 168)
        let rawX = 54 * (longitude + 168) / 336
        let rawY = 24 * (millerY(71) - millerY(latitude)) / (millerY(71) - millerY(-56))
        let row = min(max(Int((rawY / rowStep).rounded()), 0), rowMasks.count - 1)
        let offset = row.isMultiple(of: 2) ? 0.5 : 0
        let column = min(max(Int((rawX - offset).rounded()), 0), columnCount - 1)
        return CGPoint(x: Double(column) + offset, y: Double(row) * rowStep)
    }

    private static func millerY(_ latitude: Double) -> Double {
        1.25 * log(tan(.pi / 4 + latitude * .pi / 180 / 2.5))
    }

    private static let columnCount = 54
    private static let rowStep = sqrt(3.0) / 2

    /// Cell radius as a fraction of the lattice spacing. Matches the original
    /// menu-bar map, where 0.55 pt sat against a 1.92 pt spacing.
    private static let dotRadiusRatio = 0.287

    /// Hexagon circumradius as a fraction of the lattice spacing. Cells meet
    /// their six neighbours at 1/√3 (≈ 0.577), so stopping short keeps a gap
    /// between them the way the circle map has.
    private static let hexagonRadiusRatio = 0.46
    private static let rowMasks: [UInt64] = [
        0x07ffc08078e300, 0x3fff73c03915fe, 0x3fffffa188ffff, 0x3fffffb0108ffe,
        0x11ffffa4018fe4, 0x03ffffe403bf80, 0x03fffff800ff80, 0x03fff4f803ff00,
        0x00fff5e4007f80, 0x027ffe14007f00, 0x007ffe7e003f00, 0x007feffe004e00,
        0x001ddfff004400, 0x00198ffe001000, 0x000083fe002000, 0x000007fc078000,
        0x00e803f007c000, 0x041003e03fc000, 0x000001e01fc000, 0x058003e01f0000,
        0x27c005e00f0000, 0x0fc001c00f0000, 0x0fc000c0078000, 0x0c000000030000,
        0x00000000018000, 0x00000000010000, 0x00000000008000, 0x00000000010000
    ]
}
