import Foundation

protocol LocalBridgeTransporting: Sendable {
    func fetchNextJob(deviceID: String) async throws -> BridgeJobEnvelope?
    func postResult(_ result: BridgeJobResultEnvelope) async throws -> BridgePostResultResponse
    func replayOutbox(_ results: [BridgeJobResultEnvelope]) async throws -> BridgeOutboxReplayResponse
    func createJob(_ request: BridgeCreateJobRequest) async throws -> BridgeJobEnvelope
    func fetchStats() async throws -> BridgeStats
}

struct BridgePostResultResponse: Codable, Equatable, Sendable {
    let duplicate: Bool
    let result: BridgeJobResultEnvelope
}

struct BridgeOutboxReplayResponse: Codable, Equatable, Sendable {
    let accepted: Int
    let duplicates: Int
    let results: [BridgeJobResultEnvelope]
}

struct BridgeCreateJobRequest: Codable, Equatable, Sendable {
    let deviceID: String
    let kind: BridgeJobKind
    let risk: BridgeRisk
    let input: BridgeJobInput
    let ttlSeconds: Int
    let idempotencyKey: String?

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case kind
        case risk
        case input
        case ttlSeconds = "ttl_seconds"
        case idempotencyKey = "idempotency_key"
    }
}

struct BridgeStats: Codable, Equatable, Sendable {
    let queuedJobs: Int
    let results: Int

    enum CodingKeys: String, CodingKey {
        case queuedJobs = "queued_jobs"
        case results
    }
}

final class LocalBridgeHTTPClient: LocalBridgeTransporting {
    private let baseURL: URL
    private let bearerToken: String?
    private let session: URLSession
    private let encoder = BridgeJSONCoding.makeEncoder()
    private let decoder = BridgeJSONCoding.makeDecoder()

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:8765")!,
        bearerToken: String? = nil,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.session = session
    }

    func fetchNextJob(deviceID: String) async throws -> BridgeJobEnvelope? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("jobs/next"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "device_id", value: deviceID)]
        guard let url = components?.url else { throw LocalBridgeHTTPError.invalidURL }

        let (data, response) = try await session.data(for: request(url: url))
        let statusCode = try statusCode(from: response)
        if statusCode == 204 { return nil }
        try validate(statusCode: statusCode, data: data)
        return try decoder.decode(BridgeJobEnvelope.self, from: data)
    }

    func postResult(_ result: BridgeJobResultEnvelope) async throws -> BridgePostResultResponse {
        let data = try await post(path: "results", body: result)
        return try decoder.decode(BridgePostResultResponse.self, from: data)
    }

    func replayOutbox(_ results: [BridgeJobResultEnvelope]) async throws -> BridgeOutboxReplayResponse {
        let data = try await post(path: "outbox/replay", body: BridgeOutboxReplayRequest(results: results))
        return try decoder.decode(BridgeOutboxReplayResponse.self, from: data)
    }

    func createJob(_ request: BridgeCreateJobRequest) async throws -> BridgeJobEnvelope {
        let data = try await post(path: "jobs", body: request)
        return try decoder.decode(BridgeJobEnvelope.self, from: data)
    }

    func fetchStats() async throws -> BridgeStats {
        let data = try await get(path: "stats")
        return try decoder.decode(BridgeStats.self, from: data)
    }

    private func get(path: String) async throws -> Data {
        let (data, response) = try await session.data(for: request(url: baseURL.appendingPathComponent(path)))
        try validate(statusCode: try statusCode(from: response), data: data)
        return data
    }

    private func post<T: Encodable>(path: String, body: T) async throws -> Data {
        var request = request(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validate(statusCode: try statusCode(from: response), data: data)
        return data
    }

    private func request(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func statusCode(from response: URLResponse) throws -> Int {
        guard let response = response as? HTTPURLResponse else {
            throw LocalBridgeHTTPError.invalidResponse
        }
        return response.statusCode
    }

    private func validate(statusCode: Int, data: Data) throws {
        guard (200..<300).contains(statusCode) else {
            let payload = try? decoder.decode(LocalBridgeHTTPErrorPayload.self, from: data)
            throw LocalBridgeHTTPError.server(
                statusCode: statusCode,
                message: payload?.error.message ?? "Bridge request failed."
            )
        }
    }
}

private struct BridgeOutboxReplayRequest: Encodable {
    let results: [BridgeJobResultEnvelope]
}

private struct LocalBridgeHTTPErrorPayload: Decodable {
    let error: BridgeErrorPayload
}

enum LocalBridgeHTTPError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case server(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The local bridge URL is invalid."
        case .invalidResponse:
            "The local bridge returned a non-HTTP response."
        case .server(let statusCode, let message):
            "Local bridge error \(statusCode): \(message)"
        }
    }
}
