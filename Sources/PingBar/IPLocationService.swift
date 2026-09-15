import Foundation

struct PublicIPLocation: Equatable, Sendable {
    let address: String
    let latitude: Double
    let longitude: Double
}

protocol PublicIPLocationClient: Sendable {
    func locate() async throws -> PublicIPLocation
}

enum IPLocationError: LocalizedError, Equatable {
    case invalidResponse(String)
    case allProvidersFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let provider): "Invalid location response from \(provider)"
        case .allProvidersFailed: "Public IP location is temporarily unavailable"
        }
    }
}

struct IPLocationService: PublicIPLocationClient {
    private enum Provider: CaseIterable, Sendable {
        case ipWhoIs
        case ipInfo

        var name: String {
            switch self {
            case .ipWhoIs: "ipwho.is"
            case .ipInfo: "ipinfo.io"
            }
        }

        var url: URL {
            switch self {
            case .ipWhoIs: URL(string: "https://ipwho.is/")!
            case .ipInfo: URL(string: "https://ipinfo.io/json")!
            }
        }
    }

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.timeoutIntervalForRequest = 6
            configuration.timeoutIntervalForResource = 8
            self.session = URLSession(configuration: configuration)
        }
    }

    func locate() async throws -> PublicIPLocation {
        for provider in Provider.allCases {
            try Task.checkCancellation()
            do {
                var request = URLRequest(url: provider.url)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse,
                      200..<300 ~= response.statusCode else {
                    throw IPLocationError.invalidResponse(provider.name)
                }
                return try Self.parse(data, providerName: provider.name)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                continue
            }
        }
        throw IPLocationError.allProvidersFailed
    }

    static func parse(_ data: Data, providerName: String) throws -> PublicIPLocation {
        switch providerName {
        case "ipwho.is":
            let response = try JSONDecoder().decode(IPWhoIsResponse.self, from: data)
            guard response.success != false,
                  let address = response.ip,
                  !address.isEmpty,
                  let latitude = response.latitude?.value,
                  let longitude = response.longitude?.value,
                  Self.isValid(latitude: latitude, longitude: longitude) else {
                throw IPLocationError.invalidResponse(providerName)
            }
            return PublicIPLocation(address: address, latitude: latitude, longitude: longitude)
        case "ipinfo.io":
            let response = try JSONDecoder().decode(IPInfoResponse.self, from: data)
            let coordinates = response.loc?.split(separator: ",", omittingEmptySubsequences: false)
            guard let address = response.ip,
                  !address.isEmpty,
                  let coordinates, coordinates.count == 2,
                  let latitude = Double(coordinates[0].trimmingCharacters(in: .whitespaces)),
                  let longitude = Double(coordinates[1].trimmingCharacters(in: .whitespaces)),
                  Self.isValid(latitude: latitude, longitude: longitude) else {
                throw IPLocationError.invalidResponse(providerName)
            }
            return PublicIPLocation(address: address, latitude: latitude, longitude: longitude)
        default:
            throw IPLocationError.invalidResponse(providerName)
        }
    }

    private static func isValid(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
    }
}

private struct IPWhoIsResponse: Decodable {
    let success: Bool?
    let ip: String?
    let latitude: FlexibleDouble?
    let longitude: FlexibleDouble?
}

private struct IPInfoResponse: Decodable {
    let ip: String?
    let loc: String?
}

private struct FlexibleDouble: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else {
            let string = try container.decode(String.self)
            guard let number = Double(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a number")
            }
            value = number
        }
    }
}
