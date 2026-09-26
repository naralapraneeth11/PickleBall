import XCTest
@testable import CourtKit

/// Plays a transcript like "AABAB" (one character per rally winner).
func play(_ transcript: String, _ scorer: inout MatchScorer) {
    for character in transcript where !character.isWhitespace {
        guard let team = Team(code: character) else {
            XCTFail("bad transcript character \(character)")
            return
        }
        scorer.recordRally(wonBy: team)
    }
}

func scorer(_ rules: MatchRules, _ transcript: String = "") -> MatchScorer {
    var s = MatchScorer(rules: rules)
    play(transcript, &s)
    return s
}

func sideOut(to points: Int = 11, games: Int = 1, doubles: Bool = true, first: Team = .a) -> MatchRules {
    .pickleball(.sideOut, PickleballConfig(pointsToWin: points, gamesToWin: games, isDoubles: doubles, firstServer: first))
}

func rally(to points: Int = 21, games: Int = 1, doubles: Bool = true, first: Team = .a, cap: Int? = nil) -> MatchRules {
    .pickleball(.rally, PickleballConfig(pointsToWin: points, pointCap: cap, gamesToWin: games, isDoubles: doubles, firstServer: first))
}

func padel(
    _ deuce: PadelConfig.DeuceRule = .advantage,
    sets: Int = 2,
    deciding: PadelConfig.DecidingSet = .superTiebreak(points: 10),
    doubles: Bool = true,
    first: Team = .a
) -> MatchRules {
    .padel(PadelConfig(setsToWin: sets, deuceRule: deuce, decidingSet: deciding, isDoubles: doubles, firstServer: first))
}

/// Four straight points: a love game for `team`.
func loveGame(_ team: Team) -> String { String(repeating: String(team.code), count: 4) }

/// Games alternating so the set reaches `n`-`n` (A wins first).
func alternatingGames(_ n: Int) -> String {
    (0..<n).map { _ in loveGame(.a) + loveGame(.b) }.joined()
}

let t0 = Date(timeIntervalSince1970: 1_780_000_000)

func player(_ name: String) -> PlayerRef { PlayerRef(kind: .guest, displayName: name) }
