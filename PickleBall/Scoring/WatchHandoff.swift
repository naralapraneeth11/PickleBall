//
//  WatchHandoff.swift
//  PickleBall
//
//  A match set up on the phone and handed to the Watch for scoring. Saved
//  to disk because, once Start has been sent, the phone must not quietly
//  take scoring back after a relaunch: the Watch may still receive the
//  grant later. Only an accepted cancel ends it.
//

import Foundation
import CourtKit

struct WatchHandoff: Codable, Equatable {
    enum State: String, Codable {
        /// Draft sent; waiting for the Watch to save it.
        case preparing
        /// The Watch saved the draft ("Ready on Watch"). Phone scoring is
        /// still possible.
        case ready
        /// Start sent: the Watch owns scoring once it accepts.
        case starting
        /// The Watch accepted and is scoring.
        case scoringOnWatch
        /// Asked the Watch to give the match back.
        case cancelling
    }

    var draft: MatchDraft
    var grantID: UUID?
    var state: State
    var updatedAt = Date()

    var matchID: UUID { draft.matchID }

    private static func url(in directory: URL) -> URL { directory.appendingPathComponent("handoff.json") }

    static func load(from directory: URL) -> WatchHandoff? {
        guard let data = try? Data(contentsOf: url(in: directory)) else { return nil }
        return try? JSONDecoder().decode(WatchHandoff.self, from: data)
    }

    static func save(_ handoff: WatchHandoff?, to directory: URL) {
        let file = url(in: directory)
        guard let handoff else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(handoff).write(to: file, options: .atomic)
    }
}
