//
//  TournamentSchedule.swift
//  PickleBall
//
//  Created by sai praneeth reddy narala on 8/24/26.
//

import Foundation

enum TournamentSchedule {

    // MARK: - Fairness checks

    /// Returns whether a fair schedule is possible for the given parameters.
    /// - Odd participant counts require an even number of matches-per-player
    ///   (except the trivial 2-player case).
    static func isSchedulePossible(participantCount n: Int, matchesPerPlayer m: Int) -> Bool {
        guard n >= 2 else { return false }
        if n == 2 { return true }
        if n % 2 != 0 && m % 2 != 0 { return false }
        return true
    }

    /// Total number of matches in a fair schedule, or `nil` if impossible.
    static func totalMatches(participantCount n: Int, matchesPerPlayer m: Int) -> Int? {
        guard isSchedulePossible(participantCount: n, matchesPerPlayer: m) else { return nil }
        return (n * m) / 2
    }

    // MARK: - Schedule generation

    /// Pure function: given participant names and matches-per-player,
    /// returns a fair list of pairings (or an empty array if impossible).
    ///
    /// - Empty / whitespace names are filtered out.
    /// - If no valid names remain, default names `"Player 1"…` are used.
    static func generateMatchups(
        participantNames: [String],
        matchesPerPlayer: Int
    ) -> [(String, String)] {
        let names = participantNames
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let participants: [String] = names.isEmpty
            ? (1...max(participantNames.count, 2)).map { "Player \($0)" }
            : names

        let n = participants.count
        guard isSchedulePossible(participantCount: n, matchesPerPlayer: matchesPerPlayer),
              n >= 2 else {
            return []
        }

        let totalMatchCount = (n * matchesPerPlayer) / 2

        // Trivial 2-player case: just repeat the single pairing.
        if n == 2 {
            return Array(repeating: (participants[0], participants[1]), count: matchesPerPlayer)
        }

        let maxRepeatsPerPair = Int(ceil(Double(matchesPerPlayer) / Double(max(1, n - 1))))

        var allPairs: [(Int, Int)] = []
        for i in 0..<n {
            for j in (i + 1)..<n {
                allPairs.append((i, j))
            }
        }

        var bestSchedule: [(String, String)] = []

        for _ in 0..<400 {
            var schedule: [(Int, Int)] = []
            var countPerPlayer = Array(repeating: 0, count: n)
            var pairCounts = Array(repeating: 0, count: allPairs.count)

            while schedule.count < totalMatchCount {
                var pickedIndex: Int? = nil
                var bestScore = Int.max

                for idx in allPairs.indices.shuffled() {
                    let (a, b) = allPairs[idx]
                    guard countPerPlayer[a] < matchesPerPlayer,
                          countPerPlayer[b] < matchesPerPlayer,
                          pairCounts[idx] < maxRepeatsPerPair else { continue }
                    let score = countPerPlayer[a] + countPerPlayer[b] + pairCounts[idx]
                    if score < bestScore {
                        bestScore = score
                        pickedIndex = idx
                    }
                }

                guard let index = pickedIndex else { break }
                let (a, b) = allPairs[index]
                schedule.append((a, b))
                countPerPlayer[a] += 1
                countPerPlayer[b] += 1
                pairCounts[index] += 1
            }

            if schedule.count == totalMatchCount,
               countPerPlayer.allSatisfy({ $0 == matchesPerPlayer }) {
                bestSchedule = schedule.map { (participants[$0.0], participants[$0.1]) }
                break
            }

            if schedule.count > bestSchedule.count {
                bestSchedule = schedule.map { (participants[$0.0], participants[$0.1]) }
            }
        }

        return bestSchedule.count == totalMatchCount ? bestSchedule : []
    }
}
