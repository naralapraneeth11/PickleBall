import XCTest
import CourtKit
@testable import CourtNetCore

final class WireCodingTests: XCTestCase {
    func testParsesEveryPostgresTimestampShape() throws {
        let expected = Date(timeIntervalSince1970: 1_790_489_720.015)
        for text in ["2026-09-27T06:15:20.015Z", "2026-09-27T06:15:20.015+00:00", "2026-09-27 06:15:20.015123+00",
                     "2026-09-27T08:15:20.015+02:00"] {
            let date = try XCTUnwrap(WireCoding.parse(text), text)
            XCTAssertEqual(date.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001, text)
        }
        XCTAssertEqual(try XCTUnwrap(WireCoding.parse("2026-09-27T06:15:20Z")).timeIntervalSince1970, 1_790_489_720, accuracy: 0.001)
        XCTAssertNil(WireCoding.parse("yesterday"))
    }

    func testDatesRoundTripToTheMillisecond() throws {
        let date = Date(timeIntervalSince1970: 1_790_489_720.123)
        let back = try XCTUnwrap(WireCoding.parse(WireCoding.format(date)))
        XCTAssertEqual(back.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
    }
}

final class RowDecodingTests: XCTestCase {
    func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try WireCoding.decoder.decode(T.self, from: Data(json.utf8))
    }

    func testProfileFromPostgREST() throws {
        let profile = try decode(ProfileRow.self, """
        {"id":"00000000-0000-0000-0000-00000000000a","username":"alice","display_name":"Alice","avatar_path":null,
         "sports":["pickleball","padel"],"home_courts":[{"name":"Rec Center","lat":37.77,"lon":-122.42,"mapItemID":null}],
         "created_at":"2026-09-27 06:15:20.015+00","updated_at":"2026-09-27T06:15:20.015+00:00"}
        """)
        XCTAssertEqual(profile.sports, [.pickleball, .padel])
        XCTAssertEqual(profile.homeCourts.first?.name, "Rec Center")
        XCTAssertEqual(profile.homeCourts.first?.latitude, 37.77)
    }

    func testMatchRowWithEverything() throws {
        let rules = MatchRules.standard(for: .pickleball)
        let rulesJSON = String(decoding: try WireCoding.encoder.encode(rules), as: UTF8.self)
        let match = try decode(MatchRow.self, """
        {"id":"10000000-0000-0000-0000-000000000001","sport":"pickleball","rules":\(rulesJSON),"source":"watch",
         "created_by":"00000000-0000-0000-0000-00000000000a","status":"pending",
         "started_at":"2026-09-27T06:00:00+00:00","ended_at":"2026-09-27T06:30:00+00:00","winner_team":0,
         "match_score":[1,0],"points":[11,7],"units":[{"score":{"a":11,"b":7},"isSuperTiebreak":false}],
         "rally_winners":"AAB","rally_offsets":[1.5,20,41.2],"court":{"name":"Court 3"},"squad_id":null,
         "tournament_id":null,"fixture_id":null,"callout_id":null,"workout":null,"confirmed_at":null,
         "updated_at":"2026-09-27T06:30:01.5+00:00"}
        """)
        XCTAssertEqual(match.rules, rules)
        XCTAssertEqual(match.winnerTeam, .a)
        XCTAssertEqual(match.status, .pending)
        XCTAssertEqual(match.units.first?.score, TeamPair(a: 11, b: 7))
        let rallies = try XCTUnwrap(MatchWire.rallies(match))
        XCTAssertEqual(rallies.map(\.winner), [.a, .a, .b])
        XCTAssertEqual(rallies[2].at.timeIntervalSince(match.startedAt), 41.2, accuracy: 0.001)
    }

    func testCallOutRowBecomesTheCourtKitModel() throws {
        let rules = String(decoding: try WireCoding.encoder.encode(MatchRules.standard(for: .padel)), as: UTF8.self)
        let row = try decode(CallOutRow.self, """
        {"id":"30000000-0000-0000-0000-000000000001","created_by":"00000000-0000-0000-0000-00000000000a",
         "challengers":["00000000-0000-0000-0000-00000000000a"],"challenged":["00000000-0000-0000-0000-00000000000b"],
         "sport":"padel","rules":\(rules),"proposed_at":null,"court":null,"status":"countered",
         "counter":{"proposed_at":"2026-10-02T19:00:00+00:00","court":{"name":"Rec Center"},"by":"00000000-0000-0000-0000-00000000000b"},
         "match_id":null,"squad_id":null,"created_at":"2026-09-27T06:00:00+00:00","updated_at":"2026-09-27T06:00:00+00:00"}
        """)
        let callOut = row.callOut
        let alice = PlayerID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-00000000000a")!)
        XCTAssertEqual(callOut.moves(for: alice), [.accept, .counter, .decline, .cancel])
        XCTAssertEqual(callOut.currentTerms.court?.name, "Rec Center")
    }

    func testServerWrittenChatEvents() throws {
        let events = try decode([ChatEvent].self, """
        [{"type":"result","match_id":"10000000-0000-0000-0000-000000000001"},
         {"type":"callout","callout_id":"30000000-0000-0000-0000-000000000001","by":"00000000-0000-0000-0000-00000000000a"},
         {"type":"joined","user_id":"00000000-0000-0000-0000-00000000000b"},
         {"type":"champion","tournament_id":"40000000-0000-0000-0000-000000000001","champions":["00000000-0000-0000-0000-00000000000a"]},
         {"type":"something_new","whatever":1}]
        """)
        XCTAssertEqual(events.count, 5)
        XCTAssertEqual(events.last, .unknown(type: "something_new"))
        if case .champion(_, let champions) = events[3] { XCTAssertEqual(champions.count, 1) } else { XCTFail() }
    }

    func testBeltEventsTravelInsideChatEvents() throws {
        let key = BeltKey.rivalry([PlayerID()], [PlayerID()], sport: .pickleball)
        let event = ChatEvent.belt(.created(key: key, holder: key.sides[0], matchID: UUID()))
        let json = try JSONValue(encoding: event)
        XCTAssertEqual(json["type"], "belt")
        XCTAssertNotNil(json["match_id"], "the server can find the match without decoding the belt")
        XCTAssertEqual(try json.decode(as: ChatEvent.self), event)
    }

    func testMessageWithEventPayload() throws {
        let message = try decode(MessageRow.self, """
        {"id":"50000000-0000-0000-0000-000000000001","conversation_id":"60000000-0000-0000-0000-000000000001",
         "sender_id":null,"kind":"event","body":null,"payload":{"type":"result","match_id":"10000000-0000-0000-0000-000000000001"},
         "media_path":null,"created_at":"2026-09-27T06:30:02+00:00"}
        """)
        XCTAssertNil(message.senderID)
        XCTAssertEqual(message.payload, .result(matchID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!))
    }
}

final class MatchWireTests: XCTestCase {
    let alice = PlayerRef(kind: .user, displayName: "Alice")
    let sam = PlayerRef(kind: .guest, displayName: "Sam")

    func testScoredMatchPayload() throws {
        let rules = MatchRules.pickleball(.rally, PickleballConfig(pointsToWin: 3, isDoubles: false))
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let rallies = [Team.a, .b, .a, .a].enumerated().map { Rally(winner: $0.element, at: start.addingTimeInterval(Double($0.offset) * 10 + 5)) }
        let squad = UUID()
        let request = MatchWire.payload(id: UUID(), rules: rules, lineup: Lineup(teamA: [alice], teamB: [sam]), rallies: rallies,
                                        startedAt: start, endedAt: start.addingTimeInterval(60), source: .watch,
                                        context: MatchContext(court: CourtTag(name: "Court 1"), squadID: squad))
        XCTAssertEqual(request.m.winnerTeam, .a)
        XCTAssertEqual(request.m.rallyWinners, "ABAA")
        XCTAssertEqual(request.m.rallyOffsets, [5, 15, 25, 35])
        XCTAssertEqual(request.m.points, [3, 1])
        XCTAssertEqual(request.participants.map(\.kind), [.user, .guest])
        XCTAssertEqual(request.participants.map(\.team), [.a, .b])

        let json = try JSONValue(encoding: request)
        XCTAssertEqual(json["m"]?["squad_id"]?.stringValue?.lowercased(), squad.uuidString.lowercased())
        XCTAssertNil(json["m"]?["tournament_id"], "absent keys stay absent for save_match")
        XCTAssertEqual(json["participants"], .array(request.participants.map { try! JSONValue(encoding: $0) }))
    }

    func testEnteredMatchPayload() throws {
        let rules = MatchRules.standard(for: .pickleball, isDoubles: false)
        let entered = try ScoreEntry.validate([CompletedUnit(score: TeamPair(a: 11, b: 4))], rules: rules).get()
        let request = MatchWire.payload(id: UUID(), rules: rules, lineup: Lineup(teamA: [alice], teamB: [sam]), entered: entered, playedAt: Date())
        XCTAssertEqual(request.m.source, .entered)
        XCTAssertNil(request.m.rallyWinners)
        XCTAssertEqual(request.m.matchScore, [1, 0])
    }

    func testDownloadedLineupCreditsClaimedGuests() {
        let match = UUID(), claimer = UUID()
        let participants = [
            ParticipantRow(matchID: match, playerID: alice.id.rawValue, team: .a, slot: 0),
            ParticipantRow(matchID: match, playerID: sam.id.rawValue, team: .b, slot: 0)
        ]
        let players = [
            alice.id.rawValue: PlayerRow(id: alice.id.rawValue, kind: .user, displayName: "Alice"),
            sam.id.rawValue: PlayerRow(id: sam.id.rawValue, kind: .guest, displayName: "Sam", claimedBy: claimer)
        ]
        let lineup = MatchWire.lineup(participants: participants, players: players)
        XCTAssertEqual(lineup.teams.b.first?.id.rawValue, claimer)
        XCTAssertEqual(lineup.teams.b.first?.kind, .user)

        let unknown = MatchWire.lineup(participants: participants, players: [:])
        XCTAssertEqual(unknown.teams.a.first?.displayName, "Player")
    }
}

final class OutboxTests: XCTestCase {
    /// Replies from a script, recording what was sent.
    final class ScriptedTransport: OutboxTransport, @unchecked Sendable {
        var replies: [OutboxOutcome]
        var sent: [OutboxOperation] = []
        init(_ replies: [OutboxOutcome]) { self.replies = replies }
        func send(_ operation: OutboxOperation) async -> OutboxOutcome {
            sent.append(operation)
            return replies.isEmpty ? .sent : replies.removeFirst()
        }
    }

    func op(_ name: String, key: String? = nil) -> OutboxOperation {
        OutboxOperation(action: .rpc(name: name, params: [:]), key: key)
    }

    func testSendsInOrder() async {
        let outbox = Outbox(storage: MemoryOutboxStorage())
        for name in ["a", "b", "c"] { await outbox.enqueue(op(name)) }
        let transport = ScriptedTransport([])
        let sent = await outbox.drain(using: transport)
        XCTAssertEqual(sent, 3)
        XCTAssertEqual(transport.sent.map(\.action), ["a", "b", "c"].map { .rpc(name: $0, params: [:]) })
        let empty = await outbox.isEmpty
        XCTAssertTrue(empty)
    }

    func testNetworkFailureStopsTheQueueAndBacksOff() async {
        let outbox = Outbox(storage: MemoryOutboxStorage())
        await outbox.enqueue(op("a"))
        await outbox.enqueue(op("b"))
        let now = Date(timeIntervalSince1970: 1_000)
        let transport = ScriptedTransport([.retry("offline")])
        let sent = await outbox.drain(using: transport, now: { now })
        XCTAssertEqual(sent, 0)
        XCTAssertEqual(transport.sent.count, 1, "b waits behind a")

        // Too soon: nothing is attempted.
        await outbox.drain(using: transport, now: { now.addingTimeInterval(1) })
        XCTAssertEqual(transport.sent.count, 1)

        let later = await outbox.drain(using: transport, now: { now.addingTimeInterval(3) })
        XCTAssertEqual(later, 2)
    }

    func testRejectedOperationsDoNotBlockTheQueue() async {
        let outbox = Outbox(storage: MemoryOutboxStorage())
        await outbox.enqueue(op("bad"))
        await outbox.enqueue(op("good"))
        let transport = ScriptedTransport([.rejected("permission denied")])
        let sent = await outbox.drain(using: transport)
        XCTAssertEqual(sent, 1)
        let rejected = await outbox.rejected
        XCTAssertEqual(rejected.map(\.lastError), ["permission denied"])
    }

    func testSameKeyReplacesInPlace() async {
        let outbox = Outbox(storage: MemoryOutboxStorage())
        await outbox.enqueue(op("save v1", key: "match:1"))
        await outbox.enqueue(op("message"))
        await outbox.enqueue(op("save v2", key: "match:1"))
        let pending = await outbox.pending
        XCTAssertEqual(pending.map(\.action), [.rpc(name: "save v2", params: [:]), .rpc(name: "message", params: [:])])
        let isPending = await outbox.isPending(key: "match:1")
        XCTAssertTrue(isPending)
    }

    func testQueueSurvivesRelaunch() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = Outbox(storage: FileOutboxStorage(url: url))
        let request = SaveMatchRequest(
            m: MatchPayload(id: UUID(), sport: .padel, rules: .standard(for: .padel), source: .entered,
                            startedAt: Date(timeIntervalSince1970: 1_790_000_000.25),
                            endedAt: nil, winnerTeam: .b, matchScore: [0, 2], points: [4, 12], units: []),
            participants: []
        )
        await first.enqueue(try Operations.saveMatch(request))
        await first.enqueue(try Operations.sendMessage(MessageDraft(conversationID: UUID(), senderID: UUID(), body: "gg")))

        let second = Outbox(storage: FileOutboxStorage(url: url))
        let pending = await second.pending
        XCTAssertEqual(pending.count, 2)
        guard case .rpc("save_match", let params) = pending[0].action else { return XCTFail("\(pending[0].action)") }
        XCTAssertEqual(try params.decode(as: SaveMatchRequest.self), request)
        guard case .insert("messages", let row) = pending[1].action else { return XCTFail() }
        XCTAssertEqual(row["body"], "gg")
        XCTAssertNil(row["created_at"], "the server stamps message times")
    }

    func testBackoffGrowsAndCaps() {
        XCTAssertEqual(Outbox.backoff(afterAttempts: 1), 2)
        XCTAssertEqual(Outbox.backoff(afterAttempts: 3), 8)
        XCTAssertEqual(Outbox.backoff(afterAttempts: 30), Outbox.maxBackoff)
    }
}

final class InviteLinkTests: XCTestCase {
    let token = "0123456789abcdef01234567"

    func testParsesEveryShape() {
        for text in ["pickleball://invite/\(token)",
                     "https://abc.supabase.co/functions/v1/invite/\(token)",
                     "https://abc.supabase.co/functions/v1/invite?t=\(token)"] {
            XCTAssertEqual(InviteLink(url: URL(string: text)!)?.token, token, text)
        }
        XCTAssertNil(InviteLink(url: URL(string: "pickleball://invite/nope")!))
        XCTAssertNil(InviteLink(url: URL(string: "https://example.com/\(token)")!))
    }

    func testBuildsLinks() {
        let link = InviteLink(token: token)!
        XCTAssertEqual(link.appURL.absoluteString, "pickleball://invite/\(token)")
        let page = URL(string: "https://someone.github.io/PickleBall/invite/")!
        XCTAssertEqual(link.shareURL(page: page).absoluteString, "https://someone.github.io/PickleBall/invite/?t=\(token)")
        XCTAssertEqual(link.shareURL(page: nil), link.appURL)
        XCTAssertEqual(InviteLink(url: link.shareURL(page: page)), link)
        XCTAssertEqual(InviteLink(url: link.appURL), link)
        XCTAssertEqual(InviteLink(text: "  \(token.uppercased()) "), link, "codes typed by hand")
        XCTAssertEqual(InviteLink(text: link.shareURL(page: page).absoluteString), link)
        XCTAssertNil(InviteLink(text: "hello"))
    }
}
