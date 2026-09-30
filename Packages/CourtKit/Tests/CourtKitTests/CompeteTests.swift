import XCTest
@testable import CourtKit

final class BracketTests: XCTestCase {
    let seeds = (0..<16).map { _ in PlayerID() }

    /// Plays every ready match: the better seed (lower index) wins unless
    /// `upset` says otherwise. Returns the final state.
    func playOut(_ entrants: [[PlayerID]], double: Bool, upset: (Bracket.Node) -> Bool = { _ in false }) -> (Bracket.State, [Fixture], [UUID: FixtureScore]) {
        var fixtures: [Fixture] = []
        var scores: [UUID: FixtureScore] = [:]
        let rank = Dictionary(uniqueKeysWithValues: entrants.enumerated().map { ($1[0], $0) })
        for _ in 0..<100 {
            let state = Bracket.resolve(entrants: entrants, double: double, fixtures: fixtures, scores: scores)
            let new = state.fixturesToAdd
            if new.isEmpty { return (state, fixtures, scores) }
            for fixture in new {
                fixtures.append(fixture)
                let node = state.nodes.first { $0.stage == fixture.stage && $0.round == fixture.round && $0.slot == fixture.slot }!
                let aBetter = rank[fixture.teams.a[0]]! < rank[fixture.teams.b[0]]!
                let aWins = upset(node) ? !aBetter : aBetter
                scores[fixture.id] = FixtureScore(score: aWins ? TeamPair(a: 11, b: 6) : TeamPair(a: 6, b: 11))
            }
        }
        XCTFail("bracket never finished")
        return (Bracket.resolve(entrants: entrants, double: double, fixtures: fixtures, scores: scores), fixtures, scores)
    }

    func testSeedOrderKeepsTopSeedsApart() {
        XCTAssertEqual(Bracket.seedOrder(size: 2), [0, 1])
        XCTAssertEqual(Bracket.seedOrder(size: 4), [0, 3, 1, 2])
        XCTAssertEqual(Bracket.seedOrder(size: 8), [0, 7, 3, 4, 1, 6, 2, 5])
        XCTAssertEqual(Bracket.size(for: 5), 8)
        XCTAssertEqual(Bracket.size(for: 8), 8)
        XCTAssertEqual(Bracket.size(for: 2), 2)
    }

    func testKnockoutGivesByesToTopSeeds() {
        let entrants = seeds.prefix(6).map { [$0] }
        let state = Bracket.resolve(entrants: entrants, double: false, fixtures: [], scores: [:])
        // 6 in a bracket of 8: seeds 1 and 2 have byes; 3v6 and 4v5 play.
        let first = state.fixturesToAdd
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(Set(first.map { Set($0.players) }), [Set([seeds[3], seeds[4]]), Set([seeds[2], seeds[5]])])
        XCTAssertEqual(state.nodes(.winners, round: 1).filter(\.isWalkover).count, 2)
        XCTAssertNil(state.champion)
    }

    func testKnockoutPlaysToAChampion() {
        for n in 2...16 {
            let entrants = seeds.prefix(n).map { [$0] }
            let (state, fixtures, _) = playOut(entrants, double: false)
            XCTAssertEqual(state.champion, [seeds[0]], "n=\(n)")
            XCTAssertEqual(fixtures.count, n - 1, "n=\(n): every match but the byes")
            if n >= 2 { XCTAssertEqual(state.runnerUp, [seeds[1]], "n=\(n): top two meet in the final") }
        }
    }

    func testDoubleEliminationEveryoneLosesTwiceExceptTheChampion() {
        for n in 3...16 {
            let entrants = seeds.prefix(n).map { [$0] }
            let (state, fixtures, scores) = playOut(entrants, double: true)
            XCTAssertEqual(state.champion, [seeds[0]], "n=\(n)")
            var losses: [PlayerID: Int] = [:]
            for f in fixtures {
                let w = scores[f.id]!.winner!
                for p in f.teams[w.opponent] { losses[p, default: 0] += 1 }
            }
            XCTAssertNil(losses[seeds[0]], "n=\(n): the favourite never lost")
            XCTAssertEqual(losses.count, n - 1, "n=\(n)")
            // Everyone else, runner-up included, is out on two losses.
            XCTAssertTrue(losses.values.allSatisfy { $0 == 2 }, "n=\(n)")
            XCTAssertEqual(fixtures.count, 2 * n - 2, "n=\(n): 2n − 2 matches without a reset")
        }
    }

    func testLosersChampionWinningTheFinalForcesAReset() {
        let entrants = seeds.prefix(4).map { [$0] }
        let (state, fixtures, _) = playOut(entrants, double: true) { node in node.stage == .final }
        XCTAssertTrue(fixtures.contains { $0.stage == .reset })
        XCTAssertEqual(state.champion, [seeds[0]], "the favourite wins the reset")
        XCTAssertEqual(fixtures.count, 2 * 4 - 1)
    }

    func testUpsetsCarryThrough() {
        let entrants = seeds.prefix(8).map { [$0] }
        // Seed 8 knocks out seed 1 in round one, then keeps winning.
        let (state, _, _) = playOut(entrants, double: false) { node in
            node.a.entrant == [self.seeds[0]] || node.b.entrant == [self.seeds[0]] || node.a.entrant == [self.seeds[7]] || node.b.entrant == [self.seeds[7]]
        }
        XCTAssertEqual(state.champion, [seeds[7]])
    }

    func testFixturesToAddWaitForFeeders() {
        let entrants = seeds.prefix(4).map { [$0] }
        var state = Bracket.resolve(entrants: entrants, double: false, fixtures: [], scores: [:])
        let round1 = state.fixturesToAdd
        XCTAssertEqual(round1.count, 2)
        var scores = [round1[0].id: FixtureScore(score: TeamPair(a: 11, b: 3))]
        state = Bracket.resolve(entrants: entrants, double: false, fixtures: round1, scores: scores)
        XCTAssertTrue(state.fixturesToAdd.isEmpty, "the final waits for both semifinals")
        scores[round1[1].id] = FixtureScore(score: TeamPair(a: 11, b: 3))
        state = Bracket.resolve(entrants: entrants, double: false, fixtures: round1, scores: scores)
        XCTAssertEqual(state.fixturesToAdd.map(\.round), [2])
        XCTAssertEqual(state.name(of: state.upcoming[0]), .final)
        XCTAssertEqual(state.name(of: state.nodes(.winners, round: 1)[0]), .semifinal)
    }

    func testDoublesPairsStayTogether() {
        let pairs = stride(from: 0, to: 8, by: 2).map { [seeds[$0], seeds[$0 + 1]] }
        let (state, _, _) = playOut(pairs, double: false)
        XCTAssertEqual(state.champion, pairs[0])
    }

    func testFixtureDecodesWithoutStage() throws {
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","round":1,"court":2,"teams":{"a":[],"b":[]}}"#
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(old.utf8))
        XCTAssertEqual(fixture.stage, .main)
        XCTAssertNil(fixture.slot)
        let round = try JSONDecoder().decode(Fixture.self, from: JSONEncoder().encode(Fixture(round: 2, court: 1, teams: TeamPair(a: [], b: []), stage: .losers, slot: 3)))
        XCTAssertEqual(round.stage, .losers)
        XCTAssertEqual(round.slot, 3)
    }
}

final class PoolsAndMexicanoTests: XCTestCase {
    let players = (0..<16).map { _ in PlayerID() }

    func testSnakeSeeding() {
        let pools = Pools.split(players.prefix(8).map { [$0] }, pools: 2)
        XCTAssertEqual(pools[0], [[players[0]], [players[3]], [players[4]], [players[7]]])
        XCTAssertEqual(pools[1], [[players[1]], [players[2]], [players[5]], [players[6]]])
        XCTAssertEqual(Pools.suggestedCount(entrants: 8), 2)
        XCTAssertEqual(Pools.suggestedCount(entrants: 3), 1)
        XCTAssertEqual(Pools.suggestedAdvancing(entrants: 8, pools: 2), 2)
    }

    func testPoolsThenKnockout() {
        let entrants = players.prefix(8).map { [$0] }
        let pools = Pools.split(entrants, pools: 2)
        let fixtures = Pools.schedule(pools)
        XCTAssertEqual(fixtures.count, 12, "two pools of four: six matches each")
        XCTAssertTrue(fixtures.allSatisfy { $0.stage == .pool && $0.pool != nil })
        // Nobody is on two courts in the same round.
        for round in Set(fixtures.map(\.round)) {
            let courts = fixtures.filter { $0.round == round }.map(\.court)
            XCTAssertEqual(courts.count, Set(courts).count)
        }

        var scores: [UUID: FixtureScore] = [:]
        XCTAssertNil(Pools.qualifiers(pools: pools, advancing: 2, fixtures: fixtures, scores: scores))
        let seed = Dictionary(uniqueKeysWithValues: players.enumerated().map { ($1, $0) })
        for f in fixtures {
            let aWins = seed[f.teams.a[0]]! < seed[f.teams.b[0]]!
            scores[f.id] = FixtureScore(score: aWins ? TeamPair(a: 11, b: 5) : TeamPair(a: 5, b: 11))
        }
        let qualifiers = Pools.qualifiers(pools: pools, advancing: 2, fixtures: fixtures, scores: scores)!
        XCTAssertEqual(qualifiers.count, 4)
        XCTAssertEqual(Set(qualifiers.prefix(2)), [[players[0]], [players[1]]], "pool winners first")
        XCTAssertEqual(Set(qualifiers.suffix(2)), [[players[2]], [players[3]]])

        let bracket = Bracket.resolve(entrants: qualifiers, double: false, fixtures: fixtures, scores: scores)
        XCTAssertEqual(bracket.fixturesToAdd.count, 2, "pool fixtures don't count as bracket matches")
        // Pool winners don't meet their own pool's runner-up first.
        for f in bracket.fixturesToAdd {
            let poolOf = { (p: PlayerID) in pools.firstIndex { $0.contains([p]) }! }
            XCTAssertNotEqual(poolOf(f.teams.a[0]), poolOf(f.teams.b[0]))
        }
    }

    func testMexicanoGroupsByStandings() {
        let eight = Array(players.prefix(8))
        let round1 = Mexicano.firstRound(eight)
        XCTAssertEqual(round1.count, 2)
        XCTAssertEqual(round1[0].teams.a, [eight[0], eight[3]])
        XCTAssertEqual(round1[0].teams.b, [eight[1], eight[2]])
        XCTAssertNil(Mexicano.nextRound(players: eight, fixtures: round1, scores: [:]), "waits for the round")

        // Court 2's winners (players 5 and 6) run up the score.
        let scores = [round1[0].id: FixtureScore(score: TeamPair(a: 13, b: 11)),
                      round1[1].id: FixtureScore(score: TeamPair(a: 3, b: 21))]
        let round2 = Mexicano.nextRound(players: eight, fixtures: round1, scores: scores)!
        let ranking = Mexicano.ranking(players: eight, fixtures: round1, scores: scores)
        XCTAssertEqual(Array(ranking.prefix(2)), [eight[5], eight[6]].sorted { eight.firstIndex(of: $0)! < eight.firstIndex(of: $1)! })
        XCTAssertEqual(round2.map(\.round), [2, 2])
        XCTAssertEqual(Set(round2[0].players), Set(ranking.prefix(4)), "the top four share court 1")
        XCTAssertEqual(round2[0].teams.a, [ranking[0], ranking[3]])
    }

    func testMexicanoSitOutsRotate() {
        let six = Array(players.prefix(6))
        var fixtures: [Fixture] = []
        var scores: [UUID: FixtureScore] = [:]
        for _ in 0..<6 {
            let next = Mexicano.nextRound(players: six, fixtures: fixtures, scores: scores)!
            XCTAssertEqual(next.count, 1)
            for f in next { scores[f.id] = FixtureScore(score: TeamPair(a: 11, b: 8)) }
            fixtures += next
        }
        var games: [PlayerID: Int] = [:]
        for f in fixtures { for p in f.players { games[p, default: 0] += 1 } }
        XCTAssertEqual(Set(games.values), [4], "six rounds, four seats, six players: four games each")
    }

    func testMexicanoStandingsCountPoints() {
        XCTAssertTrue(TournamentFormat.mexicano.ranksByPoints)
        XCTAssertTrue(TournamentFormat.mexicano.ranksIndividuals)
        XCTAssertFalse(TournamentFormat.singleElimination.ranksIndividuals)
        XCTAssertTrue(TournamentFormat.available(for: .padel).contains(.mexicano))
        XCTAssertFalse(TournamentFormat.available(for: .pickleball).contains(.mexicano))
        XCTAssertEqual(TournamentFormat(rawValue: "double_elimination"), .doubleElimination)
    }
}

final class LadderLevelRecapTests: XCTestCase {
    let ana = PlayerRef(kind: .user, displayName: "Ana Lima")
    let ben = PlayerRef(kind: .user, displayName: "Ben")
    let cy = PlayerRef(kind: .user, displayName: "Cy")
    let dee = PlayerRef(kind: .user, displayName: "Dee")
    let eli = PlayerRef(kind: .user, displayName: "Eli")
    private var day = 0

    func match(_ winners: [PlayerRef], beat losers: [PlayerRef], points: (Int, Int) = (11, 7), sport: Sport = .pickleball, on date: Date? = nil) -> MatchResult {
        day += 1
        return MatchResult(
            id: UUID(), sport: sport, date: date ?? t0.addingTimeInterval(Double(day) * 86_400),
            lineup: Lineup(teamA: winners, teamB: losers), winner: .a,
            units: [CompletedUnit(score: TeamPair(a: points.0, b: points.1))],
            pointsWon: TeamPair(a: points.0, b: points.1), matchScore: TeamPair(a: 1, b: 0)
        )
    }

    // MARK: Ladder

    func testLadderLeapfrog() {
        let members = [ana, ben, cy, dee, eli].map(\.id)
        var rungs = Ladder.compute(members: members, results: [])
        XCTAssertEqual(rungs.map(\.player), members, "starts in joining order")

        // Dee (4th) beats Ben (2nd): Dee takes 2nd, Ben and Cy step down.
        let results = [match([dee], beat: [ben])]
        rungs = Ladder.compute(members: members, results: results)
        XCTAssertEqual(rungs.map(\.player), [ana, dee, ben, cy, eli].map(\.id))
        XCTAssertEqual(rungs[1].lastMove, 2)
        XCTAssertEqual(rungs[2].lastMove, -1)
        XCTAssertEqual(rungs[3].lastMove, 0, "Cy wasn't in the match")

        // Higher side wins: nothing moves.
        rungs = Ladder.compute(members: members, results: results + [match([ana], beat: [eli])])
        XCTAssertEqual(rungs.map(\.player), [ana, dee, ben, cy, eli].map(\.id))
        XCTAssertEqual(rungs[0].wins, 1)
        XCTAssertEqual(rungs[4].losses, 1)
    }

    func testLadderDoublesAndTop() {
        let members = [ana, ben, cy, dee].map(\.id)
        let win = match([cy, dee], beat: [ana, ben])
        let rungs = Ladder.compute(members: members, results: [win])
        XCTAssertEqual(rungs.map(\.player), [cy, dee, ana, ben].map(\.id))
        XCTAssertEqual(rungs[0].topSince, win.date)
        XCTAssertNil(rungs[1].topSince)
        // Left the squad: dropped. Guests don't count.
        let guest = PlayerRef.guest("Gus")
        let again = Ladder.compute(members: [ana, ben].map(\.id), results: [win, match([guest], beat: [ana])])
        XCTAssertEqual(again.map(\.player), [ana, ben].map(\.id))
    }

    // MARK: Levels

    func testLevelsStartAtThreeAndMoveWithResults() {
        let book = LevelBook.compute([match([ana], beat: [ben])])
        let a = book.level(of: ana.id, in: .pickleball)!, b = book.level(of: ben.id, in: .pickleball)!
        XCTAssertGreaterThan(a.level, 3.0)
        XCTAssertLessThan(b.level, 3.0)
        XCTAssertEqual(a.level - 3.0, 3.0 - b.level, accuracy: 1e-9, "zero-sum")
        XCTAssertTrue(a.isProvisional)
        XCTAssertNil(book.level(of: ana.id, in: .padel), "one level per sport")
        XCTAssertEqual(PlayerLevel().formatted, "3.00")
    }

    func testCloseLossesCostLessAndUpsetsPayMore() {
        let close = LevelBook.compute([match([ana], beat: [ben], points: (11, 9))])
        let rout = LevelBook.compute([match([ana], beat: [ben], points: (11, 0))])
        XCTAssertGreaterThan(close.level(of: ben.id, in: .pickleball)!.level, rout.level(of: ben.id, in: .pickleball)!.level)

        // Ana gets strong; beating her is worth more than beating Cy.
        var history = (0..<8).map { _ in match([ana], beat: [eli]) }
        let strongBook = LevelBook.compute(history + [match([ben], beat: [ana])])
        history = (0..<8).map { _ in match([cy], beat: [eli]) }
        let gain = strongBook.level(of: ben.id, in: .pickleball)!.level - 3.0
        let weakBook = LevelBook.compute([match([ben], beat: [dee])])
        XCTAssertGreaterThan(gain, weakBook.level(of: ben.id, in: .pickleball)!.level - 3.0)
    }

    func testLevelsPublishOnceEstablishedAndAreOrderIndependent() {
        let results = (0..<6).map { i in i.isMultiple(of: 3) ? match([ben], beat: [ana]) : match([ana, cy], beat: [ben, dee]) }
        let book = LevelBook.compute(results)
        XCTAssertEqual(LevelBook.compute(results.reversed()), book, "same result on every phone")
        XCTAssertEqual(book.published(for: ana.id).keys.sorted(), ["pickleball"])
        XCTAssertTrue(book.published(for: eli.id).isEmpty)
        XCTAssertEqual(book.level(of: ana.id, in: .pickleball)!.matches, 6)
        XCTAssertNotEqual(book.level(of: ana.id, in: .pickleball)!.recentChange, 0)
    }

    // MARK: Season recap

    func testSeasonRecap() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let season = Season(year: 2026)
        func d(_ month: Int, _ day: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 18))! }
        let results = [
            match([ana], beat: [ben], on: d(3, 1)),
            match([ben], beat: [ana], on: d(3, 8)),
            match([ben], beat: [ana], on: d(3, 15)),
            match([ben], beat: [ana], on: d(4, 1)),
            match([ana, cy], beat: [dee, eli], on: d(5, 1)),
            match([ana, cy], beat: [dee, eli], on: d(5, 8)),
            match([ana, cy], beat: [dee, eli], on: d(5, 15)),
            match([ana], beat: [eli], sport: .padel, on: d(5, 20)),
            match([ana], beat: [ben], on: calendar.date(from: DateComponents(year: 2025, month: 12, day: 30))!),
        ]
        let ledger = BeltLedger.compute(results)
        let recap = SeasonRecap.compute(for: ana.id, season: season, results: results, ledger: ledger,
                                        tournamentsWon: 1, now: d(12, 1), calendar: calendar)
        XCTAssertEqual(recap.matches, 8, "last season's match is left out")
        XCTAssertEqual(recap.wins, 5)
        XCTAssertEqual(recap.losses, 3)
        XCTAssertEqual(recap.nemesis?.player.id, ben.id)
        XCTAssertEqual(recap.nemesis?.losses, 3)
        XCTAssertEqual(recap.bestPartner?.player.id, cy.id)
        XCTAssertEqual(recap.bestPartner?.wins, 3)
        XCTAssertEqual(recap.favoriteOpponent?.player.id, eli.id)
        XCTAssertEqual(recap.longestWinStreak, 4)
        XCTAssertEqual(recap.busiestMonth, 5)
        XCTAssertEqual(recap.busiestMonthMatches, 4)
        XCTAssertEqual(recap.matchesBySport[.padel], 1)
        XCTAssertEqual(recap.peoplePlayed, 4)
        XCTAssertGreaterThanOrEqual(recap.beltsWon, 2)
        XCTAssertGreaterThan(recap.longestReignDays, 100, "the padel belt is still hers in December")
        XCTAssertEqual(recap.tournamentsWon, 1)
        XCTAssertTrue(SeasonRecap.compute(for: ana.id, season: Season(year: 2024), results: results, ledger: ledger, calendar: calendar).isEmpty)
    }
}

final class NudgeTests: XCTestCase {
    let me = PlayerRef(kind: .user, displayName: "Me")
    let sam = PlayerRef(kind: .user, displayName: "Sam Rivera")
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func at(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func result(_ w: PlayerRef, beat l: PlayerRef, on date: Date) -> MatchResult {
        MatchResult(id: UUID(), sport: .pickleball, date: date, lineup: Lineup(teamA: [w], teamB: [l]), winner: .a,
                    units: [], pointsWon: TeamPair(a: 11, b: 5), matchScore: TeamPair(a: 1, b: 0))
    }

    var names: (PlayerID) -> String? {
        { [me, sam] id in id == sam.id ? "Sam" : id == me.id ? "Me" : nil }
    }

    func testSamStillWearingYourBelt() {
        let ledger = BeltLedger.compute([result(me, beat: sam, on: at(1, 18)), result(sam, beat: me, on: at(2, 18))])
        XCTAssertTrue(Nudges.candidates(me: me.id, ledger: ledger, name: names, now: at(3, 12)).isEmpty, "give it a couple of days")
        let nudges = Nudges.candidates(me: me.id, ledger: ledger, name: names, now: at(5, 12))
        XCTAssertEqual(nudges.map(\.kind), [.beltTaken])
        XCTAssertEqual(nudges[0].name, "Sam")
        XCTAssertEqual(nudges[0].days, 2)
        // Sam never took a belt from me: no tease.
        let theirs = BeltLedger.compute([result(sam, beat: me, on: at(1, 18))])
        XCTAssertTrue(Nudges.candidates(me: me.id, ledger: theirs, name: names, now: at(9, 12)).isEmpty)
    }

    func testOneADayNeverAtNightNoRepeats() {
        let a = Nudge(kind: .beltTaken, name: "Sam", days: 3, key: "a")
        let b = Nudge(kind: .confirmWaiting, name: "Sam", key: "b")
        var history = NudgeHistory()

        // Most important first, straight away in the day.
        var pick = Nudges.choose(from: [a, b], history: history, now: at(5, 12), calendar: calendar)!
        XCTAssertEqual(pick.nudge, b)
        XCTAssertEqual(pick.at, at(5, 12))

        // At night: next morning.
        pick = Nudges.choose(from: [a], history: history, now: at(5, 23), calendar: calendar)!
        XCTAssertEqual(pick.at, calendar.date(bySettingHour: 9, minute: 30, second: 0, of: at(6, 0)))
        pick = Nudges.choose(from: [a], history: history, now: at(6, 2), calendar: calendar)!
        XCTAssertEqual(pick.at, calendar.date(bySettingHour: 9, minute: 30, second: 0, of: at(6, 0)))

        // Already sent one today: tomorrow.
        history.sent(b, at: at(5, 12))
        pick = Nudges.choose(from: [a, b], history: history, now: at(5, 15), calendar: calendar)!
        XCTAssertEqual(pick.nudge, a, "b was just sent")
        XCTAssertEqual(pick.at, calendar.date(bySettingHour: 9, minute: 30, second: 0, of: at(6, 0)))

        // Muted kinds never go out.
        XCTAssertNil(Nudges.choose(from: [a], history: history, policy: NudgePolicy(muted: [.beltTaken]), now: at(7, 12), calendar: calendar))
        // After a few days a tease can come back.
        XCTAssertEqual(Nudges.choose(from: [b], history: history, now: at(9, 12), calendar: calendar)?.nudge, b)
    }

    func testReignMilestone() {
        let ledger = BeltLedger.compute([result(me, beat: sam, on: at(1, 18))])
        let nudges = Nudges.candidates(me: me.id, ledger: ledger, name: names, now: at(8, 20))
        XCTAssertEqual(nudges.map(\.kind), [.reignMilestone])
        XCTAssertEqual(nudges[0].days, 7)
        XCTAssertTrue(Nudges.candidates(me: me.id, ledger: ledger, name: names, now: at(12, 20)).isEmpty)
    }

    func testWidgetShowsTheItchFirst() {
        let dee = PlayerRef(kind: .user, displayName: "Dee")
        let ledger = BeltLedger.compute([
            result(me, beat: sam, on: at(1, 18)),
            result(sam, beat: me, on: at(2, 18)),
            result(me, beat: dee, on: at(3, 18)),
        ])
        let snapshot = BeltWidgetSnapshot.make(me: me.id, ledger: ledger, names: { id in
            id == dee.id ? "Dee" : self.names(id)
        }, now: at(14, 12))
        XCTAssertEqual(snapshot.entries.map(\.holderName), ["Sam", "Me"])
        XCTAssertFalse(snapshot.entries[0].isMine)
        XCTAssertEqual(snapshot.entries[0].initials, "S")
        XCTAssertEqual(snapshot.entries[0].dayCount(asOf: at(14, 18)), "12d")
        let decoded = try? JSONDecoder().decode(BeltWidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded, snapshot)
    }
}

final class LocalizationTests: XCTestCase {
    func testFormatNamesAreTranslated() throws {
        for (lang, expected) in [("es", "Eliminatoria"), ("pt-BR", "Mata-mata"), ("it", "Eliminazione diretta")] {
            // SwiftPM lowercases region folders on Linux (pt-br.lproj).
            let path = try XCTUnwrap(CourtKitStrings.bundle.path(forResource: lang, ofType: "lproj")
                                     ?? CourtKitStrings.bundle.path(forResource: lang.lowercased(), ofType: "lproj"), lang)
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertEqual(bundle.localizedString(forKey: "Knockout", value: nil, table: nil), expected, lang)
        }
        XCTAssertEqual(TournamentFormat.singleElimination.title.isEmpty, false)
    }
}
