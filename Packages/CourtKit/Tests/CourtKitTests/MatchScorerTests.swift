import XCTest
@testable import CourtKit

final class MatchScorerTests: XCTestCase {

    func testUndoIsReplayOfLogMinusLastRally() {
        let rulesList: [MatchRules] = [sideOut(games: 2), rally(), padel(.starPoint)]
        for rules in rulesList {
            var s = MatchScorer(rules: rules)
            let transcript = "AABABBBAABABAAABBBABABBBBAAAABAB"
            for (i, c) in transcript.enumerated() {
                let before = s
                s.recordRally(wonBy: Team(code: c)!)
                var undone = s
                undone.undo()
                XCTAssertEqual(undone.state, before.state, "\(rules.summary) rally \(i + 1)")
                XCTAssertEqual(undone.rallies, before.rallies)
            }
        }
    }

    func testReplayFromLogMatchesLiveState() {
        let live = scorer(padel(), alternatingGames(6) + "ABABABABAAA")
        let rebuilt = MatchScorer(rules: live.rules, rallies: live.rallies)
        XCTAssertEqual(rebuilt, live)
    }

    func testRalliesAfterMatchEndAreIgnored() {
        var s = scorer(sideOut(doubles: false), String(repeating: "A", count: 11))
        XCTAssertEqual(s.winner, .a)
        XCTAssertEqual(s.recordRally(wonBy: .b), [])
        XCTAssertEqual(s.rallies.count, 11)
    }

    func testInitDropsRalliesPastTheEnd() {
        let rallies = (0..<15).map { _ in Rally(winner: .a, at: t0) }
        let s = MatchScorer(rules: sideOut(doubles: false), rallies: rallies)
        XCTAssertEqual(s.rallies.count, 11)
    }

    // MARK: - Pressure

    func testGamePointOnlyForServingSideInSideOut() {
        let s = scorer(sideOut(games: 2, doubles: false), String(repeating: "A", count: 10))
        XCTAssertEqual(s.pressure(for: .a), .gamePoint)
        XCTAssertNil(s.pressure(for: .b), "receivers cannot win a point on the next rally")
    }

    func testMatchPoint() {
        let s = scorer(sideOut(doubles: false), String(repeating: "A", count: 10))
        XCTAssertEqual(s.pressure(for: .a), .matchPoint)
    }

    func testRallyScoringGivesBothSidesGamePoints() {
        let s = scorer(rally(games: 2), String(repeating: "AB", count: 20) + "A")   // 21-20
        XCTAssertEqual(s.pressure(for: .a), .gamePoint)
        XCTAssertNil(s.pressure(for: .b))
    }

    func testPadelSetPointAndMatchPoint() {
        var s = scorer(padel(), String(repeating: loveGame(.a), count: 5) + "AAA")    // 5-0, 40-0
        XCTAssertEqual(s.pressure(for: .a), .setPoint)
        play("A", &s)
        play(String(repeating: loveGame(.a), count: 5) + "AAA", &s)
        XCTAssertEqual(s.pressure(for: .a), .matchPoint)
    }

    // MARK: - Events

    func testSideOutAndSecondServerEvents() {
        var doubles = MatchScorer(rules: sideOut())
        play("A", &doubles)
        XCTAssertEqual(doubles.recordRally(wonBy: .b), [.sideOut(to: .b)])     // 0-0-2 start: one server
        XCTAssertEqual(doubles.recordRally(wonBy: .a), [.secondServer])
        XCTAssertEqual(doubles.recordRally(wonBy: .b), [.point(.b)])
    }

    func testGameWonAndEndsEvents() {
        var s = scorer(sideOut(games: 2, doubles: false), String(repeating: "A", count: 10))
        let events = s.recordRally(wonBy: .a)
        XCTAssertTrue(events.contains(.point(.a)))
        XCTAssertTrue(events.contains(.gameWon(.a)))
        XCTAssertTrue(events.contains(.changeEnds))
        XCTAssertFalse(events.contains(.matchWon(.a)))
    }

    func testMatchWonAndPressureEvents() {
        var s = scorer(sideOut(doubles: false), String(repeating: "A", count: 9))
        XCTAssertTrue(s.recordRally(wonBy: .a).contains(.pressure(.matchPoint, .a)))
        XCTAssertTrue(s.recordRally(wonBy: .a).contains(.matchWon(.a)))
    }

    func testTiebreakStartedEvent() {
        var s = scorer(padel(), alternatingGames(5) + loveGame(.a) + "BBB")
        let events = s.recordRally(wonBy: .b)
        XCTAssertTrue(events.contains(.tiebreakStarted))
        XCTAssertTrue(events.contains(.gameWon(.b)))
    }

    func testTimelineReportsServerBeforeEachRally() {
        let s = scorer(sideOut(doubles: false), "AB")
        let timeline = s.timeline()
        XCTAssertEqual(timeline.count, 2)
        XCTAssertEqual(timeline[0].before.servingTeam, .a)
        XCTAssertEqual(timeline[1].before.servingTeam, .a)
    }

    func testRulesRoundTripThroughJSON() throws {
        for rules in [sideOut(games: 2), rally(cap: 25), padel(.starPoint, deciding: .fullSet)] {
            let data = try JSONEncoder().encode(rules)
            XCTAssertEqual(try JSONDecoder().decode(MatchRules.self, from: data), rules)
        }
    }

    func testSummaries() {
        XCTAssertEqual(sideOut(games: 2).summary, "Side-out · to 11 · best of 3")
        XCTAssertEqual(padel(.goldenPoint).summary, "Best of 3 sets · Golden point · super tiebreak to 10")
    }

    // MARK: - Serve stats

    func testServeStatsFromLog() {
        // Singles side-out: A serves and wins 3, loses serve; B serves and wins 1, loses serve.
        let s = scorer(sideOut(doubles: false), "AAAB" + "BA")
        let a = ServeStats.compute(scorer: s, team: .a)
        XCTAssertEqual(a.pointsServed, 4)
        XCTAssertEqual(a.pointsWonOnServe, 3)
        let b = ServeStats.compute(scorer: s, team: .b)
        XCTAssertEqual(b.pointsServed, 2)
        XCTAssertEqual(b.pointsWonOnServe, 1)
    }

    func testPadelServiceGamesHeld() {
        let s = scorer(padel(), loveGame(.a) + loveGame(.a) + loveGame(.b))
        // Game 1 A0 serves & holds; game 2 B0 serves & is broken; game 3 A1 serves & is broken.
        let a0 = ServeStats.compute(scorer: s, team: .a, index: 0)
        XCTAssertEqual(a0.serviceGames, 1)
        XCTAssertEqual(a0.serviceGamesHeld, 1)
        let teamA = ServeStats.compute(scorer: s, team: .a)
        XCTAssertEqual(teamA.serviceGames, 2)
        XCTAssertEqual(teamA.holdPercent, 50)
    }

    func testLiveScoreSnapshot() {
        let s = scorer(sideOut(doubles: false), String(repeating: "A", count: 10))
        let snapshot = LiveScoreSnapshot(scorer: s, updatedAt: t0)
        XCTAssertEqual(snapshot.points, TeamPair(a: "10", b: "0"))
        XCTAssertEqual(snapshot.pressure, "Match point")
        XCTAssertEqual(snapshot.pressureTeam, .a)
        XCTAssertEqual(snapshot.call, "10-0")
    }
}
