//
//  SportEngine.swift
//  CourtKit
//
//  One rules module per sport. Engines are namespaces of pure functions over
//  value-type state: no timers, no I/O, no UI. Scoring is per rally — one tap
//  for "we won the rally", one for "they won" — and the engine works out
//  points, side-outs, serve and ends.
//

import Foundation

public protocol SportEngine: Sendable {
    associatedtype Config: Codable & Hashable & Sendable
    associatedtype State: Codable & Equatable & Sendable

    static var sport: Sport { get }

    /// State before the first rally.
    static func start(_ config: Config) -> State

    /// State after `team` wins the next rally. Returns `state` unchanged once
    /// the match has a winner.
    static func rallyWon(by team: Team, in state: State) -> State

    /// Everything a scoreboard needs to render the state.
    static func display(_ state: State) -> ScoreDisplay

    static func winner(_ state: State) -> Team?
}

/// A finished game (pickleball) or set (padel).
public struct CompletedUnit: Hashable, Codable, Sendable {
    /// Points for a pickleball game, games for a padel set.
    public var score: TeamPair<Int>
    /// Tiebreak points when the set was decided by one.
    public var tiebreak: TeamPair<Int>?
    /// True when the unit was a match (super) tiebreak played instead of a set.
    public var isSuperTiebreak: Bool

    public init(score: TeamPair<Int>, tiebreak: TeamPair<Int>? = nil, isSuperTiebreak: Bool = false) {
        self.score = score
        self.tiebreak = tiebreak
        self.isSuperTiebreak = isSuperTiebreak
    }

    public var winner: Team? {
        if isSuperTiebreak, let tiebreak { return tiebreak.leader }
        if score.a == score.b, let tiebreak { return tiebreak.leader }
        return score.leader
    }

    /// "11-7", "7-6(5)", "[10-8]" from team A's point of view.
    public var label: String {
        if isSuperTiebreak, let tiebreak { return "[\(tiebreak.a)-\(tiebreak.b)]" }
        if let tiebreak {
            return "\(score.a)-\(score.b)(\(min(tiebreak.a, tiebreak.b)))"
        }
        return "\(score.a)-\(score.b)"
    }
}

public enum DecidingPointKind: String, Codable, Hashable, Sendable {
    /// Padel golden point: sudden death at the first deuce.
    case golden
    /// FIP Star Point: sudden death at the third deuce.
    case star

    public var title: String {
        switch self {
        case .golden: return "Golden point"
        case .star: return "Star point"
        }
    }
}

/// A presentation-ready snapshot of a score. Everything is derived; nothing
/// in here is ever stored or synced.
public struct ScoreDisplay: Hashable, Codable, Sendable {
    public enum Phase: Hashable, Codable, Sendable {
        case regular
        case deuce
        case advantage(Team)
        case decidingPoint(DecidingPointKind)
        case tiebreak
        case superTiebreak
        case finished
    }

    public var sport: Sport
    /// The umpire call, server first: "4-2-1", "7-5", "30-15", "Deuce".
    public var call: String
    /// The call as it should be spoken: "four, two, one".
    public var spokenCall: String
    /// The current point label per team: "4" / "40" / "AD" / tiebreak "5".
    public var points: TeamPair<String>
    /// Pickleball: games won. Padel: games in the current set.
    public var games: TeamPair<Int>
    /// Padel: sets won. Pickleball: always zero.
    public var sets: TeamPair<Int>
    /// Monotonic count of games won in the whole match (tiebreaks count as a
    /// game). Used to detect game points and game-won moments generically.
    public var totalGames: TeamPair<Int>
    /// Finished games (pickleball) or sets (padel), oldest first.
    public var completed: [CompletedUnit]
    public var servingTeam: Team?
    public var server: PlayerSlot?
    /// Pickleball side-out doubles only: 1 or 2.
    public var serverNumber: Int?
    public var serveSide: CourtSide?
    public var phase: Phase
    public var winner: Team?
    /// How many times the teams have changed ends so far. The scoreboard can
    /// use the parity to keep each team on its real side of the court.
    public var endChanges: Int
    /// 1-based number of the game (pickleball) or set (padel) in progress.
    public var unitNumber: Int

    public init(
        sport: Sport,
        call: String,
        spokenCall: String,
        points: TeamPair<String>,
        games: TeamPair<Int>,
        sets: TeamPair<Int>,
        totalGames: TeamPair<Int>,
        completed: [CompletedUnit],
        servingTeam: Team?,
        server: PlayerSlot?,
        serverNumber: Int?,
        serveSide: CourtSide?,
        phase: Phase,
        winner: Team?,
        endChanges: Int,
        unitNumber: Int
    ) {
        self.sport = sport
        self.call = call
        self.spokenCall = spokenCall
        self.points = points
        self.games = games
        self.sets = sets
        self.totalGames = totalGames
        self.completed = completed
        self.servingTeam = servingTeam
        self.server = server
        self.serverNumber = serverNumber
        self.serveSide = serveSide
        self.phase = phase
        self.winner = winner
        self.endChanges = endChanges
        self.unitNumber = unitNumber
    }

    /// The match score line: games for pickleball, sets for padel.
    public var matchScore: TeamPair<Int> {
        sport == .padel ? sets : games
    }

    /// Short status for chips and the Live Activity: "Game 2", "Tiebreak".
    public var phaseTitle: String {
        switch phase {
        case .regular:
            return sport == .padel ? "Set \(unitNumber)" : "Game \(unitNumber)"
        case .deuce: return "Deuce"
        case .advantage: return "Advantage"
        case .decidingPoint(let kind): return kind.title
        case .tiebreak: return "Tiebreak"
        case .superTiebreak: return "Super tiebreak"
        case .finished: return "Final"
        }
    }
}

// MARK: - Spoken numbers

enum Spoken {
    private static let words = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
        "eighteen", "nineteen", "twenty"
    ]

    static func number(_ n: Int) -> String {
        if n >= 0 && n < words.count { return words[n] }
        return String(n)
    }

    static func padelPoint(_ label: String) -> String {
        switch label {
        case "0": return "love"
        case "15": return "fifteen"
        case "30": return "thirty"
        case "40": return "forty"
        default: return label
        }
    }
}
