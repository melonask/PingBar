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
    case invalidTarget(TargetType)

    public var errorDescription: String? {
        switch self {
        case .invalidTarget(.http): "Enter a complete HTTP or HTTPS URL"
        case .invalidTarget(.icmp): "Enter an IP address or hostname"
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

    /// macOS measures ICMP round trips with the system `ping` tools: `/sbin/ping`
    /// for IPv4 and hostnames, `/sbin/ping6` for IPv6 literals.
    ///
    /// The process is awaited without blocking a thread, terminated when the
    /// calling task is cancelled, and bounded by `timeout` even where the tool
    /// itself has no timeout option (`ping6`).
    public struct ICMPPingClient: PingClient {
        public init() {}

        public func ping(target: PingTarget, timeout: TimeInterval) async throws -> PingResponse {
            guard target.type == .icmp else { throw PingError.wrongTarget(.icmp) }

            let invocation = Self.invocation(for: target.address, timeout: timeout)
            let result = try await PingProcess.run(invocation, timeout: max(timeout, 0.1))
            guard !result.timedOut else {
                throw PingError.unreachable("No reply from \(target.address)")
            }
            guard result.status == 0 else {
                throw PingError.unreachable(Self.summary(of: result.output) ?? "No reply from \(target.address)")
            }
            guard let latencyMilliseconds = Self.latencyMilliseconds(from: result.output) else {
                throw PingError.unreadableOutput
            }
            return PingResponse(statusCode: 0, duration: latencyMilliseconds / 1_000)
        }

        static func invocation(for address: String, timeout: TimeInterval) -> PingProcess.Invocation {
            // `-n` skips reverse DNS so the measurement is the round trip only.
            if address.contains(":") {
                return .init(executable: URL(fileURLWithPath: "/sbin/ping6"), arguments: ["-n", "-c", "1", address])
            }
            let seconds = String(max(Int(timeout.rounded(.up)), 1))
            return .init(executable: URL(fileURLWithPath: "/sbin/ping"), arguments: ["-n", "-c", "1", "-t", seconds, address])
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
    }

    /// Runs a short-lived command and collects its combined output.
    enum PingProcess {
        struct Invocation: Equatable {
            let executable: URL
            let arguments: [String]
        }

        struct Result {
            let status: Int32
            let output: String
            let timedOut: Bool
        }

        static func run(_ invocation: Invocation, timeout: TimeInterval) async throws -> Result {
            let process = Process()
            process.executableURL = invocation.executable
            process.arguments = invocation.arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            let deadline = Deadline()

            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    process.terminationHandler = { finished in
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        continuation.resume(returning: Result(
                            status: finished.terminationStatus,
                            output: String(bytes: data, encoding: .utf8) ?? "",
                            timedOut: deadline.hasPassed
                        ))
                    }
                    do {
                        try process.run()
                    } catch {
                        process.terminationHandler = nil
                        continuation.resume(throwing: error)
                        return
                    }
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                        guard process.isRunning else { return }
                        deadline.markPassed()
                        process.terminate()
                    }
                }
            } onCancel: {
                if process.isRunning { process.terminate() }
            }
        }

        /// Records whether the run was stopped by the timeout rather than by
        /// the tool exiting on its own.
        private final class Deadline: @unchecked Sendable {
            private let lock = NSLock()
            private var passed = false

            var hasPassed: Bool { lock.withLock { passed } }

            func markPassed() { lock.withLock { passed = true } }
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
            let packet = ICMPEcho.request(identifier: identifier, sequence: 1)

            let clock = ContinuousClock()
            let start = clock.now
            let deadline = start.advanced(by: .seconds(timeout))
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

            // Other ICMP traffic can arrive on the same socket, so keep reading
            // until the reply to this request arrives or the timeout passes.
            var reply = [UInt8](repeating: 0, count: 128)
            while clock.now < deadline {
                let received = reply.withUnsafeMutableBytes { buffer in
                    recv(descriptor, buffer.baseAddress, buffer.count, 0)
                }
                guard received > 0 else { break }
                if ICMPEcho.isReply(to: identifier, sequence: 1, in: reply[..<received]) {
                    return PingResponse(statusCode: 0, duration: start.duration(to: clock.now).secondsValue)
                }
            }
            throw PingError.unreachable("No reply from \(host)")
        }
    }

#endif

/// Builds and recognises ICMP echo packets for unprivileged datagram sockets.
enum ICMPEcho {
    private static let echoRequestType: UInt8 = 8
    private static let echoReplyType: UInt8 = 0

    static func request(identifier: UInt16, sequence: UInt16) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: 16)
        packet[0] = echoRequestType
        packet[4] = UInt8(identifier >> 8)
        packet[5] = UInt8(identifier & 0xff)
        packet[6] = UInt8(sequence >> 8)
        packet[7] = UInt8(sequence & 0xff)
        let sum = checksum(of: packet)
        packet[2] = UInt8(sum >> 8)
        packet[3] = UInt8(sum & 0xff)
        return packet
    }

    /// Darwin delivers IPv4 datagram-socket ICMP replies with the IP header
    /// still attached, so it is skipped before reading the ICMP message.
    static func isReply(to identifier: UInt16, sequence: UInt16, in datagram: ArraySlice<UInt8>) -> Bool {
        var message = datagram
        if let first = message.first, first >> 4 == 4 {
            let headerLength = Int(first & 0x0f) * 4
            guard message.count >= headerLength else { return false }
            message = message.dropFirst(headerLength)
        }
        guard message.count >= 8 else { return false }
        let bytes = Array(message)
        return bytes[0] == echoReplyType
            && UInt16(bytes[4]) << 8 | UInt16(bytes[5]) == identifier
            && UInt16(bytes[6]) << 8 | UInt16(bytes[7]) == sequence
    }

    static func checksum(of packet: [UInt8]) -> UInt16 {
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
