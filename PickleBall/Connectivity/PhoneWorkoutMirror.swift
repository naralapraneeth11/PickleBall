//
//  PhoneWorkoutMirror.swift
//  PickleBall
//
//  The iPhone's side of HealthKit workout mirroring. The Watch owns the
//  workout and mirrors it here; this only shows its live metrics. Match
//  history never comes this way (it travels in the match journal over
//  WatchConnectivity), because mirroring ends with the workout.
//
//  The handler is installed at launch, since mirroring can launch the app
//  in the background. A repeated callback (after a reconnect) replaces the
//  session it had.
//

import Foundation
import HealthKit
import Observation
import SwiftUI
import CourtKit

@MainActor
@Observable
final class PhoneWorkoutMirror: NSObject {
    static let shared = PhoneWorkoutMirror()

    /// The latest snapshot from the Watch, with its sample time.
    private(set) var metrics: WorkoutLiveMetrics?
    private(set) var isConnected = false

    @ObservationIgnored private let healthStore = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?

    private override init() {
        super.init()
    }

    func install() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        healthStore.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in self?.adopt(session) }
        }
    }

    /// Metrics for a match, only while they're recent enough to mean
    /// anything.
    func metrics(for matchID: UUID, now: Date = Date()) -> WorkoutLiveMetrics? {
        guard let metrics, metrics.matchID == matchID, now.timeIntervalSince(metrics.sampledAt) < 120 else { return nil }
        return metrics
    }

    private func adopt(_ session: HKWorkoutSession) {
        self.session = session
        session.delegate = self
        isConnected = true
    }

    fileprivate func receive(_ data: [Data], from session: HKWorkoutSession) {
        guard session === self.session else { return }
        // Newest valid snapshot wins; older ones arriving late are ignored.
        for item in data {
            guard let snapshot = WorkoutLiveMetrics.decode(item) else { continue }
            if let current = metrics, current.matchID == snapshot.matchID, current.sampledAt > snapshot.sampledAt { continue }
            metrics = snapshot
        }
        isConnected = true
    }

    fileprivate func ended(_ session: HKWorkoutSession) {
        guard session === self.session else { return }
        self.session = nil
        isConnected = false
        metrics = nil
    }

    fileprivate func disconnected(_ session: HKWorkoutSession) {
        guard session === self.session else { return }
        isConnected = false
    }
}

extension PhoneWorkoutMirror: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended else { return }
        Task { @MainActor in self.ended(workoutSession) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.ended(workoutSession) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in self.receive(data, from: workoutSession) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        Task { @MainActor in self.disconnected(workoutSession) }
    }
}

/// "♥ 142 · 210 kcal · 4 s ago" under a Watch-scored match. Shows nothing
/// when there's no recent reading (missing data is never shown as zero).
struct WatchMetricsLine: View {
    let matchID: UUID
    private let mirror = PhoneWorkoutMirror.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            if let metrics = mirror.metrics(for: matchID, now: context.date) {
                HStack(spacing: 10) {
                    if let heartRate = metrics.heartRate {
                        Label("\(Int(heartRate.rounded()))", systemImage: "heart.fill")
                    }
                    if let energy = metrics.activeEnergy {
                        Text("\(Int(energy.rounded())) kcal")
                    }
                    if metrics.isPaused {
                        Text("Paused")
                    }
                    Text(metrics.sampledAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                        .foregroundStyle(DS.Palette.nightMuted)
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
