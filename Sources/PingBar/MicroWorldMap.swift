import SwiftUI

/// Fixed, lightweight world grid derived from DotMap's Miller projection with
/// a diagonal grid at 24 rows. A compact bit mask avoids bundling and parsing
/// the full GeoJSON dataset for a map that never changes configuration.
struct MicroWorldMap: View {
    let location: PublicIPLocation?
    let lookupFailed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: location == nil || reduceMotion)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                let layout = MapLayout(size: size)
                drawLand(in: &context, layout: layout)
                if let location {
                    drawLocation(location, at: timeline.date, in: &context, layout: layout)
                }
            }
        }
        .frame(width: 116, height: 54)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
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
        let radius = max(0.55, layout.scale * 0.1)
        var path = Path()
        for (row, mask) in Self.rowMasks.enumerated() {
            let offset = row.isMultiple(of: 2) ? 0.5 : 0
            for column in 0..<Self.columnCount where mask & (1 << UInt64(column)) != 0 {
                let point = layout.point(x: Double(column) + offset, y: Double(row) * Self.rowStep)
                path.addEllipse(in: CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
            }
        }
        context.fill(path, with: .color(.secondary.opacity(0.5)))
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
