import XCTest
@testable import CourtKit

/// Regression tests for the release audit: finishing on the client must
/// keep every tap, and late or shuffled messages must never roll the
/// score back.
final class MatchReplicaOrderingTests: XCTestCase {

    private func makeSetup(_ rules: MatchRules = rally(to: 11, doubles: false)) -> MatchSetup {
        MatchSetup(rules: rules, lineup: Lineup(teamA: [player("Sam")], teamB: [player("Priya")]),
                   startedAt: t0, host: .phone)
    }

    private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

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

    /// Audit reproduction 1: the client scores a whole game while the host
    /// can't hear it, then finishes. Nothing may be lost.
    func testClientFinishKeepsUnacknowledgedRallies() {
        let setup = makeSetup()
        var phone = MatchReplica(setup: setup, role: .host, epoch: 100)
        var watch = MatchReplica(setup: setup, role: .client)
        var queued: [SyncMessage] = []
        for i in 0..<11 { queued += watch.recordRally(wonBy: .a, at: at(Double(i))).outgoing }
        XCTAssertTrue(watch.isFinished)

        let end = watch.end(.completed)
        XCTAssertEqual(watch.scorer.rallies.count, 11, "finishing keeps the score on screen")
        XCTAssertTrue(watch.isFinished)
        XCTAssertEqual(watch.ended, .completed)
        XCTAssertTrue(watch.isAwaitingEndAck)

        // The end request reaches the host before (or without) the taps.
        let replies = deliver(end.outgoing, to: &phone)
        XCTAssertEqual(phone.log.count, 11)
        XCTAssertTrue(phone.isFinished)
        XCTAssertEqual(phone.ended, .completed)

        // The queued taps turn up late: duplicates, nothing changes.
        let late = deliver(queued, to: &phone)
        XCTAssertEqual(phone.log.count, 11)
        deliver(replies + late, to: &watch)

        XCTAssertFalse(watch.isAwaitingEndAck)
        XCTAssertTrue(watch.pending.isEmpty)
        XCTAssertEqual(watch.log, phone.log)
        XCTAssertEqual(watch.display, phone.display)
        XCTAssertTrue(watch.isFinished)
    }

    /// Taps that arrive before the end request still count once.
    func testIntentsBeforeEndRequestCountOnce() {
        let setup = makeSetup()
        var phone = MatchReplica(setup: setup, role: .host, epoch: 100)
        var watch = MatchReplica(setup: setup, role: .client)
        var queued: [SyncMessage] = []
        for i in 0..<11 { queued += watch.recordRally(wonBy: .a, at: at(Double(i))).outgoing }
        let end = watch.end(.completed)
        let first = deliver(queued, to: &phone)
        let second = deliver(end.outgoing, to: &phone)
        XCTAssertEqual(phone.log.count, 11)
        deliver(first + second, to: &watch)
        XCTAssertEqual(watch.display, phone.display)
        XCTAssertTrue(watch.isFinished)
    }

    /// If the host ended first, its log wins and the client follows it.
    func testHostEndWinsOverLateClientEnd() {
        let setup = makeSetup()
        var phone = MatchReplica(setup: setup, role: .host, epoch: 100)
        var watch = MatchReplica(setup: setup, role: .client)
        deliver(phone.recordRally(wonBy: .b, at: at(1)).outgoing, to: &watch)
        let hostEnd = phone.end(.parked)
        _ = watch.recordRally(wonBy: .a, at: at(2))
        let clientEnd = watch.end(.parked)
        let replies = deliver(clientEnd.outgoing, to: &phone)
        deliver(hostEnd.outgoing + replies, to: &watch)
        XCTAssertEqual(watch.log, phone.log)
        XCTAssertEqual(watch.display, phone.display)
        XCTAssertFalse(watch.isAwaitingEndAck)
    }

    /// Audit reproduction 2: a current event, then an older snapshot.
    func testStaleSnapshotCannotRollBack() {
        let setup = makeSetup()
        var phone = MatchReplica(setup: setup, role: .host, epoch: 100)
        var watch = MatchReplica(setup: setup, role: .client)
        let old = phone.snapshot
        deliver(phone.recordRally(wonBy: .a, at: at(1)).outgoing, to: &watch)
        XCTAssertEqual(watch.log.count, 1)
        deliver([.log(old)], to: &watch)
        XCTAssertEqual(watch.log.count, 1, "an older snapshot is ignored")
        XCTAssertEqual(watch.display, phone.display)
    }

    /// Undo makes the rally count go down, so it can't order messages;
    /// revisions can. Every shuffle, with duplicates, converges.
    func testShuffledDuplicatedMessagesConverge() {
        let setup = makeSetup()
        for seed in 1...25 {
            var phone = MatchReplica(setup: setup, role: .host, epoch: 100)
            var sent: [SyncMessage] = [phone.startMessage]
            let script: [Team?] = [.a, .b, nil, .a, .a, nil, nil, .b, .a]
            for (i, step) in script.enumerated() {
                let outcome = step.map { phone.recordRally(wonBy: $0, at: at(Double(i))) } ?? phone.undo()
                sent += outcome.outgoing + [.log(phone.snapshot)]
            }
            var rng = SeededGenerator(seed: UInt64(seed))
            var shuffled = (sent + sent.prefix(seed % sent.count)).shuffled(using: &rng)
            // Snapshots are kept as the latest application context, so the
            // newest one always arrives at some point.
            shuffled.append(.log(phone.snapshot))

            var watch = MatchReplica(setup: setup, role: .client)
            var requests = deliver(shuffled, to: &watch)
            for _ in 0..<3 where !requests.isEmpty {
                requests = deliver(deliver(requests, to: &phone), to: &watch)
            }
            XCTAssertEqual(watch.log, phone.log, "seed \(seed)")
            XCTAssertEqual(watch.display, phone.display, "seed \(seed)")
        }
    }

    /// A resumed match starts a new host session: its snapshot is accepted
    /// even though the counter restarted.
    func testResumedHostSessionIsAccepted() {
        let setup = makeSetup()
        var phone = MatchReplica(setup: setup, role: .host, epoch: 100)
        var watch = MatchReplica(setup: setup, role: .client)
        for i in 0..<3 { deliver(phone.recordRally(wonBy: .a, at: at(Double(i))).outgoing, to: &watch) }
        var resumed = MatchReplica(setup: setup, role: .host, log: phone.log, epoch: 200)
        deliver([resumed.startMessage], to: &watch)
        deliver(resumed.recordRally(wonBy: .b, at: at(9)).outgoing, to: &watch)
        XCTAssertEqual(watch.log, resumed.log)
        // And the old session's leftovers are ignored.
        deliver(phone.undo().outgoing + [.log(phone.snapshot)], to: &watch)
        XCTAssertEqual(watch.log, resumed.log)
    }

    /// A client that finished can be saved and restored, and still knows
    /// what to resend.
    func testAwaitingEndSurvivesRelaunch() throws {
        let setup = makeSetup()
        var watch = MatchReplica(setup: setup, role: .client)
        for i in 0..<11 { _ = watch.recordRally(wonBy: .a, at: at(Double(i))) }
        _ = watch.end(.completed)
        let data = try JSONEncoder().encode(watch)
        let restored = try JSONDecoder().decode(MatchReplica.self, from: data)
        XCTAssertEqual(restored, watch)
        XCTAssertEqual(restored.pendingEndRequest, watch.pendingEndRequest)
        XCTAssertNotNil(restored.pendingEndRequest)
        XCTAssertTrue(restored.isFinished)
    }

    func testRevisionsRoundTripOnTheWire() {
        var phone = MatchReplica(setup: makeSetup(), role: .host, epoch: 100)
        let event = phone.recordRally(wonBy: .a, at: at(1)).outgoing[0]
        XCTAssertEqual(SyncMessage(wcPayload: event.wcPayload), event)
        let snapshot = SyncMessage.log(phone.snapshot)
        XCTAssertEqual(SyncMessage(wcPayload: snapshot.wcPayload), snapshot)
        XCTAssertEqual(phone.snapshot.revision, Revision(epoch: 100, counter: 1))
    }
}

/// Deterministic shuffles for the convergence test.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
