import XCTest
@testable import CourtKit

final class UsernameTests: XCTestCase {
    func testNormalizing() {
        XCTAssertEqual(Username.normalize("  @@Priya.K "), "priya.k")
    }

    func testRulesMatchTheDatabase() {
        XCTAssertNil(Username.problem(with: "priya_k.99"))
        XCTAssertEqual(Username.problem(with: "pk"), .tooShort)
        XCTAssertEqual(Username.problem(with: String(repeating: "a", count: 21)), .tooLong)
        XCTAssertEqual(Username.problem(with: "priya k"), .invalidCharacter(" "))
        XCTAssertEqual(Username.problem(with: "Priya"), .invalidCharacter("P"))
        XCTAssertEqual(Username.problem(with: "_priya"), .edgePunctuation)
        XCTAssertEqual(Username.problem(with: "priya."), .edgePunctuation)
        XCTAssertEqual(Username.problem(with: "admin"), .reserved)
    }

    func testSuggestionsAreAlwaysValid() {
        for name in ["Priya K.", "José Núñez", "A", "__", "Admin", "O'Brien-Smith III", String(repeating: "x", count: 40)] {
            let suggestion = Username.suggestion(from: name)
            XCTAssertTrue(Username.isValid(suggestion), "\(name) → \(suggestion)")
        }
        XCTAssertEqual(Username.suggestion(from: "Priya K."), "priya.k")
        XCTAssertEqual(Username.suggestion(from: "José Núñez"), "jose.nunez")
    }
}

final class ContentFilterTests: XCTestCase {
    let filter = ContentFilter.standard

    func testCleanTextPasses() {
        XCTAssertEqual(filter.check("Great dink at 9-9, see you Sunday"), .clean)
        XCTAssertEqual(filter.check("Scunthorpe classic"), .clean, "whole words only")
        XCTAssertEqual(filter.check("pros and cons, what a con"), .clean, "doubled letters are not stretched")
    }

    func testProfanityIsMaskedInPlace() {
        XCTAssertEqual(filter.check("what the fuck was that lob"), .masked("what the f*** was that lob"))
        XCTAssertEqual(filter.check("SH1T shot"), .masked("S*** shot"))
        XCTAssertEqual(filter.check("fuuuuck"), .masked("f******"))
        XCTAssertEqual(filter.check("shiiiit"), .masked("s******"))
        XCTAssertEqual(filter.check("well f u c k"), .masked("well * * * *"))
    }

    func testSlursAreRefused() {
        XCTAssertEqual(filter.check("you f@ggot"), .blocked)
        XCTAssertEqual(filter.check("r e t a r d"), .blocked)
        XCTAssertNil(filter.cleaned("what a retard"))
        XCTAssertFalse(filter.allows("RETARDED"))
    }
}

final class CallOutTests: XCTestCase {
    let alice = PlayerID(), bob = PlayerID(), carol = PlayerID(), dave = PlayerID()

    func callOut() -> CallOut {
        CallOut(createdBy: alice, challengers: [alice], challenged: [bob], rules: .standard(for: .pickleball, isDoubles: false),
                terms: .init(proposedAt: t0))
    }

    func testChallengedSideMovesFirst() {
        let c = callOut()
        XCTAssertEqual(c.moves(for: bob), [.accept, .counter, .decline])
        XCTAssertEqual(c.moves(for: alice), [.cancel])
        XCTAssertEqual(c.moves(for: carol), [])
    }

    func testCountersBounceUntilAccepted() throws {
        var c = callOut()
        let later = t0.addingTimeInterval(3600)
        try c.apply(.counter(.init(proposedAt: later, court: CourtTag(name: "Rec Center"))), by: bob)
        XCTAssertEqual(c.status, .countered)
        XCTAssertEqual(c.currentTerms.proposedAt, later)
        XCTAssertThrowsError(try c.apply(.accept, by: bob)) { XCTAssertEqual($0 as? CallOut.MoveError, .notYourTurn) }

        try c.apply(.counter(.init(proposedAt: t0.addingTimeInterval(7200))), by: alice)
        XCTAssertEqual(c.moves(for: bob), [.accept, .counter, .decline])
        try c.apply(.accept, by: bob)
        XCTAssertEqual(c.status, .accepted)
        XCTAssertEqual(c.terms.proposedAt, t0.addingTimeInterval(7200))
        XCTAssertEqual(c.terms.court?.name, nil, "a counter without a court keeps the original court")
        XCTAssertThrowsError(try c.apply(.decline, by: bob)) { XCTAssertEqual($0 as? CallOut.MoveError, .closed) }
    }

    func testOnlyTheChallengerCancels() throws {
        var c = callOut()
        XCTAssertThrowsError(try c.apply(.cancel, by: bob)) { XCTAssertEqual($0 as? CallOut.MoveError, .onlyChallengerCancels) }
        XCTAssertThrowsError(try c.apply(.accept, by: carol)) { XCTAssertEqual($0 as? CallOut.MoveError, .notInCallOut) }
        try c.apply(.accept, by: bob)
        try c.apply(.cancel, by: alice)
        XCTAssertEqual(c.status, .cancelled)
    }

    func testResultBetweenTheRightPlayersSettlesIt() {
        var c = CallOut(createdBy: alice, challengers: [alice, carol], challenged: [bob, dave], rules: .standard(for: .padel))
        let ref = { (id: PlayerID) in PlayerRef(id: id, kind: .user, displayName: "") }
        XCTAssertTrue(c.isSettled(by: Lineup(teamA: [ref(dave), ref(bob)], teamB: [ref(carol), ref(alice)])))
        XCTAssertFalse(c.isSettled(by: Lineup(teamA: [ref(alice), ref(bob)], teamB: [ref(carol), ref(dave)])))
        let match = UUID()
        c.complete(with: match)
        XCTAssertEqual(c.status, .completed)
        XCTAssertEqual(c.matchID, match)
    }
}

final class ScoreEntryTests: XCTestCase {
    func unit(_ a: Int, _ b: Int, tb: (Int, Int)? = nil, superTB: Bool = false) -> CompletedUnit {
        CompletedUnit(score: TeamPair(a: a, b: b), tiebreak: tb.map { TeamPair(a: $0.0, b: $0.1) }, isSuperTiebreak: superTB)
    }

    func testPickleballGames() throws {
        let bestOfThree = sideOut(games: 2)
        let entered = try ScoreEntry.validate([unit(11, 7), unit(9, 11), unit(13, 11)], rules: bestOfThree).get()
        XCTAssertEqual(entered.winner, .a)
        XCTAssertEqual(entered.matchScore, TeamPair(a: 2, b: 1))
        XCTAssertEqual(entered.pointsWon, TeamPair(a: 33, b: 29))

        XCTAssertEqual(ScoreEntry.validate([unit(11, 10)], rules: sideOut()), .failure(.invalidUnit(index: 0)))
        XCTAssertEqual(ScoreEntry.validate([unit(12, 5)], rules: sideOut()), .failure(.invalidUnit(index: 0)), "game ended at 11")
        XCTAssertEqual(ScoreEntry.validate([unit(14, 11)], rules: sideOut()), .failure(.invalidUnit(index: 0)), "game ended at 13-11")
        XCTAssertEqual(ScoreEntry.validate([unit(11, 3), unit(11, 4), unit(11, 5)], rules: bestOfThree), .failure(.extraUnits(from: 2)))
        XCTAssertEqual(ScoreEntry.validate([unit(11, 3)], rules: bestOfThree), .failure(.undecided))
        XCTAssertEqual(ScoreEntry.validate([], rules: sideOut()), .failure(.noScores))
    }

    func testPickleballPointCap() throws {
        let capped = rally(to: 21, cap: 25)
        XCTAssertEqual(try ScoreEntry.validate([unit(24, 25)], rules: capped).get().winner, .b)
        XCTAssertEqual(ScoreEntry.validate([unit(26, 24)], rules: capped), .failure(.invalidUnit(index: 0)))
    }

    func testPadelSets() throws {
        let rules = padel()
        let straight = try ScoreEntry.validate([unit(6, 4), unit(7, 6, tb: (7, 5))], rules: rules).get()
        XCTAssertEqual(straight.winner, .a)
        let superTB = try ScoreEntry.validate([unit(6, 4), unit(3, 6), unit(0, 0, tb: (8, 10), superTB: true)], rules: rules).get()
        XCTAssertEqual(superTB.winner, .b)
        XCTAssertEqual(try ScoreEntry.validate([unit(7, 5), unit(6, 0)], rules: rules).get().matchScore, TeamPair(a: 2, b: 0))

        XCTAssertEqual(ScoreEntry.validate([unit(6, 5), unit(6, 0)], rules: rules), .failure(.invalidUnit(index: 0)))
        XCTAssertEqual(ScoreEntry.validate([unit(7, 6, tb: (6, 7)), unit(6, 0)], rules: rules), .failure(.invalidUnit(index: 0)),
                       "tiebreak must go to the set winner")
        XCTAssertEqual(ScoreEntry.validate([unit(0, 0, tb: (10, 8), superTB: true)], rules: rules), .failure(.misplacedSuperTiebreak(index: 0)))
        XCTAssertEqual(ScoreEntry.validate([unit(6, 4), unit(3, 6), unit(6, 3)], rules: rules), .failure(.invalidUnit(index: 2)),
                       "the decider is a match tiebreak in this format")
        XCTAssertEqual(try ScoreEntry.validate([unit(6, 4), unit(3, 6), unit(6, 3)], rules: padel(deciding: .fullSet)).get().winner, .a)
        XCTAssertEqual(ScoreEntry.validate([unit(6, 4), unit(3, 6), unit(0, 0, tb: (11, 10), superTB: true)], rules: rules),
                       .failure(.invalidUnit(index: 2)))
    }
}

final class DramaTests: XCTestCase {
    let lineup = Lineup(teamA: [PlayerRef(kind: .user, displayName: "Alice")], teamB: [PlayerRef(kind: .user, displayName: "Bob")])

    func testComebackFromFarBehind() {
        // Rally scoring to 11: B leads 9-2, A wins nine straight.
        let log = "BBAABBBBBBB" + "AAAAAAAAA"
        let rules = rally(to: 11)
        let drama = DramaDetector.analyze(rules: rules, rallies: log.map { Rally(winner: Team(code: $0)!) })
        XCTAssertEqual(drama.winner, .a)
        guard case .comeback(let team, 0, let deficit, let trailing)? = drama.moments.first(where: {
            if case .comeback = $0 { return true } else { return false }
        }) else { return XCTFail("no comeback in \(drama.moments)") }
        XCTAssertEqual(team, .a)
        XCTAssertEqual(deficit, 7)
        XCTAssertEqual(trailing, TeamPair(a: 2, b: 9))
        XCTAssertTrue(drama.isBigComeback)
        XCTAssertTrue(drama.moments.contains(.run(team: .a, length: 9, unit: 0)))
        XCTAssertTrue(drama.headline(lineup).contains("Alice came back from 2-9"), drama.headline(lineup))
    }

    func testSavedMatchPoints() {
        // Rally scoring to 11: B reaches 10-8 (two match points), A wins out 12-10.
        let log = "ABABABABABABABAB" + "BB" + "AAAA"
        let drama = DramaDetector.analyze(rules: rally(to: 11), rallies: log.map { Rally(winner: Team(code: $0)!) })
        XCTAssertEqual(drama.winner, .a)
        XCTAssertTrue(drama.moments.contains(.savedMatchPoints(team: .a, count: 2)), "\(drama.moments)")
        XCTAssertTrue(drama.moments.contains(.marathon(unit: 0, score: TeamPair(a: 12, b: 10))) == false,
                      "12-10 is extra time, not a marathon (13+)")
        XCTAssertTrue(drama.isBigComeback)
        if case .savedMatchPoints = drama.moments.first {} else { XCTFail("saved match points should lead: \(drama.moments)") }
    }

    func testRoutineWinHasLittleDrama() {
        let drama = DramaDetector.analyze(rules: rally(to: 11), rallies: "ABAAAABAAAAAAA".map { Rally(winner: Team(code: $0)!) })
        XCTAssertLessThan(drama.intensity, 0.3)
        XCTAssertFalse(drama.isBigComeback)
    }

    func testEnteredScoresStillTellAStory() {
        let units = [CompletedUnit(score: TeamPair(a: 6, b: 11)), CompletedUnit(score: TeamPair(a: 15, b: 13)), CompletedUnit(score: TeamPair(a: 11, b: 0))]
        let drama = DramaDetector.analyze(units: units, rules: sideOut(games: 2), winner: .a)
        XCTAssertTrue(drama.moments.contains(.decider))
        XCTAssertTrue(drama.moments.contains(.matchComeback(team: .a, units: 1)))
        XCTAssertTrue(drama.moments.contains(.marathon(unit: 1, score: TeamPair(a: 15, b: 13))))
        XCTAssertTrue(drama.moments.contains(.bagel(team: .a, unit: 2)))
        XCTAssertEqual(drama.lines(lineup).last(where: { $0.contains("bagel") }), "Alice served up a bagel in the third game")
    }

    func testReplayStoryReadsLikeTheMatch() throws {
        let rules = rally(to: 11)
        let log = ("BBAABBBBBBB" + "AAAAAAAAA").map { Rally(winner: Team(code: $0)!) }
        let scorer = MatchScorer(rules: rules, rallies: log)
        let result = MatchResult(id: UUID(), date: t0, lineup: lineup, scorer: scorer)
        let drama = DramaDetector.analyze(rules: rules, rallies: log)
        let story = ReplayStory.make(result: result, drama: drama, beltLines: ["Alice keeps the belt"], court: CourtTag(name: "Court 3"), photoCount: 2)

        XCTAssertEqual(story.beats.first, .opening(sport: .pickleball, date: t0, court: "Court 3", isTitleMatch: true))
        XCTAssertEqual(story.beats.filter { if case .photo = $0 { return true } else { return false } }.count, 2)
        XCTAssertEqual(story.beats.last, .final(winners: "Alice", scoreLine: "11-9"))
        XCTAssertTrue(story.beats.contains(.belt("Alice keeps the belt")))
        let decoded = try JSONDecoder().decode(ReplayStory.self, from: JSONEncoder().encode(story))
        XCTAssertEqual(decoded, story)
    }
}

final class FunLayerTests: XCTestCase {
    func testReplaysLastADayUnlessSaved() {
        XCTAssertTrue(ReplayLifetime.isVisible(createdAt: t0, saved: false, now: t0.addingTimeInterval(23 * 3600)))
        XCTAssertFalse(ReplayLifetime.isVisible(createdAt: t0, saved: false, now: t0.addingTimeInterval(24 * 3600)))
        XCTAssertTrue(ReplayLifetime.isVisible(createdAt: t0, saved: true, now: t0.addingTimeInterval(90 * 86_400)))
        XCTAssertEqual(ReplayLifetime.remaining(createdAt: t0, now: t0.addingTimeInterval(6 * 3600)), 0.75, accuracy: 1e-9)
    }

    func testDeadBall() {
        let day: TimeInterval = 86_400
        XCTAssertTrue(FeedRules.isInPlay(createdAt: t0, lastReturnAt: nil, now: t0.addingTimeInterval(day - 1)))
        XCTAssertFalse(FeedRules.isInPlay(createdAt: t0, lastReturnAt: nil, now: t0.addingTimeInterval(day)))
        XCTAssertTrue(FeedRules.isInPlay(createdAt: t0, lastReturnAt: t0.addingTimeInterval(day), now: t0.addingTimeInterval(1.5 * day)),
                      "a Return keeps the ball in play")
        let items: [(Date, Date?)] = [(t0, nil), (t0.addingTimeInterval(10), nil), (t0, t0.addingTimeInterval(20))]
        let sorted = FeedRules.sorted(items, createdAt: { $0.0 }, lastReturnAt: { $0.1 })
        XCTAssertEqual(sorted.map { $0.1 != nil }, [true, false, false])
    }

    func testPhotoPromptsAreRareAndOnlyAtChangeovers() {
        var prompter = PhotoPrompter()
        XCTAssertFalse(prompter.shouldPrompt(after: [.point(.a)], at: t0))
        XCTAssertTrue(prompter.shouldPrompt(after: [.point(.a), .gameWon(.a)], at: t0))
        prompter.didPrompt(at: t0)
        XCTAssertFalse(prompter.shouldPrompt(after: [.changeEnds], at: t0.addingTimeInterval(60)))
        XCTAssertTrue(prompter.shouldPrompt(after: [.changeEnds], at: t0.addingTimeInterval(9 * 60)))
        XCTAssertFalse(prompter.shouldPrompt(after: [.gameWon(.a), .matchWon(.a)], at: t0.addingTimeInterval(30 * 60)))
        prompter.didPrompt(at: t0.addingTimeInterval(600))
        prompter.didPrompt(at: t0.addingTimeInterval(1200))
        XCTAssertFalse(prompter.shouldPrompt(after: [.changeEnds], at: t0.addingTimeInterval(3600)), "three is enough")
    }

    func testChantsAreShortAndSorted() {
        let wild = Chant(id: "x", name: "x", beats: (0..<20).map { Chant.Beat(at: Double(20 - $0), strength: 2) })
        XCTAssertEqual(wild.beats.count, Chant.maxBeats)
        XCTAssertLessThanOrEqual(wild.duration, Chant.maxDuration)
        XCTAssertEqual(wild.beats.map(\.at), wild.beats.map(\.at).sorted())
        XCTAssertTrue(wild.beats.allSatisfy { $0.strength == 1 })
        XCTAssertEqual(Chant.preset(id: "lets-go"), .letsGo)
    }

    func testCrowdMeterRisesAndFades() {
        var meter = CrowdMeter()
        XCTAssertEqual(meter.level(at: t0), 0)
        for i in 0..<10 { meter.add(at: t0.addingTimeInterval(Double(i) * 0.3)) }
        let loud = meter.level(at: t0.addingTimeInterval(3))
        XCTAssertGreaterThan(loud, 0.7)
        XCTAssertLessThan(meter.level(at: t0.addingTimeInterval(63)), loud / 3)
    }

    func testChantsNeverFloodTheWrist() {
        var player = ChantPlayer()
        let bob = PlayerID(), carol = PlayerID()
        let tap = { (who: PlayerID) in CrowdTap(matchID: UUID(), from: who, fromName: "", chantID: "lets-go") }
        XCTAssertTrue(player.shouldPlay(tap(bob), now: t0))
        XCTAssertFalse(player.shouldPlay(tap(carol), now: t0.addingTimeInterval(1)))
        XCTAssertTrue(player.shouldPlay(tap(carol), now: t0.addingTimeInterval(5)))
        XCTAssertFalse(player.shouldPlay(tap(bob), now: t0.addingTimeInterval(10)), "same friend, too soon")
        XCTAssertTrue(player.shouldPlay(tap(bob), now: t0.addingTimeInterval(16)))
    }

    func testShuffleNeverRepeatsThePairing() {
        let players = ["A", "B", "C", "D"].map { PlayerRef(kind: .user, displayName: $0) }
        let previous = Lineup(teamA: [players[0], players[1]], teamB: [players[2], players[3]])
        var rng = SeededGenerator(seed: 7)
        for _ in 0..<50 {
            let lineup = TeamShuffle.shuffle(players, avoiding: previous, using: &rng)!
            XCTAssertNotEqual(TeamShuffle.partnerships(lineup), TeamShuffle.partnerships(previous))
            XCTAssertEqual(Set(lineup.allPlayers.map(\.id)), Set(players.map(\.id)))
        }
        XCTAssertNil(TeamShuffle.shuffle(Array(players.prefix(3))))
        XCTAssertEqual(TeamShuffle.shuffle(Array(players.prefix(2)))?.isDoubles, false)
    }
}

/// Deterministic generator for shuffle tests (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
