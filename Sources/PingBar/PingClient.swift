import Foundation

enum TargetType: String, CaseIterable, Identifiable, Sendable {
    case http
    case icmp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .http: "HTTP"
        case .icmp: "Ping"
        }
    }
}

struct PingTarget: Sendable, Equatable {
    let type: TargetType
    let address: String
}

struct PingResponse: Sendable, Equatable {
    let statusCode: Int
    let duration: TimeInterval
}

enum PingError: LocalizedError, Equatable {
    case unreachable(String)
    case unreadableOutput
    case wrongTarget(TargetType)

    var errorDescription: String? {
        switch self {
        case .unreachable(let detail): detail
        case .unreadableOutput: "Ping completed but the response could not be read"
        case .wrongTarget(let expected): "Unsupported target type: \(expected.rawValue)"
        }
    }
}

protocol PingClient: Sendable {
    func ping(target: PingTarget, timeout: TimeInterval) async throws -> PingResponse
}

struct HTTPPingClient: PingClient {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
    }

    func ping(target: PingTarget, timeout: TimeInterval) async throws -> PingResponse {
        guard target.type == .http else { throw PingError.wrongTarget(.http) }
        guard let url = URL(string: target.address) else { throw URLError(.badURL) }

        var request = URLRequest(url: url, timeoutInterval: max(timeout, 0.1))
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let clock = ContinuousClock()
        let start = clock.now
        let (_, response) = try await session.data(for: request)
        let duration = start.duration(to: clock.now)

        guard let response = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        return PingResponse(statusCode: response.statusCode, duration: duration.secondsValue)
    }
}

struct ICMPPingClient: PingClient {
    private static let executableURL = URL(fileURLWithPath: "/sbin/ping")

    func ping(target: PingTarget, timeout: TimeInterval) async throws -> PingResponse {
        guard target.type == .icmp else { throw PingError.wrongTarget(.icmp) }

        return try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = Self.executableURL
            process.arguments = ["-c", "1", "-t", Self.timeoutArgument(timeout), target.address]
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            try process.run()
            process.waitUntilExit()

            let output = String(
                data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""

            guard process.terminationStatus == 0 else {
                throw PingError.unreachable(
                    Self.summary(of: output) ?? "No reply from \(target.address)"
                )
            }
            guard let latencyMilliseconds = Self.latencyMilliseconds(from: output) else {
                throw PingError.unreadableOutput
            }
            return PingResponse(statusCode: 0, duration: latencyMilliseconds / 1_000)
        }.value
    }

    static func latencyMilliseconds(from output: String) -> Double? {
        if output.contains("time<") { return 0.5 }
        guard let range = output.range(of: "time=") else { return nil }
        let remainder = output[range.upperBound...]
        guard let end = remainder.firstIndex(of: " ") else { return nil }
        return Double(remainder[..<end])
    }

    static func summary(of output: String) -> String? {
        guard let line = output.split(separator: "\n").last?.trimmingCharacters(in: .whitespaces),
              !line.isEmpty else {
            return nil
        }
        return line
    }

    private static func timeoutArgument(_ timeout: TimeInterval) -> String {
        String(max(Int(timeout.rounded(.up)), 1))
    }
}

struct RouterPingClient: PingClient {
    private let http: any PingClient
    private let icmp: any PingClient

    init(http: any PingClient = HTTPPingClient(), icmp: any PingClient = ICMPPingClient()) {
        self.http = http
        self.icmp = icmp
    }

    func ping(target: PingTarget, timeout: TimeInterval) async throws -> PingResponse {
        switch target.type {
        case .http: try await http.ping(target: target, timeout: timeout)
        case .icmp: try await icmp.ping(target: target, timeout: timeout)
        }
    }
}

private extension Duration {
    var secondsValue: Double {
        let components = components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
