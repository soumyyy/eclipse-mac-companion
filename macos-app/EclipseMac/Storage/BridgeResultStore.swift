import Foundation

@MainActor
protocol BridgeResultStoring: AnyObject {
    func result(for idempotencyKey: String) throws -> BridgeJobResultEnvelope?
    func save(job: BridgeJobEnvelope, result: BridgeJobResultEnvelope) throws
    func unpostedResults(limit: Int) throws -> [BridgeJobResultEnvelope]
    func markPosted(jobID: String) throws
}

enum BridgeResultStoreError: LocalizedError {
    case openFailed(String)
    case migrationFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            "Could not open the local bridge store: \(message)"
        case .migrationFailed(let message):
            "Could not prepare the local bridge store: \(message)"
        case .prepareFailed(let message):
            "Could not prepare a bridge store statement: \(message)"
        case .stepFailed(let message):
            "Could not run a bridge store statement: \(message)"
        case .bindFailed(let message):
            "Could not bind a bridge store value: \(message)"
        case .decodeFailed:
            "Could not decode a stored bridge result."
        }
    }
}
