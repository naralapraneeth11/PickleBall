//
//  PickleballRallyEngine.swift
//  CourtKit
//
//  Rally scoring: every rally scores a point, and the rally winner serves
//  next. There is no server number. In doubles the serving partners switch
//  sides after each point they win on serve; when the receivers win a rally
//  they score, take the serve, and the partner standing in the court that
//  matches their new score serves (even → right, odd → left).
//

import Foundation

public enum PickleballRallyEngine: SportEngine {
    public typealias Config = PickleballConfig

    public struct State: PickleballGameState {
        public var config: PickleballConfig
        public var score: TeamPair<Int>
        public var servingTeam: Team
        public var serverIndex: Int
        public var rightCourt: TeamPair<Int>
        public var gamesWon: TeamPair<Int>
        public var completedGames: [TeamPair<Int>]
        public var endChanges: Int
        public var didMidGameSwitch: Bool
        public var winner: Team?
    }

    public static var sport: Sport { .pickleball }

    /// Sensible default for rally scoring: one game to 21.
    public static func defaultConfig(isDoubles: Bool = true, firstServer: Team = .a) -> PickleballConfig {
        PickleballConfig(pointsToWin: 21, gamesToWin: 1, isDoubles: isDoubles, firstServer: firstServer)
    }

    public static func start(_ config: PickleballConfig) -> State {
        var state = State(
            config: config,
            score: .zero,
            servingTeam: config.firstServer,
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
        let wasServing = team == next.servingTeam

        next.score[team] += 1

        if wasServing {
            if next.config.isDoubles {
                next.rightCourt[team] = 1 - next.rightCourt[team]
            }
        } else {
            next.servingTeam = team
            next.serverIndex = serverForCurrentScore(team, next)
        }

        if PickleballRules.scorePoint(for: team, in: &next) {
            beginGame(&next)
        }
        return next
    }

    public static func winner(_ state: State) -> Team? { state.winner }

    public static func display(_ state: State) -> ScoreDisplay {
        let serving = state.servingTeam
        let finished = state.winner != nil
        let servingScore = state.score[serving]
        let receivingScore = state.score[serving.opponent]

        let side: CourtSide
        if state.config.isDoubles {
            side = state.serverIndex == state.rightCourt[serving] ? .right : .left
        } else {
            side = servingScore % 2 == 0 ? .right : .left
        }

        return ScoreDisplay(
            sport: .pickleball,
            call: finished ? "Final" : "\(servingScore)-\(receivingScore)",
            spokenCall: finished
                ? "game, set, match"
                : "\(Spoken.number(servingScore)), \(Spoken.number(receivingScore))",
            points: state.score.map(String.init),
            games: state.gamesWon,
            sets: .zero,
            totalGames: state.gamesWon,
            completed: state.completedGames.map { CompletedUnit(score: $0) },
            servingTeam: finished ? nil : serving,
            server: finished ? nil : PlayerSlot(team: serving, index: state.serverIndex),
            serverNumber: nil,
            serveSide: finished ? nil : side,
            phase: finished ? .finished : .regular,
            winner: state.winner,
            endChanges: state.endChanges,
            unitNumber: min(state.completedGames.count + 1, state.config.maxGames)
        )
    }

    /// The partner who serves when `team` takes the serve at its current score.
    private static func serverForCurrentScore(_ team: Team, _ state: State) -> Int {
        guard state.config.isDoubles else { return 0 }
        let right = state.rightCourt[team]
        return state.score[team] % 2 == 0 ? right : 1 - right
    }

    private static func beginGame(_ state: inout State) {
        let index = state.completedGames.count
        state.score = .zero
        state.didMidGameSwitch = false
        state.rightCourt = state.config.startingRightCourt
        state.servingTeam = state.config.firstServer(forGameAt: index)
        state.serverIndex = state.config.isDoubles ? state.rightCourt[state.servingTeam] : 0
    }
}
