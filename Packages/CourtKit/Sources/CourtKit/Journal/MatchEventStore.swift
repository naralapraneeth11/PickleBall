//
//  MatchEventStore.swift
//  CourtKit
//
//  Durable storage for match journals, drafts and the inbox of operations
//  for matches whose manifest hasn't arrived yet. One file per match,
//  written atomically: a crash leaves either the old or the new version,
//  never half of one. Every failure is thrown, so a tap is only reported
//  as saved once it really is.
//
//  UserDefaults is never the journal.
//

import Foundation

public protocol MatchEventStore: Sendable {
    func loadJournals() throws -> [MatchJournal]
    func save(_ journal: MatchJournal) throws
    func deleteJournal(_ matchID: UUID) throws

    func loadDrafts() throws -> [MatchDraft]
    func save(_ draft: MatchDraft) throws
    func deleteDraft(_ matchID: UUID) throws

    /// Operations waiting for their match's manifest.
    func loadInbox() throws -> [MatchOperation]
    func saveInbox(_ operations: [MatchOperation]) throws
}

public enum MatchStoreError: Error, Equatable, Sendable {
    case writeFailed(String)
    case readFailed(String)
}

/// Files under a directory, typically one per account scope:
/// `<root>/matches/<id>.json`, `<root>/drafts/<id>.json`, `<root>/inbox.json`.
public struct FileMatchEventStore: MatchEventStore {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The store for one account scope (nil: signed out) under `base`.
    public static func scoped(base: URL, accountScopeID: UUID?) -> FileMatchEventStore {
        FileMatchEventStore(root: base.appendingPathComponent(accountScopeID.map { $0.uuidString.lowercased() } ?? "signed-out",
                                                              isDirectory: true))
    }

    private var matchesDirectory: URL { root.appendingPathComponent("matches", isDirectory: true) }
    private var draftsDirectory: URL { root.appendingPathComponent("drafts", isDirectory: true) }
    private var inboxURL: URL { root.appendingPathComponent("inbox.json") }

    public func loadJournals() throws -> [MatchJournal] {
        try loadAll(MatchJournal.self, in: matchesDirectory)
    }

    public func save(_ journal: MatchJournal) throws {
        try write(journal, to: matchesDirectory.appendingPathComponent("\(journal.matchID.uuidString).json"))
    }

    public func deleteJournal(_ matchID: UUID) throws {
        try remove(matchesDirectory.appendingPathComponent("\(matchID.uuidString).json"))
    }

    public func loadDrafts() throws -> [MatchDraft] {
        try loadAll(MatchDraft.self, in: draftsDirectory)
    }

    public func save(_ draft: MatchDraft) throws {
        try write(draft, to: draftsDirectory.appendingPathComponent("\(draft.matchID.uuidString).json"))
    }

    public func deleteDraft(_ matchID: UUID) throws {
        try remove(draftsDirectory.appendingPathComponent("\(matchID.uuidString).json"))
    }

    public func loadInbox() throws -> [MatchOperation] {
        guard FileManager.default.fileExists(atPath: inboxURL.path) else { return [] }
        do {
            return try JSONDecoder.courtKit.decode([MatchOperation].self, from: Data(contentsOf: inboxURL))
        } catch {
            throw MatchStoreError.readFailed("inbox: \(error)")
        }
    }

    public func saveInbox(_ operations: [MatchOperation]) throws {
        try write(operations, to: inboxURL)
    }

    // MARK: Files

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        do {
            let data = try JSONEncoder.courtKit.encode(value)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            throw MatchStoreError.writeFailed("\(url.lastPathComponent): \(error)")
        }
    }

    private func remove(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw MatchStoreError.writeFailed("\(url.lastPathComponent): \(error)")
        }
    }

    /// Every readable file. One damaged file is skipped (and reported by
    /// name) rather than hiding every other match.
    private func loadAll<T: Decodable>(_ type: T.Type, in directory: URL) throws -> [T] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".json") }
        } catch {
            throw MatchStoreError.readFailed("\(directory.lastPathComponent): \(error)")
        }
        return names.sorted().compactMap { name in
            let url = directory.appendingPathComponent(name)
            return try? JSONDecoder.courtKit.decode(T.self, from: Data(contentsOf: url))
        }
    }
}

/// For tests and previews. `failWrites` simulates a full disk.
public final class InMemoryMatchEventStore: MatchEventStore, @unchecked Sendable {
    private let lock = NSLock()
    private var journals: [UUID: MatchJournal] = [:]
    private var drafts: [UUID: MatchDraft] = [:]
    private var inbox: [MatchOperation] = []
    public var failWrites = false

    public init() {}

    public func loadJournals() throws -> [MatchJournal] { lock.withLock { Array(journals.values) } }
    public func save(_ journal: MatchJournal) throws {
        try lock.withLock {
            if failWrites { throw MatchStoreError.writeFailed("simulated") }
            journals[journal.matchID] = journal
        }
    }
    public func deleteJournal(_ matchID: UUID) throws { _ = lock.withLock { journals.removeValue(forKey: matchID) } }
    public func loadDrafts() throws -> [MatchDraft] { lock.withLock { Array(drafts.values) } }
    public func save(_ draft: MatchDraft) throws {
        try lock.withLock {
            if failWrites { throw MatchStoreError.writeFailed("simulated") }
            drafts[draft.matchID] = draft
        }
    }
    public func deleteDraft(_ matchID: UUID) throws { _ = lock.withLock { drafts.removeValue(forKey: matchID) } }
    public func loadInbox() throws -> [MatchOperation] { lock.withLock { inbox } }
    public func saveInbox(_ operations: [MatchOperation]) throws {
        try lock.withLock {
            if failWrites { throw MatchStoreError.writeFailed("simulated") }
            inbox = operations
        }
    }
}
