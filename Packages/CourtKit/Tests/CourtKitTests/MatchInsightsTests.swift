import XCTest
@testable import CourtKit

final class MatchInsightsTests: XCTestCase {
    func testRallyScoringServeAndReturn() {
        // Rally scoring singles to 11, A serves first. A wins three on serve,
        // B wins the fourth on return (and the serve), A wins it back.
        let s = scorer(rally(to: 11, doubles: false), "AAABA")
        let insights = MatchInsights.compute(scorer: s)
        XCTAssertEqual(insights.teams.a.servePlayed, 4)
        XCTAssertEqual(insights.teams.a.serveWon, 3)
        XCTAssertEqual(insights.teams.b.returnPlayed, 4)
        XCTAssertEqual(insights.teams.b.returnWon, 1)
        // B served one rally (after winning one back) and lost it.
        XCTAssertEqual(insights.teams.b.servePlayed, 1)
        XCTAssertEqual(insights.teams.a.returnWon, 1)
        XCTAssertEqual(insights.teams.a.longestRun, 3)
        XCTAssertEqual(insights.teams.b.longestRun, 1)
        XCTAssertEqual(insights.totalRallies, 5)
        XCTAssertEqual(insights.teams.a.servePercent, 75)
    }

    func testServeCountsAddUp() {
        let transcript = "ABABBBAAABABAAABBBABAAAAA"
        let s = scorer(sideOut(to: 11, doubles: true), transcript)
        let insights = MatchInsights.compute(scorer: s)
        let a = insights.teams.a, b = insights.teams.b
        XCTAssertEqual(a.servePlayed + b.servePlayed, s.rallies.count)
        XCTAssertEqual(a.servePlayed, b.returnPlayed)
        XCTAssertEqual(a.serveWon + b.returnWon, a.servePlayed)
        XCTAssertEqual(a.ralliesWon + b.ralliesWon, s.rallies.count)
        // Per-player serve totals match the team totals.
        let perPlayerA = insights.players.filter { $0.key.team == .a }.values.reduce(0) { $0 + $1.pointsServed }
        XCTAssertEqual(perPlayerA, a.servePlayed)
        // Matches the older serve stats.
        XCTAssertEqual(ServeStats.compute(scorer: s, team: .a).pointsServed, a.servePlayed)
    }

    func testSideOutsCountServeWonBack() {
        // Side-out singles: every return won hands over the serve.
        let s = scorer(sideOut(to: 11, doubles: false), "BAB")
        let insights = MatchInsights.compute(scorer: s)
        // Singles: B wins the return (side out), A wins B's serve back
        // (side out), B wins A's serve again (side out).
        XCTAssertEqual(insights.teams.b.breaks, 2)
        XCTAssertEqual(insights.teams.a.breaks, 1)
    }

    func testPressurePointsAndComeback() {
        // Rally scoring to 5, win by 2. B goes 4-0 up; A wins six straight
        // to take it 6-4.
        let s = scorer(rally(to: 5, doubles: false), "BBBBA" + "AAAAA")
        let insights = MatchInsights.compute(scorer: s)
        XCTAssertNotNil(s.winner)
        XCTAssertEqual(s.winner, .a)
        // B had match point at 0-4, 1-4, 2-4 and 3-4; A saved all four.
        XCTAssertEqual(insights.teams.a.pressureSaved, 4)
        XCTAssertEqual(insights.teams.b.pressureChances, 4)
        XCTAssertEqual(insights.teams.b.pressureConverted, 0)
        XCTAssertEqual(insights.teams.a.pressureConverted, 1)
        XCTAssertEqual(insights.teams.a.biggestComeback, 4)
        XCTAssertEqual(insights.teams.a.longestRun, 6)
        XCTAssertEqual(insights.leadChanges, 1)
    }

    func testPadelHoldsAndBreaks() {
        // A serves the first game and holds; B serves and A breaks.
        let s = scorer(padel(), loveGame(.a) + loveGame(.a))
        let insights = MatchInsights.compute(scorer: s)
        XCTAssertEqual(insights.teams.a.serviceGames, 1)
        XCTAssertEqual(insights.teams.a.serviceGamesHeld, 1)
        XCTAssertEqual(insights.teams.b.serviceGames, 1)
        XCTAssertEqual(insights.teams.b.serviceGamesHeld, 0)
        XCTAssertEqual(insights.teams.a.breaks, 1)
        XCTAssertEqual(insights.teams.a.holdPercent, 100)
    }

    func testTypedScoreHasNoTiming() {
        let s = scorer(rally(to: 11), "AB")
        let insights = MatchInsights.compute(scorer: s)
        // The helper records rallies at the same instant.
        XCTAssertNil(insights.duration)
        XCTAssertTrue(MatchInsights.compute(scorer: MatchScorer(rules: rally())).isEmpty)
    }

    func testTiming() {
        var s = MatchScorer(rules: rally(to: 11))
        s.recordRally(wonBy: .a, at: t0)
        s.recordRally(wonBy: .b, at: t0.addingTimeInterval(20))
        s.recordRally(wonBy: .a, at: t0.addingTimeInterval(40))
        let insights = MatchInsights.compute(scorer: s)
        XCTAssertEqual(insights.duration, 40)
        XCTAssertEqual(insights.secondsPerRally, 20)
    }
}
