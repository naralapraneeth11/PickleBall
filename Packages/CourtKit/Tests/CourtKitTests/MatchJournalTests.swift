import XCTest
@testable import CourtKit

final class MatchJournalTests: XCTestCase {
    private let watchID = UUID()

    private func manifest(_ rules: MatchRules = rally(to: 11, doubles: false), epoch: Int64 = 1) -> MatchManifest {
        let setup = MatchSetup(rules: rules, lineup: Lineup(teamA: [player("Me")], teamB: [player("Them")]),
                               startedAt: t0, host: .watch)
        return MatchManifest(setup: setup, accountScopeID: nil, ownerDeviceID: watchID, ownerRole: .watch,
                             authorityEpoch: epoch, wearerTeam: .a, createdAt: t0)
    }

    private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    func testOwnerAppendsWithMonotonicSequences() throws {
        var journal = MatchJournal.owned(manifest(), startedAt: t0)
        try journal.append(.rallyWon(.a), at: at(1))
        try journal.append(.rallyWon(.a), at: at(2))
        try journal.append(.undo(target: UUID()), at: at(3))
        try journal.append(.rallyWon(.b), at: at(4))
        XCTAssertEqual(journal.operations.map(\.sequence), [1, 2, 3, 4, 5], "undo is an operation; sequences never fall")
        XCTAssertEqual(journal.rallies.map(\.winner), [.a, .b])
        XCTAssertEqual(journal.scorer, MatchScorer(rules: journal.manifest.setup.rules, rallies: journal.rallies))
    }

    func testUndoTargetsTheLastRally() throws {
        var journal = MatchJournal.owned(manifest(), startedAt: t0)
        let first = try journal.append(.rallyWon(.a), at: at(1))
        let second = try journal.append(.rallyWon(.b), at: at(2))
        let undo = try journal.append(.undo(target: first.eventID), at: at(3))
        XCTAssertEqual(undo.payload, .undo(target: second.eventID), "undo always removes the latest rally")
        XCTAssertThrowsError(try {
            var empty = MatchJournal.owned(manifest(), startedAt: t0)
            try empty.append(.undo(target: UUID()), at: at(1))
        }())
    }

    func testFinishNeedsAWinnerAndClosesTheMatch() throws {
        var journal = MatchJournal.owned(manifest(rally(to: 3, doubles: false)), startedAt: t0)
        XCTAssertThrowsError(try journal.append(.finished(finalSequence: 0, winner: .a, checksum: ""), at: at(1)))
        for i in 1...3 { try journal.append(.rallyWon(.a), at: at(Double(i))) }
        XCTAssertThrowsError(try journal.append(.rallyWon(.a), at: at(4)), "no rallies after a winner")
        let finish = try journal.append(.finished(finalSequence: 0, winner: .b, checksum: ""), at: at(5))
        guard case .finished(let final, let winner, let checksum) = finish.payload else { return XCTFail() }
        XCTAssertEqual(final, finish.sequence)
        XCTAssertEqual(winner, .a, "the winner comes from the engine, not the caller")
        XCTAssertEqual(checksum, MatchJournal.checksum(journal.rallies))
        XCTAssertEqual(journal.status, .finished)
        XCTAssertThrowsError(try journal.append(.undo(target: UUID()), at: at(6))) { error in
            XCTAssertEqual(error as? JournalError, .matchClosed)
        }
    }

    func testPauseBlocksRallies() throws {
        var journal = MatchJournal.owned(manifest(), startedAt: t0)
        try journal.append(.paused, at: at(1))
        XCTAssertThrowsError(try journal.append(.rallyWon(.a), at: at(2)))
        try journal.append(.resumed, at: at(3))
        try journal.append(.rallyWon(.a), at: at(4))
        XCTAssertEqual(journal.status, .live)
    }

    func testMirrorCannotAppend() {
        var mirror = MatchJournal.mirror(manifest())
        XCTAssertThrowsError(try mirror.append(.rallyWon(.a), at: t0)) { error in
            XCTAssertEqual(error as? JournalError, .notOwner, "the non-owner can never score on its own")
        }
    }

    func testMirrorCommitsInOrderAndNeverPastAGap() throws {
        var owner = MatchJournal.owned(manifest(), startedAt: t0)
        for i in 1...4 { try owner.append(.rallyWon(i % 2 == 0 ? .b : .a), at: at(Double(i))) }
        var mirror = MatchJournal.mirror(owner.manifest)
        let ops = owner.operations

        var result = try mirror.ingest([ops[0], ops[2], ops[4]])
        XCTAssertEqual(mirror.committedSequence, 1)
        XCTAssertEqual(result.missingFrom, 2)
        result = try mirror.ingest([ops[1]])
        XCTAssertEqual(mirror.committedSequence, 3)
        result = try mirror.ingest([ops[3]])
        XCTAssertEqual(mirror.committedSequence, 5)
        XCTAssertNil(result.missingFrom)
        XCTAssertEqual(mirror.scorer, owner.scorer)
    }

    func testDuplicatesAreHarmlessAndConflictsNeverReplace() throws {
        var owner = MatchJournal.owned(manifest(), startedAt: t0)
        try owner.append(.rallyWon(.a), at: at(1))
        var mirror = MatchJournal.mirror(owner.manifest)
        try mirror.ingest(owner.operations)
        for _ in 0..<10 {
            let result = try mirror.ingest(owner.operations)
            XCTAssertEqual(result.newlyCommitted, 0)
        }
        XCTAssertEqual(mirror.rallies.count, 1, "replayed ten times, counted once")

        let forged = MatchOperation(accountScopeID: nil, matchID: owner.matchID, ownerDeviceID: watchID,
                                    authorityEpoch: 1, sequence: 2, occurredAt: at(1), payload: .rallyWon(.b))
        let result = try mirror.ingest([forged])
        XCTAssertEqual(result.conflicts, 1)
        XCTAssertEqual(mirror.rallies.map(\.winner), [.a])
        XCTAssertThrowsError(try mirror.ingest([MatchOperation(accountScopeID: nil, matchID: owner.matchID, ownerDeviceID: UUID(),
                                                               authorityEpoch: 1, sequence: 3, occurredAt: at(2), payload: .rallyWon(.b))]))
    }

    func testOldEpochOperationsAreIgnored() throws {
        let current = manifest(epoch: 2)
        var mirror = MatchJournal.mirror(current)
        let stale = MatchOperation(accountScopeID: nil, matchID: current.matchID, ownerDeviceID: watchID,
                                   authorityEpoch: 1, sequence: 1, occurredAt: t0, payload: .started)
        let result = try mirror.ingest([stale])
        XCTAssertEqual(result.conflicts, 1)
        XCTAssertEqual(mirror.committedSequence, 0)
    }

    func testFinishBeforeMissingRalliesIsNotComplete() throws {
        var owner = MatchJournal.owned(manifest(rally(to: 3, doubles: false)), startedAt: t0)
        for i in 1...3 { try owner.append(.rallyWon(.a), at: at(Double(i))) }
        try owner.append(.finished(finalSequence: 0, winner: .a, checksum: ""), at: at(4))
        var mirror = MatchJournal.mirror(owner.manifest)
        try mirror.ingest([owner.operations[0], owner.operations[4]])
        XCTAssertFalse(mirror.isComplete)
        XCTAssertEqual(mirror.expectedFinalSequence, 5)
        try mirror.ingest(Array(owner.operations[1...3]))
        XCTAssertTrue(mirror.isComplete)
        XCTAssertEqual(MatchJournal.checksum(mirror.rallies), MatchJournal.checksum(owner.rallies))
    }

    func testReceiptsOnlyMoveForward() throws {
        var owner = MatchJournal.owned(manifest(), startedAt: t0)
        try owner.append(.rallyWon(.a), at: at(1))
        owner.acknowledge(JournalReceipt(matchID: owner.matchID, authorityEpoch: 1, committedSequence: 2, isComplete: false))
        owner.acknowledge(JournalReceipt(matchID: owner.matchID, authorityEpoch: 1, committedSequence: 1, isComplete: false))
        XCTAssertEqual(owner.acknowledgedSequence, 2)
        owner.acknowledge(JournalReceipt(matchID: owner.matchID, authorityEpoch: 1, committedSequence: 99, isComplete: false))
        XCTAssertEqual(owner.acknowledgedSequence, 2, "never beyond what exists")
        XCTAssertTrue(owner.unacknowledged.isEmpty)
    }

    func testWireRoundTripAndVersioning() throws {
        var owner = MatchJournal.owned(manifest(), startedAt: t0)
        try owner.append(.rallyWon(.a), at: at(1))
        try owner.append(.paused, at: at(2))
        let messages: [JournalMessage] = [
            .manifest(owner.manifest),
            .operations(matchID: owner.matchID, owner.operations),
            .receipt(JournalReceipt(matchID: owner.matchID, authorityEpoch: 1, committedSequence: 3, isComplete: false)),
            .resend(matchID: owner.matchID, fromSequence: 2, needsManifest: true),
            .grant(ScoringGrant(draft: MatchDraft(setup: owner.manifest.setup, accountScopeID: UUID(), wearerTeam: .b), issuedAt: t0)),
            .grantCancelled(grantID: UUID(), matchID: owner.matchID, accepted: false)
        ]
        for message in messages {
            XCTAssertEqual(JournalMessage(wcPayload: message.wcPayload), message)
        }
        let batch = JournalMessage.messages(in: JournalMessage.batchPayload(messages))
        XCTAssertEqual(batch, messages)
        XCTAssertNil(JournalMessage(wcPayload: [JournalMessage.payloadKey: Data("garbage".utf8)]), "malformed data is dropped")
        let future = Data(#"{"version":99,"message":{"type":"whatever"}}"#.utf8)
        XCTAssertEqual(JournalMessage.decode(future), .unsupportedVersion(99))
        XCTAssertNil(SyncMessage(wcPayload: messages[0].wcPayload), "schema 1 decoders ignore schema 2")
        let journalData = try JSONEncoder().encode(owner)
        XCTAssertEqual(try JSONDecoder().decode(MatchJournal.self, from: journalData), owner)
    }
}
