//
//  Telemetry.swift
//  PickleBall
//
//  What breaks and where people play, without knowing who anyone is.
//
//  • A daily ping: a random install ID (not the account), the device's
//    region setting, language and app version. That's enough for "top
//    countries" and "weekly return rate", and nothing more.
//  • Crash and hang reports from MetricKit, which Apple delivers the day
//    after they happen, already symbolicated-ready and anonymous.
//
//  Both can be switched off in Settings. Neither is linked to the account,
//  used for ads, or shared with anyone.
//

import Foundation
import MetricKit
import UIKit
import CourtNet

final class Telemetry: NSObject, MXMetricManagerSubscriber {
    static let shared = Telemetry()

    private static let enabledKey = "telemetry.enabled"
    nonisolated private static let installKey = "telemetry.installID"
    nonisolated private static let firstSeenKey = "telemetry.firstSeen"
    private static let lastPingKey = "telemetry.lastPingDay"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Random, per install, reset by deleting the app.
    nonisolated static var installID: UUID {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: installKey), let id = UUID(uuidString: raw) { return id }
        let id = UUID()
        defaults.set(id.uuidString, forKey: installKey)
        defaults.set(Date(), forKey: firstSeenKey)
        return id
    }

    nonisolated static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    func start() {
        MXMetricManager.shared.add(self)
    }

    /// Once a day, when the app comes to the front.
    func pingIfNeeded() async {
        guard Self.isEnabled, let backend = Social.shared.backend else { return }
        let today = Self.day(Date())
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Self.lastPingKey) != today else { return }
        let install = Self.installID
        let firstSeen = defaults.object(forKey: Self.firstSeenKey) as? Date
        let ping = PingDraft(install: install, country: Locale.current.region?.identifier, appVersion: Self.appVersion,
                             locale: Locale.current.identifier, firstSeen: firstSeen)
        do {
            try await backend.ping(ping)
            defaults.set(today, forKey: Self.lastPingKey)
        } catch {
            // Tomorrow, then.
        }
    }

    // MARK: MetricKit

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        var reports: [CrashDraft] = []
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                var parts: [String] = []
                if let type = crash.exceptionType { parts.append("exception \(type)") }
                if let signal = crash.signal { parts.append("signal \(signal)") }
                if let reason = crash.terminationReason { parts.append(reason) }
                reports.append(Self.draft(crash, kind: .crash, summary: parts.joined(separator: " · ")))
            }
            for hang in payload.hangDiagnostics ?? [] {
                reports.append(Self.draft(hang, kind: .hang, summary: "hang \(hang.hangDuration.description)"))
            }
            for cpu in payload.cpuExceptionDiagnostics ?? [] {
                reports.append(Self.draft(cpu, kind: .cpu, summary: "cpu \(cpu.totalCPUTime.description)"))
            }
            for disk in payload.diskWriteExceptionDiagnostics ?? [] {
                reports.append(Self.draft(disk, kind: .disk, summary: "writes \(disk.totalWritesCaused.description)"))
            }
        }
        guard !reports.isEmpty else { return }
        Task { @MainActor in
            guard Telemetry.isEnabled, let backend = Social.shared.backend else { return }
            for report in reports.prefix(10) {
                try? await backend.reportCrash(report)
            }
        }
    }

    private nonisolated static func draft(_ diagnostic: MXDiagnostic, kind: CrashDraft.Kind, summary: String) -> CrashDraft {
        let meta = diagnostic.metaData
        // The call stack tree is what makes a crash fixable; drop it only if
        // it's too big for the table.
        let json = diagnostic.jsonRepresentation()
        let payload = json.count < 150_000 ? ((try? JSONDecoder().decode(JSONValue.self, from: json)) ?? .null) : .null
        return CrashDraft(install: installID, appVersion: diagnostic.applicationVersion, osVersion: meta.osVersion,
                          device: meta.deviceType, kind: kind, summary: summary.isEmpty ? kind.rawValue : summary, payload: payload)
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
