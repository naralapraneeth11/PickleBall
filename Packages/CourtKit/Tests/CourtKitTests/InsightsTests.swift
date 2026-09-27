import XCTest
@testable import CourtKit

final class InsightsTests: XCTestCase {
    let me = player("Me")
    let sam = player("Sam")
    let priya = player("Priya")
    let jay = player("Jay")
    let alex1 = player("Alex")
    let alex2 = player("Alex")   // same name, different person

    private func result(
        _ day: Int,
        _ teamA: [PlayerRef],
        _ teamB: [PlayerRef],
        points: (Int, Int),
        sport: Sport = .pickleball
    ) -> MatchResult {
        let winner: Team = points.0 > points.1 ? .a : .b
        return MatchResult(
            id: UUID(),
            sport: sport,
            date: t0.addingTimeInterval(Double(day) * 86_400),
            lineup: Lineup(teamA: teamA, teamB: teamB),
            winner: winner,
            units: [CompletedUnit(score: TeamPair(a: points.0, b: points.1))],
            pointsWon: TeamPair(a: points.0, b: points.1),
            matchScore: winner == .a ? TeamPair(a: 1, b: 0) : TeamPair(a: 0, b: 1)
        )
    }

    func testHeadToHeadRecordStreakAndClosest() {
        let results = [
            result(1, [me], [sam], points: (11, 5)),
            result(2, [sam], [me], points: (11, 9)),
            result(3, [me], [sam], points: (12, 10)),
            result(4, [me], [sam], points: (8, 11)),
            result(5, [sam], [me], points: (11, 3)),
            result(6, [me], [priya], points: (11, 0))    // not against Sam
        ]
        let h2h = HeadToHead.compute(me: me.id, opponent: sam.id, results: results)
        XCTAssertEqual(h2h.wins, 2)
        XCTAssertEqual(h2h.losses, 3)
        XCTAssertEqual(h2h.lastFive, [false, false, true, false, true])
        XCTAssertEqual(h2h.streak?.winner, sam.id)
        XCTAssertEqual(h2h.streak?.count, 2)
        XCTAssertEqual(h2h.pointDifferential, (6) + (-2) + (2) + (-3) + (-8))
        XCTAssertEqual(abs(h2h.closest?.pointDifferential ?? 0), 2)
    }

    func testSameNameDifferentPeopleStaySeparate() {
        let results = [
            result(1, [me], [alex1], points: (11, 2)),
            result(2, [me], [alex2], points: (2, 11))
        ]
        let h2h = HeadToHead.compute(me: me.id, opponent: alex1.id, results: results)
        XCTAssertEqual(h2h.wins, 1)
        XCTAssertEqual(h2h.losses, 0)
        XCTAssertEqual(OpponentSummary.list(for: me.id, results: results).count, 2)
    }

    func testPartnerRecords() {
        let results = [
            result(1, [me, priya], [sam, jay], points: (11, 4)),
            result(2, [me, priya], [sam, jay], points: (11, 7)),
            result(3, [me, jay], [sam, priya], points: (5, 11)),
            result(4, [sam, jay], [me, priya], points: (11, 9))
        ]
        let partners = PartnerRecord.all(for: me.id, results: results)
        XCTAssertEqual(partners.first?.partner.id, priya.id)
        XCTAssertEqual(partners.first?.wins, 2)
        XCTAssertEqual(partners.first?.played, 3)
        XCTAssertEqual(partners.last?.partner.id, jay.id)
        XCTAssertEqual(partners.last?.winRate, 0)
    }

    func testOpponentWatchlistIsNewestFirstWithForm() {
        let results = [
            result(1, [me], [sam], points: (11, 5)),
            result(2, [me], [priya], points: (4, 11)),
            result(3, [me], [sam], points: (7, 11))
        ]
        let list = OpponentSummary.list(for: me.id, results: results)
        XCTAssertEqual(list.map(\.opponent.id), [sam.id, priya.id])
        XCTAssertEqual(list.first?.recentForm, [true, false])
        XCTAssertEqual(list.first?.trend, -1)
    }

    func testFormLineSmoothsPointShare() {
        let results = [
            result(1, [me], [sam], points: (11, 11)),    // 50%
            result(2, [me], [sam], points: (15, 5)),     // 75%
            result(3, [sam], [me], points: (11, 0))      // 0%
        ]
        let line = FormLine.compute(for: me.id, results: results)
        XCTAssertEqual(line.points.count, 3)
        XCTAssertEqual(line.points[0].value, 50, accuracy: 0.001)
        XCTAssertEqual(line.points[1].value, 50 + 0.35 * 25, accuracy: 0.001)
        let third = (50 + 0.35 * 25) * 0.65
        XCTAssertEqual(line.points[2].value, third, accuracy: 0.001)
        XCTAssertEqual(line.latestChange ?? 0, third - (50 + 0.35 * 25), accuracy: 0.001)
        XCTAssertEqual(line.streak, -1)
    }

    func testFormLineFiltersBySport() {
        let results = [
            result(1, [me], [sam], points: (11, 5)),
            result(2, [me], [sam], points: (6, 4), sport: .padel)
        ]
        XCTAssertEqual(FormLine.compute(for: me.id, results: results, sport: .padel).points.count, 1)
    }

    func testResultFromScorerAndPerspective() {
        let s = scorer(sideOut(doubles: false), String(repeating: "B", count: 1) + String(repeating: "B", count: 11))
        let lineup = Lineup(teamA: [me], teamB: [sam])
        let r = MatchResult(id: UUID(), date: t0, lineup: lineup, scorer: s)
        XCTAssertEqual(r.winner, .b)
        let p = r.perspective(of: me.id)
        XCTAssertEqual(p?.didWin, false)
        XCTAssertEqual(p?.team, .a)
        let samView = r.perspective(of: sam.id)
        XCTAssertEqual(samView?.scoreLine, "11-0")
        XCTAssertNil(r.perspective(of: priya.id))
    }
}

final class HeartRateZoneTests: XCTestCase {

    func testTanakaMaxAndPercentOfMaxZones() {
        let zones = HeartRateZones(age: 40)
        XCTAssertEqual(zones.maxHeartRate, 180, accuracy: 0.001)
        XCTAssertEqual(zones.zone(for: 80), .rest)
        XCTAssertEqual(zones.zone(for: 95), .warmUp)
        XCTAssertEqual(zones.zone(for: 130), .aerobic)
        XCTAssertEqual(zones.zone(for: 150), .threshold)
        XCTAssertEqual(zones.zone(for: 165), .maximum)
        XCTAssertEqual(zones.rangeLabel(for: .threshold), "144–161")
        XCTAssertEqual(zones.rangeLabel(for: .maximum), "162+")
    }

    func testKarvonenWithRestingHeartRate() {
        let zones = HeartRateZones(maxHeartRate: 180, restingHeartRate: 60)
        XCTAssertEqual(zones.lowerBound(of: .aerobic), 144, accuracy: 0.001)
        XCTAssertEqual(zones.zone(for: 140), .easy)
    }

    func testImplausibleRestingHeartRateIsIgnored() {
        XCTAssertNil(HeartRateZones(maxHeartRate: 180, restingHeartRate: 175).restingHeartRate)
    }

    func testAccumulatorWeightsByTimeAndCapsGaps() {
        var acc = ZoneAccumulator(zones: HeartRateZones(age: 40))
        acc.add(bpm: 100, at: t0)
        acc.add(bpm: 150, at: t0.addingTimeInterval(5))
        acc.add(bpm: 170, at: t0.addingTimeInterval(10))
        acc.add(bpm: 120, at: t0.addingTimeInterval(100))   // 90 s gap counts as 15 s
        XCTAssertEqual(acc.seconds[HeartRateZones.Zone.warmUp.rawValue], 5, accuracy: 0.001)
        XCTAssertEqual(acc.seconds[HeartRateZones.Zone.threshold.rawValue], 5, accuracy: 0.001)
        XCTAssertEqual(acc.seconds[HeartRateZones.Zone.maximum.rawValue], 15, accuracy: 0.001)
        XCTAssertEqual(acc.totalSeconds, 25, accuracy: 0.001)
        XCTAssertEqual(acc.peakBPM, 170)
        XCTAssertEqual(acc.averageBPM, 152, accuracy: 0.001)
        XCTAssertEqual(acc.hardSeconds, 20, accuracy: 0.001)
        XCTAssertEqual(acc.currentZone, .easy)
    }
}
