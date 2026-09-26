import XCTest
@testable import CourtKit

final class PickleballSideOutTests: XCTestCase {

    func testDoublesStartsAtZeroZeroTwo() {
        let d = scorer(sideOut()).display
        XCTAssertEqual(d.call, "0-0-2")
        XCTAssertEqual(d.servingTeam, .a)
        XCTAssertEqual(d.serverNumber, 2)
        XCTAssertEqual(d.serveSide, .right)
        XCTAssertEqual(d.spokenCall, "zero, zero, two")
    }

    /// A real opening sequence, called rally by rally.
    func testDoublesCallTranscript() {
        let transcript: [(Character, String)] = [
            ("A", "1-0-2"),   // server 2 of the opening turn scores
            ("B", "0-1-1"),   // opening turn has one server: side out
            ("B", "1-1-1"),
            ("B", "2-1-1"),
            ("A", "2-1-2"),   // B's first server faults: partner serves
            ("A", "1-2-1"),   // side out to A, server 1
            ("A", "2-2-1"),
            ("B", "2-2-2"),
            ("A", "3-2-2"),
            ("A", "4-2-2"),
            ("B", "2-4-1"),   // side out
            ("A", "2-4-2"),
            ("A", "4-2-1"),   // side out back to A
        ]
        var s = MatchScorer(rules: sideOut())
        for (index, step) in transcript.enumerated() {
            s.recordRally(wonBy: Team(code: step.0)!)
            XCTAssertEqual(s.display.call, step.1, "after rally \(index + 1)")
        }
    }

    /// Who serves, and from which court, follows player positions.
    func testServerIdentityAndCourtPositions() {
        var s = MatchScorer(rules: sideOut())
        // A0 in the right court serves first.
        XCTAssertEqual(s.display.server, PlayerSlot(team: .a, index: 0))
        XCTAssertEqual(s.display.serveSide, .right)

        s.recordRally(wonBy: .a)   // A scores, partners switch: A0 now on the left
        XCTAssertEqual(s.display.server, PlayerSlot(team: .a, index: 0))
        XCTAssertEqual(s.display.serveSide, .left)

        s.recordRally(wonBy: .b)   // side out: B's right-court player (B0) serves
        XCTAssertEqual(s.display.server, PlayerSlot(team: .b, index: 0))
        XCTAssertEqual(s.display.serveSide, .right)

        s.recordRally(wonBy: .b)   // B scores, B0 moves to the left
        XCTAssertEqual(s.display.serveSide, .left)

        s.recordRally(wonBy: .a)   // second server B1 serves from where they stand (right)
        XCTAssertEqual(s.display.server, PlayerSlot(team: .b, index: 1))
        XCTAssertEqual(s.display.serverNumber, 2)
        XCTAssertEqual(s.display.serveSide, .right)

        s.recordRally(wonBy: .a)   // side out: A's right-court player is A1 after the switch
        XCTAssertEqual(s.display.server, PlayerSlot(team: .a, index: 1))
        XCTAssertEqual(s.display.serverNumber, 1)
    }

    func testSinglesHasNoServerNumberAndSidesFollowScore() {
        var s = scorer(sideOut(doubles: false))
        XCTAssertEqual(s.display.call, "0-0")
        XCTAssertNil(s.display.serverNumber)
        play("A", &s)
        XCTAssertEqual(s.display.serveSide, .left)       // odd score serves from the left
        play("B", &s)                                     // immediate side out in singles
        XCTAssertEqual(s.display.servingTeam, .b)
        XCTAssertEqual(s.display.call, "0-1")
        XCTAssertEqual(s.display.serveSide, .right)
    }

    func testReceiversCannotScore() {
        let s = scorer(sideOut(doubles: false), "ABBAB")
        // A 1, then side out, B 1, side out, side out... only servers score.
        XCTAssertEqual(s.display.points, TeamPair(a: "1", b: "1"))
    }

    func testWinByTwo() {
        // Singles: A serves 10 straight, then B wins serve and ties 10-10.
        var s = scorer(sideOut(doubles: false), String(repeating: "A", count: 10))
        play("B" + String(repeating: "B", count: 10), &s)
        XCTAssertEqual(s.display.points, TeamPair(a: "10", b: "10"))
        XCTAssertNil(s.winner)
        play("B", &s)   // 11-10: not enough
        XCTAssertNil(s.winner)
        play("B", &s)   // 12-10
        XCTAssertEqual(s.winner, .b)
        XCTAssertEqual(s.display.completed.first?.score, TeamPair(a: 10, b: 12))
        XCTAssertEqual(s.display.call, "Final")
    }

    func testBestOfThreeAlternatesFirstServerAndSwitchesEnds() {
        var s = MatchScorer(rules: sideOut(games: 2, doubles: false))
        play(String(repeating: "A", count: 11), &s)
        XCTAssertEqual(s.display.games, TeamPair(a: 1, b: 0))
        XCTAssertEqual(s.display.unitNumber, 2)
        XCTAssertEqual(s.display.servingTeam, .b, "team that received first serves first in game two")
        XCTAssertEqual(s.display.endChanges, 1)

        play(String(repeating: "B", count: 11), &s)
        XCTAssertEqual(s.display.games, TeamPair(a: 1, b: 1))
        XCTAssertEqual(s.display.servingTeam, .a)
        XCTAssertEqual(s.display.endChanges, 2)

        // Deciding game: ends switch when the first team reaches 6.
        play(String(repeating: "A", count: 5), &s)
        XCTAssertEqual(s.display.endChanges, 2)
        play("A", &s)
        XCTAssertEqual(s.display.endChanges, 3)
        play(String(repeating: "A", count: 5), &s)
        XCTAssertEqual(s.winner, .a)
        XCTAssertEqual(s.display.completed.map(\.label), ["11-0", "0-11", "11-0"])
    }

    func testEachGameRestartsAtZeroZeroTwo() {
        var s = MatchScorer(rules: sideOut(games: 2))
        play(String(repeating: "A", count: 11), &s)
        XCTAssertEqual(s.display.call, "0-0-2")
        XCTAssertEqual(s.display.servingTeam, .b)
    }

    func testPointCapEndsGameWithOnePointMargin() {
        let rules = MatchRules.pickleball(.sideOut, PickleballConfig(pointsToWin: 11, pointCap: 13, isDoubles: false))
        // 10-0 A, side out, 10-10, then trade points on serve up to 12-12.
        var s = scorer(rules, String(repeating: "A", count: 10) + "B" + String(repeating: "B", count: 10))
        play("B" + "AA" + "BB" + "AA", &s)
        XCTAssertEqual(s.display.points, TeamPair(a: "12", b: "12"))
        XCTAssertNil(s.winner)
        play("BB", &s)   // side out, then 13-12 at the cap
        XCTAssertEqual(s.winner, .b)
    }
}
