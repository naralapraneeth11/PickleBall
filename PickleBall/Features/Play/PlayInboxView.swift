//
//  PlayInboxView.swift
//  PickleBall
//
//  Everything on the Play tab that wants an answer: results to confirm,
//  call outs, upcoming matches, and friends playing right now.
//

import SwiftUI
import CourtKit
import CourtNet

struct PlayInboxItem: Identifiable {
    enum Kind {
        case confirm(MatchRecord)
        case callOut(CallOutRow)
        case upcoming(UpcomingMatch)
        case live(LiveMatchRow)
    }

    let id: String
    let title: String
    let symbol: String
    let kind: Kind

    @MainActor
    static func all(social: Social) -> [PlayInboxItem] {
        var items: [PlayInboxItem] = []
        for record in social.awaitingMyConfirmation {
            let names = record.lineup.map { "\($0.shortName(of: .a)) vs \($0.shortName(of: .b))" } ?? "A result"
            items.append(PlayInboxItem(id: "confirm-\(record.id)", title: "Confirm: \(names)", symbol: "checkmark.seal.fill", kind: .confirm(record)))
        }
        for callOut in social.callOutsAwaitingMe {
            let who = callOut.challengers.map(social.firstName(of:)).joined(separator: " & ")
            items.append(PlayInboxItem(id: "callout-\(callOut.id)", title: "\(who) called you out", symbol: "flag.2.crossed.fill", kind: .callOut(callOut)))
        }
        for live in social.liveMatches {
            items.append(PlayInboxItem(id: "live-\(live.matchID)", title: "Live: \(live.lineup.shortName(of: .a)) vs \(live.lineup.shortName(of: .b))",
                                       symbol: "dot.radiowaves.left.and.right", kind: .live(live)))
        }
        if let next = social.upcoming.first {
            items.append(PlayInboxItem(id: "upcoming-\(next.id)", title: "Next: \(next.title)", symbol: "calendar", kind: .upcoming(next)))
        }
        return items
    }
}

struct PlayInboxView: View {
    @Environment(\.dismiss) private var dismiss
    private let social = Social.shared
    @State private var prefill: MatchPrefill?
    @State private var enterPrefill: MatchPrefill?
    @State private var following: LiveMatchRow?

    var body: some View {
        List {
            let confirm = social.awaitingMyConfirmation
            if !confirm.isEmpty {
                Section("Confirm results") {
                    ForEach(confirm) { record in
                        NavigationLink {
                            MatchDetailView(record: record)
                        } label: {
                            ResultRow(record: record)
                        }
                    }
                }
            }

            let callOuts = social.activeCallOuts
            if !callOuts.isEmpty {
                Section("Call outs") {
                    ForEach(callOuts) { callOut in
                        CallOutCard(callOut: callOut, onPlay: { prefill = MatchPrefill(callOut: callOut, social: social) },
                                    onEnterScore: { enterPrefill = MatchPrefill(callOut: callOut, social: social) })
                    }
                }
            }

            if !social.liveMatches.isEmpty {
                Section("Live now") {
                    ForEach(social.liveMatches) { live in
                        Button { following = live } label: { LiveRow(live: live) }
                    }
                }
            }

            let upcoming = social.upcoming
            if !upcoming.isEmpty {
                Section("Upcoming") {
                    ForEach(upcoming) { match in
                        UpcomingRow(match: match) {
                            prefill = MatchPrefill(upcoming: match, social: social)
                        } onEnterScore: {
                            enterPrefill = MatchPrefill(upcoming: match, social: social)
                        }
                    }
                }
            }

            let waiting = social.awaitingTheirConfirmation
            if !waiting.isEmpty {
                Section("Waiting on them") {
                    ForEach(waiting) { record in
                        NavigationLink {
                            MatchDetailView(record: record)
                        } label: {
                            ResultRow(record: record)
                        }
                    }
                }
            }

            if confirm.isEmpty && callOuts.isEmpty && upcoming.isEmpty && waiting.isEmpty && social.liveMatches.isEmpty {
                ContentUnavailableView("All clear", systemImage: "checkmark.circle",
                                       description: Text("Results to confirm, call outs and upcoming matches show up here."))
            }
        }
        .navigationTitle("Play")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .refreshable { await social.refreshAll() }
        .fullScreenCover(item: $prefill) { prefill in
            PlayView(onDismiss: { self.prefill = nil }, prefill: prefill)
        }
        .sheet(item: $enterPrefill) { prefill in
            EnterScoreView(prefill: prefill)
        }
        .fullScreenCover(item: $following) { live in
            LiveFollowView(live: live)
        }
    }
}

// MARK: - Rows

struct ResultRow: View {
    let record: MatchRecord

    var body: some View {
        HStack(spacing: 12) {
            BallIcon(sport: record.sport, size: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.lineup.map { "\($0.name(of: .a, separator: " & ")) vs \($0.name(of: .b, separator: " & "))" } ?? "Match")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(subtitle)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            StatusBadge(confirmation: record.confirmation)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let score = record.result?.scoreLine ?? ""
        let date = record.startedAt.formatted(.dateTime.month(.abbreviated).day())
        return [score, date, record.court?.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct StatusBadge: View {
    let confirmation: MatchConfirmation

    var body: some View {
        let (text, color): (String, Color) = {
            switch confirmation {
            case .local: return ("Sending", DS.Palette.textMuted)
            case .pending: return ("Pending", DS.Palette.warning)
            case .confirmed: return ("Confirmed", DS.Palette.win)
            case .disputed: return ("Disputed", DS.Palette.loss)
            }
        }()
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

struct LiveRow: View {
    let live: LiveMatchRow

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(DS.Palette.loss).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(live.lineup.name(of: .a, separator: " & ")) vs \(live.lineup.name(of: .b, separator: " & "))")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(live.score.history.isEmpty ? live.score.phaseTitle : live.score.history)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(live.score.points.a)–\(live.score.points.b)")
                .font(DS.Typography.score(22))
                .foregroundStyle(.primary)
        }
    }
}

struct UpcomingRow: View {
    let match: UpcomingMatch
    let onPlay: () -> Void
    let onEnterScore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(match.title).font(.system(size: 15, weight: .semibold, design: .rounded))
            Text([RelativeTime.upcoming(match.date), match.court?.name, match.subtitle].compactMap { $0 }.joined(separator: " · "))
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
            HStack {
                PillButton(title: "Start match", systemImage: "play.fill", prominent: true, action: onPlay)
                PillButton(title: "Enter score", systemImage: "square.and.pencil", action: onEnterScore)
            }
        }
        .padding(.vertical, 4)
    }
}

/// What a match started from a call out or a tournament fixture carries.
struct MatchPrefill: Identifiable {
    let id = UUID()
    var rules: MatchRules
    var lineup: Lineup
    var context: MatchContext

    @MainActor
    init(callOut: CallOutRow, social: Social) {
        rules = callOut.rules
        lineup = social.lineup(for: callOut)
        context = MatchContext(court: callOut.court, squadID: callOut.squadID, calloutID: callOut.id)
    }

    @MainActor
    init(tournament: TournamentRow, fixture: FixtureRow, social: Social) {
        rules = tournament.rules
        lineup = Lineup(teamA: fixture.teamA.map(social.playerRef(for:)), teamB: fixture.teamB.map(social.playerRef(for:)))
        context = MatchContext(court: fixture.court, squadID: tournament.squadID, tournamentID: tournament.id, fixtureID: fixture.id)
    }

    @MainActor
    init(upcoming: UpcomingMatch, social: Social) {
        switch upcoming.kind {
        case .callOut(let row): self.init(callOut: row, social: social)
        case .fixture(let tournament, let fixture): self.init(tournament: tournament, fixture: fixture, social: social)
        }
    }
}
