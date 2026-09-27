import XCTest
@testable import CourtKit

final class PickleballRallyTests: XCTestCase {

    func testEveryRallyScoresAndWinnerServes() {
        var s = MatchScorer(rules: rally())
        XCTAssertEqual(s.display.call, "0-0")
        XCTAssertNil(s.display.serverNumber)

        play("A", &s)
        XCTAssertEqual(s.display.call, "1-0")
        play("B", &s)
        XCTAssertEqual(s.display.servingTeam, .b)
        XCTAssertEqual(s.display.call, "1-1")
        play("B", &s)
        XCTAssertEqual(s.display.call, "2-1")
    }

    /// Serving partners switch on each point won; receivers never move, and
    /// the partner whose court matches the new score takes the serve.
    func testDoublesServerFollowsScoreParity() {
        var s = MatchScorer(rules: rally())
        XCTAssertEqual(s.display.server, PlayerSlot(team: .a, index: 0))
        XCTAssertEqual(s.display.serveSide, .right)

        play("A", &s)                 // 1-0: A0 switched to the left
        XCTAssertEqual(s.display.server, PlayerSlot(team: .a, index: 0))
        XCTAssertEqual(s.display.serveSide, .left)

        play("B", &s)                 // B scores to 1 (odd): left-court B1 serves
        XCTAssertEqual(s.display.server, PlayerSlot(team: .b, index: 1))
        XCTAssertEqual(s.display.serveSide, .left)

        play("B", &s)                 // 2: B partners switch, B1 now on the right
        XCTAssertEqual(s.display.server, PlayerSlot(team: .b, index: 1))
        XCTAssertEqual(s.display.serveSide, .right)

        play("A", &s)                 // A to 2 (even): right-court A1 serves
        XCTAssertEqual(s.display.server, PlayerSlot(team: .a, index: 1))
        XCTAssertEqual(s.display.serveSide, .right)
        XCTAssertEqual(s.display.call, "2-2")
    }

    func testGameToTwentyOneWinByTwo() {
        var s = MatchScorer(rules: rally())
        play(String(repeating: "AB", count: 20), &s)
        XCTAssertEqual(s.display.points, TeamPair(a: "20", b: "20"))
        play("A", &s)
        XCTAssertNil(s.winner)
        play("B", &s)
        play("B", &s)
        XCTAssertNil(s.winner)
        play("B", &s)
        XCTAssertEqual(s.winner, .b)
        XCTAssertEqual(s.display.completed.first?.label, "21-23")
    }

    func testDecidingGameSwitchAtEleven() {
        var s = MatchScorer(rules: rally(games: 1))
        play(String(repeating: "A", count: 10), &s)
        XCTAssertEqual(s.display.endChanges, 0)
        play("A", &s)
        XCTAssertEqual(s.display.endChanges, 1)
    }

    func testSinglesSideFollowsServerScore() {
        var s = MatchScorer(rules: rally(doubles: false))
        play("B", &s)
        XCTAssertEqual(s.display.servingTeam, .b)
        XCTAssertEqual(s.display.serveSide, .left)
        play("B", &s)
        XCTAssertEqual(s.display.serveSide, .right)
    }
}
