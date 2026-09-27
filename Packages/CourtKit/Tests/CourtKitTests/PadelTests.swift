import XCTest
@testable import CourtKit

final class PadelTests: XCTestCase {

    // MARK: - Games and deuce rules

    func testPointLabelsAndServerFirstCalls() {
        var s = MatchScorer(rules: padel())
        XCTAssertEqual(s.display.call, "0-all")
        play("A", &s)
        XCTAssertEqual(s.display.points, TeamPair(a: "15", b: "0"))
        play("A", &s)
        play("B", &s)
        XCTAssertEqual(s.display.points, TeamPair(a: "30", b: "15"))
        XCTAssertEqual(s.display.call, "30-15")
        XCTAssertEqual(s.display.spokenCall, "thirty, fifteen")
        play("B", &s)
        XCTAssertEqual(s.display.call, "30-all")
    }

    func testAdvantageDeuceCycles() {
        var s = scorer(padel(.advantage), "AAABBB")
        XCTAssertEqual(s.display.phase, .deuce)
        XCTAssertEqual(s.display.call, "Deuce")
        play("A", &s)
        XCTAssertEqual(s.display.phase, .advantage(.a))
        XCTAssertEqual(s.display.points, TeamPair(a: "AD", b: "40"))
        XCTAssertEqual(s.display.call, "Ad in")
        play("B", &s)
        XCTAssertEqual(s.display.phase, .deuce)
        play("BABABA", &s)           // endless deuce under advantage
        XCTAssertEqual(s.display.games, .zero)
        play("AA", &s)
        XCTAssertEqual(s.display.games, TeamPair(a: 1, b: 0))
    }

    func testGoldenPointIsSuddenDeathAtFirstDeuce() {
        var s = scorer(padel(.goldenPoint), "AAABBB")
        XCTAssertEqual(s.display.phase, .decidingPoint(.golden))
        XCTAssertEqual(s.display.call, "Golden point")
        play("B", &s)
        XCTAssertEqual(s.display.games, TeamPair(a: 0, b: 1))
    }

    func testStarPointAfterTwoAdvantages() {
        var s = scorer(padel(.starPoint), "AAABBB")
        XCTAssertEqual(s.display.phase, .deuce, "first deuce plays advantage")
        play("AB", &s)
        XCTAssertEqual(s.display.phase, .deuce, "second deuce plays advantage")
        play("A", &s)
        XCTAssertEqual(s.display.phase, .advantage(.a))
        play("B", &s)
        XCTAssertEqual(s.display.phase, .decidingPoint(.star), "third deuce is the star point")
        XCTAssertEqual(s.display.games, .zero)
        play("A", &s)
        XCTAssertEqual(s.display.games, TeamPair(a: 1, b: 0))
    }

    // MARK: - Sets, tiebreaks, match

    func testSetToSixNeedsTwoGameMargin() {
        var s = scorer(padel(), alternatingGames(5))          // 5-5
        play(loveGame(.a), &s)                                 // 6-5
        XCTAssertEqual(s.display.games, TeamPair(a: 6, b: 5))
        XCTAssertEqual(s.display.sets, .zero)
        play(loveGame(.a), &s)                                 // 7-5
        XCTAssertEqual(s.display.sets, TeamPair(a: 1, b: 0))
        XCTAssertEqual(s.display.completed.last?.label, "7-5")
        XCTAssertEqual(s.display.games, .zero)
    }

    func testTiebreakAtSixAll() {
        var s = scorer(padel(), alternatingGames(6))
        XCTAssertEqual(s.display.phase, .tiebreak)
        XCTAssertEqual(s.display.points, TeamPair(a: "0", b: "0"))

        play(String(repeating: "AB", count: 5), &s)            // 5-5
        XCTAssertEqual(s.display.call.split(separator: "-").count, 2)
        play("AA", &s)                                         // 7-5
        XCTAssertEqual(s.display.sets, TeamPair(a: 1, b: 0))
        let set = s.display.completed.last
        XCTAssertEqual(set?.score, TeamPair(a: 7, b: 6))
        XCTAssertEqual(set?.tiebreak, TeamPair(a: 7, b: 5))
        XCTAssertEqual(set?.label, "7-6(5)")
        XCTAssertEqual(s.display.phase, .regular)
    }

    func testSuperTiebreakDecidesAtOneSetAll() {
        var s = scorer(padel(), String(repeating: loveGame(.a), count: 6))   // 6-0
        play(String(repeating: loveGame(.b), count: 6), &s)                  // 0-6
        XCTAssertEqual(s.display.sets, TeamPair(a: 1, b: 1))
        XCTAssertEqual(s.display.phase, .superTiebreak)

        play(String(repeating: "AB", count: 8), &s)                          // 8-8
        play("A", &s)
        XCTAssertNil(s.winner, "super tiebreak is won by two")
        play("A", &s)
        XCTAssertEqual(s.winner, .a)
        XCTAssertEqual(s.display.completed.map(\.label), ["6-0", "0-6", "[10-8]"])
        XCTAssertEqual(s.display.matchScore, TeamPair(a: 2, b: 1))
    }

    func testFullDecidingSet() {
        var s = scorer(padel(deciding: .fullSet), String(repeating: loveGame(.a), count: 6))
        play(String(repeating: loveGame(.b), count: 6), &s)
        XCTAssertEqual(s.display.phase, .regular)
        play(String(repeating: loveGame(.a), count: 6), &s)
        XCTAssertEqual(s.winner, .a)
    }

    func testOneSetMatch() {
        let s = scorer(padel(sets: 1), String(repeating: loveGame(.b), count: 6))
        XCTAssertEqual(s.winner, .b)
    }

    // MARK: - Serve rotation and ends

    func testServeRotatesThroughAllFourPlayers() {
        var s = MatchScorer(rules: padel())
        let expected = [
            PlayerSlot(team: .a, index: 0), PlayerSlot(team: .b, index: 0),
            PlayerSlot(team: .a, index: 1), PlayerSlot(team: .b, index: 1),
            PlayerSlot(team: .a, index: 0)
        ]
        for (game, slot) in expected.enumerated() {
            XCTAssertEqual(s.display.server, slot, "game \(game + 1)")
            play(loveGame(game % 2 == 0 ? .a : .b), &s)
        }
    }

    func testServeSidesAlternateFromTheRight() {
        var s = MatchScorer(rules: padel())
        XCTAssertEqual(s.display.serveSide, .right)
        play("A", &s)
        XCTAssertEqual(s.display.serveSide, .left)
        play("B", &s)
        XCTAssertEqual(s.display.serveSide, .right)
    }

    func testTiebreakServeOrderAndNextSetServer() {
        var s = scorer(padel(), alternatingGames(6))   // 12 games: rotation back to A0
        // One point, then two each, following the rotation.
        let expected: [PlayerSlot] = [
            PlayerSlot(team: .a, index: 0),
            PlayerSlot(team: .b, index: 0), PlayerSlot(team: .b, index: 0),
            PlayerSlot(team: .a, index: 1), PlayerSlot(team: .a, index: 1),
            PlayerSlot(team: .b, index: 1), PlayerSlot(team: .b, index: 1),
            PlayerSlot(team: .a, index: 0)
        ]
        for (point, slot) in expected.enumerated() {
            XCTAssertEqual(s.display.server, slot, "tiebreak point \(point + 1)")
            play(point % 2 == 0 ? "A" : "B", &s)
        }
        play("AAA", &s)   // A takes the tiebreak 7-4... then the set
        XCTAssertEqual(s.display.sets, TeamPair(a: 1, b: 0))
        // A0 served first in the tiebreak, so team B serves the next set.
        XCTAssertEqual(s.display.server?.team, .b)
    }

    func testEndsChangeOnOddGamesAndEverySixTiebreakPoints() {
        var s = scorer(padel(), loveGame(.a))
        XCTAssertEqual(s.display.endChanges, 1)
        play(loveGame(.b), &s)
        XCTAssertEqual(s.display.endChanges, 1)
        play(loveGame(.a), &s)
        XCTAssertEqual(s.display.endChanges, 2)

        var tb = scorer(padel(), alternatingGames(6))
        XCTAssertEqual(tb.display.endChanges, 6)
        play("ABABA", &tb)
        XCTAssertEqual(tb.display.endChanges, 6)
        play("B", &tb)
        XCTAssertEqual(tb.display.endChanges, 7)
    }

    func testSinglesRotation() {
        var s = MatchScorer(rules: padel(doubles: false))
        XCTAssertEqual(s.display.server, PlayerSlot(team: .a, index: 0))
        play(loveGame(.a), &s)
        XCTAssertEqual(s.display.server, PlayerSlot(team: .b, index: 0))
    }
}
