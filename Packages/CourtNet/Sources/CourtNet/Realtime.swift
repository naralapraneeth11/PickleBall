//
//  Realtime.swift
//  CourtNet
//
//  Two kinds of live traffic:
//
//  • Changes: one channel per signed-in user listening to the tables that
//    matter. Row-level security applies, so each phone only hears about
//    rows it could read anyway. Chat messages arrive decoded, so they show
//    instantly; everything else just says "this table changed" and the app
//    re-reads it.
//  • Crowd taps: a broadcast channel per live match. Friends send taps; the
//    players' phones hear them and pass them to the Watch.
//

import Foundation
import CourtKit
import Supabase

public enum LiveChange: Sendable, Equatable {
    case message(MessageRow)
    /// A message was deleted (by its sender or a moderator).
    case messageDeleted(UUID)
    case table(String)
    /// Whether live updates are flowing. When they come back after a drop,
    /// re-read everything: changes made meanwhile weren't heard.
    case connection(isLive: Bool)
}

public final class LiveUpdates: @unchecked Sendable {
    public static let tables = [
        "friendships", "squad_members", "conversations", "matches", "match_participants",
        "callouts", "tournaments", "tournament_fixtures", "serves", "returns", "replays", "live_matches"
    ]

    private let client: SupabaseClient
    private var channel: RealtimeChannelV2?
    private var tasks: [Task<Void, Never>] = []

    public init(backend: SupabaseBackend) {
        self.client = backend.client
    }

    /// Starts listening. Changes arrive on the returned stream until `stop()`.
    public func start(userID: UUID) async -> AsyncStream<LiveChange> {
        await stop()
        let (stream, continuation) = AsyncStream<LiveChange>.makeStream(bufferingPolicy: .bufferingNewest(200))
        // Private: only this user may join (Realtime Authorization policy in
        // migration 3), so it works with "Private channels only" turned on.
        let channel = client.channel("user-\(userID.uuidString.lowercased())") {
            $0.isPrivate = true
        }

        let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "messages")
        tasks.append(Task {
            for await insert in inserts {
                if let message = try? insert.decodeRecord(as: MessageRow.self, decoder: WireCoding.decoder) {
                    continuation.yield(.message(message))
                } else {
                    continuation.yield(.table("messages"))
                }
            }
        })
        let deletes = channel.postgresChange(DeleteAction.self, schema: "public", table: "messages")
        tasks.append(Task {
            for await delete in deletes {
                if let raw = delete.oldRecord["id"]?.stringValue, let id = UUID(uuidString: raw) {
                    continuation.yield(.messageDeleted(id))
                } else {
                    continuation.yield(.table("messages"))
                }
            }
        })
        let updates = channel.postgresChange(UpdateAction.self, schema: "public", table: "messages")
        tasks.append(Task {
            for await _ in updates { continuation.yield(.table("messages")) }
        })
        for table in Self.tables {
            let changes = channel.postgresChange(AnyAction.self, schema: "public", table: table)
            tasks.append(Task {
                for await _ in changes { continuation.yield(.table(table)) }
            })
        }
        let statuses = channel.statusChange
        tasks.append(Task {
            var last: Bool?
            for await status in statuses {
                let live = status == .subscribed
                if live != last { continuation.yield(.connection(isLive: live)) }
                last = live
            }
        })
        // Joining can fail (no signal, a policy problem): say so and retry
        // with growing gaps instead of failing silently.
        tasks.append(Task {
            for delay in [0, 2, 5, 15, 30, 60] {
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000) }
                if Task.isCancelled { return }
                do {
                    try await channel.subscribeWithError()
                    return
                } catch {
                    continuation.yield(.connection(isLive: false))
                }
            }
        })
        self.channel = channel
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stop() }
        }
        return stream
    }

    public func stop() async {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        if let channel {
            await client.removeChannel(channel)
            self.channel = nil
        }
    }
}

/// Crowd taps for one live match.
public final class CrowdChannel: @unchecked Sendable {
    static let event = "tap"

    private let client: SupabaseClient
    private let channel: RealtimeChannelV2
    private var listener: Task<Void, Never>?

    public init(backend: SupabaseBackend, matchID: UUID) {
        self.client = backend.client
        self.channel = backend.client.channel("crowd-\(matchID.uuidString.lowercased())") {
            $0.broadcast.receiveOwnBroadcasts = false
            // Only people who can see the live match may join (Realtime
            // Authorization policy in the launch migration).
            $0.isPrivate = true
        }
    }

    /// Joins the channel. Taps from others arrive on the stream.
    public func join() async -> AsyncStream<CrowdTap> {
        let (stream, continuation) = AsyncStream<CrowdTap>.makeStream(bufferingPolicy: .bufferingNewest(50))
        let broadcasts = channel.broadcastStream(event: Self.event)
        listener = Task {
            for await message in broadcasts {
                guard let payload = message["payload"],
                      let data = try? JSONEncoder().encode(payload),
                      let tap = try? WireCoding.decoder.decode(CrowdTap.self, from: data) else { continue }
                continuation.yield(tap)
            }
            continuation.finish()
        }
        try? await channel.subscribeWithError()
        return stream
    }

    public func send(_ tap: CrowdTap) async {
        guard let payload = try? JSONValue(encoding: tap) else { return }
        try? await channel.broadcast(event: Self.event, message: payload)
    }

    public func leave() async {
        listener?.cancel()
        await client.removeChannel(channel)
    }
}
