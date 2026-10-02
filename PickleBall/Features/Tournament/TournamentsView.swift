//
//  TournamentsView.swift
//  PickleBall
//
//  Squad tournaments: what's on, what's coming, and past champions.
//

import SwiftUI
import CourtKit
import CourtNet

struct TournamentsView: View {
    private let social = Social.shared
    @State private var showCreate = false

    var body: some View {
        List {
            let active = social.tournaments.filter { $0.status == .active }
            let done = social.tournaments.filter { $0.status == .completed }
            if !active.isEmpty {
                Section("On now") {
                    ForEach(active) { tournament in
                        NavigationLink(value: tournament) { TournamentListRow(tournament: tournament) }
                    }
                }
            }
            if !done.isEmpty {
                Section("Finished") {
                    ForEach(done) { tournament in
                        NavigationLink(value: tournament) { TournamentListRow(tournament: tournament) }
                    }
                }
            }
        }
        .courtList()
        .navigationTitle("Tournaments")
        .navigationDestination(for: TournamentRow.self) { tournament in
            TournamentDetailView(tournamentID: tournament.id)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New tournament")
                    .disabled(social.squads.isEmpty)
            }
        }
        .sheet(isPresented: $showCreate) { CreateTournamentView() }
        .refreshable { await social.refreshTournaments() }
        .overlay {
            if social.tournaments.isEmpty {
                ContentUnavailableView {
                    Label("No tournaments yet", systemImage: "trophy")
                } description: {
                    Text(social.squads.isEmpty
                         ? "Tournaments belong to a squad. Start a squad in Chats, then run one here."
                         : "Round robin, King of the Court or padel Americano, straight from your squad.")
                } actions: {
                    if !social.squads.isEmpty {
                        Button("New tournament") { showCreate = true }.buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }
}

private struct TournamentListRow: View {
    let tournament: TournamentRow
    private let social = Social.shared

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tournament.status == .completed ? DS.Palette.gold.opacity(0.2) : tournament.sport.theme.accent.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: tournament.status == .completed ? "trophy.fill" : "calendar")
                    .foregroundStyle(tournament.status == .completed ? DS.Palette.gold : tournament.sport.theme.accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(tournament.name).font(.system(size: 16, weight: .semibold, design: .rounded))
                Text(subtitle).font(DS.Typography.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var subtitle: String {
        let squad = social.squad(tournament.squadID)?.name ?? "Squad"
        if tournament.status == .completed {
            let champions = tournament.champions.map(social.firstName(of:)).joined(separator: " & ")
            return "\(squad) · Won by \(champions)"
        }
        let fixtures = social.fixtures(of: tournament)
        let played = social.scores(of: tournament).count
        return "\(squad) · \(tournament.format.title) · \(played)/\(fixtures.count) played"
    }
}
