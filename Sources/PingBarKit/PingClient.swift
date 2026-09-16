import Foundation

public enum TargetType: String, CaseIterable, Identifiable, Sendable {
    case http
    case icmp

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .http: "HTTP"
        case .icmp: "Ping"
        }
    }
}

public struct PingTarget: Sendable, Equatable {
    public let type: TargetType
    public let address: String

    public init(type: TargetType, address: String) {
        self.type = type
        self.address = address
    }
}

public struct PingResponse: Sendable, Equatable {
    public let statusCode: Int
    public let duration: TimeInterval

    public init(statusCode: Int, duration: TimeInterval) {
        self.statusCode = statusCode
        self.duration = duration
    }
}

public enum PingError: LocalizedError, Equatable {
    case unreachable(String)
    case unreadableOutput
    case wrongTarget(TargetType)

    public var errorDescription: String? {
        switch self {
        case .unreachable(let detail): detail
        case .unreadableOutput: "Ping completed but the response could not be read"
        case .wrongTarget(let expected): "Unsupported target type: \(expected.rawValue)"
        }
    }
}

public protocol PingClient: Sendable {
    func ping(target: PingTarget, timeout: TimeInterval) async throws -> PingResponse
}

public struct HTTPPingClient: PingClient {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
    }

    public func ping(target: PingTarget, timeout: TimeInterval) async throws -> PingResponse {
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

#if os(macOS)

    /// macOS measures ICMP round trips by running the system `/sbin/ping` tool.
    public struct ICMPPingClient: PingClient {
        private static let executableURL = URL(fileURLWithPath: "/sbin/ping")

        public init() {}

        public func ping(target: PingTarget, timeout: TimeInterval) async throws -> PingResponse {
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

#else

    /// iOS has no `/sbin/ping` and cannot spawn processes, so ICMP is measured with
    /// an unprivileged datagram socket, which Apple platforms allow without root.
    public struct ICMPPingClient: PingClient {
        public init() {}

        public func ping(target: PingTarget, timeout: TimeInterval) async throws -> PingResponse {
            guard target.type == .icmp else { throw PingError.wrongTarget(.icmp) }

            let address = target.address
            let timeout = max(timeout, 0.1)
            return try await Task.detached(priority: .utility) {
                try Self.echo(to: address, timeout: timeout)
            }.value
        }

        private static func echo(to host: String, timeout: TimeInterval) throws -> PingResponse {
            var hints = addrinfo()
            hints.ai_family = AF_INET
            hints.ai_socktype = SOCK_DGRAM
            var resolved: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, nil, &hints, &resolved) == 0, let resolved else {
                throw PingError.unreachable("Could not resolve \(host)")
            }
            defer { freeaddrinfo(resolved) }
            guard let address = resolved.pointee.ai_addr else {
                throw PingError.unreachable("Could not resolve \(host)")
            }

            let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
            guard descriptor >= 0 else {
                throw PingError.unreachable("Ping is unavailable on this device")
            }
            defer { close(descriptor) }

            var receiveTimeout = timeval(
                tv_sec: Int(timeout),
                tv_usec: Int32((timeout - timeout.rounded(.down)) * 1_000_000)
            )
            setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_RCVTIMEO,
                &receiveTimeout,
                socklen_t(MemoryLayout<timeval>.size)
            )

            let identifier = UInt16.random(in: 1...UInt16.max)
            var packet = [UInt8](repeating: 0, count: 16)
            packet[0] = 8
            packet[4] = UInt8(identifier >> 8)
            packet[5] = UInt8(identifier & 0xff)
            packet[7] = 1

            let checksum = Self.checksum(of: packet)
            packet[2] = UInt8(checksum >> 8)
            packet[3] = UInt8(checksum & 0xff)

            let clock = ContinuousClock()
            let start = clock.now
            let sent = packet.withUnsafeBytes { buffer in
                sendto(
                    descriptor,
                    buffer.baseAddress,
                    buffer.count,
                    0,
                    address,
                    resolved.pointee.ai_addrlen
                )
            }
            guard sent >= 0 else {
                throw PingError.unreachable("Could not send request to \(host)")
            }

            var reply = [UInt8](repeating: 0, count: 64)
            var from = sockaddr_storage()
            var fromLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let received = reply.withUnsafeMutableBytes { buffer in
                withUnsafeMutablePointer(to: &from) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                        recvfrom(
                            descriptor,
                            buffer.baseAddress,
                            buffer.count,
                            0,
                            socketAddress,
                            &fromLength
                        )
                    }
                }
            }
            let duration = start.duration(to: clock.now)

            guard received >= 8, reply[0] == 0 else {
                throw PingError.unreachable("No reply from \(host)")
            }
            return PingResponse(statusCode: 0, duration: duration.secondsValue)
        }

        private static func checksum(of packet: [UInt8]) -> UInt16 {
            var sum: UInt32 = 0
            var index = 0
            while index + 1 < packet.count {
                sum += UInt32(packet[index]) << 8 | UInt32(packet[index + 1])
                index += 2
            }
            if index < packet.count {
                sum += UInt32(packet[index]) << 8
            }
            while sum >> 16 != 0 {
                sum = (sum & 0xffff) + (sum >> 16)
            }
            return UInt16(truncatingIfNeeded: ~sum)
        }
    }

#endif

public struct RouterPingClient: PingClient {
    private let http: any PingClient
    private let icmp: any PingClient

    public init(http: any PingClient = HTTPPingClient(), icmp: any PingClient = ICMPPingClient()) {
        self.http = http
        self.icmp = icmp
    }

    public func ping(target: PingTarget, timeout: TimeInterval) async throws -> PingResponse {
        switch target.type {
        case .http: try await http.ping(target: target, timeout: timeout)
        case .icmp: try await icmp.ping(target: target, timeout: timeout)
        }
    }
}

extension Duration {
    var secondsValue: Double {
        let components = components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
