//
//  PickleballSideOutEngine.swift
//  CourtKit
//
//  Traditional side-out scoring: only the serving side scores. In doubles
//  both partners serve before a side-out (server 1, then server 2), except
//  at the start of each game where the first serving team gets one server
//  only — the "0-0-2" start.
//
//  Player positions are tracked so the engine knows exactly who serves and
//  from which court: serving partners switch sides after every point they
//  win, receivers never move, and after a side-out the player in the right
//  court serves first.
//

import Foundation

public enum PickleballSideOutEngine: SportEngine {
    public typealias Config = PickleballConfig

    public struct State: PickleballGameState {
        public var config: PickleballConfig
        public var score: TeamPair<Int>
        public var servingTeam: Team
        /// 1 or 2 in doubles, always 1 in singles.
        public var serverNumber: Int
        /// Roster index of the current server within `servingTeam`.
        public var serverIndex: Int
        /// Roster index of the player in the right court, per team.
        public var rightCourt: TeamPair<Int>
        public var gamesWon: TeamPair<Int>
        public var completedGames: [TeamPair<Int>]
        public var endChanges: Int
        public var didMidGameSwitch: Bool
        public var winner: Team?
    }

    public static var sport: Sport { .pickleball }

    public static func start(_ config: PickleballConfig) -> State {
        var state = State(
            config: config,
            score: .zero,
            servingTeam: config.firstServer,
            serverNumber: 1,
            serverIndex: 0,
            rightCourt: config.startingRightCourt,
            gamesWon: .zero,
            completedGames: [],
            endChanges: 0,
            didMidGameSwitch: false,
            winner: nil
        )
        beginGame(&state)
        return state
    }

    public static func rallyWon(by team: Team, in state: State) -> State {
        guard state.winner == nil else { return state }
        var next = state

        if team == next.servingTeam {
            next.score[team] += 1
            if next.config.isDoubles {
                next.rightCourt[team] = 1 - next.rightCourt[team]
            }
            if PickleballRules.scorePoint(for: team, in: &next) {
                beginGame(&next)
            }
        } else if next.config.isDoubles && next.serverNumber == 1 {
            // First server lost the rally: partner serves from wherever they stand.
            next.serverNumber = 2
            next.serverIndex = 1 - next.serverIndex
        } else {
            // Side out.
            next.servingTeam = team
            next.serverNumber = 1
            next.serverIndex = next.config.isDoubles ? next.rightCourt[team] : 0
        }
        return next
    }

    public static func winner(_ state: State) -> Team? { state.winner }

    public static func display(_ state: State) -> ScoreDisplay {
        let serving = state.servingTeam
        let finished = state.winner != nil
        let servingScore = state.score[serving]
        let receivingScore = state.score[serving.opponent]
        let doubles = state.config.isDoubles

        let call: String
        let spoken: String
        if finished {
            call = "Final"
            spoken = "game, set, match"
        } else if doubles {
            call = "\(servingScore)-\(receivingScore)-\(state.serverNumber)"
            spoken = "\(Spoken.number(servingScore)), \(Spoken.number(receivingScore)), \(Spoken.number(state.serverNumber))"
        } else {
            call = "\(servingScore)-\(receivingScore)"
            spoken = "\(Spoken.number(servingScore)), \(Spoken.number(receivingScore))"
        }

        let side: CourtSide
        if doubles {
            side = state.serverIndex == state.rightCourt[serving] ? .right : .left
        } else {
            side = servingScore % 2 == 0 ? .right : .left
        }

        return ScoreDisplay(
            sport: .pickleball,
            call: call,
            spokenCall: spoken,
            points: state.score.map(String.init),
            games: state.gamesWon,
            sets: .zero,
            totalGames: state.gamesWon,
            completed: state.completedGames.map { CompletedUnit(score: $0) },
            servingTeam: finished ? nil : serving,
            server: finished ? nil : PlayerSlot(team: serving, index: state.serverIndex),
            serverNumber: finished || !doubles ? nil : state.serverNumber,
            serveSide: finished ? nil : side,
            phase: finished ? .finished : .regular,
            winner: state.winner,
            endChanges: state.endChanges,
            unitNumber: min(state.completedGames.count + 1, state.config.maxGames)
        )
    }

    private static func beginGame(_ state: inout State) {
        let index = state.completedGames.count
        state.score = .zero
        state.didMidGameSwitch = false
        state.rightCourt = state.config.startingRightCourt
        state.servingTeam = state.config.firstServer(forGameAt: index)
        if state.config.isDoubles {
            // First-server exception: the opening service turn has one server.
            state.serverNumber = 2
            state.serverIndex = state.rightCourt[state.servingTeam]
        } else {
            state.serverNumber = 1
            state.serverIndex = 0
        }
    }
}

/// The parts of state both pickleball engines share.
public protocol PickleballGameState: Codable, Equatable, Sendable {
    var config: PickleballConfig { get }
    var score: TeamPair<Int> { get set }
    var gamesWon: TeamPair<Int> { get set }
    var completedGames: [TeamPair<Int>] { get set }
    var endChanges: Int { get set }
    var didMidGameSwitch: Bool { get set }
    var winner: Team? { get set }
}

/// Game/match bookkeeping shared by both pickleball engines.
enum PickleballRules {
    /// Call after `team`'s score was incremented. Closes the game and the
    /// match when appropriate and handles the mid-game end switch.
    /// - Returns: `true` when a new game must begin.
    static func scorePoint<S: PickleballGameState>(for team: Team, in state: inout S) -> Bool {
        let config = state.config
        if config.hasWonGame(state.score[team], against: state.score[team.opponent]) {
            state.completedGames.append(state.score)
            state.gamesWon[team] += 1
            if state.gamesWon[team] >= config.gamesToWin {
                state.winner = team
                return false
            }
            state.endChanges += 1
            return true
        }

        if !state.didMidGameSwitch,
           config.isDecidingGame(state.gamesWon),
           state.score[team] == config.midGameSwitchScore {
            state.didMidGameSwitch = true
            state.endChanges += 1
        }
        return false
    }
}
