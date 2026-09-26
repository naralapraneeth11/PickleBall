//
//  PadelEngine.swift
//  CourtKit
//
//  Padel scoring: 15-30-40 games, sets to six with a tiebreak at 6-6, and a
//  choice of deuce rule:
//    • advantage — classic deuce/advantage, unlimited
//    • golden point — the first deuce is sudden death
//    • star point (FIP 2026) — two advantage cycles; at the third deuce the
//      next point decides the game
//  The deciding set can be a full set or a match (super) tiebreak to 10.
//
//  Points are stored raw (0, 1, 2, 3, 4…) and only turned into 15/30/40/AD
//  for display, which keeps every deuce rule a one-line predicate.
//
//  Serve rotates by game through a fixed order (A1, B1, A2, B2). In a
//  tiebreak the next server in the order serves one point, then each server
//  serves two. A tiebreak counts as one game for rotation and for ends.
//

import Foundation

public struct PadelConfig: Codable, Hashable, Sendable {
    public enum DeuceRule: String, Codable, Hashable, Sendable, CaseIterable {
        case advantage
        case goldenPoint
        case starPoint

        public var title: String {
            switch self {
            case .advantage: return "Advantage"
            case .goldenPoint: return "Golden point"
            case .starPoint: return "Star point"
            }
        }
    }

    public enum DecidingSet: Codable, Hashable, Sendable {
        case fullSet
        case superTiebreak(points: Int)
    }

    /// 1 = one set, 2 = best of three.
    public var setsToWin: Int
    public var gamesPerSet: Int
    public var tiebreakPoints: Int
    public var deuceRule: DeuceRule
    public var decidingSet: DecidingSet
    public var isDoubles: Bool
    public var firstServer: Team
    /// Which player on each team serves that team's first service game.
    public var firstServerIndex: TeamPair<Int>

    public init(
        setsToWin: Int = 2,
        gamesPerSet: Int = 6,
        tiebreakPoints: Int = 7,
        deuceRule: DeuceRule = .advantage,
        decidingSet: DecidingSet = .superTiebreak(points: 10),
        isDoubles: Bool = true,
        firstServer: Team = .a,
        firstServerIndex: TeamPair<Int> = .zero
    ) {
        self.setsToWin = max(1, setsToWin)
        self.gamesPerSet = max(1, gamesPerSet)
        self.tiebreakPoints = max(1, tiebreakPoints)
        self.deuceRule = deuceRule
        self.decidingSet = decidingSet
        self.isDoubles = isDoubles
        self.firstServer = firstServer
        self.firstServerIndex = firstServerIndex.map { $0 == 1 ? 1 : 0 }
    }

    /// Service order for the whole match.
    public var serviceOrder: [PlayerSlot] {
        let first = firstServer
        let second = firstServer.opponent
        guard isDoubles else {
            return [PlayerSlot(team: first, index: 0), PlayerSlot(team: second, index: 0)]
        }
        return [
            PlayerSlot(team: first, index: firstServerIndex[first]),
            PlayerSlot(team: second, index: firstServerIndex[second]),
            PlayerSlot(team: first, index: 1 - firstServerIndex[first]),
            PlayerSlot(team: second, index: 1 - firstServerIndex[second])
        ]
    }

    var maxSets: Int { setsToWin * 2 - 1 }
}

public enum PadelEngine: SportEngine {
    public typealias Config = PadelConfig

    public enum Mode: String, Codable, Hashable, Sendable {
        case game
        case tiebreak
        case superTiebreak
    }

    public struct State: Codable, Equatable, Sendable {
        public var config: PadelConfig
        public var mode: Mode
        /// Raw points in the current game or tiebreak.
        public var points: TeamPair<Int>
        /// Games in the current set.
        public var games: TeamPair<Int>
        public var sets: TeamPair<Int>
        public var completedSets: [CompletedUnit]
        /// Index into the service order for the current game (or for the
        /// first point of the current tiebreak).
        public var rotationIndex: Int
        /// Games played in the match, a tiebreak counting as one. Ends change
        /// whenever this becomes odd.
        public var gamesPlayed: Int
        public var totalGames: TeamPair<Int>
        public var endChanges: Int
        public var winner: Team?
    }

    public static var sport: Sport { .padel }

    public static func start(_ config: PadelConfig) -> State {
        var state = State(
            config: config,
            mode: .game,
            points: .zero,
            games: .zero,
            sets: .zero,
            completedSets: [],
            rotationIndex: 0,
            gamesPlayed: 0,
            totalGames: .zero,
            endChanges: 0,
            winner: nil
        )
        state.mode = modeForNewSet(state)
        return state
    }

    public static func rallyWon(by team: Team, in state: State) -> State {
        guard state.winner == nil else { return state }
        var next = state
        next.points[team] += 1

        switch next.mode {
        case .game:
            if hasWonGame(team, next) {
                finishGame(wonBy: team, &next)
            }

        case .tiebreak:
            if hasWonTiebreak(team, next, target: next.config.tiebreakPoints) {
                next.games[team] += 1
                let tiebreak = next.points
                closeSet(wonBy: team, unit: CompletedUnit(score: next.games, tiebreak: tiebreak), &next)
            } else if next.points.total % 6 == 0 {
                next.endChanges += 1
            }

        case .superTiebreak:
            let target: Int
            if case .superTiebreak(let points) = next.config.decidingSet { target = points } else { target = 10 }
            if hasWonTiebreak(team, next, target: target) {
                let unit = CompletedUnit(score: .zero, tiebreak: next.points, isSuperTiebreak: true)
                closeSet(wonBy: team, unit: unit, &next)
            } else if next.points.total % 6 == 0 {
                next.endChanges += 1
            }
        }
        return next
    }

    public static func winner(_ state: State) -> Team? { state.winner }

    /// The player serving the next point.
    public static func server(_ state: State) -> PlayerSlot {
        let order = state.config.serviceOrder
        switch state.mode {
        case .game:
            return order[state.rotationIndex % order.count]
        case .tiebreak, .superTiebreak:
            let played = state.points.total
            return order[(state.rotationIndex + (played + 1) / 2) % order.count]
        }
    }

    public static func display(_ state: State) -> ScoreDisplay {
        let finished = state.winner != nil
        let serverSlot = Self.server(state)
        let serving = serverSlot.team
        let phase = finished ? ScoreDisplay.Phase.finished : Self.phase(of: state)
        let labels = pointLabels(state)
        let serveSide: CourtSide = state.points.total % 2 == 0 ? .right : .left

        let call: String
        let spoken: String
        switch phase {
        case .finished:
            call = "Final"
            spoken = "game, set, match"
        case .deuce:
            call = "Deuce"
            spoken = "deuce"
        case .advantage(let team):
            call = team == serving ? "Ad in" : "Ad out"
            spoken = "advantage"
        case .decidingPoint(let kind):
            call = kind.title
            spoken = kind.title.lowercased()
        case .tiebreak, .superTiebreak:
            call = "\(state.points[serving])-\(state.points[serving.opponent])"
            spoken = "\(Spoken.number(state.points[serving])), \(Spoken.number(state.points[serving.opponent]))"
        case .regular:
            let s = labels[serving], r = labels[serving.opponent]
            call = s == r ? "\(s)-all" : "\(s)-\(r)"
            spoken = s == r
                ? "\(Spoken.padelPoint(s)) all"
                : "\(Spoken.padelPoint(s)), \(Spoken.padelPoint(r))"
        }

        return ScoreDisplay(
            sport: .padel,
            call: call,
            spokenCall: spoken,
            points: labels,
            games: state.games,
            sets: state.sets,
            totalGames: state.totalGames,
            completed: state.completedSets,
            servingTeam: finished ? nil : serving,
            server: finished ? nil : serverSlot,
            serverNumber: nil,
            serveSide: finished ? nil : serveSide,
            phase: phase,
            winner: state.winner,
            endChanges: state.endChanges,
            unitNumber: min(state.completedSets.count + 1, state.config.maxSets)
        )
    }

    // MARK: - Rules

    static func hasWonGame(_ team: Team, _ state: State) -> Bool {
        let p = state.points[team]
        let o = state.points[team.opponent]
        guard p >= 4, p > o else { return false }
        if p - o >= 2 { return true }
        // One point ahead: only a deciding point closes the game.
        switch state.config.deuceRule {
        case .advantage: return false
        case .goldenPoint: return o >= 3          // 4-3 from the first deuce
        case .starPoint: return o >= 5            // 6-5 from the third deuce
        }
    }

    static func hasWonTiebreak(_ team: Team, _ state: State, target: Int) -> Bool {
        let p = state.points[team]
        return p >= target && p - state.points[team.opponent] >= 2
    }

    private static func finishGame(wonBy team: Team, _ state: inout State) {
        state.games[team] += 1
        state.points = .zero

        let won = state.games[team]
        let lost = state.games[team.opponent]
        let target = state.config.gamesPerSet

        if won >= target && won - lost >= 2 {
            closeSet(wonBy: team, unit: CompletedUnit(score: state.games), &state)
            return
        }

        countGamePlayed(wonBy: team, &state)
        if won == target && lost == target {
            state.mode = .tiebreak
        }
    }

    /// Shared close-out for a set won on games, a tiebreak or a super tiebreak.
    private static func closeSet(wonBy team: Team, unit: CompletedUnit, _ state: inout State) {
        state.completedSets.append(unit)
        state.sets[team] += 1
        state.points = .zero
        state.games = .zero
        if state.sets[team] >= state.config.setsToWin {
            state.winner = team
            state.totalGames[team] += 1
            return
        }
        countGamePlayed(wonBy: team, &state)
        state.mode = modeForNewSet(state)
    }

    /// Advances the service rotation and the ends counter after a game (or a
    /// tiebreak, which counts as one game) that did not end the match.
    private static func countGamePlayed(wonBy team: Team, _ state: inout State) {
        state.totalGames[team] += 1
        state.rotationIndex += 1
        state.gamesPlayed += 1
        if state.gamesPlayed % 2 == 1 {
            state.endChanges += 1
        }
    }

    private static func modeForNewSet(_ state: State) -> Mode {
        let deciding = state.sets.a == state.config.setsToWin - 1
            && state.sets.b == state.config.setsToWin - 1
            && state.config.setsToWin > 1
        if deciding, case .superTiebreak = state.config.decidingSet {
            return .superTiebreak
        }
        return .game
    }

    private static func phase(of state: State) -> ScoreDisplay.Phase {
        switch state.mode {
        case .tiebreak: return .tiebreak
        case .superTiebreak: return .superTiebreak
        case .game: break
        }
        let a = state.points.a, b = state.points.b
        guard a >= 3 && b >= 3 else { return .regular }
        if a == b {
            switch state.config.deuceRule {
            case .goldenPoint: return .decidingPoint(.golden)
            case .starPoint where a >= 5: return .decidingPoint(.star)
            default: return .deuce
            }
        }
        return .advantage(a > b ? .a : .b)
    }

    private static func pointLabels(_ state: State) -> TeamPair<String> {
        guard state.winner == nil else { return TeamPair(repeating: "") }
        switch state.mode {
        case .tiebreak, .superTiebreak:
            return state.points.map(String.init)
        case .game:
            let a = state.points.a, b = state.points.b
            if a >= 3 && b >= 3 {
                if a == b { return TeamPair(repeating: "40") }
                return a > b ? TeamPair(a: "AD", b: "40") : TeamPair(a: "40", b: "AD")
            }
            let names = ["0", "15", "30", "40"]
            return TeamPair(a: names[min(a, 3)], b: names[min(b, 3)])
        }
    }
}
