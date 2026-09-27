//
//  Outbox.swift
//  CourtNetCore
//
//  Offline-first writes. Anything that must survive a dead zone at the
//  courts — saving a result, confirming one, a chat message, a Return — is
//  written to the outbox first and sent when there's a connection.
//
//  • Operations run strictly in order, so a match is saved before the
//    message that talks about it.
//  • A network failure stops the queue and retries with backoff.
//  • A permanent failure (the server said no) is set aside so it can't
//    block everything behind it, and reported.
//  • Operations with the same key replace each other: re-saving a match
//    offline sends only the latest version.
//  • Every operation is idempotent on the server (client-generated IDs),
//    so a retry after a lost response is harmless.
//

import Foundation

public struct OutboxOperation: Codable, Hashable, Sendable, Identifiable {
    public enum Action: Codable, Hashable, Sendable {
        /// A Postgres function, with its named arguments.
        case rpc(name: String, params: JSONValue)
        /// An insert into a table the caller may write directly.
        case insert(table: String, row: JSONValue)
    }

    public let id: UUID
    public let action: Action
    /// Operations sharing a key replace each other while still queued.
    public let key: String?
    public let createdAt: Date
    public internal(set) var attempts: Int
    public internal(set) var notBefore: Date?
    public internal(set) var lastError: String?

    public init(id: UUID = UUID(), action: Action, key: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.action = action
        self.key = key
        self.createdAt = createdAt
        self.attempts = 0
    }

    public static func rpc(_ name: String, _ params: some Encodable, key: String? = nil) throws -> OutboxOperation {
        OutboxOperation(action: .rpc(name: name, params: try JSONValue(encoding: params)), key: key)
    }

    public static func insert(_ table: String, _ row: some Encodable, key: String? = nil) throws -> OutboxOperation {
        OutboxOperation(action: .insert(table: table, row: try JSONValue(encoding: row)), key: key)
    }
}

/// How an attempt went.
public enum OutboxOutcome: Hashable, Sendable {
    case sent
    /// No connection, a timeout, a 5xx, an expired session: try again later.
    case retry(String)
    /// The server refused it. Retrying won't help.
    case rejected(String)
}

/// Performs one operation against the backend.
public protocol OutboxTransport: Sendable {
    func send(_ operation: OutboxOperation) async -> OutboxOutcome
}

/// Where the queue lives between launches.
public protocol OutboxStorage: Sendable {
    func load() -> OutboxState
    func save(_ state: OutboxState)
}

public struct OutboxState: Codable, Hashable, Sendable {
    public var pending: [OutboxOperation] = []
    /// Refused operations, newest last, kept so the app can explain them.
    public var rejected: [OutboxOperation] = []

    public init(pending: [OutboxOperation] = [], rejected: [OutboxOperation] = []) {
        self.pending = pending
        self.rejected = rejected
    }
}

public actor Outbox {
    public static let maxBackoff: TimeInterval = 5 * 60
    static let keepRejected = 50

    private var state: OutboxState
    private let storage: OutboxStorage
    private var draining = false

    public init(storage: OutboxStorage) {
        self.storage = storage
        self.state = storage.load()
    }

    public var pending: [OutboxOperation] { state.pending }
    public var rejected: [OutboxOperation] { state.rejected }
    public var isEmpty: Bool { state.pending.isEmpty }

    /// Queues an operation. One already queued with the same key is
    /// replaced in place, keeping its position.
    public func enqueue(_ operation: OutboxOperation) {
        if let key = operation.key, let index = state.pending.firstIndex(where: { $0.key == key }) {
            state.pending[index] = operation
        } else {
            state.pending.append(operation)
        }
        storage.save(state)
    }

    public func isPending(key: String) -> Bool {
        state.pending.contains { $0.key == key }
    }

    /// Sends queued operations in order until the queue is empty or one
    /// needs a retry. Returns how many were sent.
    @discardableResult
    public func drain(using transport: OutboxTransport, now: @Sendable () -> Date = { Date() }) async -> Int {
        guard !draining else { return 0 }
        draining = true
        defer { draining = false }

        var sent = 0
        while let head = state.pending.first {
            if let notBefore = head.notBefore, notBefore > now() { break }
            let outcome = await transport.send(head)
            // The queue may have changed while we were waiting (a newer
            // version of the same operation). Only act on the head we sent.
            guard let index = state.pending.firstIndex(where: { $0.id == head.id }) else { continue }
            switch outcome {
            case .sent:
                state.pending.remove(at: index)
                sent += 1
            case .retry(let message):
                var op = state.pending[index]
                op.attempts += 1
                op.lastError = message
                op.notBefore = now().addingTimeInterval(Self.backoff(afterAttempts: op.attempts))
                state.pending[index] = op
                storage.save(state)
                return sent
            case .rejected(let message):
                var op = state.pending.remove(at: index)
                op.attempts += 1
                op.lastError = message
                state.rejected.append(op)
                state.rejected = Array(state.rejected.suffix(Self.keepRejected))
            }
            storage.save(state)
        }
        return sent
    }

    /// Lets queued operations go again right away (e.g. the network just
    /// came back).
    public func resetBackoff() {
        for i in state.pending.indices { state.pending[i].notBefore = nil }
        storage.save(state)
    }

    public func clearRejected() {
        state.rejected.removeAll()
        storage.save(state)
    }

    /// Signing out: nothing queued belongs to the next account.
    public func removeAll() {
        state = OutboxState()
        storage.save(state)
    }

    /// 2, 4, 8… seconds, capped at five minutes.
    static func backoff(afterAttempts attempts: Int) -> TimeInterval {
        min(maxBackoff, pow(2, Double(min(attempts, 20))))
    }
}

/// JSON file storage, written atomically.
public struct FileOutboxStorage: OutboxStorage {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> OutboxState {
        guard let data = try? Data(contentsOf: url),
              let state = try? WireCoding.decoder.decode(OutboxState.self, from: data) else { return OutboxState() }
        return state
    }

    public func save(_ state: OutboxState) {
        guard let data = try? WireCoding.encoder.encode(state) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
    }
}

/// In-memory storage for tests and previews.
public final class MemoryOutboxStorage: OutboxStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var state: OutboxState

    public init(_ state: OutboxState = OutboxState()) {
        self.state = state
    }

    public func load() -> OutboxState { lock.withLock { state } }
    public func save(_ state: OutboxState) { lock.withLock { self.state = state } }
}
