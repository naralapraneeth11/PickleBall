import XCTest
@testable import CourtKit

final class TournamentFormatTests: XCTestCase {
    let players = (0..<8).map { _ in PlayerID() }

    func pairsPlayed(_ fixtures: [Fixture]) -> [Set<PlayerID>: Int] {
        var count: [Set<PlayerID>: Int] = [:]
        for f in fixtures {
            for p in f.teams.a {
                for q in f.teams.b { count[Set([p, q]), default: 0] += 1 }
            }
        }
        return count
    }

    // MARK: Round robin

    func testRoundRobinEveryoneMeetsEveryoneOnce() {
        for n in 2...9 {
            let entrants = players.prefix(n).map { [$0] } + (n > 8 ? [[PlayerID()]] : [])
            let fixtures = RoundRobin.schedule(Array(entrants))
            XCTAssertEqual(fixtures.count, entrants.count * (entrants.count - 1) / 2, "n=\(n)")
            let meetings = pairsPlayed(fixtures)
            XCTAssertTrue(meetings.values.allSatisfy { $0 == 1 }, "n=\(n)")
            // Nobody plays twice in a round.
            for round in Set(fixtures.map(\.round)) {
                let inRound = fixtures.filter { $0.round == round }.flatMap(\.players)
                XCTAssertEqual(inRound.count, Set(inRound).count, "n=\(n) round \(round)")
            }
        }
    }

    func testRoundRobinThreeWayTieFallsToPointDifference() {
        let (a, b, c) = (players[0], players[1], players[2])
        let fixtures = RoundRobin.schedule([[a], [b], [c]])
        // a edges b, b crushes c, c beats a: everyone 1-1.
        let scores = results(fixtures, [(a, b, 11, 9), (b, c, 11, 0), (c, a, 11, 8)])
        let rows = Standings.compute(format: .roundRobin, entrants: [[a], [b], [c]], fixtures: fixtures, scores: scores)
        XCTAssertEqual(rows.map(\.entrant), [[b], [a], [c]])
        XCTAssertEqual(rows.map(\.rank), [1, 2, 3])
    }

    func testRoundRobinTwoWayTieGoesToHeadToHead() {
        let (a, b, c, d) = (players[0], players[1], players[2], players[3])
        let entrants = [[a], [b], [c], [d]]
        let fixtures = RoundRobin.schedule(entrants)
        // a and b finish 2-1, c and d 1-2. b and d have the better point
        // differences, but lost the meetings that matter.
        let scores = results(fixtures, [
            (a, b, 11, 9), (a, c, 11, 9), (d, a, 11, 0),
            (b, c, 11, 0), (b, d, 11, 0),
            (c, d, 11, 9)
        ])
        let rows = Standings.compute(format: .roundRobin, entrants: entrants, fixtures: fixtures, scores: scores)
        XCTAssertEqual(rows.map(\.entrant), [[a], [b], [c], [d]])
        XCTAssertGreaterThan(rows[1].pointDifference, rows[0].pointDifference)
        XCTAssertEqual(Standings.champions(rows, fixtures: fixtures, scores: scores), [a])
    }

    func results(_ fixtures: [Fixture], _ games: [(PlayerID, PlayerID, Int, Int)]) -> [UUID: FixtureScore] {
        var scores: [UUID: FixtureScore] = [:]
        for (winner, loser, w, l) in games {
            let f = fixtures.first { Set($0.players) == [winner, loser] }!
            scores[f.id] = FixtureScore(score: f.teams.a == [winner] ? TeamPair(a: w, b: l) : TeamPair(a: l, b: w))
        }
        return scores
    }

    func testChampionsWaitForEveryResult() {
        let fixtures = RoundRobin.schedule(players.prefix(4).map { [$0] })
        let rows = Standings.compute(format: .roundRobin, entrants: players.prefix(4).map { [$0] }, fixtures: fixtures, scores: [:])
        XCTAssertNil(Standings.champions(rows, fixtures: fixtures, scores: [:]))
        XCTAssertEqual(rows.map(\.rank), [1, 1, 1, 1], "nobody has played: all level")
    }

    func testDoublesRoundRobinRanksPairs() {
        let teams = [[players[0], players[1]], [players[2], players[3]], [players[4], players[5]]]
        let fixtures = RoundRobin.schedule(teams)
        XCTAssertEqual(fixtures.count, 3)
        var scores: [UUID: FixtureScore] = [:]
        for f in fixtures {
            // The pair listed first always wins.
            let aWins = teams.firstIndex(of: f.teams.a)! < teams.firstIndex(of: f.teams.b)!
            scores[f.id] = FixtureScore(score: aWins ? TeamPair(a: 11, b: 5) : TeamPair(a: 5, b: 11))
        }
        let rows = Standings.compute(format: .roundRobin, entrants: teams, fixtures: fixtures, scores: scores)
        XCTAssertEqual(rows.map(\.entrant), teams)
    }

    // MARK: King of the Court

    func testKingOfTheCourtMovesWinnersUpAndSplitsPartners() throws {
        let (round1, bench) = KingOfTheCourt.firstRound(players, doubles: true)
        XCTAssertEqual(round1.count, 2)
        XCTAssertTrue(bench.isEmpty)

        // Team A wins on both courts.
        let scores = Dictionary(uniqueKeysWithValues: round1.map { ($0.id, FixtureScore(score: TeamPair(a: 11, b: 6))) })
        let (round2, _) = try XCTUnwrap(KingOfTheCourt.nextRound(after: round1, scores: scores, bench: bench, doubles: true))

        let king1 = round1[0], court2 = round1[1]
        let kingNext = try XCTUnwrap(round2.first { $0.court == 1 })
        let bottomNext = try XCTUnwrap(round2.first { $0.court == 2 })
        XCTAssertEqual(Set(kingNext.players), Set(king1.teams.a + court2.teams.a), "king court: its winners plus the winners from below")
        XCTAssertEqual(Set(bottomNext.players), Set(king1.teams.b + court2.teams.b), "bottom: losers from above plus its own losers")
        // Nobody keeps their partner.
        for fixture in round2 {
            for team in Team.allCases {
                let pair = Set(fixture.teams[team])
                XCTAssertFalse(round1.contains { Set($0.teams.a) == pair || Set($0.teams.b) == pair })
            }
        }
        XCTAssertNil(KingOfTheCourt.nextRound(after: round1, scores: [:], bench: bench, doubles: true), "waits for every court")
    }

    func testKingOfTheCourtBenchRotatesIn() throws {
        let ten = players + [PlayerID(), PlayerID()]
        let (round1, bench) = KingOfTheCourt.firstRound(ten, doubles: true)
        XCTAssertEqual(bench.count, 2)
        let scores = Dictionary(uniqueKeysWithValues: round1.map { ($0.id, FixtureScore(score: TeamPair(a: 11, b: 6))) })
        let (round2, bench2) = try XCTUnwrap(KingOfTheCourt.nextRound(after: round1, scores: scores, bench: bench, doubles: true))
        let bottomLosers = round1[1].teams.b
        XCTAssertEqual(Set(bench2), Set(bottomLosers), "bottom-court losers sit")
        XCTAssertTrue(Set(bench).isSubset(of: Set(round2.flatMap(\.players))), "the bench plays")
    }

    func testKingOfTheCourtStandings() {
        let (round1, _) = KingOfTheCourt.firstRound(Array(players.prefix(4)), doubles: false)
        XCTAssertEqual(round1.count, 2)
        let scores = [round1[0].id: FixtureScore(score: TeamPair(a: 11, b: 3)), round1[1].id: FixtureScore(score: TeamPair(a: 11, b: 9))]
        let rows = Standings.compute(format: .kingOfTheCourt, entrants: players.prefix(4).map { [$0] }, fixtures: round1, scores: scores)
        XCTAssertEqual(rows.first?.entrant, round1[0].teams.a, "a king-court win outranks a lower-court win")
        XCTAssertEqual(rows.first?.kingCourtWins, 1)
    }

    // MARK: Americano

    func testAmericanoEveryonePartnersEveryoneOnce() {
        for n in [4, 8] {
            let group = Array(players.prefix(n))
            let fixtures = Americano.schedule(group)
            XCTAssertEqual(Set(fixtures.map(\.round)).count, n - 1)
            var partners: [Set<PlayerID>: Int] = [:]
            for f in fixtures { for team in Team.allCases { partners[Set(f.teams[team]), default: 0] += 1 } }
            XCTAssertEqual(partners.count, n * (n - 1) / 2, "n=\(n)")
            XCTAssertTrue(partners.values.allSatisfy { $0 == 1 }, "n=\(n)")
            for round in Set(fixtures.map(\.round)) {
                let inRound = fixtures.filter { $0.round == round }.flatMap(\.players)
                XCTAssertEqual(inRound.count, n)
                XCTAssertEqual(Set(inRound).count, n)
            }
        }
    }

    func testAmericanoSharesSitOutsFairly() {
        for n in [5, 6, 7, 9, 10, 11] {
            let players = self.players + (0..<4).map { _ in PlayerID() }
            let group = Array(players.prefix(n))
            let fixtures = Americano.schedule(group)
            var games: [PlayerID: Int] = [:]
            for f in fixtures { for p in f.players { games[p, default: 0] += 1 } }
            let counts = group.map { games[$0, default: 0] }
            XCTAssertEqual(Set(counts).count, 1, "n=\(n): everyone plays the same number of games \(counts)")
            for round in Set(fixtures.map(\.round)) {
                let inRound = fixtures.filter { $0.round == round }.flatMap(\.players)
                XCTAssertEqual(inRound.count, Set(inRound).count)
            }
        }
    }

    func testAmericanoCountsEveryPointForTheIndividual() {
        let group = Array(players.prefix(4))
        let fixtures = Americano.schedule(group)
        var scores: [UUID: FixtureScore] = [:]
        // Player 0 wins every match 16-8; everyone else trades.
        for f in fixtures {
            scores[f.id] = FixtureScore(score: f.teams.a.contains(group[0]) ? TeamPair(a: 16, b: 8) : TeamPair(a: 8, b: 16))
        }
        let rows = Standings.compute(format: .americano, entrants: group.map { [$0] }, fixtures: fixtures, scores: scores)
        XCTAssertEqual(rows.first?.entrant, [group[0]])
        XCTAssertEqual(rows.first?.pointsFor, 48)
        XCTAssertEqual(rows.dropFirst().map(\.pointsFor), [32, 32, 32])
        XCTAssertEqual(rows.dropFirst().map(\.rank), [2, 2, 2])
    }

    func testFormatRawValuesMatchTheDatabase() {
        XCTAssertEqual(TournamentFormat.allCases.map(\.rawValue), ["round_robin", "king_of_court", "americano", "mexicano", "single_elimination", "double_elimination", "pools"])
        XCTAssertEqual(TournamentFormat.available(for: .padel).first, .americano)
        XCTAssertFalse(TournamentFormat.available(for: .pickleball).contains(.americano))
    }
}
