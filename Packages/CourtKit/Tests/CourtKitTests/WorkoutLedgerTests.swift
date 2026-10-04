import XCTest
@testable import CourtKit

final class WorkoutLedgerTests: XCTestCase {
    private let report = WorkoutReport(duration: 1_800, averageHeartRate: 128, peakHeartRate: 171, calories: 310,
                                       secondsInZone: [60, 400, 800, 400, 140], maxHeartRate: 185, shots: nil)

    func testOneWorkoutPerMatch() {
        var ledger = WorkoutLedger()
        let match = UUID()
        XCTAssertEqual(ledger.decision(forBeginning: match), .start)
        XCTAssertTrue(ledger.begin(matchID: match, sport: .pickleball, isIndoor: true, at: t0))
        XCTAssertEqual(ledger.decision(forBeginning: match), .alreadyActive, "a relaunch mid-match recovers, never starts again")
        XCTAssertFalse(ledger.begin(matchID: match, sport: .pickleball, isIndoor: true, at: t0))

        ledger.markFinishing(match, report: report, at: t0.addingTimeInterval(1_800))
        ledger.markSaved(match, workoutID: UUID())
        XCTAssertEqual(ledger.decision(forBeginning: match), .alreadyRecorded, "a saved match is never recorded twice")
        XCTAssertFalse(ledger.begin(matchID: match, sport: .pickleball, isIndoor: true, at: t0))
    }

    func testOnlyOneActiveWorkout() {
        var ledger = WorkoutLedger()
        let first = UUID(), second = UUID()
        ledger.begin(matchID: first, sport: .pickleball, isIndoor: false, at: t0)
        XCTAssertEqual(ledger.decision(forBeginning: second), .otherActive(first))
        XCTAssertFalse(ledger.begin(matchID: second, sport: .padel, isIndoor: false, at: t0))
        ledger.markFinishing(first, report: report, at: t0)
        XCTAssertTrue(ledger.begin(matchID: second, sport: .padel, isIndoor: false, at: t0))
        XCTAssertEqual(ledger.active?.matchID, second)
    }

    func testSummarySurvivesARelaunch() throws {
        var ledger = WorkoutLedger()
        let match = UUID()
        ledger.begin(matchID: match, sport: .pickleball, isIndoor: false, at: t0)
        ledger.markFinishing(match, report: report, at: t0.addingTimeInterval(1_800))

        // The app is killed while HealthKit is still saving.
        let restored = try JSONDecoder().decode(WorkoutLedger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(restored, ledger)
        XCTAssertEqual(restored.reportsToSend.map(\.matchID), [match])
        XCTAssertEqual(restored.entry(match)?.report, report)
        XCTAssertEqual(restored.recoveryAction(journalStatus: .finished), .finalize(matchID: match))

        var sent = restored
        sent.markReportQueued(match)
        XCTAssertTrue(sent.reportsToSend.isEmpty, "handed to WatchConnectivity once")
    }

    func testFailedSavesAreRetriedThenKept() {
        var ledger = WorkoutLedger()
        let match = UUID()
        ledger.begin(matchID: match, sport: .pickleball, isIndoor: false, at: t0)
        ledger.markFinishing(match, report: report, at: t0)
        XCTAssertTrue(ledger.markAttemptFailed(match))
        XCTAssertTrue(ledger.markAttemptFailed(match))
        XCTAssertFalse(ledger.markAttemptFailed(match))
        XCTAssertEqual(ledger.entry(match)?.state, .failed)
        XCTAssertEqual(ledger.entry(match)?.report, report, "a failed save keeps the summary for the phone")
        XCTAssertEqual(ledger.decision(forBeginning: match), .alreadyRecorded)
    }

    func testRecoveryFollowsTheJournal() {
        var ledger = WorkoutLedger()
        let match = UUID()
        XCTAssertEqual(ledger.recoveryAction(journalStatus: nil), .finalize(matchID: nil), "an unknown session is saved, not dropped")
        ledger.begin(matchID: match, sport: .pickleball, isIndoor: false, at: t0)
        XCTAssertEqual(ledger.recoveryAction(journalStatus: .live), .resume(matchID: match, paused: false))
        XCTAssertEqual(ledger.recoveryAction(journalStatus: .paused), .resume(matchID: match, paused: true))
        XCTAssertEqual(ledger.recoveryAction(journalStatus: .finished), .finalize(matchID: match))
        XCTAssertEqual(ledger.recoveryAction(journalStatus: .abandoned), .finalize(matchID: match))
        XCTAssertEqual(ledger.recoveryAction(journalStatus: nil), .finalize(matchID: match))
    }

    func testLostSessionCanStartAgain() {
        var ledger = WorkoutLedger()
        let match = UUID()
        ledger.begin(matchID: match, sport: .pickleball, isIndoor: false, at: t0)
        ledger.discardLostSession(match)
        XCTAssertEqual(ledger.decision(forBeginning: match), .start)
        ledger.begin(matchID: match, sport: .pickleball, isIndoor: false, at: t0)
        ledger.markFinishing(match, report: report, at: t0)
        ledger.discardLostSession(match)
        XCTAssertNotNil(ledger.entry(match), "only a running session can be discarded")
    }

    func testInterruptionKeepsScoringRecordAndSummary() {
        var ledger = WorkoutLedger()
        let match = UUID()
        ledger.begin(matchID: match, sport: .pickleball, isIndoor: false, at: t0)
        ledger.markInterrupted(match, report: report, at: t0.addingTimeInterval(600))
        XCTAssertNil(ledger.active)
        XCTAssertEqual(ledger.entry(match)?.state, .failed)
        XCTAssertEqual(ledger.reportsToSend.map(\.matchID), [match])
    }

    func testCompactionKeepsAnythingUnsettled() {
        var ledger = WorkoutLedger()
        let saved = UUID(), unsent = UUID(), running = UUID()
        ledger.begin(matchID: saved, sport: .pickleball, isIndoor: false, at: t0)
        ledger.markFinishing(saved, report: report, at: t0)
        ledger.markSaved(saved, workoutID: nil)
        ledger.markReportQueued(saved)
        ledger.begin(matchID: unsent, sport: .pickleball, isIndoor: false, at: t0)
        ledger.markFinishing(unsent, report: report, at: t0)
        ledger.markSaved(unsent, workoutID: nil)
        ledger.begin(matchID: running, sport: .pickleball, isIndoor: false, at: t0)

        ledger.compact(olderThan: 3_600, now: t0.addingTimeInterval(86_400))
        XCTAssertNil(ledger.entry(saved))
        XCTAssertNotNil(ledger.entry(unsent))
        XCTAssertNotNil(ledger.entry(running))
    }

    func testLiveMetricsAreCompactAndThrottled() throws {
        let metrics = WorkoutLiveMetrics(matchID: UUID(), heartRate: 142, activeEnergy: nil, elapsed: 600,
                                         isPaused: false, sampledAt: t0)
        XCTAssertEqual(WorkoutLiveMetrics.decode(metrics.encoded), metrics)
        XCTAssertLessThan(metrics.encoded.count, 200)
        XCTAssertNil(WorkoutLiveMetrics.decode(Data("nope".utf8)))

        var throttle = MetricsThrottle(interval: 5)
        XCTAssertTrue(throttle.shouldSend(metrics, now: t0))
        XCTAssertFalse(throttle.shouldSend(metrics, now: t0.addingTimeInterval(2)))
        var paused = metrics
        paused.isPaused = true
        XCTAssertTrue(throttle.shouldSend(paused, now: t0.addingTimeInterval(3)), "a pause goes out at once")
        XCTAssertFalse(throttle.shouldSend(paused, now: t0.addingTimeInterval(4)))
        XCTAssertTrue(throttle.shouldSend(paused, now: t0.addingTimeInterval(8.5)))
        // Two snapshots per 10 s at well under 200 bytes is far below 100 KB.
    }
}
