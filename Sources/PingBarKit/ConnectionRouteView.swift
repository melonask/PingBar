import SwiftUI

public enum ConnectionRouteStatus: Equatable {
    case waiting
    case active
    case degraded
    case offline

    public var color: Color {
        switch self {
        case .waiting: .secondary
        case .active: .green
        case .degraded: .yellow
        case .offline: .red
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .waiting: "Waiting for first check"
        case .active: "Connection active"
        case .degraded: "Connection interrupted"
        case .offline: "Connection offline"
        }
    }
}

public struct ConnectionRouteView: View {
    public let sourceAddress: String
    public let target: PingTarget
    public let status: ConnectionRouteStatus

    public init(sourceAddress: String, target: PingTarget, status: ConnectionRouteStatus) {
        self.sourceAddress = sourceAddress
        self.target = target
        self.status = status
    }

    public var body: some View {
        HStack(spacing: 7) {
            addressButton(sourceAddress, label: sourceLabel, alignment: .center)
                .frame(width: 116)

            Image(systemName: "house.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

            ConnectionFlowIndicator(status: status)
                .frame(width: 48)

            DestinationIcon(target: target)

            addressButton(
                target.address,
                displayValue: displayedTargetAddress,
                label: targetLabel,
                alignment: .center
            )
            .frame(width: 116)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(status.color.opacity(status == .waiting ? 0.08 : 0.18), lineWidth: 0.7)
        }
    }

    private func addressButton(
        _ value: String,
        displayValue: String? = nil,
        label: String,
        alignment: HorizontalAlignment
    ) -> some View {
        Button {
            PlatformPasteboard.copy(value)
        } label: {
            VStack(alignment: alignment, spacing: 2) {
                Text(label)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(displayValue ?? value)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: frameAlignment(for: alignment))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(value) — click to copy")
        .accessibilityLabel("\(label): \(value). Click to copy")
    }

    private func frameAlignment(for alignment: HorizontalAlignment) -> Alignment {
        if alignment == .leading { return .leading }
        if alignment == .trailing { return .trailing }
        return .center
    }

    private var targetLabel: String {
        switch target.type {
        case .http: "DESTINATION"
        case .icmp: "DEVICE"
        }
    }

    /// The address on the left is always the device running the app, which is a
    /// Mac on macOS and an iPhone on iOS.
    private var sourceLabel: String {
        #if os(iOS)
            "THIS IPHONE"
        #else
            "THIS MAC"
        #endif
    }

    private var displayedTargetAddress: String {
        guard target.type == .http else { return target.address }
        var value = target.address
        for prefix in ["https://", "http://"] where value.lowercased().hasPrefix(prefix) {
            value.removeFirst(prefix.count)
            break
        }
        if value.lowercased().hasPrefix("www.") {
            value.removeFirst(4)
        }
        return value
    }
}

private struct ConnectionFlowIndicator: View {
    let status: ConnectionRouteStatus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.16, paused: status != .active || reduceMotion)) { timeline in
            let activeIndex = Int(timeline.date.timeIntervalSinceReferenceDate * 5) % 3
            HStack(spacing: 1) {
                ForEach(0..<3) { index in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .opacity(opacity(for: index, activeIndex: activeIndex))
                        .scaleEffect(status == .active && !reduceMotion && index == activeIndex ? 1.08 : 0.92)
                }
            }
            .foregroundStyle(status.color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.accessibilityLabel)
    }

    private func opacity(for index: Int, activeIndex: Int) -> Double {
        guard status == .active, !reduceMotion else {
            return status == .waiting ? 0.35 : 0.9
        }
        return index == activeIndex ? 1 : 0.22
    }
}

private struct DestinationIcon: View {
    let target: PingTarget

    @State private var favicon: PlatformImage?

    var body: some View {
        Group {
            if let favicon {
                Image(platformImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(3)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
        .task(id: faviconURL) {
            favicon = nil
            guard let faviconURL else { return }
            favicon = await FaviconLoader.shared.image(for: faviconURL)
        }
    }

    private var faviconURL: URL? {
        guard target.type == .http,
              let targetURL = URL(string: target.address),
              let scheme = targetURL.scheme,
              let host = targetURL.host else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = targetURL.port
        components.path = "/favicon.ico"
        return components.url
    }
}

@MainActor
private final class FaviconLoader {
    static let shared = FaviconLoader()

    private let cache = NSCache<NSURL, PlatformImage>()
    private var recentFailures: [NSURL: Date] = [:]
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 5
        session = URLSession(configuration: configuration)
        cache.countLimit = 32
    }

    func image(for url: URL) async -> PlatformImage? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) { return cached }
        if let failureDate = recentFailures[key], failureDate > Date.now.addingTimeInterval(-600) {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard !Task.isCancelled,
                  let response = response as? HTTPURLResponse,
                  200..<300 ~= response.statusCode,
                  data.count <= 1_000_000,
                  let image = PlatformImage(data: data) else {
                recentFailures[key] = .now
                return nil
            }
            recentFailures[key] = nil
            cache.setObject(image, forKey: key)
            return image
        } catch {
            if !Task.isCancelled {
                recentFailures[key] = .now
            }
            return nil
        }
    }
}
