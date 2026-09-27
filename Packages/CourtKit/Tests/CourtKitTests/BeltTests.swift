import XCTest
@testable import CourtKit

final class BeltTests: XCTestCase {
    let alice = PlayerRef(kind: .user, displayName: "Alice")
    let bob = PlayerRef(kind: .user, displayName: "Bob")
    let carol = PlayerRef(kind: .user, displayName: "Carol")
    let dave = PlayerRef(kind: .user, displayName: "Dave")
    let squad = UUID()

    private var day = 0

    /// A confirmed result one day after the previous one.
    func match(_ winners: [PlayerRef], beat losers: [PlayerRef], sport: Sport = .pickleball, squad: UUID? = nil) -> MatchResult {
        day += 1
        return MatchResult(
            id: UUID(),
            sport: sport,
            date: t0.addingTimeInterval(Double(day) * 86_400),
            lineup: Lineup(teamA: winners, teamB: losers),
            winner: .a,
            units: [CompletedUnit(score: TeamPair(a: 11, b: 7))],
            pointsWon: TeamPair(a: 11, b: 7),
            matchScore: TeamPair(a: 1, b: 0),
            squadID: squad
        )
    }

    func testFirstMatchBetweenFriendsCreatesTheBelt() {
        var ledger = BeltLedger()
        let first = match([alice], beat: [bob])
        let events = ledger.record(first)

        let key = BeltKey.rivalry([alice.id], [bob.id], sport: .pickleball)
        XCTAssertEqual(events, [.created(key: key, holder: [alice.id], matchID: first.id)])
        XCTAssertEqual(ledger.belt(key)?.holder, [alice.id])
        XCTAssertTrue(ledger.isTitleMatch(first.id))
        XCTAssertEqual(BeltKey.rivalry([bob.id], [alice.id], sport: .pickleball), key, "the key doesn't depend on who won")
    }

    func testEveryMatchBetweenThemIsATitleMatch() throws {
        let results = [
            match([alice], beat: [bob]),   // created
            match([alice], beat: [bob]),   // defense 1
            match([bob], beat: [alice]),   // bob takes it
            match([bob], beat: [alice]),   // defense 1
            match([bob], beat: [alice]),   // defense 2
            match([alice], beat: [bob])    // alice back
        ]
        let ledger = BeltLedger.compute(results.shuffled())
        let belt = try XCTUnwrap(ledger.rivalryBelts(between: alice.id, and: bob.id).first)

        XCTAssertEqual(belt.holder, [alice.id])
        XCTAssertEqual(belt.reigns.count, 3)
        XCTAssertEqual(belt.reigns.map(\.defenses), [1, 2, 0])
        XCTAssertEqual(belt.totalReigns(of: alice.id), 2)
        XCTAssertEqual(belt.totalReigns(of: bob.id), 1)
        XCTAssertEqual(belt.mostDefenses, 2)
        XCTAssertEqual(belt.record(of: alice.id).wins, 3)
        XCTAssertEqual(belt.record(of: alice.id).losses, 3)
        XCTAssertEqual(belt.bouts.map(\.outcome), [.created, .defended, .changedHands, .defended, .defended, .changedHands])

        // Bob held it for three days (day 3 → day 6); Alice's first reign
        // lasted two, her current one has just started.
        let longest = try XCTUnwrap(belt.longestReign(asOf: results[5].date))
        XCTAssertEqual(longest.holder, [bob.id])
        XCTAssertEqual(longest.days(asOf: results[5].date), 3)
        XCTAssertEqual(ledger.events(for: results[2].id),
                       [.changedHands(key: belt.key, from: [alice.id], to: [bob.id], matchID: results[2].id)])
    }

    func testSportsHaveSeparateBelts() {
        let ledger = BeltLedger.compute([
            match([alice], beat: [bob], sport: .pickleball),
            match([bob], beat: [alice], sport: .padel)
        ])
        let belts = ledger.rivalryBelts(between: alice.id, and: bob.id)
        XCTAssertEqual(belts.count, 2)
        XCTAssertEqual(belts.first { $0.key.sport == .pickleball }?.holder, [alice.id])
        XCTAssertEqual(belts.first { $0.key.sport == .padel }?.holder, [bob.id])
    }

    func testPairsHoldDoublesBeltsTogether() throws {
        let ledger = BeltLedger.compute([
            match([alice, bob], beat: [carol, dave]),
            match([dave, carol], beat: [bob, alice]),
            // Same four players, different pairs: a different belt.
            match([alice, carol], beat: [bob, dave])
        ])
        let key = BeltKey.rivalry([alice.id, bob.id], [carol.id, dave.id], sport: .pickleball)
        let belt = try XCTUnwrap(ledger.belt(key))
        XCTAssertEqual(belt.key.kind, .doubles)
        XCTAssertEqual(Set(belt.holder ?? []), [carol.id, dave.id])
        XCTAssertEqual(belt.reigns.count, 2)
        XCTAssertEqual(ledger.belts.count, 2)
    }

    func testSquadBeltOnlyChangesInMatchesTheHolderPlays() throws {
        let ledger = BeltLedger.compute([
            match([alice], beat: [bob], squad: squad),    // alice holds the squad belt
            match([carol], beat: [dave], squad: squad),   // not a title match for the squad belt
            match([carol], beat: [alice], squad: squad),  // carol takes it
            match([carol], beat: [bob]),                  // no squad: rivalry only
            match([carol], beat: [dave], squad: squad)    // defense
        ])
        let belt = try XCTUnwrap(ledger.belt(.squad(squad, doubles: false, sport: .pickleball)))
        XCTAssertEqual(belt.holder, [carol.id])
        XCTAssertEqual(belt.defenses, 1)
        XCTAssertEqual(belt.bouts.count, 3)
        XCTAssertEqual(ledger.squadBelts(squad).count, 1)
        // carol-dave's own rivalry belt was created by their first meeting.
        XCTAssertEqual(ledger.rivalryBelts(between: carol.id, and: dave.id).first?.defenses, 1)
    }

    func testGuestsAndUnevenSidesNeverTouchABelt() {
        let guest = PlayerRef.guest("Sam")
        var ledger = BeltLedger()
        XCTAssertEqual(ledger.record(match([alice], beat: [guest])), [])
        XCTAssertEqual(ledger.record(match([alice, bob], beat: [carol])), [])
        XCTAssertTrue(ledger.belts.isEmpty)
    }

    func testRecordingTheSameMatchTwiceIsIgnored() {
        var ledger = BeltLedger()
        let result = match([alice], beat: [bob])
        ledger.record(result)
        ledger.record(result)
        XCTAssertEqual(ledger.belts.values.first?.bouts.count, 1)
    }

    func testArtUpgradesWithDefenses() {
        XCTAssertEqual(BeltTier(defenses: 0), .plain)
        XCTAssertEqual(BeltTier(defenses: 2), .plain)
        XCTAssertEqual(BeltTier(defenses: 3), .gold)
        XCTAssertEqual(BeltTier(defenses: 5), .undisputed)
        XCTAssertEqual(BeltTier.defensesToNextTier(from: 1), 2)
        XCTAssertEqual(BeltTier.defensesToNextTier(from: 4), 1)
        XCTAssertNil(BeltTier.defensesToNextTier(from: 9))

        var results = [match([alice], beat: [bob])]
        for _ in 0..<5 { results.append(match([alice], beat: [bob])) }
        let ledger = BeltLedger.compute(results)
        XCTAssertEqual(ledger.held(by: alice.id).first?.tier, .undisputed)

        let shareWorthy = results.flatMap { ledger.events(for: $0.id) }.filter(\.isShareWorthy)
        XCTAssertEqual(shareWorthy.count, 2, "gold at 3 defenses and undisputed at 5")
    }

    func testBeltEventsRoundTripThroughJSON() throws {
        let key = BeltKey.squad(squad, doubles: true, sport: .padel)
        let event = BeltEvent.changedHands(key: key, from: [alice.id, bob.id], to: [carol.id, dave.id], matchID: UUID())
        let decoded = try JSONDecoder().decode(BeltEvent.self, from: JSONEncoder().encode(event))
        XCTAssertEqual(decoded, event)
    }

    func testShareCardOfferedToTheNewHolderOnly() throws {
        var ledger = BeltLedger()
        ledger.record(match([alice], beat: [bob]))
        let upset = match([bob], beat: [alice])
        let events = ledger.record(upset)

        let card = try XCTUnwrap(ShareCards.prompt(for: bob.id, result: upset, beltEvents: events, drama: nil))
        XCTAssertEqual(card.kind, .beltWon)
        XCTAssertEqual(card.callToAction, "Beat Bob and take the belt.")
        XCTAssertNil(ShareCards.prompt(for: alice.id, result: upset, beltEvents: events, drama: nil))
    }
}
