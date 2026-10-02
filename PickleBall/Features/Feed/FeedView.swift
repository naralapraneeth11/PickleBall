//
//  FeedView.swift
//  PickleBall
//
//  Friends only, never public. Replays (24-hour match stories) across the
//  top; friends' Serves below. No likes and no follower counts: a Serve's
//  only number is its rally. A Serve nobody returns for a day is a dead
//  ball and leaves the Feed. When you've seen everything, it says so.
//

import SwiftUI
import CourtKit
import CourtNet

struct FeedView: View {
    private let social = Social.shared
    @State private var showComposer = false
    @State private var viewingReplays: ReplayGroup?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                replaysRow
                let serves = social.liveFeed
                if serves.isEmpty {
                    ExampleServe()
                } else {
                    ForEach(serves) { serve in
                        NavigationLink(value: serve) { ServeCard(serve: serve) }
                            .buttonStyle(.plain)
                    }
                    CaughtUpFooter()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
        .courtGround()
        .navigationTitle("Feed")
        .navigationDestination(for: ServeRow.self) { serve in
            ServeDetailView(serveID: serve.id)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showComposer = true } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("New Serve")
            }
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { MyServesView() } label: { Image(systemName: "archivebox") }
                    .accessibilityLabel("Your Serves")
            }
        }
        .sheet(isPresented: $showComposer) { ServeComposerView() }
        .fullScreenCover(item: $viewingReplays) { group in
            ReplayViewer(replays: group.replays)
        }
        .refreshable {
            await social.refreshFeed()
            await social.refreshReplays()
        }
    }

    /// One bubble per friend, newest first; mine first if I have one.
    private var replaysRow: some View {
        let replays = social.liveReplays
        let byAuthor = Dictionary(grouping: replays, by: \.authorID)
        let authors = byAuthor.keys.sorted { a, b in
            if a == social.userID { return true }
            if b == social.userID { return false }
            return (byAuthor[a]?.first?.createdAt ?? .distantPast) > (byAuthor[b]?.first?.createdAt ?? .distantPast)
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("REPLAYS").eyebrowStyle()
            if authors.isEmpty {
                Text("Finish a match and post its Replay. It stays up for 24 hours.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(authors, id: \.self) { author in
                            let theirs = byAuthor[author] ?? []
                            Button {
                                viewingReplays = ReplayGroup(replays: theirs.sorted { $0.createdAt < $1.createdAt })
                            } label: {
                                VStack(spacing: 6) {
                                    ProfileAvatar(userID: author, size: 62)
                                        .padding(3)
                                        .overlay(
                                            Circle().trim(from: 0, to: ReplayLifetime.remaining(createdAt: theirs.first?.createdAt ?? Date()))
                                                .stroke(theirs.contains { $0.story.intensity > 0.5 } ? DS.Palette.gold : DS.Palette.electricBlue,
                                                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                                .rotationEffect(.degrees(-90))
                                        )
                                    Text(author == social.userID ? "You" : social.firstName(of: author))
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                                .frame(width: 72)
                            }
                            .buttonStyle(.press)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.top, 8)
    }
}

struct ReplayGroup: Identifiable {
    let id = UUID()
    let replays: [ReplayRow]
}

struct ServeCard: View {
    let serve: ServeRow
    private let social = Social.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProfileAvatar(userID: serve.authorID, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(social.name(of: serve.authorID)).font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(RelativeTime.short(serve.createdAt)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let body = serve.body {
                Text(body).font(.system(size: 16, design: .rounded)).foregroundStyle(.primary)
            }
            if serve.kind == .result, let matchID = serve.matchID, let record = MatchStore.shared.record(id: matchID) {
                MatchScoreCard(record: record)
            }
            if let first = serve.mediaPaths.first {
                RemotePhoto(path: first)
                    .frame(height: 240)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if serve.mediaPaths.count > 1 {
                            Text("+\(serve.mediaPaths.count - 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(Capsule().fill(.black.opacity(0.5)))
                                .padding(8)
                        }
                    }
            }
            HStack(spacing: 6) {
                Image(systemName: "arrow.left.arrow.right")
                Text(serve.rallyCount == 0 ? "Return it" : "Rally · \(serve.rallyCount)")
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(serve.rallyCount > 0 ? DS.Palette.electricBlue : .secondary)
        }
        .padding(16)
        .courtRaised()
    }
}

/// The end of the Feed. There's no more to scroll.
private struct CaughtUpFooter: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 30)).foregroundStyle(DS.Palette.win)
            Text("You’re all caught up").font(.system(size: 16, weight: .bold, design: .rounded))
            Text("Serves nobody returns for a day drop out. Go play.")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

/// What a Serve looks like, for an empty Feed.
private struct ExampleServe: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EXAMPLE").eyebrowStyle()
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Avatar(name: "Sam Rivera", color: DS.Palette.courtBlue, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Sam").font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("2h").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Came back from 3–9 to take the belt off Priya. Rematch Thursday?")
                    .font(.system(size: 16, design: .rounded))
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right")
                    Text("Rally · 6")
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Palette.electricBlue)
            }
            .padding(16)
            .courtRaised()
            .opacity(0.7)
            Text("Serves are posts only your friends see. Friends Return them with a comment, a chant or a photo. Every Return keeps the ball in play; no Returns for a day and it’s a dead ball.")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}

/// Your Serves, including dead balls (the archive).
struct MyServesView: View {
    private let social = Social.shared

    var body: some View {
        List {
            Group {
                ForEach(social.myServes) { serve in
                    NavigationLink {
                        ServeDetailView(serveID: serve.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(serve.body ?? (serve.kind == .result ? "Result" : "Photo"))
                                .lineLimit(2)
                            HStack(spacing: 6) {
                                Text(serve.createdAt.formatted(date: .abbreviated, time: .shortened))
                                Text("· Rally \(serve.rallyCount)")
                                if !serve.isInPlay() { Text("· Dead ball") }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { Task { await social.deleteServe(serve) } }
                    }
                }
            }
            .courtRows()
        }
        .courtList()
        .navigationTitle("Your Serves")
        .overlay {
            if social.myServes.isEmpty {
                ContentUnavailableView("No Serves yet", systemImage: "archivebox")
            }
        }
    }
}
