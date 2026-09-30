//
//  Nudger.swift
//  PickleBall
//
//  Teaser notifications, Snapchat-style: one short line ("👀 Sam's still
//  wearing your belt"), the rest only in the app. At most one a day, never
//  at night, each kind mutable, all of it switchable off.
//
//  Everything is local: the phone refreshes in the background now and
//  then (BGAppRefresh), works out whether anything is worth a nudge with
//  CourtKit's Nudges, and schedules at most one local notification. Open
//  the app and any pending nudge is withdrawn — you're already here.
//

import Foundation
import BackgroundTasks
import UserNotifications
import CourtKit

final class Nudger {
    static let shared = Nudger()
    static let taskID = "ME.PickleBall.refresh"
    private static let requestID = "nudge"

    private static let enabledKey = "nudges.enabled"
    private static let mutedKey = "nudges.muted"
    private static let historyKey = "nudges.history"
    private static let backupKey = "nudges.historyBeforePending"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if !newValue { shared.withdraw() }
        }
    }

    static var muted: Set<Nudge.Kind> {
        get { Set((UserDefaults.standard.stringArray(forKey: mutedKey) ?? []).compactMap(Nudge.Kind.init(rawValue:))) }
        set { UserDefaults.standard.set(newValue.map(\.rawValue).sorted(), forKey: mutedKey) }
    }

    private var history: NudgeHistory {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.historyKey) else { return NudgeHistory() }
            return (try? JSONDecoder().decode(NudgeHistory.self, from: data)) ?? NudgeHistory()
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: Self.historyKey) }
    }

    // MARK: Background refresh

    /// Call before the app finishes launching.
    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskID, using: nil) { @Sendable task in
            guard let task = task as? BGAppRefreshTask else { return }
            Task { @MainActor in await Nudger.shared.handle(task) }
        }
    }

    func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskID)
        request.earliestBeginDate = Date().addingTimeInterval(4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handle(_ task: BGAppRefreshTask) async {
        scheduleRefresh()
        let work = Task { @MainActor in
            await Social.shared.refreshAll()
            await self.plan()
        }
        task.expirationHandler = { @Sendable in work.cancel() }
        await work.value
        task.setTaskCompleted(success: !work.isCancelled)
    }

    // MARK: Planning

    /// Works out the one nudge worth sending (if any) and schedules it.
    func plan() async {
        guard Self.isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        // One already waiting: leave it be.
        if await center.pendingNotificationRequests().contains(where: { $0.identifier == Self.requestID }) { return }

        let social = Social.shared
        guard let userID = social.userID else { return }
        let me = PlayerID(rawValue: userID)
        let first = { (id: PlayerID) -> String? in
            let name = social.firstName(of: id.rawValue)
            return name == "Player" ? nil : name
        }
        let waiting = social.awaitingMyConfirmation.compactMap { record in
            record.createdByID.map { (matchID: record.id, from: PlayerID(rawValue: $0)) }
        }
        let calledOut = social.callOutsAwaitingMe.filter { $0.status == .pending }
            .map { (calloutID: $0.id, from: PlayerID(rawValue: $0.createdBy)) }
        let candidates = Nudges.candidates(me: me, ledger: MatchStore.shared.belts, name: first,
                                           waitingOn: waiting, calledOutBy: calledOut)
        let current = history
        guard let choice = Nudges.choose(from: candidates, history: current, policy: NudgePolicy(muted: Self.muted)) else { return }
        let nudge = choice.nudge, at = choice.at

        let content = UNMutableNotificationContent()
        content.body = Self.text(for: nudge)
        content.sound = nil
        content.threadIdentifier = "nudges"
        content.interruptionLevel = .passive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(60, at.timeIntervalSinceNow), repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: Self.requestID, content: content, trigger: trigger))
            UserDefaults.standard.set(try? JSONEncoder().encode(current), forKey: Self.backupKey)
            var updated = current
            updated.sent(nudge, at: at)
            history = updated
        } catch {
            // Try again next time.
        }
    }

    /// Opening the app answers any nudge: withdraw what hasn't gone out,
    /// and forget it was ever planned.
    func withdraw() {
        let center = UNUserNotificationCenter.current()
        Task {
            let pending = await center.pendingNotificationRequests().contains { $0.identifier == Self.requestID }
            center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
            center.removeDeliveredNotifications(withIdentifiers: [Self.requestID])
            if pending, let data = UserDefaults.standard.data(forKey: Self.backupKey),
               let backup = try? JSONDecoder().decode(NudgeHistory.self, from: data) {
                history = backup
            }
            UserDefaults.standard.removeObject(forKey: Self.backupKey)
        }
    }

    func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge])) ?? false
    }

    static func text(for nudge: Nudge) -> String {
        switch nudge.kind {
        case .beltTaken: return String(localized: "👀 \(nudge.name)’s still wearing your belt")
        case .confirmWaiting: return String(localized: "🤝 \(nudge.name)’s waiting on you")
        case .calledOut: return String(localized: "⚔️ \(nudge.name) called you out")
        case .reignMilestone: return String(localized: "👑 \(nudge.days ?? 0)d")
        }
    }

    static func title(for kind: Nudge.Kind) -> String {
        switch kind {
        case .beltTaken: return String(localized: "Someone’s wearing your belt")
        case .confirmWaiting: return String(localized: "A result needs you")
        case .calledOut: return String(localized: "You’ve been called out")
        case .reignMilestone: return String(localized: "Reign milestones")
        }
    }
}
