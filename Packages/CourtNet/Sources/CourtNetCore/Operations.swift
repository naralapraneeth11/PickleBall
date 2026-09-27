//
//  Operations.swift
//  CourtNetCore
//
//  The writes that go through the offline outbox, built in one place so
//  their keys and argument names can't drift from the database.
//

import Foundation
import CourtKit

public enum Operations {
    /// Saves (or re-saves) a match. Keyed by match so only the latest
    /// version goes up.
    public static func saveMatch(_ request: SaveMatchRequest) throws -> OutboxOperation {
        try .rpc("save_match", request, key: "match:\(request.m.id)")
    }

    public static func confirmMatch(_ matchID: UUID, agree: Bool, events: [ChatEvent] = []) throws -> OutboxOperation {
        try .rpc("confirm_match", ConfirmMatchParams(mid: matchID, agree: agree, events: events), key: "confirm:\(matchID)")
    }

    public static func sendMessage(_ message: MessageDraft) throws -> OutboxOperation {
        try .insert("messages", message)
    }

    public static func sendReturn(_ draft: ReturnDraft) throws -> OutboxOperation {
        try .insert("returns", draft)
    }
}

struct ConfirmMatchParams: Codable, Hashable, Sendable {
    var mid: UUID
    var agree: Bool
    var events: [ChatEvent]
}

/// A chat message as sent. The server stamps the time.
public struct MessageDraft: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var conversationID: UUID
    public var senderID: UUID
    public var kind: MessageRow.Kind
    public var body: String?
    public var mediaPath: String?

    public init(id: UUID = UUID(), conversationID: UUID, senderID: UUID, kind: MessageRow.Kind = .text, body: String?, mediaPath: String? = nil) {
        self.id = id
        self.conversationID = conversationID
        self.senderID = senderID
        self.kind = kind
        self.body = body
        self.mediaPath = mediaPath
    }

    /// How it shows in the chat until the server's copy arrives.
    public func optimisticRow(at date: Date = Date()) -> MessageRow {
        MessageRow(id: id, conversationID: conversationID, senderID: senderID, kind: kind, body: body, mediaPath: mediaPath, createdAt: date)
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, body
        case conversationID = "conversation_id"
        case senderID = "sender_id"
        case mediaPath = "media_path"
    }
}

/// A Return as sent.
public struct ReturnDraft: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var serveID: UUID
    public var authorID: UUID
    public var kind: ReturnKind
    public var body: String?
    public var mediaPath: String?

    public init(id: UUID = UUID(), serveID: UUID, authorID: UUID, kind: ReturnKind, body: String? = nil, mediaPath: String? = nil) {
        self.id = id
        self.serveID = serveID
        self.authorID = authorID
        self.kind = kind
        self.body = body
        self.mediaPath = mediaPath
    }

    public func optimisticRow(at date: Date = Date()) -> ReturnRow {
        ReturnRow(id: id, serveID: serveID, authorID: authorID, kind: kind, body: body, mediaPath: mediaPath, createdAt: date)
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, body
        case serveID = "serve_id"
        case authorID = "author_id"
        case mediaPath = "media_path"
    }
}
