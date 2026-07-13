import Foundation

struct PingResponse: Sendable, Equatable {
    let statusCode: Int
    let duration: TimeInterval
}

protocol PingClient: Sendable {
    func ping(url: URL, timeout: TimeInterval) async throws -> PingResponse
}

struct HTTPPingClient: PingClient {
    func ping(url: URL, timeout: TimeInterval) async throws -> PingResponse {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let clock = ContinuousClock()
        let start = clock.now
        let (_, response) = try await URLSession.shared.data(for: request)
        let elapsed = start.duration(to: clock.now)

        guard let response = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let duration = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
        return PingResponse(statusCode: response.statusCode, duration: duration)
    }
}
