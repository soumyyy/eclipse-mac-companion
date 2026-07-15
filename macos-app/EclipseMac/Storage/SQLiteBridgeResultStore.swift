import Foundation
import SQLite3

@MainActor
final class SQLiteBridgeResultStore: BridgeResultStoring {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let connection: SQLiteConnection

    static func `default`() throws -> SQLiteBridgeResultStore {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseURL.appendingPathComponent("Eclipse Mac", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try SQLiteBridgeResultStore(
            path: directory.appendingPathComponent("bridge.sqlite3").path
        )
    }

    init(path: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(path, &database) == SQLITE_OK else {
            throw BridgeResultStoreError.openFailed(Self.message(from: database))
        }
        connection = SQLiteConnection(database: database)
        try migrate()
    }

    func result(for idempotencyKey: String) throws -> BridgeJobResultEnvelope? {
        let sql = """
        SELECT result_json
        FROM bridge_results
        WHERE idempotency_key = ?
        LIMIT 1;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(idempotencyKey, at: 1, in: statement)

        let step = sqlite3_step(statement)
        guard step == SQLITE_ROW else {
            if step == SQLITE_DONE { return nil }
            throw BridgeResultStoreError.stepFailed(Self.message(from: connection.database))
        }
        guard let data = dataColumn(statement, index: 0),
              let result = try? decoder.decode(BridgeJobResultEnvelope.self, from: data) else {
            throw BridgeResultStoreError.decodeFailed
        }
        return result
    }

    func save(job: BridgeJobEnvelope, result: BridgeJobResultEnvelope) throws {
        let sql = """
        INSERT INTO bridge_results (
            job_id,
            idempotency_key,
            kind,
            status,
            job_json,
            result_json,
            created_at,
            updated_at,
            posted_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL)
        ON CONFLICT(idempotency_key) DO UPDATE SET
            job_id = excluded.job_id,
            kind = excluded.kind,
            status = excluded.status,
            job_json = excluded.job_json,
            result_json = excluded.result_json,
            updated_at = excluded.updated_at,
            posted_at = NULL;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        try bind(job.jobID, at: 1, in: statement)
        try bind(job.idempotencyKey, at: 2, in: statement)
        try bind(job.kind.rawValue, at: 3, in: statement)
        try bind(result.status.rawValue, at: 4, in: statement)
        try bind(encoder.encode(job), at: 5, in: statement)
        try bind(encoder.encode(result), at: 6, in: statement)
        try bind(Date().timeIntervalSince1970, at: 7, in: statement)
        try bind(Date().timeIntervalSince1970, at: 8, in: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw BridgeResultStoreError.stepFailed(Self.message(from: connection.database))
        }
    }

    func unpostedResults(limit: Int) throws -> [BridgeJobResultEnvelope] {
        let sql = """
        SELECT result_json
        FROM bridge_results
        WHERE posted_at IS NULL
        ORDER BY updated_at ASC
        LIMIT ?;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_int(statement, 1, Int32(limit)) == SQLITE_OK else {
            throw BridgeResultStoreError.bindFailed(Self.message(from: connection.database))
        }

        var results: [BridgeJobResultEnvelope] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let data = dataColumn(statement, index: 0),
                  let result = try? decoder.decode(BridgeJobResultEnvelope.self, from: data) else {
                throw BridgeResultStoreError.decodeFailed
            }
            results.append(result)
        }
        return results
    }

    func markPosted(jobID: String) throws {
        let sql = """
        UPDATE bridge_results
        SET posted_at = ?
        WHERE job_id = ?;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(Date().timeIntervalSince1970, at: 1, in: statement)
        try bind(jobID, at: 2, in: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw BridgeResultStoreError.stepFailed(Self.message(from: connection.database))
        }
    }

    private func migrate() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS bridge_results (
            job_id TEXT NOT NULL PRIMARY KEY,
            idempotency_key TEXT NOT NULL UNIQUE,
            kind TEXT NOT NULL,
            status TEXT NOT NULL,
            job_json BLOB NOT NULL,
            result_json BLOB NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            posted_at REAL
        );

        CREATE INDEX IF NOT EXISTS bridge_results_outbox_idx
        ON bridge_results(posted_at, updated_at);
        """

        guard sqlite3_exec(connection.database, sql, nil, nil, nil) == SQLITE_OK else {
            throw BridgeResultStoreError.migrationFailed(Self.message(from: connection.database))
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection.database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw BridgeResultStoreError.prepareFailed(Self.message(from: connection.database))
        }
        return statement
    }

    private func bind(_ value: String, at index: Int32, in statement: OpaquePointer?) throws {
        guard sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw BridgeResultStoreError.bindFailed(Self.message(from: connection.database))
        }
    }

    private func bind(_ value: Double, at index: Int32, in statement: OpaquePointer?) throws {
        guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else {
            throw BridgeResultStoreError.bindFailed(Self.message(from: connection.database))
        }
    }

    private func bind(_ data: Data, at index: Int32, in statement: OpaquePointer?) throws {
        let bytes = [UInt8](data)
        guard sqlite3_bind_blob(statement, index, bytes, Int32(bytes.count), SQLITE_TRANSIENT) == SQLITE_OK else {
            throw BridgeResultStoreError.bindFailed(Self.message(from: connection.database))
        }
    }

    private func dataColumn(_ statement: OpaquePointer?, index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, index) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, index))
        return Data(bytes: bytes, count: count)
    }

    private static func message(from database: OpaquePointer?) -> String {
        guard let database, let message = sqlite3_errmsg(database) else {
            return "unknown SQLite error"
        }
        return String(cString: message)
    }
}

private final class SQLiteConnection {
    let database: OpaquePointer?

    init(database: OpaquePointer?) {
        self.database = database
    }

    deinit {
        sqlite3_close(database)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
