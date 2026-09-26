//
//  Untitled.swift
//  PickleBall
//
//  Created by sai praneeth reddy narala on 8/26/26.
import SwiftUI

struct TournamentHistoryView: View {
    @ObservedObject private var tournamentStore = TournamentStore.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var tournamentToDelete: SavedTournament?
    
    // Filter and sort: completed, newest first
    private var completedTournaments: [SavedTournament] {
        tournamentStore.tournaments
            .filter { $0.isComplete }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                
                if completedTournaments.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(completedTournaments) { tournament in
                            NavigationLink(destination: TournamentHistoryDetailView(tournament: tournament)) {
                                historyRow(tournament: tournament)
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            // Explicit, non-accidental swipe-to-delete
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    tournamentToDelete = tournament
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Delete Tournament?", isPresented: .constant(tournamentToDelete != nil)) {
                Button("Cancel", role: .cancel) { tournamentToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let t = tournamentToDelete {
                        tournamentStore.delete(id: t.id)
                        tournamentToDelete = nil
                    }
                }
            } message: {
                Text("This will permanently remove this tournament from your history.")
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "trophy")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No completed tournaments yet")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func historyRow(tournament: SavedTournament) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Date (Primary anchor)
            Text(tournament.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
            
            // Title / Winner (Secondary)
            Text(tournament.resolvedTitle)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            // Format (Tertiary, quiet)
            Text(formatString(for: tournament))
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(.secondary.opacity(0.8))
                .lineLimit(1)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .padding(.horizontal, 16)
        .contentShape(Rectangle()) // Ensures the whole row is tappable
    }
    
    private func formatString(for tournament: SavedTournament) -> String {
        let type = tournament.isSingles ? "Singles" : "Doubles"
        return "\(type) · \(tournament.targetScore)-point · Best of \(tournament.bestOf)"
    }
}

