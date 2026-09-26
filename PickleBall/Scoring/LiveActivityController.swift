//
//  LiveActivityController.swift
//  PickleBall
//
//  Lock Screen / Dynamic Island score for the match in progress. The
//  payload (`LiveScoreSnapshot`) and attributes live in CourtKit so the
//  widget extension renders exactly what the app computed.
//

import Foundation
import ActivityKit
import CourtKit

@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    private var activity: Activity<LiveScoreAttributes>?

    private init() {}

    func start(for match: LiveMatch) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let existing = activity {
            if existing.attributes.matchID == match.id {
                update(for: match)
                return
            }
            end(for: nil, dismissImmediately: true)
        }

        let attributes = LiveScoreAttributes(
            matchID: match.id,
            sport: match.sport,
            teamA: match.lineup.shortName(of: .a),
            teamB: match.lineup.shortName(of: .b),
            rulesSummary: match.rules.summary
        )
        let content = ActivityContent(state: LiveScoreSnapshot(scorer: match.scorer), staleDate: nil)
        do {
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            print("LiveActivity: request failed: \(error.localizedDescription)")
        }
    }

    func update(for match: LiveMatch) {
        guard let activity, activity.attributes.matchID == match.id else { return }
        let content = ActivityContent(state: LiveScoreSnapshot(scorer: match.scorer), staleDate: nil)
        Task { await activity.update(content) }
    }

    func end(for match: LiveMatch?, dismissImmediately: Bool) {
        guard let activity else { return }
        self.activity = nil
        let final = match.map { ActivityContent(state: LiveScoreSnapshot(scorer: $0.scorer), staleDate: nil) }
        let policy: ActivityUIDismissalPolicy = dismissImmediately
            ? .immediate
            : .after(Date().addingTimeInterval(10 * 60))
        Task { await activity.end(final, dismissalPolicy: policy) }
    }

    /// Clears activities left behind by a previous run of the app.
    func endStaleActivities() {
        let stale = Activity<LiveScoreAttributes>.activities
        guard !stale.isEmpty else { return }
        Task {
            for activity in stale {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
