//
//  TournamentHistoryDetailView.swift
//  PickleBall
//
//  Created by sai praneeth reddy narala on 8/26/26.
import SwiftUI
import CourtKit

struct TournamentHistoryDetailView: View {
    let tournament: SavedTournament
    @Environment(\.dismiss) private var dismiss
    
    // Pure function to compute standings from saved matches
    private var computedStandings: [PlayerStanding] {
        var stats: [String: (points: Int, wins: Int, draws: Int, losses: Int, pointsFor: Int, pointsAgainst: Int)] = [:]
        
        for match in tournament.matches {
            guard let p1Games = match.player1GamesWon, let p2Games = match.player2GamesWon else { continue }
            
            if stats[match.player1] == nil { stats[match.player1] = (0, 0, 0, 0, 0, 0) }
            if stats[match.player2] == nil { stats[match.player2] = (0, 0, 0, 0, 0, 0) }
            
            let p1Points = match.gameScores != nil ? match.gameScores!.reduce(0) { $0 + $1.player1 } : p1Games
            let p2Points = match.gameScores != nil ? match.gameScores!.reduce(0) { $0 + $1.player2 } : p2Games
            
            stats[match.player1]!.pointsFor += p1Points
            stats[match.player1]!.pointsAgainst += p2Points
            stats[match.player2]!.pointsFor += p2Points
            stats[match.player2]!.pointsAgainst += p1Points
            
            if p1Games > p2Games {
                stats[match.player1]!.wins += 1; stats[match.player1]!.points += 2; stats[match.player2]!.losses += 1
            } else if p2Games > p1Games {
                stats[match.player2]!.wins += 1; stats[match.player2]!.points += 2; stats[match.player1]!.losses += 1
            } else {
                stats[match.player1]!.draws += 1; stats[match.player2]!.draws += 1
                stats[match.player1]!.points += 1; stats[match.player2]!.points += 1
            }
        }
        
        return stats.map { name, s in
            PlayerStanding(name: name, points: s.points, wins: s.wins, draws: s.draws,
                           losses: s.losses, pointsFor: s.pointsFor, pointsAgainst: s.pointsAgainst)
        }
        .sorted { a, b in
            if a.points != b.points { return a.points > b.points }
            if a.pointDifferential != b.pointDifferential { return a.pointDifferential > b.pointDifferential }
            return a.pointsFor > b.pointsFor
        }
    }
    
    // Color tokens
    private let royalBlue = DS.Palette.royalBlue
    private let cardWhite = Color(UIColor.secondarySystemGroupedBackground)
    private let textSecondary = Color.secondary
    private let stroke = Color.black.opacity(0.08)
    private let fieldGrey = Color(UIColor.systemGroupedBackground)
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Title Block
                VStack(alignment: .leading, spacing: 4) {
                    Text(tournament.displayTitle)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .tracking(-0.6)
                    
                    Text(tournament.createdAt.formatted(date: .long, time: .omitted))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                
                // Final Standings
                VStack(alignment: .leading, spacing: 12) {
                    Text("FINAL STANDINGS")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                    
                    VStack(spacing: 0) {
                        ForEach(Array(computedStandings.enumerated()), id: \.element.id) { rank, standing in
                            historyStandingRow(standing: standing, rank: rank + 1)
                            if rank < computedStandings.count - 1 {
                                Rectangle().fill(stroke).frame(height: 1).padding(.leading, 56)
                            }
                        }
                    }
                    .background(cardWhite)
                    .cornerRadius(14)
                    .padding(.horizontal, 20)
                }
                
                // Matches (Read-Only)
                VStack(alignment: .leading, spacing: 12) {
                    Text("MATCHES")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                    
                    VStack(spacing: 12) {
                        // Map saved matches to TournamentMatch to reuse Step 11 UI
                        let runMatches = tournament.matches.map { savedMatch in
                            TournamentMatch(
                                id: savedMatch.id, player1: savedMatch.player1, player2: savedMatch.player2,
                                player1GamesWon: savedMatch.player1GamesWon, player2GamesWon: savedMatch.player2GamesWon,
                                gameScores: savedMatch.gameScores
                            )
                        }
                        
                        // Sort by original shuffled order
                        let orderedMatches = tournament.shuffledOrder.isEmpty
                            ? runMatches
                            : runMatches.sorted {
                                let idx0 = tournament.shuffledOrder.firstIndex(of: $0.id) ?? 0
                                let idx1 = tournament.shuffledOrder.firstIndex(of: $1.id) ?? 0
                                return idx0 < idx1
                              }
                        
                        ForEach(orderedMatches.enumerated(), id: \.element.id) { index, match in
                            HistoryMatchRow(match: match, index: index)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 40)
        }
        .scrollContentBackground(.hidden)
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("History") { dismiss() }
            }
        }
    }
    
    private func historyStandingRow(standing: PlayerStanding, rank: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(rank == 1 ? .orange : .secondary)
                .frame(width: 22, alignment: .center)
            
            Text(standing.name)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Spacer()
            
            Text("\(standing.wins)–\(standing.losses)")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .monospacedDigit()
            
            Text(standing.pointDifferential >= 0 ? "+\(standing.pointDifferential)" : "\(standing.pointDifferential)")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }
}

// MARK: - Read-Only Expandable Match Row for History
struct HistoryMatchRow: View {
    let match: TournamentMatch
    let index: Int
    
    @State private var isExpanded = false
    
    private let royalBlue = DS.Palette.royalBlue
    private let cardWhite = Color(UIColor.secondarySystemGroupedBackground)
    private let textSecondary = Color.secondary
    private let stroke = Color.black.opacity(0.08)
    private let fieldGrey = Color(UIColor.systemGroupedBackground)
    
    var body: some View {
        Button {
            if match.isCompleted {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75, blendDuration: 0)) {
                    isExpanded.toggle()
                }
                isExpanded ? Haptics.light() : Haptics.soft()
            }
        } label: {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MATCH \(index + 1)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(textSecondary)
                            .tracking(1.0)
                        Text(match.player1)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(royalBlue)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    if match.isCompleted, let score = match.scoreText {
                        Text(score)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(royalBlue)
                            .monospacedDigit()
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Text(match.player2)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(royalBlue)
                            .lineLimit(1)
                            .multilineTextAlignment(.trailing)
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(textSecondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                
                if isExpanded && match.isCompleted {
                    matchDetailContent(match: match)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(cardWhite))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(stroke, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    @ViewBuilder
    private func matchDetailContent(match: TournamentMatch) -> some View {
        if let scores = match.gameScores, !scores.isEmpty {
            VStack(spacing: 0) {
                Rectangle().fill(stroke).frame(height: 1).padding(.horizontal, 16)
                
                VStack(spacing: 12) {
                    ForEach(Array(scores.enumerated()), id: \.offset) { index, game in
                        HStack {
                            Text("Game \(index + 1)")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(textSecondary)
                                .frame(width: 64, alignment: .leading)
                            
                            Spacer()
                            
                            let p1Won = game.player1 > game.player2
                            let p2Won = game.player2 > game.player1
                            
                            Text("\(game.player1)")
                                .font(.system(size: 16, weight: p1Won ? .bold : .medium, design: .rounded))
                                .foregroundColor(p1Won ? royalBlue : textSecondary.opacity(0.5))
                                .monospacedDigit()
                                .frame(width: 28, alignment: .trailing)
                            
                            Text("–")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundColor(textSecondary.opacity(0.4))
                                .padding(.horizontal, 4)
                            
                            Text("\(game.player2)")
                                .font(.system(size: 16, weight: p2Won ? .bold : .medium, design: .rounded))
                                .foregroundColor(p2Won ? royalBlue : textSecondary.opacity(0.5))
                                .monospacedDigit()
                                .frame(width: 28, alignment: .leading)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
                .background(fieldGrey.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .padding(.horizontal, 1)
                .padding(.bottom, 1)
            }
        }
    }
}
