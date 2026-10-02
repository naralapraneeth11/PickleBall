//
//  TournamentDetailView.swift
//  PickleBall
//
//  A squad tournament: live standings or the bracket, pool tables, the
//  schedule (anyone can set a time or court, anyone can score any match),
//  King of the Court and Mexicano rounds, a live page to share, and the
//  champion's moment. Results post to the squad chat and count for
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
    @State private var pointsFixture: FixtureRow?
    @State private var scheduling: FixtureRow?
    @State private var champions: [PlayerID]?
    @State private var isWorking = false
    @State private var shareURL: IdentifiedURL?

    private var tournament: TournamentRow? { social.tournaments.first { $0.id == tournamentID } }

    var body: some View {
        if let tournament {
            content(tournament)
        } else {
            ContentUnavailableView("Tournament not found", systemImage: "trophy")
        }
    }

    private func content(_ tournament: TournamentRow) -> some View {
        let format = tournament.format
        let fixtures = social.fixtures(of: tournament)
        let scores = social.scores(of: tournament)
        let standings = social.standings(of: tournament)
        let bracket = social.bracket(of: tournament)
        let league = fixtures.filter { ($0.stage ?? .main) == .main }
        let rounds = Dictionary(grouping: league, by: \.round).sorted { $0.key < $1.key }
        let decided = social.champions(of: tournament) != nil

        return List {
            Section {
                Group {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(social.squad(tournament.squadID)?.name ?? "Squad") · \(format.title)")
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                        Text(tournament.rules.summary)
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                        if format == .mexicano {
                            Text("Round \(rounds.last?.key ?? 1) of \(tournament.settings?.rounds ?? 6)")
                                .font(DS.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                        if tournament.status == .completed {
                            Label("Won by \(tournament.champions.map(social.firstName(of:)).joined(separator: " & "))", systemImage: "trophy.fill")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Palette.gold)
                                .padding(.top, 6)
                        }
                    }
                }
                .courtRows()
            }

            if format == .pools {
                poolSections(tournament, fixtures: fixtures, scores: scores)
            } else if !format.isBracket {
                standingsSection(format, standings: standings)
            }

            if let bracket {
                Section(format == .pools ? "Knockout" : "Bracket") {
                    Group {
                        BracketView(state: bracket, fixtures: fixtures, scores: scores, isActive: tournament.status == .active,
                                    onPlay: { playPrefill = MatchPrefill(tournament: tournament, fixture: $0, social: social) },
                                    onEnter: { enter($0, in: tournament) },
                                    onSchedule: { scheduling = $0 })
                            .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                    }
                    .courtRows()
                }
            } else if format == .pools {
                Section {
                    Group {
                        Label("The knockout starts when every pool match is in.", systemImage: "arrow.triangle.branch")
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    .courtRows()
                }
            }

            if !format.isBracket && format != .pools {
                ForEach(rounds, id: \.key) { round, roundFixtures in
                    Section("Round \(round)") {
                        Group {
                            ForEach(roundFixtures) { fixture in
                                fixtureRow(tournament, fixture, score: scores[fixture.id])
                            }
                        }
                        .courtRows()
                    }
                }
            }

            if tournament.status == .active {
                Section {
                    Group {
                        if format == .kingOfTheCourt || format == .mexicano {
                            Button {
                                run { await social.startNextRound(of: tournament) }
                            } label: {
                                Label("Start the next round", systemImage: format == .mexicano ? "shuffle" : "arrow.up.arrow.down")
                            }
                            .disabled(!social.canStartNextRound(of: tournament) || isWorking)
                        }
                        Button {
                            run {
                                if let won = await social.complete(tournament) { champions = won }
                            }
                        } label: {
                            Label("Finish and crown the champion", systemImage: "trophy.fill")
                                .fontWeight(.semibold)
                        }
                        .disabled(!decided || isWorking)
                    }
                    .courtRows()
                } footer: {
                    Text(decided ? "It’s decided. Time to crown the champion." : "Finish every match to crown the champion.")
                }
            }
        }
        .navigationTitle(tournament.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        if let url = await social.shareLink(.tournament, target: tournament.id) { shareURL = IdentifiedURL(url: url) }
                    }
                } label: {
                    Label("Share live page", systemImage: "square.and.arrow.up")
                }
            }
        }
        .refreshable {
            await social.refreshTournaments()
            await social.refreshMatches()
            await social.advanceTournaments()
        }
        .fullScreenCover(item: $playPrefill) { prefill in
            PlayView(onDismiss: { playPrefill = nil }, prefill: prefill)
        }
        .sheet(item: $enterPrefill) { prefill in
            EnterScoreView(prefill: prefill)
        }
        .sheet(item: $pointsFixture) { fixture in
            AmericanoScoreView(tournament: tournament, fixture: fixture)
        }
        .sheet(item: $scheduling) { fixture in
            ScheduleFixtureView(fixture: fixture)
        }
        .sheet(item: $shareURL) { item in
            ShareSheet(items: [String(localized: "Follow \(tournament.name) live"), item.url])
                .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: Binding(get: { champions != nil }, set: { if !$0 { champions = nil } })) {
            championView(tournament, standings: standings, bracket: bracket)
        }
    }

    private func standingsSection(_ format: TournamentFormat, standings: [StandingRow]) -> some View {
        Section(format.ranksByPoints ? "Standings · points" : "Standings") {
            Group {
                ForEach(standings) { row in
                    StandingLine(row: row, byPoints: format.ranksByPoints)
                }
            }
            .courtRows()
        }
    }

    @ViewBuilder
    private func poolSections(_ tournament: TournamentRow, fixtures: [FixtureRow], scores: [UUID: FixtureScore]) -> some View {
        let pools = social.pools(of: tournament)
        let tables = Pools.standings(pools: pools, fixtures: fixtures.map(\.fixture), scores: scores)
        let advancing = tournament.settings?.advancing ?? Pools.suggestedAdvancing(entrants: pools.joined().count, pools: pools.count)
        ForEach(Array(tables.enumerated()), id: \.offset) { index, table in
            Section {
                Group {
                    ForEach(table) { row in
                        StandingLine(row: row, byPoints: false, qualifies: row.rank <= advancing)
                    }
                    ForEach(fixtures.filter { $0.stage == .pool && $0.pool == index }) { fixture in
                        fixtureRow(tournament, fixture, score: scores[fixture.id])
                    }
                }
                .courtRows()
            } header: {
                Text("Pool \(Self.poolLetter(index))")
            } footer: {
                if index == tables.count - 1 {
                    Text("Top \(advancing) in each pool go through to the knockout.")
                }
            }
        }
    }

    static func poolLetter(_ index: Int) -> String {
        String(UnicodeScalar(UInt8(65 + index % 26)))
    }

    private func fixtureRow(_ tournament: TournamentRow, _ fixture: FixtureRow, score: FixtureScore?) -> some View {
        FixtureRowView(tournament: tournament, fixture: fixture, score: score,
                       onPlay: { playPrefill = MatchPrefill(tournament: tournament, fixture: fixture, social: social) },
                       onEnter: { enter(fixture, in: tournament) },
                       onSchedule: { scheduling = fixture })
    }

    private func enter(_ fixture: FixtureRow, in tournament: TournamentRow) {
        if tournament.format.ranksByPoints {
            pointsFixture = fixture
        } else {
            enterPrefill = MatchPrefill(tournament: tournament, fixture: fixture, social: social)
        }
    }

    private func championView(_ tournament: TournamentRow, standings: [StandingRow], bracket: Bracket.State?) -> some View {
        let name = { (ids: [PlayerID]) in ids.map { social.firstName(of: $0.rawValue) }.joined(separator: " & ") }
        let podium: [PlayerStanding]
        if let bracket, let champion = bracket.champion {
            podium = ([champion] + (bracket.runnerUp.map { [$0] } ?? [])).map {
                PlayerStanding(name: name($0), points: 0, wins: 0, draws: 0, losses: 0, pointsFor: 0, pointsAgainst: 0)
            }
        } else {
            podium = standings.prefix(3).map { row in
                PlayerStanding(name: name(row.entrant),
                               points: tournament.format.ranksByPoints ? row.pointsFor : row.wins,
                               wins: row.wins, draws: 0, losses: row.losses, pointsFor: row.pointsFor, pointsAgainst: row.pointsAgainst)
            }
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

private struct StandingLine: View {
    let row: StandingRow
    let byPoints: Bool
    var qualifies = false
    private let social = Social.shared

    var body: some View {
        HStack(spacing: 10) {
            Text("\(row.rank)")
                .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(row.rank == 1 ? DS.Palette.gold : .secondary)
                .frame(width: 22)
            Text(row.entrant.map { social.firstName(of: $0.rawValue) }.joined(separator: " & "))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .lineLimit(1)
            if qualifies {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Palette.win)
                    .accessibilityLabel("Goes through")
            }
            Spacer()
            if byPoints {
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
                        if !tournament.format.ranksByPoints {
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
        if tournament.format == .kingOfTheCourt { parts.append(fixture.courtNumber == 1 ? String(localized: "King court") : String(localized: "Court \(fixture.courtNumber)")) }
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
                    Group {
                        LabeledContent(fixture.teamA.map(social.firstName(of:)).joined(separator: " & ")) {
                            TextField("0", text: $a).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        }
                        LabeledContent(fixture.teamB.map(social.firstName(of:)).joined(separator: " & ")) {
                            TextField("0", text: $b).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        }
                    }
                    .courtRows()
                } footer: {
                    Text("Points each pair won. Every point counts for both partners.")
                }
            }
            .courtList()
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
            .courtList()
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
