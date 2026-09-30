//
//  Launch.swift
//  CourtNetCore
//
//  Wire types for Phase 3: tournament settings, share links, moderation,
//  and the privacy-friendly launch numbers (pings and crash reports).
//

import Foundation
import CourtKit

// MARK: - Tournaments

/// What a tournament needs beyond its fixtures: the entrants in seed order
/// (players or fixed pairs), and format knobs.
public struct TournamentSettings: Codable, Hashable, Sendable {
    /// Seed order; pairs stay together.
    public var entrants: [[UUID]]?
    public var courts: Int?
    /// Mexicano: rounds to play.
    public var rounds: Int?
    /// Pools + knockout.
    public var pools: Int?
    public var advancing: Int?

    public init(entrants: [[UUID]]? = nil, courts: Int? = nil, rounds: Int? = nil, pools: Int? = nil, advancing: Int? = nil) {
        self.entrants = entrants
        self.courts = courts
        self.rounds = rounds
        self.pools = pools
        self.advancing = advancing
    }

    public var seededEntrants: [[PlayerID]]? {
        entrants?.map { $0.map(PlayerID.init(rawValue:)) }
    }
}

// MARK: - Share links

public enum ShareLinkKind: String, Codable, Sendable {
    case match
    case tournament
}

public enum ShareLinks {
    /// The public scoreboard page for a token: https://<site>/live/?t=<token>
    public static func url(token: String, site: URL) -> URL {
        var components = URLComponents(url: site.appendingPathComponent("live/"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "t", value: token)]
        return components.url!
    }
}

// MARK: - Moderation

public enum ReportResolution: String, Codable, Sendable, CaseIterable {
    case dismissed
    case removed
    case banned
}

/// One report as an admin sees it: what was said, who said it.
public struct AdminReportRow: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var reporter: UUID
    public var targetType: ReportDraft.Target
    public var targetID: UUID
    public var reason: String
    public var createdAt: Date
    public var resolvedAt: Date?
    public var resolution: ReportResolution?
    public var author: UUID?
    public var authorName: String?
    public var body: String?
    public var media: [String]
    /// Reports against the same author, all time.
    public var authorReports: Int

    enum CodingKeys: String, CodingKey {
        case id, reporter, reason, resolution, author, body, media
        case targetType = "target_type"
        case targetID = "target_id"
        case createdAt = "created_at"
        case resolvedAt = "resolved_at"
        case authorName = "author_name"
        case authorReports = "author_reports"
    }
}

public struct AdminBanRow: Codable, Hashable, Sendable, Identifiable {
    public var userID: UUID
    public var name: String
    public var reason: String
    public var createdAt: Date

    public var id: UUID { userID }

    enum CodingKeys: String, CodingKey {
        case name, reason
        case userID = "user_id"
        case createdAt = "created_at"
    }
}

/// The launch numbers: where people are and whether they come back.
public struct AdminStats: Codable, Hashable, Sendable {
    public struct Country: Codable, Hashable, Sendable, Identifiable {
        public var country: String
        public var installs: Int
        public var id: String { country }
    }

    public struct Week: Codable, Hashable, Sendable, Identifiable {
        public var week: String
        public var active: Int
        public var returning: Int
        /// Share of last week's actives who came back.
        public var retention: Double?
        public var id: String { week }
    }

    public struct Crash: Codable, Hashable, Sendable, Identifiable {
        public var appVersion: String?
        public var kind: String
        public var summary: String?
        public var count: Int
        public var last: Date
        public var id: String { "\(appVersion ?? "")-\(kind)-\(summary ?? "")" }

        enum CodingKeys: String, CodingKey {
            case kind, summary, count, last
            case appVersion = "app_version"
        }
    }

    public var countries: [Country]
    public var weeks: [Week]
    public var installs: Int
    public var crashes: [Crash]
}

// MARK: - Launch numbers

/// Once a day per install. A random install ID, the device's region
/// setting and the app version; nothing about the person.
public struct PingDraft: Codable, Hashable, Sendable {
    public var install: UUID
    public var country: String?
    public var appVersion: String
    public var locale: String?
    public var firstSeen: String?

    public init(install: UUID, country: String?, appVersion: String, locale: String?, firstSeen: Date?) {
        self.install = install
        self.country = country
        self.appVersion = appVersion
        self.locale = locale
        self.firstSeen = firstSeen.map(Self.day)
    }

    static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    enum CodingKeys: String, CodingKey {
        case install, country, locale
        case appVersion = "app_version"
        case firstSeen = "first_seen"
    }

    /// Every argument goes out, nulls included, so PostgREST finds ping().
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(install, forKey: .install)
        try c.encode(country, forKey: .country)
        try c.encode(appVersion, forKey: .appVersion)
        try c.encode(locale, forKey: .locale)
        try c.encode(firstSeen, forKey: .firstSeen)
    }
}

/// A crash or hang report from MetricKit, trimmed.
public struct CrashDraft: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case crash, hang, cpu, disk }

    public var install: UUID
    public var appVersion: String
    public var osVersion: String
    public var device: String
    public var kind: Kind
    public var summary: String
    public var payload: JSONValue

    public init(install: UUID, appVersion: String, osVersion: String, device: String, kind: Kind, summary: String, payload: JSONValue) {
        self.install = install
        self.appVersion = String(appVersion.prefix(20))
        self.osVersion = String(osVersion.prefix(40))
        self.device = String(device.prefix(40))
        self.kind = kind
        self.summary = String(summary.prefix(500))
        self.payload = payload
    }

    enum CodingKeys: String, CodingKey {
        case install, kind, summary, payload
        case appVersion = "app_version"
        case osVersion = "os_version"
        case device
    }
}
