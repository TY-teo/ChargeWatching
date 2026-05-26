import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum DatabaseError: Error {
    case open(String)
    case prepare(String)
    case step(String)
    case bind(String)
}

final class Database {
    private var handle: OpaquePointer?
    let url: URL

    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        var h: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &h, flags, nil) == SQLITE_OK, h != nil else {
            let msg = h.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw DatabaseError.open(msg)
        }
        self.handle = h
        try exec("PRAGMA journal_mode = WAL")
        try exec("PRAGMA synchronous = NORMAL")
        try exec("PRAGMA temp_store = MEMORY")
        try Migrations.run(on: self)
    }

    deinit {
        if let h = handle { sqlite3_close_v2(h) }
    }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &err) == SQLITE_OK else {
            let msg = err.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(err)
            throw DatabaseError.prepare(msg)
        }
    }

    @discardableResult
    func write(_ sql: String, _ bind: (Statement) throws -> Void = { _ in }) throws -> Int64 {
        let stmt = try Statement(handle: handle, sql: sql)
        defer { stmt.finalize() }
        try bind(stmt)
        try stmt.step()
        return sqlite3_last_insert_rowid(handle)
    }

    func query<T>(_ sql: String,
                  bind: (Statement) throws -> Void = { _ in },
                  map: (Statement) throws -> T) throws -> [T] {
        let stmt = try Statement(handle: handle, sql: sql)
        defer { stmt.finalize() }
        try bind(stmt)
        var out: [T] = []
        while sqlite3_step(stmt.ptr) == SQLITE_ROW {
            try out.append(map(stmt))
        }
        return out
    }

    func scalar<T>(_ sql: String,
                   bind: (Statement) throws -> Void = { _ in },
                   map: (Statement) -> T?) throws -> T? {
        let stmt = try Statement(handle: handle, sql: sql)
        defer { stmt.finalize() }
        try bind(stmt)
        guard sqlite3_step(stmt.ptr) == SQLITE_ROW else { return nil }
        return map(stmt)
    }

    func checkpoint() {
        sqlite3_wal_checkpoint_v2(handle, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
    }
}

final class Statement {
    let ptr: OpaquePointer
    private var finalized = false

    init(handle: OpaquePointer?, sql: String) throws {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &s, nil) == SQLITE_OK, let s else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "prepare failed"
            throw DatabaseError.prepare(msg)
        }
        self.ptr = s
    }

    func finalize() {
        if !finalized {
            sqlite3_finalize(ptr)
            finalized = true
        }
    }

    func bind(_ index: Int32, _ value: Int64) throws {
        guard sqlite3_bind_int64(ptr, index, value) == SQLITE_OK else { throw DatabaseError.bind("int64") }
    }

    func bind(_ index: Int32, _ value: Int) throws {
        try bind(index, Int64(value))
    }

    func bind(_ index: Int32, _ value: Double) throws {
        guard sqlite3_bind_double(ptr, index, value) == SQLITE_OK else { throw DatabaseError.bind("double") }
    }

    func bind(_ index: Int32, _ value: String) throws {
        guard sqlite3_bind_text(ptr, index, value, -1, SQLITE_TRANSIENT) == SQLITE_OK else { throw DatabaseError.bind("text") }
    }

    func bind(_ index: Int32, nullable: Int?) throws {
        if let v = nullable { try bind(index, v) } else { try bindNull(index) }
    }

    func bind(_ index: Int32, nullable: Double?) throws {
        if let v = nullable { try bind(index, v) } else { try bindNull(index) }
    }

    func bind(_ index: Int32, nullable: String?) throws {
        if let v = nullable { try bind(index, v) } else { try bindNull(index) }
    }

    func bindNull(_ index: Int32) throws {
        guard sqlite3_bind_null(ptr, index) == SQLITE_OK else { throw DatabaseError.bind("null") }
    }

    func step() throws {
        let code = sqlite3_step(ptr)
        guard code == SQLITE_DONE || code == SQLITE_ROW else {
            throw DatabaseError.step("step code \(code)")
        }
    }

    func int(_ index: Int32) -> Int { Int(sqlite3_column_int64(ptr, index)) }
    func int64(_ index: Int32) -> Int64 { sqlite3_column_int64(ptr, index) }
    func double(_ index: Int32) -> Double { sqlite3_column_double(ptr, index) }
    func text(_ index: Int32) -> String? {
        guard let c = sqlite3_column_text(ptr, index) else { return nil }
        return String(cString: c)
    }
    func isNull(_ index: Int32) -> Bool { sqlite3_column_type(ptr, index) == SQLITE_NULL }

    func intOpt(_ index: Int32) -> Int? { isNull(index) ? nil : int(index) }
    func doubleOpt(_ index: Int32) -> Double? { isNull(index) ? nil : double(index) }
}
