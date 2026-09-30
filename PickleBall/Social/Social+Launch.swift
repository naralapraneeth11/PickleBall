//
//  Social+Launch.swift
//  PickleBall
//
//  Phase 3 on the signed-in side: publishing my level so friends see the
//  same number, and the moderation tools for admins.
//

import Foundation
import CourtKit
import CourtNet

extension Social {
    private static let publishedLevelsKey = "levels.published"

    /// Publishes my levels when they change. Friends can't see every match
    /// I play, so they read the number I publish rather than working it
    /// out from what they can see.
    func publishLevels() async {
        guard let backend, let userID else { return }
        let levels = MatchStore.shared.levels.published(for: PlayerID(rawValue: userID))
        let key = "\(Self.publishedLevelsKey).\(userID.uuidString)"
        let last = UserDefaults.standard.dictionary(forKey: key) as? [String: Double]
        guard levels != last, !levels.isEmpty else { return }
        do {
            try await backend.publishLevels(levels)
            UserDefaults.standard.set(levels, forKey: key)
        } catch {
            report(error)
        }
    }

    func refreshAdminFlag() async {
        guard let backend else { return }
        isAdmin = (try? await backend.isAdmin()) ?? false
    }

    // MARK: Moderation

    func adminReports(openOnly: Bool) async -> [AdminReportRow] {
        var rows: [AdminReportRow] = []
        await run { rows = try await $0.adminReports(openOnly: openOnly) }
        return rows
    }

    func resolve(_ report: AdminReportRow, as resolution: ReportResolution) async -> Bool {
        await run { try await $0.adminResolve(report.id, resolution) }
    }

    func adminBans() async -> [AdminBanRow] {
        var rows: [AdminBanRow] = []
        await run { rows = try await $0.adminBans() }
        return rows
    }

    func unban(_ userID: UUID) async -> Bool {
        await run { try await $0.adminUnban(userID) }
    }

    func adminStats() async -> AdminStats? {
        var stats: AdminStats?
        await run { stats = try await $0.adminStats() }
        return stats
    }
}
