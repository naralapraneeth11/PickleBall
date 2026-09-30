//
//  SupabaseBackend+Launch.swift
//  CourtNet
//
//  Phase 3 calls: levels, share links, moderation, launch numbers.
//

import Foundation
import CourtNetCore
import Supabase

extension SupabaseBackend {
    public func publishLevels(_ levels: [String: Double]) async throws {
        struct Update: Encodable { let levels: [String: Double] }
        try await db.from("profiles").update(Update(levels: levels), returning: .minimal).eq("id", value: try me()).execute()
    }

    public func createShareLink(_ kind: ShareLinkKind, target: UUID) async throws -> String {
        struct Params: Encodable { let link_kind: String; let target: UUID }
        return try await db.rpc("create_share_link", params: Params(link_kind: kind.rawValue, target: target)).execute().value
    }

    // MARK: Moderation

    public func isAdmin() async throws -> Bool {
        try await db.rpc("is_admin").execute().value
    }

    public func adminReports(openOnly: Bool) async throws -> [AdminReportRow] {
        struct Params: Encodable { let open_only: Bool }
        return try await db.rpc("admin_reports", params: Params(open_only: openOnly)).execute().value
    }

    public func adminResolve(_ reportID: UUID, _ resolution: ReportResolution) async throws {
        struct Params: Encodable { let report: UUID; let action: String }
        try await db.rpc("admin_resolve", params: Params(report: reportID, action: resolution.rawValue)).execute()
    }

    public func adminBans() async throws -> [AdminBanRow] {
        try await db.rpc("admin_bans").execute().value
    }

    public func adminBan(_ userID: UUID, reason: String) async throws {
        struct Params: Encodable { let target: UUID; let why: String }
        try await db.rpc("admin_ban", params: Params(target: userID, why: reason)).execute()
    }

    public func adminUnban(_ userID: UUID) async throws {
        struct Params: Encodable { let target: UUID }
        try await db.rpc("admin_unban", params: Params(target: userID)).execute()
    }

    public func adminStats() async throws -> AdminStats {
        try await db.rpc("admin_stats").execute().value
    }

    // MARK: Launch numbers

    public func ping(_ ping: PingDraft) async throws {
        try await db.rpc("ping", params: ping).execute()
    }

    public func reportCrash(_ crash: CrashDraft) async throws {
        try await db.rpc("report_crash", params: crash).execute()
    }
}
