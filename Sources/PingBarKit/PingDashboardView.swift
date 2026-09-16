import Charts
import SwiftUI

/// The status dashboard shared by the macOS menu-bar panel and the iOS app.
public struct PingDashboardView: View {
    @ObservedObject var monitor: PingMonitor

    public init(monitor: PingMonitor) {
        self.monitor = monitor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ConnectionRouteView(
                sourceAddress: sourceAddress,
                target: monitor.target,
                status: connectionRouteStatus
            )

            pingTimeAndMap

            statistics

            latencyChart

            if monitor.consecutiveFailures > 0 {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(monitor.level.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(monitor.consecutiveFailures) consecutive failed request\(monitor.consecutiveFailures == 1 ? "" : "s")")
                            .font(.caption.weight(.semibold))
                        if let error = monitor.lastError {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
    }

    /// The macOS panel keeps the ping time and map on one row to stay compact.
    /// iOS has the room to give the reading its own centered row with a map
    /// large enough to actually read.
    @ViewBuilder private var pingTimeAndMap: some View {
        #if os(iOS)
            VStack(spacing: 12) {
                pingTime(alignment: .center)
                MicroWorldMap(
                    location: monitor.publicIPLocation,
                    lookupFailed: monitor.publicIPLookupFailed,
                    scale: 3,
                    dotShape: .hexagon
                )
            }
            .frame(maxWidth: .infinity)
        #else
            HStack(alignment: .center) {
                pingTime(alignment: .leading)
                Spacer()
                MicroWorldMap(
                    location: monitor.publicIPLocation,
                    lookupFailed: monitor.publicIPLookupFailed
                )
            }
        #endif
    }

    private func pingTime(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text("PING TIME")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(monitor.statusText)
                .font(.system(size: 29, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    private var statistics: some View {
        HStack(spacing: 7) {
            statistic("Average", value: formattedLatency(averageLatency))
            statistic("Minimum", value: formattedLatency(minimumLatency))
            statistic("Success", value: successRate)
        }
    }

    private func statistic(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var latencyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Text(chartWindowText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if monitor.history.isEmpty {
                Image(systemName: "waveform.path.ecg")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 110)
            } else {
                Chart(chartPoints) { point in
                    if let latency = point.latency {
                        AreaMark(
                            x: .value("Time", point.date),
                            yStart: .value("Baseline", 0),
                            yEnd: .value("Ping", latency),
                            series: .value("Run", point.segment)
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [.green.opacity(0.22), .green.opacity(0.01)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("Ping", latency),
                            series: .value("Run", point.segment)
                        )
                        .foregroundStyle(.green)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

                        if point.id == latestSuccessfulID {
                            PointMark(
                                x: .value("Time", point.date),
                                y: .value("Ping", latency)
                            )
                            .foregroundStyle(.green)
                            .symbolSize(28)
                        }
                    } else {
                        RuleMark(x: .value("Failed", point.date))
                            .foregroundStyle(.red.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    }
                }
                .chartXAxis(.hidden)
                .chartXScale(domain: chartDomain)
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine()
                        AxisValueLabel(format: Decimal.FormatStyle().precision(.fractionLength(0)))
                    }
                }
                .frame(height: 110)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private var sourceAddress: String {
        if let address = monitor.publicIPLocation?.address { return address }
        return monitor.publicIPLookupFailed ? "Unavailable" : "Locating…"
    }

    private var connectionRouteStatus: ConnectionRouteStatus {
        switch monitor.state {
        case .waiting: .waiting
        case .healthy: .active
        case .failing: monitor.level == .red ? .offline : .degraded
        }
    }

    private var successfulLatencies: [Double] {
        monitor.history.compactMap(\.latency)
    }

    private var averageLatency: Double? {
        guard !successfulLatencies.isEmpty else { return nil }
        return successfulLatencies.reduce(0, +) / Double(successfulLatencies.count)
    }

    private var minimumLatency: Double? { successfulLatencies.min() }

    private var successRate: String {
        guard !monitor.history.isEmpty else { return "--" }
        let value = Double(successfulLatencies.count) / Double(monitor.history.count) * 100
        return String(format: "%.0f%%", value)
    }

    private func formattedLatency(_ value: Double?) -> String {
        PingMonitor.displayLatencyText(milliseconds: value)
    }

    private var chartDomain: ClosedRange<Date> {
        let end = Date.now
        return end.addingTimeInterval(-monitor.settings.chartWindow)...end
    }

    private var chartWindowText: String {
        let seconds = monitor.settings.chartWindow
        if seconds >= 3_600 { return "Last \(Int(seconds / 3_600))h" }
        if seconds >= 60 { return "Last \(Int(seconds / 60))m" }
        return "Last \(Int(seconds))s"
    }

    private var chartPoints: [ChartPoint] {
        var segment = 0
        return monitor.history.map { sample in
            let point = ChartPoint(sample: sample, segment: segment)
            if sample.latency == nil { segment += 1 }
            return point
        }
    }

    private var latestSuccessfulID: UUID? {
        monitor.history.last(where: { $0.latency != nil })?.id
    }
}

private struct ChartPoint: Identifiable {
    let id: UUID
    let date: Date
    let latency: Double?
    let segment: Int

    init(sample: PingSample, segment: Int) {
        id = sample.id
        date = sample.date
        latency = sample.latency
        self.segment = segment
    }
}
