//
//  MatchRules.swift
//  CourtKit
//
//  Type erasure over the engines so the app can hold "a match" without
//  knowing at compile time which sport or format it is.
//

import Foundation

public enum PickleballScoring: String, Codable, Hashable, Sendable, CaseIterable {
    case sideOut
    case rally

    public var title: String {
        switch self {
        case .sideOut: return "Side-out"
        case .rally: return "Rally"
        }
    }
}

public enum MatchRules: Hashable, Sendable {
    case pickleball(PickleballScoring, PickleballConfig)
    case padel(PadelConfig)

    public var sport: Sport {
        switch self {
        case .pickleball: return .pickleball
        case .padel: return .padel
        }
    }

    public var isDoubles: Bool {
        switch self {
        case .pickleball(_, let config): return config.isDoubles
        case .padel(let config): return config.isDoubles
        }
    }

    public var firstServer: Team {
        switch self {
        case .pickleball(_, let config): return config.firstServer
        case .padel(let config): return config.firstServer
        }
    }

    /// One-line description: "Side-out · to 11 · best of 3".
    public var summary: String {
        switch self {
        case .pickleball(let scoring, let config):
            var parts = [scoring.title, "to \(config.pointsToWin)"]
            if config.gamesToWin > 1 { parts.append("best of \(config.maxGames)") }
            return parts.joined(separator: " · ")
        case .padel(let config):
            var parts = [config.setsToWin > 1 ? "Best of \(config.maxSets) sets" : "1 set", config.deuceRule.title]
            if config.setsToWin > 1, case .superTiebreak(let points) = config.decidingSet {
                parts.append("super tiebreak to \(points)")
            }
            return parts.joined(separator: " · ")
        }
    }

    /// Defaults per sport, used by quick-start flows.
    public static func standard(for sport: Sport, isDoubles: Bool = true, firstServer: Team = .a) -> MatchRules {
        switch sport {
        case .pickleball:
            return .pickleball(.sideOut, PickleballConfig(isDoubles: isDoubles, firstServer: firstServer))
        case .padel:
            return .padel(PadelConfig(isDoubles: isDoubles, firstServer: firstServer))
        }
    }

    public func start() -> ScoreState {
        switch self {
        case .pickleball(.sideOut, let config): return .pickleballSideOut(PickleballSideOutEngine.start(config))
        case .pickleball(.rally, let config): return .pickleballRally(PickleballRallyEngine.start(config))
        case .padel(let config): return .padel(PadelEngine.start(config))
        }
    }
}

// MARK: - Stable Codable form

extension MatchRules: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, pickleball, padel
    }

    private enum Kind: String, Codable {
        case pickleballSideOut, pickleballRally, padel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .pickleballSideOut:
            self = .pickleball(.sideOut, try container.decode(PickleballConfig.self, forKey: .pickleball))
        case .pickleballRally:
            self = .pickleball(.rally, try container.decode(PickleballConfig.self, forKey: .pickleball))
        case .padel:
            self = .padel(try container.decode(PadelConfig.self, forKey: .padel))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pickleball(.sideOut, let config):
            try container.encode(Kind.pickleballSideOut, forKey: .kind)
            try container.encode(config, forKey: .pickleball)
        case .pickleball(.rally, let config):
            try container.encode(Kind.pickleballRally, forKey: .kind)
            try container.encode(config, forKey: .pickleball)
        case .padel(let config):
            try container.encode(Kind.padel, forKey: .kind)
            try container.encode(config, forKey: .padel)
        }
    }
}

// MARK: - Erased state

public enum ScoreState: Equatable, Sendable {
    case pickleballSideOut(PickleballSideOutEngine.State)
    case pickleballRally(PickleballRallyEngine.State)
    case padel(PadelEngine.State)

    public func rallyWon(by team: Team) -> ScoreState {
        switch self {
        case .pickleballSideOut(let s): return .pickleballSideOut(PickleballSideOutEngine.rallyWon(by: team, in: s))
        case .pickleballRally(let s): return .pickleballRally(PickleballRallyEngine.rallyWon(by: team, in: s))
        case .padel(let s): return .padel(PadelEngine.rallyWon(by: team, in: s))
        }
    }

    public var display: ScoreDisplay {
        switch self {
        case .pickleballSideOut(let s): return PickleballSideOutEngine.display(s)
        case .pickleballRally(let s): return PickleballRallyEngine.display(s)
        case .padel(let s): return PadelEngine.display(s)
        }
    }

    public var winner: Team? {
        switch self {
        case .pickleballSideOut(let s): return PickleballSideOutEngine.winner(s)
        case .pickleballRally(let s): return PickleballRallyEngine.winner(s)
        case .padel(let s): return PadelEngine.winner(s)
        }
    }
}
