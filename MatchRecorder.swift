//
//  MatchRecorder.swift
//  PickleBall
//
//  Created by sai praneeth reddy narala on 8/26/26.
//
//  MatchRecorder.swift
//  PickleBall
//

import Foundation

enum MatchRecorder {

    static func isProfilePlayerInMatch(
        profileFirstName: String,
        player1Display: String,
        player2Display: String
    ) -> Bool {
        let first = profileFirstName.trimmingCharacters(in: .whitespaces).uppercased()
        guard !first.isEmpty else { return false }

        let names1 = player1Display.uppercased()
            .split(separator: "/")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        let names2 = player2Display.uppercased()
            .split(separator: "/")
            .map { String($0).trimmingCharacters(in: .whitespaces) }

        return (names1 + names2).contains { $0 == first }
    }

    /// 1 = player1 side, 2 = player2 side
    static func profilePlayerSide(
        profileFirstName: String,
        player1Display: String,
        player2Display: String
    ) -> Int? {
        let first = profileFirstName.trimmingCharacters(in: .whitespaces).uppercased()
        guard !first.isEmpty else { return nil }

        let names1 = player1Display.uppercased()
            .split(separator: "/")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        let names2 = player2Display.uppercased()
            .split(separator: "/")
            .map { String($0).trimmingCharacters(in: .whitespaces) }

        if names1.contains(first) { return 1 }
        if names2.contains(first) { return 2 }
        return nil
    }

    /// Career only. Does **not** touch TournamentStore.
    @MainActor
    @discardableResult
    static func recordIfProfilePlaying(
        matchID: UUID,
        player1Name: String,
        player2Name: String,
        player1GamesWon: Int,
        player2GamesWon: Int,
        completedGameScores: [GameScore],
        wonByPlayer1: Bool
    ) -> Bool {
        let profileFirstName = UserDefaults.standard.string(forKey: "profile_firstName") ?? ""
        guard isProfilePlayerInMatch(
            profileFirstName: profileFirstName,
            player1Display: player1Name,
            player2Display: player2Name
        ) else { return false }

        guard let side = profilePlayerSide(
            profileFirstName: profileFirstName,
            player1Display: player1Name,
            player2Display: player2Name
        ) else { return false }

        let didWin = (side == 1 && wonByPlayer1) || (side == 2 && !wonByPlayer1)
        let opponent = side == 1 ? player2Name : player1Name
        let (myScore, opponentScore) = side == 1
            ? (player1GamesWon, player2GamesWon)
            : (player2GamesWon, player1GamesWon)

        let gameScores: [MatchGameScore] = completedGameScores.map { gs in
            side == 1
                ? MatchGameScore(myPoints: gs.player1, opponentPoints: gs.player2)
                : MatchGameScore(myPoints: gs.player2, opponentPoints: gs.player1)
        }

        let match = StoredMatch(
            matchID: matchID,
            playerName: profileFirstName.trimmingCharacters(in: .whitespaces),
            opponent: opponent,
            didWin: didWin,
            myScore: myScore,
            opponentScore: opponentScore,
            gameScores: gameScores
        )
        MatchStore.shared.addMatch(match)
        return didWin
    }
}

