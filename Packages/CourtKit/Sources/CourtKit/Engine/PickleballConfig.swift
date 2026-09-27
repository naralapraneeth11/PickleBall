//
//  PickleballConfig.swift
//  CourtKit
//

import Foundation

public struct PickleballConfig: Codable, Hashable, Sendable {
    /// Points needed to win a game (11, 15, 21…).
    public var pointsToWin: Int
    /// Required margin. 2 in every sanctioned format.
    public var winBy: Int
    /// Optional hard cap: first to this score wins regardless of margin.
    public var pointCap: Int?
    /// Games needed to win the match: 1 = single game, 2 = best of three.
    public var gamesToWin: Int
    public var isDoubles: Bool
    /// Team serving first in game one. Serve alternates at the start of each
    /// following game (the team that received first in game one serves first
    /// in game two, and so on).
    public var firstServer: Team
    /// Index of the player standing in the right (even) court at the start of
    /// each game, per team. In doubles that player serves first.
    public var startingRightCourt: TeamPair<Int>

    public init(
        pointsToWin: Int = 11,
        winBy: Int = 2,
        pointCap: Int? = nil,
        gamesToWin: Int = 1,
        isDoubles: Bool = true,
        firstServer: Team = .a,
        startingRightCourt: TeamPair<Int> = .zero
    ) {
        self.pointsToWin = max(1, pointsToWin)
        self.winBy = max(1, winBy)
        self.pointCap = pointCap
        self.gamesToWin = max(1, gamesToWin)
        self.isDoubles = isDoubles
        self.firstServer = firstServer
        self.startingRightCourt = startingRightCourt.map { $0 == 1 ? 1 : 0 }
    }

    /// Score at which ends are switched mid-game in a deciding game:
    /// 6 in a game to 11, 8 to 15, 11 to 21.
    public var midGameSwitchScore: Int { (pointsToWin + 1) / 2 }

    /// Maximum number of games a match can take.
    public var maxGames: Int { gamesToWin * 2 - 1 }

    func hasWonGame(_ score: Int, against other: Int) -> Bool {
        if let pointCap, score >= pointCap { return true }
        return score >= pointsToWin && score - other >= winBy
    }

    func isDecidingGame(_ gamesWon: TeamPair<Int>) -> Bool {
        gamesWon.a == gamesToWin - 1 && gamesWon.b == gamesToWin - 1
    }

    func firstServer(forGameAt index: Int) -> Team {
        index % 2 == 0 ? firstServer : firstServer.opponent
    }
}
