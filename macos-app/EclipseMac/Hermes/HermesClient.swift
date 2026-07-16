import Foundation

struct HermesClient: Sendable {
    private let baseURL: URL
    private let apiTokenProvider: @Sendable () async -> String
    private let conversationIDProvider: @Sendable () async -> String
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        baseURL: URL,
        apiTokenProvider: @escaping @Sendable () async -> String,
        conversationIDProvider: @escaping @Sendable () async -> String,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiTokenProvider = apiTokenProvider
        self.conversationIDProvider = conversationIDProvider
        self.session = session
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    func sendMessage(input: String) async throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HermesClientError.emptyInput
        }

        let conversationID = await conversationIDProvider()
        let body = HermesResponsesRequest(
            model: "eclipse",
            input: trimmed,
            conversation: conversationID,
            store: true
        )
        var request = try await authorizedRequest(
            path: "responses",
            method: "POST",
            conversationID: conversationID
        )
        request.httpBody = try encoder.encode(body)

        let data = try await data(for: request)
        do {
            return try decoder.decode(HermesResponsesResponse.self, from: data).assistantText()
        } catch let error as HermesClientError {
            throw error
        } catch {
            throw HermesClientError.malformedResponse(error.localizedDescription)
        }
    }

    func healthCheck() async throws -> Bool {
        let request = try await authorizedRequest(path: "health", method: "GET")
        _ = try await data(for: request)
        return true
    }

    func modelsCheck() async throws -> Bool {
        let request = try await authorizedRequest(path: "models", method: "GET")
        _ = try await data(for: request)
        return true
    }

    private func authorizedRequest(
        path: String,
        method: String,
        conversationID: String? = nil
    ) async throws -> URLRequest {
        let token = await apiTokenProvider()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw HermesClientError.missingToken
        }

        var request = URLRequest(url: endpoint(path))
        request.httpMethod = method
        request.timeoutInterval = 90
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if method != "GET" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let conversationID {
            request.setValue(conversationID, forHTTPHeaderField: "X-Hermes-Session-Key")
        }
        return request
    }

    private func endpoint(_ path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    private func data(for request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HermesClientError.malformedResponse("Hermes returned a non-HTTP response.")
            }
            try validate(httpResponse, data: data)
            return data
        } catch let error as HermesClientError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut:
                throw HermesClientError.networkUnavailable(error.localizedDescription)
            default:
                throw HermesClientError.transport(error.localizedDescription)
            }
        } catch {
            throw HermesClientError.transport(error.localizedDescription)
        }
    }

    private func validate(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw HermesClientError.unauthorized
        default:
            if let envelope = try? decoder.decode(HermesErrorEnvelope.self, from: data) {
                throw HermesClientError.hermesFailure(envelope.error.message)
            }
            let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw HermesClientError.httpStatus(response.statusCode, body)
        }
    }
}

enum HermesClientError: LocalizedError, Equatable {
    case invalidBaseURL
    case missingToken
    case emptyInput
    case unauthorized
    case networkUnavailable(String)
    case malformedResponse(String)
    case hermesFailure(String)
    case httpStatus(Int, String?)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Hermes Base URL is invalid."
        case .missingToken:
            "Missing Hermes API token. Add API_SERVER_KEY in Settings."
        case .emptyInput:
            "Enter a message before sending."
        case .unauthorized:
            "Hermes rejected the API token with 401 Unauthorized."
        case .networkUnavailable(let message):
            "Hermes is unavailable: \(message)"
        case .malformedResponse(let message):
            "Hermes returned an unexpected response: \(message)"
        case .hermesFailure(let message):
            "Hermes reported a run failure: \(message)"
        case .httpStatus(let status, let body):
            "Hermes returned HTTP \(status)\(body.map { ": \($0)" } ?? ".")"
        case .transport(let message):
            "Hermes request failed: \(message)"
        }
    }
}

