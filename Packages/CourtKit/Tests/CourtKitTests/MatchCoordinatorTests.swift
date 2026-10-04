import XCTest
@testable import CourtKit

/// Acceptance scenarios from the Apple Watch plan, run against real files
/// and a simulated link that can drop, delay, duplicate and reorder.
final class MatchCoordinatorTests: XCTestCase {
    private var directory: URL!
    private let watchID = UUID()
    private let phoneID = UUID()

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("journal-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private var watchStore: FileMatchEventStore { FileMatchEventStore(root: directory.appendingPathComponent("watch")) }
    private var phoneStore: FileMatchEventStore { FileMatchEventStore(root: directory.appendingPathComponent("phone")) }

    private func setup(_ rules: MatchRules = rally(to: 11, doubles: false)) -> MatchSetup {
        MatchSetup(rules: rules, lineup: Lineup(teamA: [player("Me")], teamB: [player("Them")]), startedAt: t0, host: .watch)
    }

    /// Delivers messages both ways until nothing is left to say.
    private func exchange(_ messages: [JournalMessage], from sender: MatchCoordinator, to receiver: MatchCoordinator) async throws {
        var toReceiver = messages
        var toSender: [JournalMessage] = []
        for _ in 0..<20 {
            guard !toReceiver.isEmpty || !toSender.isEmpty else { return }
            var next: [JournalMessage] = []
            for message in toReceiver { next += try await receiver.receive(message) }
            toReceiver = []
            for message in toSender { toReceiver += try await sender.receive(message) }
            toSender = next
        }
    }

    func testEveryAcknowledgedTapSurvivesAKill() async throws {
        let watch = try MatchCoordinator(store: watchStore, deviceID: watchID)
        let match = try await watch.startMatch(setup: setup(), accountScopeID: nil, wearerTeam: .a, role: .watch)
        for team in [Team.a, .b, .a, .a] { try await watch.perform(.rallyWon(team), in: match.matchID) }
        try await watch.perform(.undo(target: UUID()), in: match.matchID)

        // The process dies; a new one loads from disk.
        let relaunched = try MatchCoordinator(store: watchStore, deviceID: watchID)
        let restored = try await XCTUnwrapAsync(await relaunched.journal(match.matchID))
        XCTAssertEqual(restored.rallies.map(\.winner), [.a, .b, .a])
        XCTAssertEqual(restored.committedSequence, 6)
        let active = await relaunched.activeOwnedMatch()
        XCTAssertEqual(active?.matchID, match.matchID, "the match resumes after a crash")
    }

    func testLostAcknowledgementsNeverDoubleCount() async throws {
        let watch = try MatchCoordinator(store: watchStore, deviceID: watchID)
        let phone = try MatchCoordinator(store: phoneStore, deviceID: phoneID)
        let match = try await watch.startMatch(setup: setup(), accountScopeID: nil, wearerTeam: .a, role: .watch)
        try await watch.perform(.rallyWon(.a), in: match.matchID)

        // Deliver ten times, dropping every receipt.
        for _ in 0..<10 {
            for message in await watch.outgoing() { _ = try await phone.receive(message) }
        }
        let mirror = try await XCTUnwrapAsync(await phone.journal(match.matchID))
        XCTAssertEqual(mirror.rallies.count, 1)
        let unsynced = await watch.unsyncedOwnedMatches()
        XCTAssertEqual(unsynced.count, 1, "still unconfirmed on the Watch, so it keeps retrying")

        // Now a receipt gets through.
        try await exchange(await watch.outgoing(), from: watch, to: phone)
        let pending = await watch.unsyncedOwnedMatches()
        XCTAssertTrue(pending.isEmpty)
        let outgoing = await watch.outgoing()
        XCTAssertTrue(outgoing.isEmpty, "nothing left to send")
    }

    func testFinishBeforeItsRalliesIsFetched() async throws {
        let watch = try MatchCoordinator(store: watchStore, deviceID: watchID)
        let phone = try MatchCoordinator(store: phoneStore, deviceID: phoneID)
        let match = try await watch.startMatch(setup: setup(rally(to: 3, doubles: false)), accountScopeID: nil,
                                               wearerTeam: .a, role: .watch)
        for _ in 0..<3 { try await watch.perform(.rallyWon(.a), in: match.matchID) }
        let finished = try await watch.perform(.finished(finalSequence: 0, winner: .a, checksum: ""), in: match.matchID)

        // Only the manifest and the finish arrive.
        let last = try XCTUnwrap(finished.operations.last)
        var replies = try await phone.receive(.manifest(finished.manifest))
        replies += try await phone.receive(.operations(matchID: match.matchID, [last]))
        let partial = try await XCTUnwrapAsync(await phone.journal(match.matchID))
        XCTAssertFalse(partial.isComplete)
        XCTAssertTrue(replies.contains(.resend(matchID: match.matchID, fromSequence: 1, needsManifest: false)))

        // The Watch answers the resend.
        try await exchange(replies, from: phone, to: watch)
        let complete = try await XCTUnwrapAsync(await phone.journal(match.matchID))
        XCTAssertTrue(complete.isComplete)
        XCTAssertEqual(complete.scorer.winner, .a)
    }

    func testThreeOfflineMatchesArriveExactlyOnceAfterRestart() async throws {
        var watch = try MatchCoordinator(store: watchStore, deviceID: watchID)
        var ids: [UUID] = []
        for n in 0..<3 {
            var s = setup(rally(to: 3, doubles: false))
            s.matchID = UUID()
            s.startedAt = t0.addingTimeInterval(Double(n) * 600)
            let match = try await watch.startMatch(setup: s, accountScopeID: nil, wearerTeam: .a, role: .watch, at: s.startedAt)
            for _ in 0..<3 { try await watch.perform(.rallyWon(n == 1 ? .b : .a), in: match.matchID) }
            try await watch.perform(.finished(finalSequence: 0, winner: .a, checksum: ""), in: match.matchID)
            try await watch.dismiss(match.matchID)
            ids.append(match.matchID)
        }
        // Restart before the phone ever hears about them.
        watch = try MatchCoordinator(store: watchStore, deviceID: watchID)
        let phone = try MatchCoordinator(store: phoneStore, deviceID: phoneID)
        let outgoing = await watch.outgoing()
        try await exchange(outgoing + outgoing, from: watch, to: phone)   // duplicated delivery too

        let mirrored = await phone.allJournals()
        XCTAssertEqual(Set(mirrored.map(\.matchID)), Set(ids))
        XCTAssertEqual(mirrored.count, 3)
        XCTAssertTrue(mirrored.allSatisfy(\.isComplete))
        XCTAssertEqual(mirrored.first { $0.matchID == ids[1] }?.scorer.winner, .b)
        let unsynced = await watch.unsyncedOwnedMatches()
        XCTAssertTrue(unsynced.isEmpty)
    }

    func testUndoDisconnectReconnectKeepsServeAndScore() async throws {
        let watch = try MatchCoordinator(store: watchStore, deviceID: watchID)
        let phone = try MatchCoordinator(store: phoneStore, deviceID: phoneID)
        let match = try await watch.startMatch(setup: setup(sideOut(to: 11, doubles: true)), accountScopeID: nil,
                                               wearerTeam: .a, role: .watch)
        for team in [Team.a, .b, .b] { try await watch.perform(.rallyWon(team), in: match.matchID) }
        try await exchange(await watch.outgoing(), from: watch, to: phone)
        // Offline: undo and keep playing.
        try await watch.perform(.undo(target: UUID()), in: match.matchID)
        try await watch.perform(.rallyWon(.a), in: match.matchID)
        // Back online.
        try await exchange(await watch.outgoing(), from: watch, to: phone)
        let owner = try await XCTUnwrapAsync(await watch.journal(match.matchID))
        let mirror = try await XCTUnwrapAsync(await phone.journal(match.matchID))
        XCTAssertEqual(mirror.scorer.display, owner.scorer.display, "same score and serve state")
        XCTAssertEqual(mirror.rallies, owner.rallies)
    }

    func testShuffledLossyDeliveryConverges() async throws {
        let watch = try MatchCoordinator(store: watchStore, deviceID: watchID)
        let phone = try MatchCoordinator(store: phoneStore, deviceID: phoneID)
        let match = try await watch.startMatch(setup: setup(), accountScopeID: nil, wearerTeam: .a, role: .watch)
        var rng = SeededGenerator(seed: 7)
        var inFlight: [JournalMessage] = []
        for i in 0..<30 {
            let action: MatchOperationPayload = i % 7 == 6 ? .undo(target: UUID()) : .rallyWon(i % 3 == 0 ? .b : .a)
            _ = try? await watch.perform(action, in: match.matchID)
            inFlight += await watch.outgoing()
            // Deliver a random half, out of order; drop the rest.
            inFlight.shuffle(using: &rng)
            let delivered = inFlight.prefix(inFlight.count / 2)
            inFlight.removeFirst(delivered.count)
            for message in delivered {
                for reply in try await phone.receive(message) where Bool.random(using: &rng) {
                    _ = try await watch.receive(reply)
                }
            }
        }
        // The link recovers.
        try await exchange(await watch.outgoing(), from: watch, to: phone)
        let owner = try await XCTUnwrapAsync(await watch.journal(match.matchID))
        let mirror = try await XCTUnwrapAsync(await phone.journal(match.matchID))
        XCTAssertEqual(mirror.operations, owner.operations)
        XCTAssertEqual(mirror.scorer, owner.scorer)
    }

    func testOperationsBeforeTheManifestWaitInTheInbox() async throws {
        let watch = try MatchCoordinator(store: watchStore, deviceID: watchID)
        let phone = try MatchCoordinator(store: phoneStore, deviceID: phoneID)
        let match = try await watch.startMatch(setup: setup(), accountScopeID: nil, wearerTeam: .a, role: .watch)
        let journal = try await watch.perform(.rallyWon(.b), in: match.matchID)
        let replies = try await phone.receive(.operations(matchID: match.matchID, journal.operations))
        XCTAssertEqual(replies, [.resend(matchID: match.matchID, fromSequence: 1, needsManifest: true)])
        // The phone restarts; the inbox survives.
        let relaunched = try MatchCoordinator(store: phoneStore, deviceID: phoneID)
        _ = try await relaunched.receive(.manifest(journal.manifest))
        let mirror = try await XCTUnwrapAsync(await relaunched.journal(match.matchID))
        XCTAssertEqual(mirror.rallies.map(\.winner), [.b])
    }

    func testLostGrantAcceptanceNeverMakesASecondOwner() async throws {
        let watch = try MatchCoordinator(store: watchStore, deviceID: watchID)
        let draft = MatchDraft(setup: setup(), accountScopeID: UUID(), wearerTeam: .b)
        let ready = try await watch.receive(.draft(draft))
        XCTAssertEqual(ready, [.draftReady(matchID: draft.matchID, draftVersion: 1)])

        let grant = ScoringGrant(draft: draft, authorityEpoch: 1, issuedAt: t0)
        let first = try await watch.receive(.grant(grant))
        XCTAssertEqual(first.first, .grantAccepted(grantID: grant.grantID, matchID: draft.matchID, authorityEpoch: 1))
        // The acceptance is lost; the phone sends the grant again, even after a restart.
        let relaunched = try MatchCoordinator(store: watchStore, deviceID: watchID)
        let second = try await relaunched.receive(.grant(grant))
        XCTAssertEqual(second, [.grantAccepted(grantID: grant.grantID, matchID: draft.matchID, authorityEpoch: 1)])
        let all = await relaunched.allJournals()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.manifest.wearerTeam, .b)
        XCTAssertEqual(all.first?.manifest.setup.host, .watch)
    }

    func testGrantCancelOnlyBeforeTheFirstRally() async throws {
        let watch = try MatchCoordinator(store: watchStore, deviceID: watchID)
        let grant = ScoringGrant(draft: MatchDraft(setup: setup(), accountScopeID: nil, wearerTeam: .a))
        _ = try await watch.receive(.grant(grant))
        try await watch.perform(.rallyWon(.a), in: grant.matchID)
        let refused = try await watch.receive(.grantCancel(grantID: grant.grantID, matchID: grant.matchID))
        XCTAssertEqual(refused, [.grantCancelled(grantID: grant.grantID, matchID: grant.matchID, accepted: false)],
                       "once a rally exists, the Watch keeps scoring rather than splitting history")

        var other = setup()
        other.matchID = UUID()
        let second = ScoringGrant(draft: MatchDraft(setup: other, accountScopeID: nil, wearerTeam: .a))
        let busy = try await watch.receive(.grant(second))
        XCTAssertEqual(busy, [.grantCancelled(grantID: second.grantID, matchID: other.matchID, accepted: false)],
                       "one match on the wrist at a time")
    }

    func testFailedSaveChangesNothing() async throws {
        let store = InMemoryMatchEventStore()
        let watch = try MatchCoordinator(store: store, deviceID: watchID)
        let match = try await watch.startMatch(setup: setup(), accountScopeID: nil, wearerTeam: .a, role: .watch)
        store.failWrites = true
        do {
            try await watch.perform(.rallyWon(.a), in: match.matchID)
            XCTFail("a failed save must be reported")
        } catch {
            XCTAssertEqual(error as? MatchStoreError, .writeFailed("simulated"))
        }
        let journal = try await XCTUnwrapAsync(await watch.journal(match.matchID))
        XCTAssertTrue(journal.rallies.isEmpty, "nothing shown that wasn't saved")
    }

    func testRetentionKeepsUnconfirmedMatches() async throws {
        let watch = try MatchCoordinator(store: watchStore, deviceID: watchID)
        let phone = try MatchCoordinator(store: phoneStore, deviceID: phoneID)
        var ids: [UUID] = []
        for n in 0..<2 {
            var s = setup(rally(to: 1, doubles: false))
            s.matchID = UUID()
            _ = try await watch.startMatch(setup: s, accountScopeID: nil, wearerTeam: .a, role: .watch, at: t0)
            try await watch.perform(.rallyWon(.a), in: s.matchID)
            try await watch.perform(.finished(finalSequence: 0, winner: .a, checksum: ""), in: s.matchID)
            ids.append(s.matchID)
            if n == 0 { try await exchange(await watch.outgoing(), from: watch, to: phone) }
        }
        try await watch.compact(olderThan: 60, now: t0.addingTimeInterval(3_600))
        let left = await watch.allJournals().map(\.matchID)
        XCTAssertEqual(left, [ids[1]], "only the confirmed one is compacted")
    }
}

/// `XCTUnwrap` for values read across an actor boundary.
func XCTUnwrapAsync<T>(_ value: @autoclosure () async throws -> T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    let resolved = try await value()
    return try XCTUnwrap(resolved, file: file, line: line)
}
