import Foundation

protocol LocalBridgeTransporting: Sendable {
    func fetchNextJob(deviceID: String) async throws -> BridgeJobEnvelope?
    func postResult(_ result: BridgeJobResultEnvelope) async throws -> BridgePostResultResponse
    func replayOutbox(_ results: [BridgeJobResultEnvelope]) async throws -> BridgeOutboxReplayResponse
    func cancelJob(jobID: String, message: String) async throws -> BridgeCancelJobResponse
    func createJob(_ request: BridgeCreateJobRequest) async throws -> BridgeJobEnvelope
    func fetchStats() async throws -> BridgeStats
    func fetchQueuedJobs() async throws -> [BridgeJobEnvelope]
    func fetchResults() async throws -> [BridgeJobResultEnvelope]
    func postHeartbeat(_ heartbeat: BridgeHeartbeatRequest) async throws -> BridgeHeartbeatResponse
    func fetchDevices() async throws -> [BridgeDevicePresence]
    func askCompanion(_ request: BridgeCompanionAskRequest) async throws -> BridgeCompanionAskResponse
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

struct BridgeCancelJobResponse: Codable, Equatable, Sendable {
    let cancelled: Bool
    let result: BridgeJobResultEnvelope
}

struct BridgeCancelJobRequest: Codable, Equatable, Sendable {
    let message: String
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

struct BridgeHeartbeatRequest: Codable, Equatable, Sendable {
    let protocolVersion: String
    let deviceID: String
    let sentAt: Date
    let capabilities: [BridgeJobKind]
    let status: String
    let appVersion: String
    let pendingJobID: String?
    let outboxCount: Int
    let bridgeStatus: String

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case deviceID = "device_id"
        case sentAt = "sent_at"
        case capabilities
        case status
        case appVersion = "app_version"
        case pendingJobID = "pending_job_id"
        case outboxCount = "outbox_count"
        case bridgeStatus = "bridge_status"
    }
}

struct BridgeHeartbeatResponse: Codable, Equatable, Sendable {
    let heartbeat: BridgeDevicePresence
}

struct BridgeDevicePresence: Codable, Equatable, Sendable {
    let protocolVersion: String
    let deviceID: String
    let sentAt: Date
    let capabilities: [BridgeJobKind]
    let status: String?
    let appVersion: String?
    let pendingJobID: String?
    let outboxCount: Int?
    let bridgeStatus: String?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case deviceID = "device_id"
        case sentAt = "sent_at"
        case capabilities
        case status
        case appVersion = "app_version"
        case pendingJobID = "pending_job_id"
        case outboxCount = "outbox_count"
        case bridgeStatus = "bridge_status"
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

struct BridgeCompanionAskRequest: Codable, Equatable, Sendable {
    let protocolVersion: String
    let deviceID: String
    let prompt: String
    let context: ContextSnapshot
    let screenshot: BridgeCompanionScreenshotAttachment?
    let clientTimings: BridgeCompanionAskClientTimings?
    let sentAt: Date

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case deviceID = "device_id"
        case prompt
        case context
        case screenshot
        case clientTimings = "client_timings"
        case sentAt = "sent_at"
    }
}

struct BridgeCompanionScreenshotAttachment: Codable, Equatable, Sendable {
    let captureID: String
    let mimeType: String
    let dataBase64: String
    let width: Int
    let height: Int
    let capturedAt: Date

    enum CodingKeys: String, CodingKey {
        case captureID = "capture_id"
        case mimeType = "mime_type"
        case dataBase64 = "data_base64"
        case width
        case height
        case capturedAt = "captured_at"
    }
}

struct BridgeCompanionAskClientTimings: Codable, Equatable, Sendable {
    let contextCaptureMS: Int?
    let screenshotCaptureMS: Int?
    let screenshotEncodeMS: Int?

    enum CodingKeys: String, CodingKey {
        case contextCaptureMS = "context_capture_ms"
        case screenshotCaptureMS = "screenshot_capture_ms"
        case screenshotEncodeMS = "screenshot_encode_ms"
    }
}

struct BridgeCompanionAskTimings: Codable, Equatable, Sendable {
    let contextCaptureMS: Int?
    let screenshotCaptureMS: Int?
    let screenshotEncodeMS: Int?
    let bridgeBackendMS: Int?

    enum CodingKeys: String, CodingKey {
        case contextCaptureMS = "context_capture_ms"
        case screenshotCaptureMS = "screenshot_capture_ms"
        case screenshotEncodeMS = "screenshot_encode_ms"
        case bridgeBackendMS = "bridge_backend_ms"
    }
}

struct BridgeCompanionAskResponse: Codable, Equatable, Sendable {
    let responseID: String
    let answer: String
    let mode: String
    let createdAt: Date
    let contextSummary: String?
    let timings: BridgeCompanionAskTimings?

    enum CodingKeys: String, CodingKey {
        case responseID = "response_id"
        case answer
        case mode
        case createdAt = "created_at"
        case contextSummary = "context_summary"
        case timings
    }
}

private struct BridgeJobsResponse: Decodable {
    let jobs: [BridgeJobEnvelope]
}

private struct BridgeResultsResponse: Decodable {
    let results: [BridgeJobResultEnvelope]
}

private struct BridgeDevicesResponse: Decodable {
    let devices: [BridgeDevicePresence]
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

    func cancelJob(jobID: String, message: String = "Job cancelled from Eclipse Mac") async throws -> BridgeCancelJobResponse {
        let data = try await post(
            path: "jobs/\(jobID)/cancel",
            body: BridgeCancelJobRequest(message: message)
        )
        return try decoder.decode(BridgeCancelJobResponse.self, from: data)
    }

    func createJob(_ request: BridgeCreateJobRequest) async throws -> BridgeJobEnvelope {
        let data = try await post(path: "jobs", body: request)
        return try decoder.decode(BridgeJobEnvelope.self, from: data)
    }

    func fetchStats() async throws -> BridgeStats {
        let data = try await get(path: "stats")
        return try decoder.decode(BridgeStats.self, from: data)
    }

    func fetchQueuedJobs() async throws -> [BridgeJobEnvelope] {
        let data = try await get(path: "jobs")
        return try decoder.decode(BridgeJobsResponse.self, from: data).jobs
    }

    func fetchResults() async throws -> [BridgeJobResultEnvelope] {
        let data = try await get(path: "results")
        return try decoder.decode(BridgeResultsResponse.self, from: data).results
    }

    func postHeartbeat(_ heartbeat: BridgeHeartbeatRequest) async throws -> BridgeHeartbeatResponse {
        let data = try await post(path: "heartbeats", body: heartbeat)
        return try decoder.decode(BridgeHeartbeatResponse.self, from: data)
    }

    func fetchDevices() async throws -> [BridgeDevicePresence] {
        let data = try await get(path: "devices")
        return try decoder.decode(BridgeDevicesResponse.self, from: data).devices
    }

    func askCompanion(_ request: BridgeCompanionAskRequest) async throws -> BridgeCompanionAskResponse {
        let data = try await post(path: "ask", body: request)
        return try decoder.decode(BridgeCompanionAskResponse.self, from: data)
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
