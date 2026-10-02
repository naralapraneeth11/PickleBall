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
    @State private var showCreateSquad = false

    var body: some View {
        List {
            let active = social.tournaments.filter { $0.status == .active }
            let done = social.tournaments.filter { $0.status == .completed }
            if !active.isEmpty {
                Section("On now") {
                    Group {
                        ForEach(active) { tournament in
                            NavigationLink(value: tournament) { TournamentListRow(tournament: tournament) }
                        }
                    }
                    .courtRows()
                }
            }
            if !done.isEmpty {
                Section("Finished") {
                    Group {
                        ForEach(done) { tournament in
                            NavigationLink(value: tournament) { TournamentListRow(tournament: tournament) }
                        }
                    }
                    .courtRows()
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
                Button {
                    if social.squads.isEmpty { showCreateSquad = true } else { showCreate = true }
                } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New tournament")
            }
        }
        .sheet(isPresented: $showCreate) { CreateTournamentView() }
        .sheet(isPresented: $showCreateSquad, onDismiss: {
            // Straight on to the tournament once the squad exists.
            if !social.squads.isEmpty { showCreate = true }
        }) { CreateSquadView() }
        .refreshable { await social.refreshTournaments() }
        .overlay {
            if social.tournaments.isEmpty {
                ContentUnavailableView {
                    Label("No tournaments yet", systemImage: "trophy")
                } description: {
                    Text(social.squads.isEmpty
                         ? "Tournaments belong to a squad. Start one with the people you play, then run a tournament here."
                         : "Round robin, King of the Court or padel Americano, straight from your squad.")
                } actions: {
                    Button {
                        if social.squads.isEmpty { showCreateSquad = true } else { showCreate = true }
                    } label: {
                        Text(social.squads.isEmpty ? "Start a squad" : "New tournament")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Court.text)
                            .padding(.horizontal, 22)
                            .frame(height: 48)
                            .courtRaisedCapsule()
                    }
                    .buttonStyle(.press)
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
                    .fill(tournament.status == .completed ? DS.Palette.gold.opacity(0.2) : Court.sunken)
                    .frame(width: 44, height: 44)
                Image(systemName: tournament.status == .completed ? "trophy.fill" : "calendar")
                    .foregroundStyle(tournament.status == .completed ? DS.Palette.gold : Court.text)
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
