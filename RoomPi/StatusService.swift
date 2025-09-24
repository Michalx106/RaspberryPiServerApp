import Foundation

struct StatusService {
    struct BasicCredentials {
        let username: String
        let password: String
    }

    struct ShellyCommandResponse: Decodable, Equatable {
        let success: Bool?
        let message: String?
        let state: String?

        static let successPlaceholder = ShellyCommandResponse(success: true, message: nil, state: nil)

        var isSuccessful: Bool { success ?? true }
    }

    enum ServiceError: LocalizedError {
        case invalidURL
        case invalidResponse
        case httpError(statusCode: Int, message: String?)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Nieprawidłowy adres usługi API."
            case .invalidResponse:
                return "Nieoczekiwana odpowiedź serwera."
            case let .httpError(statusCode, message):
                if let message, !message.isEmpty {
                    return "Serwer zwrócił błąd (\(statusCode)): \(message)"
                }
                return "Serwer zwrócił błąd (\(statusCode))."
            }
        }
    }

    let baseURL: URL
    var session: URLSession = .shared
    var credentials: BasicCredentials?

    enum ShellyCommand: String {
        case turnOn = "on"
        case turnOff = "off"
        case toggle
    }

    func fetchStatusBundle(historyLimit: Int? = 120) async throws -> StatusBundle {
        guard let requestURL = makeBundleURL(historyLimit: historyLimit) else {
            throw ServiceError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let credentials {
            let token = "\(credentials.username):\(credentials.password)"
            if let data = token.data(using: .utf8) {
                request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
            }
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let payload = String(data: data, encoding: .utf8)
            throw ServiceError.httpError(statusCode: httpResponse.statusCode, message: payload)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(StatusBundle.self, from: data)
    }

    func sendShellyCommand(deviceID: String, command: ShellyCommand, overrideURL: URL? = nil) async throws -> ShellyCommandResponse {
        guard let requestURL = overrideURL ?? makeShellyCommandURL(deviceID: deviceID, command: command) else {
            throw ServiceError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let credentials {
            let token = "\(credentials.username):\(credentials.password)"
            if let data = token.data(using: .utf8) {
                request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
            }
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let payload = String(data: data, encoding: .utf8)
            throw ServiceError.httpError(statusCode: httpResponse.statusCode, message: payload)
        }

        guard !data.isEmpty else {
            return .successPlaceholder
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let response = try? decoder.decode(ShellyCommandResponse.self, from: data) {
            return response
        }

        let message = String(data: data, encoding: .utf8)
        return ShellyCommandResponse(success: true, message: message, state: nil)
    }

    private func makeBundleURL(historyLimit: Int?) -> URL? {
        var bundleURL = baseURL

        if bundleURL.pathExtension.lowercased() != "php" {
            bundleURL.appendPathComponent("index.php")
        }

        var components = URLComponents(url: bundleURL, resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "status", value: "ios")]
        if let historyLimit {
            queryItems.append(URLQueryItem(name: "limit", value: String(historyLimit)))
        }
        components?.queryItems = queryItems

        return components?.url
    }

    private func makeShellyCommandURL(deviceID: String, command: ShellyCommand) -> URL? {
        var shellyURL = baseURL

        if shellyURL.pathExtension.lowercased() == "php" {
            shellyURL.deleteLastPathComponent()
        }

        shellyURL.appendPathComponent("shelly.php")

        var components = URLComponents(url: shellyURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "device", value: deviceID),
            URLQueryItem(name: "command", value: command.rawValue)
        ]

        return components?.url
    }
}
