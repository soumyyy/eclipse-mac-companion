import Foundation

@MainActor
final class InMemoryBridgeResultStore: BridgeResultStoring {
    private struct Entry {
        let job: BridgeJobEnvelope
        var result: BridgeJobResultEnvelope
        var posted: Bool
    }

    private var entriesByIdempotencyKey: [String: Entry] = [:]
    private var idempotencyKeyByJobID: [String: String] = [:]

    func result(for idempotencyKey: String) throws -> BridgeJobResultEnvelope? {
        entriesByIdempotencyKey[idempotencyKey]?.result
    }

    func save(job: BridgeJobEnvelope, result: BridgeJobResultEnvelope) throws {
        let existingPosted = entriesByIdempotencyKey[job.idempotencyKey]?.posted ?? false
        entriesByIdempotencyKey[job.idempotencyKey] = Entry(
            job: job,
            result: result,
            posted: existingPosted
        )
        idempotencyKeyByJobID[job.jobID] = job.idempotencyKey
    }

    func unpostedResults(limit: Int) throws -> [BridgeJobResultEnvelope] {
        entriesByIdempotencyKey.values
            .filter { !$0.posted }
            .sorted { $0.result.completedAt < $1.result.completedAt }
            .prefix(limit)
            .map(\.result)
    }

    func markPosted(jobID: String) throws {
        guard let key = idempotencyKeyByJobID[jobID],
              var entry = entriesByIdempotencyKey[key] else {
            return
        }
        entry.posted = true
        entriesByIdempotencyKey[key] = entry
    }
}
