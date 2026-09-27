//
//  Feed.swift
//  CourtKit
//
//  Rules for the friends-only Feed. There are no likes and no follower
//  counts: a Serve's only number is its rally, the count of Returns. A
//  Serve that goes 24 hours without a Return is a dead ball and leaves the
//  Feed (it stays in its author's archive). Every Return keeps the ball in
//  play for another 24 hours. The Feed ends; there is no infinite scroll.
//
//  The database view `feed_serves` applies the same rule.
//

import Foundation

public enum FeedRules {
    public static let deadBallAfter: TimeInterval = 24 * 60 * 60

    public static func isInPlay(createdAt: Date, lastReturnAt: Date?, now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastReturnAt ?? createdAt) < deadBallAfter
    }

    /// When the ball dies if nobody returns it.
    public static func deadBallAt(createdAt: Date, lastReturnAt: Date?) -> Date {
        (lastReturnAt ?? createdAt).addingTimeInterval(deadBallAfter)
    }

    /// Feed order: newest activity first (a fresh Return lifts a Serve).
    public static func sorted<T>(_ items: [T], createdAt: (T) -> Date, lastReturnAt: (T) -> Date?) -> [T] {
        items.sorted { lhs, rhs in
            (lastReturnAt(lhs) ?? createdAt(lhs)) > (lastReturnAt(rhs) ?? createdAt(rhs))
        }
    }
}

/// What a Serve is.
public enum ServeKind: String, Codable, Hashable, Sendable {
    case text
    case photo
    case video
    /// "Serve this result": always chosen by the player, never automatic.
    case result
}

/// What a Return is.
public enum ReturnKind: String, Codable, Hashable, Sendable {
    case comment
    case chant
    case photo
}
