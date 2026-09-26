import XCTest
@testable import CourtKit

final class MatchReplicaTests: XCTestCase {

    private var setup: MatchSetup!
    private var phone: MatchReplica!
    private var watch: MatchReplica!

    override func setUp() {
        super.setUp()
        setup = MatchSetup(
            rules: sideOut(doubles: false),
            lineup: Lineup(teamA: [player("Sam")], teamB: [player("Priya")]),
            startedAt: t0,
            host: .phone
        )
        phone = MatchReplica(setup: setup, role: .host)
        watch = MatchReplica(setup: setup, role: .client)
    }

    /// Sends messages through the real wire encoding, like WatchConnectivity would.
    @discardableResult
    private func deliver(_ messages: [SyncMessage], to replica: inout MatchReplica) -> [SyncMessage] {
        var replies: [SyncMessage] = []
        for message in messages {
            let decoded = SyncMessage(wcPayload: message.wcPayload)
            XCTAssertEqual(decoded, message, "wire round trip")
            replies += replica.receive(decoded ?? message).outgoing
        }
        return replies
    }

    private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    func testClientTapIsOptimisticThenAcknowledged() {
        let tap = watch.recordRally(wonBy: .a, at: at(5))
        XCTAssertEqual(watch.display.points.a, "1", "shows immediately")
        XCTAssertEqual(watch.pending.count, 1)

        let hostReplies = deliver(tap.outgoing, to: &phone)
        XCTAssertEqual(phone.log.count, 1)
        deliver(hostReplies, to: &watch)
        XCTAssertTrue(watch.pending.isEmpty)
        XCTAssertEqual(watch.log, phone.log)
        XCTAssertEqual(watch.display, phone.display)
    }

    func testHostTapReachesClient() {
        let tap = phone.recordRally(wonBy: .b, at: at(3))
        XCTAssertTrue(tap.events.contains(.sideOut(to: .b)))
        let outcome = watch.receive(tap.outgoing[0])
        XCTAssertTrue(outcome.changed)
        XCTAssertTrue(outcome.events.contains(.sideOut(to: .b)), "client gets events for remote rallies")
        XCTAssertEqual(watch.display, phone.display)
    }

    /// Both devices tap the same rally at once: it must count once.
    func testSimultaneousTapsNeverDoubleCount() {
        let hostTap = phone.recordRally(wonBy: .a, at: at(10))
        let clientTap = watch.recordRally(wonBy: .a, at: at(10.2))

        let hostReplies = deliver(clientTap.outgoing, to: &phone)
        XCTAssertEqual(phone.log.count, 1, "stale intent rejected")
        deliver(hostTap.outgoing, to: &watch)
        deliver(hostReplies, to: &watch)

        XCTAssertEqual(watch.log.count, 1)
        XCTAssertTrue(watch.pending.isEmpty)
        XCTAssertEqual(watch.display, phone.display)
    }

    func testQueuedOfflineTapsApplyInOrder() {
        var queued: [SyncMessage] = []
        for (i, team) in [Team.a, .a, .b, .b, .b].enumerated() {
            queued += watch.recordRally(wonBy: team, at: at(Double(i))).outgoing
        }
        XCTAssertEqual(watch.pending.count, 5)
        let replies = deliver(queued, to: &phone)
        XCTAssertEqual(phone.log.count, 5)
        deliver(replies, to: &watch)
        XCTAssertTrue(watch.pending.isEmpty)
        XCTAssertEqual(watch.display, phone.display)
    }

    func testDuplicateIntentDeliveryIsIgnored() {
        let tap = watch.recordRally(wonBy: .a, at: at(1))
        let first = deliver(tap.outgoing, to: &phone)
        let second = deliver(tap.outgoing, to: &phone)
        XCTAssertEqual(first.count, 1)
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(phone.log.count, 1)
    }

    func testGapTriggersLogRequestAndCatchUp() {
        let e1 = phone.recordRally(wonBy: .a, at: at(1)).outgoing
        _ = phone.recordRally(wonBy: .a, at: at(2))
        let e3 = phone.recordRally(wonBy: .a, at: at(3)).outgoing

        deliver(e1, to: &watch)
        let request = deliver(e3, to: &watch)
        XCTAssertEqual(request, [.logRequest(matchID: setup.matchID)])
        let log = deliver(request, to: &phone)
        deliver(log, to: &watch)
        XCTAssertEqual(watch.log, phone.log)
        XCTAssertEqual(watch.display, phone.display)
    }

    func testClientUndo() {
        for i in 0..<3 {
            deliver(phone.recordRally(wonBy: .a, at: at(Double(i))).outgoing, to: &watch)
        }
        let undo = watch.undo()
        XCTAssertEqual(watch.display.points.a, "2")
        let replies = deliver(undo.outgoing, to: &phone)
        XCTAssertEqual(phone.log.count, 2)
        deliver(replies, to: &watch)
        XCTAssertTrue(watch.pending.isEmpty)
        XCTAssertEqual(watch.display, phone.display)
    }

    func testHostUndoReachesClient() {
        let e1 = phone.recordRally(wonBy: .a, at: at(1)).outgoing
        deliver(e1, to: &watch)
        deliver(phone.undo().outgoing, to: &watch)
        XCTAssertTrue(watch.log.isEmpty)
        XCTAssertEqual(watch.display.call, "0-0")
    }

    func testLateClientBootstrapsFromStartSnapshot() {
        for i in 0..<4 { _ = phone.recordRally(wonBy: i % 2 == 0 ? .a : .b, at: at(Double(i))) }
        var late = MatchReplica(setup: setup, role: .client)
        deliver([.log(phone.snapshot)], to: &late)
        XCTAssertEqual(late.display, phone.display)
    }

    func testMatchEndPropagates() {
        let end = phone.end(.completed)
        deliver(end.outgoing, to: &watch)
        XCTAssertEqual(watch.ended, .completed)
        XCTAssertEqual(watch.recordRally(wonBy: .a), MatchReplica.Outcome())
    }

    func testMessagesForOtherMatchesAreIgnored() {
        let other = MatchSetup(rules: setup.rules, lineup: setup.lineup, startedAt: t0, host: .phone)
        var otherHost = MatchReplica(setup: other, role: .host)
        let foreign = otherHost.recordRally(wonBy: .a).outgoing
        XCTAssertFalse(watch.receive(foreign[0]).changed)
    }

    func testLogSnapshotCompactEncodingRoundTrips() throws {
        for i in 0..<30 { _ = phone.recordRally(wonBy: i % 3 == 0 ? .b : .a, at: at(Double(i) * 7)) }
        let data = try JSONEncoder().encode(phone.snapshot)
        let decoded = try JSONDecoder().decode(LogSnapshot.self, from: data)
        XCTAssertEqual(decoded, phone.snapshot)
        XCTAssertLessThan(data.count, 2_000)
    }

    func testSportModeMessageRoundTrip() {
        let message = SyncMessage.sportMode(.padel)
        XCTAssertEqual(SyncMessage(wcPayload: message.wcPayload), message)
        XCTAssertNil(SyncMessage(wcPayload: ["type": "phoneMatchState"]), "legacy payloads are not CourtKit messages")
    }
}
