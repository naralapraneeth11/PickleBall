import XCTest
import CourtKit
@testable import CourtNetCore

final class LaunchWireTests: XCTestCase {
    func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try WireCoding.decoder.decode(T.self, from: Data(json.utf8))
    }

    func json(_ value: some Encodable) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: WireCoding.encoder.encode(value)) as! [String: Any]
    }

    func testFixtureRowCarriesItsBracketPlace() throws {
        let a = PlayerID(), b = PlayerID()
        let fixture = Fixture(round: 2, court: 1, teams: TeamPair(a: [a], b: [b]), stage: .losers, slot: 1)
        let row = FixtureRow(fixture, tournamentID: UUID())
        let out = try json(row)
        XCTAssertEqual(out["stage"] as? String, "losers")
        XCTAssertEqual(out["slot"] as? Int, 1)
        XCTAssertNil(out["match_id"], "new fixtures never claim a match")
        XCTAssertEqual(row.fixture, fixture)

        // League fixtures leave stage to the database default.
        let league = try json(FixtureRow(Fixture(round: 1, court: 1, teams: TeamPair(a: [a], b: [b])), tournamentID: UUID()))
        XCTAssertNil(league["stage"])
        let old = try decode(FixtureRow.self, """
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","tournament_id":"6F9619FF-8B86-D011-B42D-00C04FC964FE","round":1,
         "court_number":1,"team_a":[],"team_b":[],"scheduled_at":null,"court":null,"match_id":null}
        """)
        XCTAssertEqual(old.fixture.stage, .main)
    }

    func testTournamentSettingsAndLevels() throws {
        let rules = String(decoding: try WireCoding.encoder.encode(MatchRules.standard(for: .padel)), as: UTF8.self)
        let tournament = try decode(TournamentRow.self, """
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","squad_id":"6F9619FF-8B86-D011-B42D-00C04FC964FE","name":"Cup",
         "sport":"padel","format":"mexicano","rules":\(rules),
         "status":"active","champions":[],"created_by":null,"created_at":null,"completed_at":null,
         "settings":{"rounds":6,"entrants":[["6F9619FF-8B86-D011-B42D-00C04FC964FD"]]}}
        """)
        XCTAssertEqual(tournament.format, .mexicano)
        XCTAssertEqual(tournament.settings?.rounds, 6)
        XCTAssertEqual(tournament.settings?.seededEntrants?.count, 1)

        let profile = try decode(ProfileRow.self, """
        {"id":"00000000-0000-0000-0000-00000000000a","username":"alice","display_name":"Alice","avatar_path":null,
         "sports":["padel"],"home_courts":[],"levels":{"padel":3.42}}
        """)
        XCTAssertEqual(profile.level(in: .padel), 3.42)
        XCTAssertNil(profile.level(in: .pickleball))
    }

    func testPingSendsEveryArgument() throws {
        let out = try json(PingDraft(install: UUID(), country: nil, appVersion: "1.0", locale: "es_ES", firstSeen: nil))
        XCTAssertEqual(Set(out.keys), ["install", "country", "app_version", "locale", "first_seen"])
        XCTAssertTrue(out["country"] is NSNull)
        let day = try json(PingDraft(install: UUID(), country: "ES", appVersion: "1.0", locale: nil,
                                     firstSeen: Date(timeIntervalSince1970: 1_790_489_720)))
        XCTAssertEqual(day["first_seen"] as? String, "2026-09-27")
    }

    func testCrashReportsAreTrimmed() throws {
        let crash = CrashDraft(install: UUID(), appVersion: String(repeating: "9", count: 50), osVersion: "iOS 26.1",
                               device: "iPhone17,1", kind: .hang, summary: String(repeating: "x", count: 900), payload: .null)
        XCTAssertEqual(crash.appVersion.count, 20)
        XCTAssertEqual(crash.summary.count, 500)
        XCTAssertEqual(try json(crash)["kind"] as? String, "hang")
    }

    func testAdminRows() throws {
        let report = try decode(AdminReportRow.self, """
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","reporter":"6F9619FF-8B86-D011-B42D-00C04FC964FE","target_type":"serve",
         "target_id":"6F9619FF-8B86-D011-B42D-00C04FC964FD","reason":"spam","created_at":"2026-09-27 06:15:20+00",
         "resolved_at":null,"resolution":null,"author":null,"author_name":null,"body":"buy now","media":[],"author_reports":3}
        """)
        XCTAssertEqual(report.targetType, .serve)
        XCTAssertEqual(report.authorReports, 3)

        let stats = try decode(AdminStats.self, """
        {"countries":[{"country":"ES","installs":12},{"country":"BR","installs":7}],
         "weeks":[{"week":"2026-09-28","active":19,"returning":11,"retention":0.611},{"week":"2026-09-21","active":18,"returning":0,"retention":null}],
         "installs":25,
         "crashes":[{"app_version":"1.0","kind":"crash","summary":"EXC_BAD_ACCESS","count":3,"last":"2026-09-27T06:15:20.015+00:00"}]}
        """)
        XCTAssertEqual(stats.countries.map(\.country), ["ES", "BR"])
        XCTAssertEqual(stats.weeks.first?.retention, 0.611)
        XCTAssertNil(stats.weeks.last?.retention)
        XCTAssertEqual(stats.crashes.first?.count, 3)
    }

    func testShareLinkURL() {
        let url = ShareLinks.url(token: "abc123", site: URL(string: "https://pickleball.pages.dev")!)
        XCTAssertEqual(url.absoluteString, "https://pickleball.pages.dev/live/?t=abc123")
    }
}
