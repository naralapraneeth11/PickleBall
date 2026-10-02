//
//  MatchDetailView.swift
//  PickleBall
//
//  One match: the score, where it stands with the other side, and what you
//  can do with it — confirm or dispute, post its Replay, Serve it to your
//  friends, send guests a link to claim it.
//

import SwiftUI
import CourtKit
import CourtNet

struct MatchDetailView: View {
    let record: MatchRecord
    @Environment(\.dismiss) private var dismiss
    private let social = Social.shared
    @State private var isWorking = false
    @State private var showServe = false
    @State private var postedReplay: ReplayRow?
    @State private var claimLink: ClaimLink?
    @State private var confirmWithdraw = false

    private var result: MatchResult? { record.result }
    private var me: PlayerID? { social.userID.map(PlayerID.init(rawValue:)) }
    private var isMine: Bool { record.createdByID == nil || record.createdByID == social.userID }
    private var needsMyAnswer: Bool { social.awaitingMyConfirmation.contains { $0.id == record.id } }
    private var drama: DramaReport? {
        guard let rules = record.rules else { return nil }
        return record.rallies.isEmpty
            ? DramaDetector.analyze(units: record.units, rules: rules, winner: record.winner)
            : DramaDetector.analyze(rules: rules, rallies: record.rallyLog)
    }

    var body: some View {
        List {
            Section {
                MatchScoreCard(record: record, headline: result.flatMap { r in drama?.headline(r.lineup) })
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if let rules = record.rules, !record.rallies.isEmpty {
                let insights = MatchInsights.compute(scorer: MatchScorer(rules: rules, rallies: record.rallyLog))
                if !insights.isEmpty {
                    Section {
                        MatchStatsCard(insights: insights, lineup: record.lineup, rules: rules)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
            }

            Section {
                Group {
                    LabeledContent("Status") { StatusBadge(confirmation: record.confirmation) }
                    LabeledContent("Scored", value: sourceText)
                    if let court = record.court { LabeledContent("Court", value: court.name) }
                    if let squad = social.squad(record.squadID) { LabeledContent("Squad", value: squad.name) }
                    if let recorder = record.createdByID, recorder != social.userID {
                        LabeledContent("Recorded by", value: social.name(of: recorder))
                    }
                }
                .courtRows()
            } footer: {
                Text(statusExplanation)
            }

            if needsMyAnswer {
                Section {
                    Group {
                        Button {
                            answer(true)
                        } label: {
                            Label("Confirm result", systemImage: "checkmark.seal.fill")
                                .fontWeight(.semibold)
                        }
                        Button(role: .destructive) {
                            answer(false)
                        } label: {
                            Label("Dispute", systemImage: "exclamationmark.bubble")
                        }
                    }
                    .courtRows()
                } footer: {
                    Text("Confirming makes it count for records and the Belt.")
                }
                .disabled(isWorking)
            }

            let events = MatchStore.shared.belts.events(for: record.id)
            if !events.isEmpty {
                Section("Belt") {
                    Group {
                        ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                            Label(social.beltLine(event), systemImage: "crown.fill")
                                .foregroundStyle(DS.Palette.gold)
                        }
                    }
                    .courtRows()
                }
            }

            if social.phase == .ready, record.lineup?.team(of: me ?? PlayerID()) != nil {
                Section("Share") {
                    Group {
                        Button {
                            Task { await postReplay() }
                        } label: {
                            Label(postedReplay == nil ? "Post Replay" : "Replay posted", systemImage: "play.rectangle.on.rectangle")
                        }
                        .disabled(postedReplay != nil || isWorking || record.confirmation == .disputed)
                        Button {
                            showServe = true
                        } label: {
                            Label("Serve this result", systemImage: "arrow.up.forward.circle")
                        }
                        .disabled(record.confirmation == .disputed)
                    }
                    .courtRows()
                }
            }

            let guests = record.lineup?.allPlayers.filter { $0.kind == .guest } ?? []
            if isMine, social.phase == .ready, !guests.isEmpty {
                Section {
                    Group {
                        ForEach(guests) { guest in
                            Button {
                                Task { await makeClaimLink(for: guest) }
                            } label: {
                                Label("Send \(guest.shortName) a claim link", systemImage: "link")
                            }
                        }
                    }
                    .courtRows()
                } header: {
                    Text("Guests")
                } footer: {
                    Text("When they sign up with the link, this match and every other one with them becomes theirs.")
                }
            }

            if isMine, record.confirmation == .pending || record.confirmation == .disputed {
                Section {
                    Group {
                        Button("Withdraw result", role: .destructive) { confirmWithdraw = true }
                    }
                    .courtRows()
                }
            } else if !isMine, social.phase == .ready {
                Section {
                    Group {
                        Button("Report", role: .destructive) {
                            Task { _ = await social.report(.match, id: record.id, reason: "Incorrect or abusive match") }
                        }
                    }
                    .courtRows()
                }
            }
        }
        .courtList()
        .navigationTitle(record.sport.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showServe) {
            ServeComposerView(matchID: record.id, matchSummary: result.map { "\($0.lineup.name(of: .a, separator: " & ")) vs \($0.lineup.name(of: .b, separator: " & ")) · \($0.scoreLine)" })
        }
        .sheet(item: $claimLink) { link in
            ShareLink(item: link.url, message: Text("Claim our match on PickleBall: \(link.url.absoluteString)")) {
                Label("Share claim link", systemImage: "square.and.arrow.up")
            }
            .presentationDetents([.height(160)])
        }
        .confirmationDialog("Withdraw this result?", isPresented: $confirmWithdraw, titleVisibility: .visible) {
            Button("Withdraw", role: .destructive) {
                Task {
                    await social.withdraw(record)
                    dismiss()
                }
            }
        }
    }

    private var sourceText: String {
        switch record.source {
        case .watch: return "On Apple Watch"
        case .phone: return "On iPhone"
        case .entered: return "Entered after"
        }
    }

    private var statusExplanation: String {
        switch record.confirmation {
        case .local: return social.phase == .ready ? "Sends as soon as there’s signal." : "Saved on this phone."
        case .pending: return needsMyAnswer ? "Your side hasn’t confirmed yet." : "Waiting for the other side to confirm."
        case .confirmed: return "Both sides agreed. It counts."
        case .disputed: return "Someone disputed this score. It doesn’t count until it’s fixed."
        }
    }

    private func answer(_ agree: Bool) {
        isWorking = true
        Haptics.medium()
        Task {
            await social.confirm(record, agree: agree)
            isWorking = false
        }
    }

    private func postReplay() async {
        isWorking = true
        postedReplay = await social.postReplay(for: record)
        isWorking = false
        if postedReplay != nil { Haptics.success() }
    }

    private func makeClaimLink(for guest: PlayerRef) async {
        guard let link = await social.inviteLink(.guestClaim, target: guest.id.rawValue) else { return }
        claimLink = ClaimLink(url: social.shareURL(for: link))
    }
}

private struct ClaimLink: Identifiable {
    let id = UUID()
    let url: URL
}

/// The score of a match as a card: names, games, winner highlighted.
struct MatchScoreCard: View {
    let record: MatchRecord
    var headline: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let headline {
                Text(headline)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Court.muted)
            }
            if let lineup = record.lineup {
                ForEach(Team.allCases, id: \.self) { team in
                    HStack(spacing: 10) {
                        Text(lineup.name(of: team, separator: " & "))
                            .font(.system(size: 17, weight: record.winner == team ? .bold : .medium, design: .rounded))
                            .foregroundStyle(record.winner == team ? Color.primary : Color.secondary)
                            .lineLimit(1)
                        if record.winner == team {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.Palette.win)
                        }
                        Spacer()
                        ForEach(Array(record.units.enumerated()), id: \.offset) { _, unit in
                            Text(unitText(unit, team: team))
                                .font(DS.Typography.score(20))
                                .foregroundStyle(unit.winner == team ? Color.primary : Color.secondary)
                                .frame(minWidth: 28)
                        }
                    }
                }
            }
            Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .courtRaised()
    }

    private func unitText(_ unit: CompletedUnit, team: Team) -> String {
        if unit.isSuperTiebreak, let tb = unit.tiebreak { return "\(tb[team])" }
        return "\(unit.score[team])"
    }
}

/// Shown right after a typed-in score is saved.
struct MatchSavedView: View {
    let record: MatchRecord
    @Environment(\.dismiss) private var dismiss
    private let social = Social.shared

    var body: some View {
        NavigationStack {
            MatchDetailView(record: record)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
        .sharePromptHost()
        .onAppear {
            // Guests-only results count at once; show the card if it's big.
            if let result = record.result, let rules = record.rules {
                let drama = DramaDetector.analyze(units: record.units, rules: rules, winner: record.winner)
                if drama.isBigComeback { social.offerShareCard(for: result, beltEvents: [], drama: drama) }
            }
        }
    }
}
