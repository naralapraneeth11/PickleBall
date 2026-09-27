//
//  Social+Feed.swift
//  PickleBall
//
//  Serves, Returns and Replays. Photos are checked on the device with
//  SensitiveContentAnalysis before they're posted; text goes through the
//  content filter. Serving a result is always a choice, never automatic.
//

import Foundation
import CourtKit
import CourtNet

extension Social {
    // MARK: Serves

    /// Friends' Serves still in play, newest activity first.
    var liveFeed: [ServeRow] {
        FeedRules.sorted(feed.filter { $0.isInPlay() }, createdAt: \.createdAt, lastReturnAt: \.lastReturnAt)
    }

    func serve(text: String, photos: [Data] = [], video: Data? = nil, matchID: UUID? = nil) async -> Bool {
        guard let userID else { return false }
        var body: String?
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            guard let cleaned = ContentFilter.standard.cleaned(trimmed) else {
                notice = "That Serve breaks the community rules."
                return false
            }
            body = cleaned
        }
        var paths: [String] = []
        for photo in photos.prefix(4) {
            guard let path = await uploadMedia(photo, kind: "serves") else { return false }
            paths.append(path)
        }
        if let video {
            guard let path = await uploadMedia(video, kind: "serves", contentType: "video/mp4") else { return false }
            paths.append(path)
        }
        let kind: ServeKind = matchID != nil ? .result : video != nil ? .video : paths.isEmpty ? .text : .photo
        guard body != nil || !paths.isEmpty || matchID != nil else { return false }
        let draft = ServeDraft(authorID: userID, kind: kind, body: body, mediaPaths: paths, matchID: matchID)
        let ok = await run { try await $0.createServe(draft) }
        if ok { await refreshFeed() }
        return ok
    }

    func deleteServe(_ serve: ServeRow) async {
        guard await run({ try await $0.deleteServe(serve.id) }) else { return }
        try? await backend?.removeMedia(serve.mediaPaths, from: .media)
        setMyServes(myServes.filter { $0.id != serve.id })
    }

    // MARK: Returns

    func sendReturn(_ kind: ReturnKind, text: String? = nil, photo: Data? = nil, to serve: ServeRow) async {
        guard let userID else { return }
        var body = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw = body, !raw.isEmpty {
            guard let cleaned = ContentFilter.standard.cleaned(raw) else {
                notice = "That Return breaks the community rules."
                return
            }
            body = cleaned
        } else {
            body = nil
        }
        var mediaPath: String?
        if let photo {
            guard let path = await uploadMedia(photo, kind: "returns") else { return }
            mediaPath = path
        }
        let draft = ReturnDraft(serveID: serve.id, authorID: userID, kind: kind, body: body, mediaPath: mediaPath)
        setReturns((returns[serve.id] ?? []) + [draft.optimisticRow()], for: serve.id)
        bumpRally(serve.id)
        do {
            await enqueue(try Operations.sendReturn(draft))
        } catch {
            report(error)
        }
    }

    func deleteReturn(_ row: ReturnRow) async {
        guard await run({ try await $0.deleteReturn(row.id) }) else { return }
        setReturns((returns[row.serveID] ?? []).filter { $0.id != row.id }, for: row.serveID)
    }

    func loadReturns(for serve: ServeRow) async {
        guard let backend else { return }
        if let rows = try? await backend.returns(serveIDs: [serve.id]) {
            setReturns(rows.filter { !blocked.contains($0.authorID) }, for: serve.id)
        }
    }

    private func bumpRally(_ serveID: UUID) {
        func bumped(_ list: [ServeRow]) -> [ServeRow] {
            list.map { row in
                guard row.id == serveID else { return row }
                var copy = row
                copy.rallyCount += 1
                copy.lastReturnAt = Date()
                return copy
            }
        }
        setFeed(bumped(feed))
        setMyServes(bumped(myServes))
    }

    // MARK: Replays

    /// Friends' and my Replays that are still up, newest first.
    var liveReplays: [ReplayRow] {
        // The row shows the last 24 hours; saved Replays live on in the trophy case.
        replays.filter { !blocked.contains($0.authorID) && ReplayLifetime.isVisible(createdAt: $0.createdAt, saved: false) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Builds and posts the Replay for a finished match.
    func postReplay(for record: MatchRecord) async -> ReplayRow? {
        guard let userID, let result = record.result, let rules = record.rules else { return nil }
        let drama = record.rallies.isEmpty
            ? DramaDetector.analyze(units: record.units, rules: rules, winner: record.winner)
            : DramaDetector.analyze(rules: rules, rallies: record.rallyLog)
        let beltLines = MatchStore.shared.belts.events(for: record.id).map { beltLine($0) }
        let photos = MatchCenter.photos(for: record.id)
        var paths: [String] = []
        for url in photos.prefix(6) {
            guard let data = try? Data(contentsOf: url), let path = await uploadMedia(data, kind: "replays") else { continue }
            paths.append(path)
        }
        let story = ReplayStory.make(result: result, drama: drama, beltLines: beltLines, court: record.court,
                                     workout: record.source == .watch ? record.workout : nil, photoCount: paths.count)
        let replay = ReplayRow(matchID: record.id, authorID: userID, story: story, photoPaths: paths)
        guard await run({ try await $0.createReplay(replay) }) else { return nil }
        setReplays([replay] + replays)
        return replay
    }

    func sendReplay(_ replay: ReplayRow, to conversationID: UUID) async {
        if await run({ try await $0.shareReplay(replay.id, to: conversationID) }) {
            notice = "Replay sent."
        }
    }

    func saveReplayToTrophyCase(_ replay: ReplayRow) async {
        let title = replay.story.headline
        guard await run({ try await $0.saveReplay(replay.id, title: title) }) else { return }
        setReplays(replays.map { row in
            guard row.id == replay.id else { return row }
            var copy = row
            copy.saved = true
            return copy
        })
        await refreshTrophies()
    }

    /// One line about a belt change, in names.
    func beltLine(_ event: BeltEvent) -> String {
        let sport = event.key.sport.displayName.lowercased()
        let who = { (ids: [PlayerID]) in ids.map { self.firstName(of: $0.rawValue) }.joined(separator: " & ") }
        switch event {
        case .created(_, let holder, _):
            return "\(who(holder)) won the first \(sport) belt"
        case .defended(_, let holder, let defenses, _):
            let tier = BeltTier(defenses: defenses)
            return defenses == BeltTier.goldDefenses || defenses == BeltTier.undisputedDefenses
                ? "\(who(holder)) made it \(tier.title) with defense \(defenses)"
                : "\(who(holder)) defended the belt (\(defenses))"
        case .changedHands(_, let from, let to, _):
            return "\(who(to)) took the belt from \(who(from))"
        }
    }
}
