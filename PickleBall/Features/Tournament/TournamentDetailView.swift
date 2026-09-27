//
//  TournamentDetailView.swift
//  PickleBall
//
//  A squad tournament: live standings, the schedule (anyone can set a time
//  or court, anyone can score any match), King of the Court rounds, and
//  the champion's moment. Results post to the squad chat and count for
//  the Belt like any other squad match.
//

import SwiftUI
import SwiftData
import CourtKit
import CourtNet

struct TournamentDetailView: View {
    let tournamentID: UUID
    private let social = Social.shared
    @State private var playPrefill: MatchPrefill?
    @State private var enterPrefill: MatchPrefill?
    @State private var americanoFixture: FixtureRow?
    @State private var scheduling: FixtureRow?
    @State private var champions: [PlayerID]?
    @State private var isWorking = false

    private var tournament: TournamentRow? { social.tournaments.first { $0.id == tournamentID } }

    var body: some View {
        if let tournament {
            content(tournament)
        } else {
            ContentUnavailableView("Tournament not found", systemImage: "trophy")
        }
    }

    private func content(_ tournament: TournamentRow) -> some View {
        let fixtures = social.fixtures(of: tournament)
        let scores = social.scores(of: tournament)
        let standings = social.standings(of: tournament)
        let rounds = Dictionary(grouping: fixtures, by: \.round).sorted { $0.key < $1.key }
        let allPlayed = !fixtures.isEmpty && fixtures.allSatisfy { scores[$0.id] != nil }
        let lastRoundDone = rounds.last.map { $0.value.allSatisfy { scores[$0.id] != nil } } ?? false

        return List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(social.squad(tournament.squadID)?.name ?? "Squad") · \(tournament.format.title)")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                    Text(tournament.rules.summary)
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                    if tournament.status == .completed {
                        Label("Won by \(tournament.champions.map(social.firstName(of:)).joined(separator: " & "))", systemImage: "trophy.fill")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.Palette.gold)
                            .padding(.top, 6)
                    }
                }
            }

            Section(tournament.format == .americano ? "Standings · points" : "Standings") {
                ForEach(standings) { row in
                    HStack(spacing: 10) {
                        Text("\(row.rank)")
                            .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(row.rank == 1 ? DS.Palette.gold : .secondary)
                            .frame(width: 22)
                        Text(row.entrant.map { social.firstName(of: $0.rawValue) }.joined(separator: " & "))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Spacer()
                        if tournament.format == .americano {
                            Text("\(row.pointsFor)").font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                        } else {
                            Text("\(row.wins)–\(row.losses)").font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                            Text(row.pointDifference >= 0 ? "+\(row.pointDifference)" : "\(row.pointDifference)")
                                .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }

            ForEach(rounds, id: \.key) { round, roundFixtures in
                Section("Round \(round)") {
                    ForEach(roundFixtures) { fixture in
                        FixtureRowView(tournament: tournament, fixture: fixture, score: scores[fixture.id],
                                       onPlay: { playPrefill = MatchPrefill(tournament: tournament, fixture: fixture, social: social) },
                                       onEnter: {
                                           if tournament.format == .americano {
                                               americanoFixture = fixture
                                           } else {
                                               enterPrefill = MatchPrefill(tournament: tournament, fixture: fixture, social: social)
                                           }
                                       },
                                       onSchedule: { scheduling = fixture })
                    }
                }
            }

            if tournament.status == .active {
                Section {
                    if tournament.format == .kingOfTheCourt {
                        Button {
                            run { await social.startNextRound(of: tournament) }
                        } label: {
                            Label("Start the next round", systemImage: "arrow.up.arrow.down")
                        }
                        .disabled(!lastRoundDone || isWorking)
                    }
                    Button {
                        run {
                            if let won = await social.complete(tournament) { champions = won }
                        }
                    } label: {
                        Label("Finish and crown the champion", systemImage: "trophy.fill")
                            .fontWeight(.semibold)
                    }
                    .disabled(!allPlayed || isWorking)
                } footer: {
                    Text(allPlayed ? "Everyone’s played. Time to crown the champion." : "Finish every match to crown the champion.")
                }
            }
        }
        .navigationTitle(tournament.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await social.refreshTournaments()
            await social.refreshMatches()
        }
        .fullScreenCover(item: $playPrefill) { prefill in
            PlayView(onDismiss: { playPrefill = nil }, prefill: prefill)
        }
        .sheet(item: $enterPrefill) { prefill in
            EnterScoreView(prefill: prefill)
        }
        .sheet(item: $americanoFixture) { fixture in
            AmericanoScoreView(tournament: tournament, fixture: fixture)
        }
        .sheet(item: $scheduling) { fixture in
            ScheduleFixtureView(fixture: fixture)
        }
        .fullScreenCover(isPresented: Binding(get: { champions != nil }, set: { if !$0 { champions = nil } })) {
            championView(tournament, standings: standings)
        }
    }

    private func championView(_ tournament: TournamentRow, standings: [StandingRow]) -> some View {
        let podium = standings.prefix(3).map { row in
            PlayerStanding(name: row.entrant.map { social.firstName(of: $0.rawValue) }.joined(separator: " & "),
                           points: tournament.format == .americano ? row.pointsFor : row.wins,
                           wins: row.wins, draws: 0, losses: row.losses, pointsFor: row.pointsFor, pointsAgainst: row.pointsAgainst)
        }
        let ordered = podium.count >= 3 ? [podium[1], podium[0], podium[2]] : podium
        return TournamentChampionView(champion: podium.first ?? PlayerStanding(name: "", points: 0, wins: 0, draws: 0, losses: 0, pointsFor: 0, pointsAgainst: 0),
                                      podium: ordered) {
            champions = nil
        }
    }

    private func run(_ work: @escaping () async -> Void) {
        isWorking = true
        Task {
            await work()
            isWorking = false
        }
    }
}

private struct FixtureRowView: View {
    let tournament: TournamentRow
    let fixture: FixtureRow
    let score: FixtureScore?
    let onPlay: () -> Void
    let onEnter: () -> Void
    let onSchedule: () -> Void
    private let social = Social.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    side(fixture.teamA, won: score?.winner == .a)
                    side(fixture.teamB, won: score?.winner == .b)
                }
                Spacer()
                if let score {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(score.score.a)").font(DS.Typography.score(18))
                        Text("\(score.score.b)").font(DS.Typography.score(18))
                    }
                }
            }
            HStack(spacing: 6) {
                Text(details)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if score == nil, tournament.status == .active {
                    Menu {
                        if tournament.format != .americano {
                            Button { onPlay() } label: { Label("Score it live", systemImage: "play.fill") }
                        }
                        Button { onEnter() } label: { Label("Enter the score", systemImage: "square.and.pencil") }
                        Button { onSchedule() } label: { Label("Set time or court", systemImage: "calendar") }
                    } label: {
                        Text("Score")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(DS.Palette.electricBlue.opacity(0.12)))
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func side(_ ids: [UUID], won: Bool) -> some View {
        Text(ids.map(social.firstName(of:)).joined(separator: " & "))
            .font(.system(size: 15, weight: won ? .bold : .medium, design: .rounded))
            .foregroundStyle(won || score == nil ? Color.primary : Color.secondary)
    }

    private var details: String {
        var parts: [String] = []
        if tournament.format == .kingOfTheCourt { parts.append(fixture.courtNumber == 1 ? "King court" : "Court \(fixture.courtNumber)") }
        else if fixture.courtNumber > 1 { parts.append("Court \(fixture.courtNumber)") }
        if let date = fixture.scheduledAt { parts.append(RelativeTime.upcoming(date)) }
        if let court = fixture.court { parts.append(court.name) }
        return parts.joined(separator: " · ")
    }
}

/// Americano: each match is a race to a points total; every point counts.
private struct AmericanoScoreView: View {
    let tournament: TournamentRow
    let fixture: FixtureRow
    @Environment(\.dismiss) private var dismiss
    private let social = Social.shared
    @State private var a = ""
    @State private var b = ""

    private var valid: Bool {
        guard let x = Int(a), let y = Int(b) else { return false }
        return x != y && x >= 0 && y >= 0 && x + y > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(fixture.teamA.map(social.firstName(of:)).joined(separator: " & ")) {
                        TextField("0", text: $a).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent(fixture.teamB.map(social.firstName(of:)).joined(separator: " & ")) {
                        TextField("0", text: $b).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Points each pair won. Every point counts for both partners.")
                }
            }
            .navigationTitle("Round \(fixture.round)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!valid) }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard let x = Int(a), let y = Int(b) else { return }
        let points = TeamPair(a: x, b: y)
        let winner: Team = x > y ? .a : .b
        let score = EnteredScore(units: [CompletedUnit(score: points)], winner: winner,
                                 matchScore: TeamPair(a: winner == .a ? 1 : 0, b: winner == .b ? 1 : 0), pointsWon: points)
        let lineup = Lineup(teamA: fixture.teamA.map(social.playerRef(for:)), teamB: fixture.teamB.map(social.playerRef(for:)))
        let context = MatchContext(court: fixture.court, squadID: tournament.squadID, tournamentID: tournament.id, fixtureID: fixture.id)
        let record = MatchRecord(entered: score, rules: tournament.rules, lineup: lineup, playedAt: Date(), context: context)
        AppDatabase.context.insert(record)
        AppDatabase.save()
        PlayerDirectory.shared.adopt(lineup)
        MatchStore.shared.reload()
        Haptics.success()
        Task { await social.upload(record) }
        dismiss()
    }
}

private struct ScheduleFixtureView: View {
    let fixture: FixtureRow
    @Environment(\.dismiss) private var dismiss
    private let social = Social.shared
    @State private var date = Date()
    @State private var hasDate = true
    @State private var court: CourtTag?

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Set a time", isOn: $hasDate)
                if hasDate { DatePicker("When", selection: $date) }
                CourtPickerRow(court: $court)
            }
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await social.schedule(fixture, at: hasDate ? date : nil, court: court)
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                date = fixture.scheduledAt ?? Date()
                hasDate = true
                court = fixture.court
            }
        }
        .presentationDetents([.medium])
    }
}
