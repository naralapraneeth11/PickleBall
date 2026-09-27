//
//  TournamentRunView.swift
//  PickleBall
//

import SwiftUI
import CourtKit
import UIKit

struct TournamentRunView: View {
    @Environment(\.dismiss) private var dismiss

    var isReadOnly: Bool = false

    private let initialTournament: SavedTournament

    @ObservedObject private var tournamentStore = TournamentStore.shared

    @State private var currentTournamentId: UUID
    @State private var tournamentCreatedAt: Date
    @State private var isSingles: Bool
    @State private var selectedBestOf: Int
    @State private var targetScore: Int
    @State private var participantCount: Int
    @State private var tournamentName: String?

    @State private var tournamentMatches: [TournamentMatch] = []
    @State private var shuffledMatchOrder: [UUID] = []

    private enum RunTab: String, CaseIterable {
        case matches, standings, stats
    }
    @State private var selectedTab: RunTab = .matches
    @State private var matchToPlay: MatchToPlay?
    @State private var showShareSheet = false
    @State private var showResetConfirm = false

    @State private var recentlyCompletedIds: Set<UUID> = []
    @State private var bloomTasks: [UUID: Task<Void, Never>] = [:]
    @State private var showChampionScreen = false
    @State private var hasPresentedChampion = false
    @State private var expandedMatchId: UUID?
    @State private var showClearMatchConfirm = false
    @State private var clearMatchIndex: Int?

    private let lightGrey     = DS.Palette.pageGrey
    private let cardWhite     = Color.white
    private let royalBlue     = DS.Palette.royalBlue
    private let fieldGrey     = DS.Palette.fieldGrey
    private let textSecondary = DS.Palette.textSecondary
    private let stroke        = Color.black.opacity(0.08)

    private static let uiSpring: Animation = .spring(response: 0.26, dampingFraction: 0.85)

    init(tournament: SavedTournament, isReadOnly: Bool = false) {
        self.initialTournament = tournament
        self.isReadOnly = isReadOnly
        _currentTournamentId = State(initialValue: tournament.id)
        _tournamentCreatedAt = State(initialValue: tournament.createdAt)
        _isSingles = State(initialValue: tournament.isSingles)
        _selectedBestOf = State(initialValue: tournament.bestOf)
        _targetScore = State(initialValue: tournament.targetScore)
        _participantCount = State(initialValue: tournament.participantCount)
        _tournamentName = State(initialValue: tournament.name)
    }

    private var computedStandings: [PlayerStanding] {
        TournamentStandings.compute(from: tournamentMatches)
    }

    private var completedCount: Int {
        tournamentMatches.filter { $0.isCompleted }.count
    }

    private var totalMatchCount: Int {
        tournamentMatches.count
    }

    private var progressFraction: Double {
        guard totalMatchCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalMatchCount)
    }

    private var isTournamentComplete: Bool {
        !tournamentMatches.isEmpty && tournamentMatches.allSatisfy(\.isCompleted)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            lightGrey.ignoresSafeArea()

            matchesListContent

            VStack {
                HStack {
                    backButton
                    Spacer()
                    if !isReadOnly {
                        resetButton
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                Spacer()
            }

            shareButton
                .padding(.leading, 20)
                .padding(.bottom, 24)
        }
        .fullScreenCover(item: $matchToPlay) { _ in
            LiveMatchScreen()
        }
        .fullScreenCover(isPresented: $showChampionScreen) {
            championCover
        }
        .sheet(isPresented: $showShareSheet) {
            shareSheetContent
        }
        .alert("Reset Tournament?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                tournamentStore.delete(id: currentTournamentId)
                dismiss()
            }
        } message: {
            Text("This will permanently delete the tournament and all its match results.")
        }
        .alert("Clear Match Result?", isPresented: $showClearMatchConfirm) {
            Button("Cancel", role: .cancel) { clearMatchIndex = nil }
            Button("Clear", role: .destructive) {
                if let i = clearMatchIndex {
                    clearMatchResult(at: i)
                }
                clearMatchIndex = nil
            }
        } message: {
            Text("This removes the score so you can play the match again. Standings will update.")
        }
        .onAppear {
            Haptics.warm()
            restoreFromSaved(initialTournament)
            presentChampionIfNeeded()
        }
        .onDisappear {
            bloomTasks.values.forEach { $0.cancel() }
            bloomTasks.removeAll()
        }
        .onChange(of: isTournamentComplete) { _, isComplete in
            if isComplete {
                presentChampionIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var championCover: some View {
        let standings = computedStandings
        let topThree = Array(standings.prefix(3))

        let podiumOrder: [PlayerStanding] = {
            guard topThree.count >= 3 else { return topThree }
            return [topThree[1], topThree[0], topThree[2]]
        }()

        let champion = topThree.first ?? PlayerStanding(
            name: "Champion",
            points: 0,
            wins: 0,
            draws: 0,
            losses: 0,
            pointsFor: 0,
            pointsAgainst: 0
        )

        TournamentChampionView(
            champion: champion,
            podium: podiumOrder,
            onDone: {
                showChampionScreen = false
                dismiss()
            }
        )
    }

    private func presentChampionIfNeeded() {
        guard isTournamentComplete, !hasPresentedChampion else { return }
        hasPresentedChampion = true
        showChampionScreen = true
    }

    private var progressHeader: some View {
        VStack(spacing: 8) {
            if let name = tournamentName, !name.isEmpty {
                Text(name.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(completedCount)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(royalBlue)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: completedCount)

                Text("of \(totalMatchCount)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(textSecondary)

                Text("matches")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(textSecondary.opacity(0.85))

                Spacer()

                Text("\(Int((progressFraction * 100).rounded()))%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(royalBlue.opacity(0.9))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: completedCount)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(fieldGrey)
                    Capsule()
                        .fill(royalBlue)
                        .frame(width: max(0, geo.size.width * progressFraction))
                        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: progressFraction)
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(completedCount) of \(totalMatchCount) matches complete")
        .accessibilityValue("\(Int((progressFraction * 100).rounded())) percent")
    }

    private var backButton: some View {
        Button {
            Haptics.light()
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(royalBlue)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.black.opacity(0.05), lineWidth: 1))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Dismiss tournament")
    }

    private var resetButton: some View {
        Button {
            Haptics.light()
            showResetConfirm = true
        } label: {
            Image(systemName: "trash.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.red.opacity(0.9))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.black.opacity(0.05), lineWidth: 1))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Reset tournament")
    }

    private var shareButton: some View {
        Button {
            Haptics.medium()
            showShareSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .bold))
                Text("SHARE")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .tracking(1.0)
            }
            .foregroundColor(royalBlue)
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(0.05), lineWidth: 1))
            .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Share tournament")
    }

    private var shareSummaryText: String {
        var lines: [String] = ["Tournament Standings", ""]
        for (i, s) in computedStandings.enumerated() {
            let diff = s.pointDifferential >= 0 ? "+\(s.pointDifferential)" : "\(s.pointDifferential)"
            lines.append("\(i + 1). \(s.name) — \(s.points) pts (W\(s.wins) L\(s.losses), diff \(diff))")
        }
        if computedStandings.isEmpty {
            lines.append("No completed matches yet.")
        }
        return lines.joined(separator: "\n")
    }

    private var shareSheetContent: some View {
        ActivityView(activityItems: [shareSummaryText])
    }

    private var matchesListContent: some View {
        VStack(spacing: 0) {
            progressHeader
                .padding(.horizontal, 20)
                .padding(.top, 74)
                .padding(.bottom, 10)

            HStack(spacing: 4) {
                segmentButton(title: "Matches", isSelected: selectedTab == .matches) { selectedTab = .matches }
                segmentButton(title: "Standings", isSelected: selectedTab == .standings) { selectedTab = .standings }
                segmentButton(title: "Stats", isSelected: selectedTab == .stats) { selectedTab = .stats }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fieldGrey))
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            switch selectedTab {
            case .matches:
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(Array(shuffledMatchOrder.enumerated()), id: \.element) { _, matchId in
                            if let index = tournamentMatches.firstIndex(where: { $0.id == matchId }),
                               index < tournamentMatches.count {
                                matchRow(match: tournamentMatches[index], index: index)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 110)
                }

            case .standings:
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        if !computedStandings.isEmpty {
                            Text("RANKED BY: POINTS → DIFF → POINTS FOR")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(1.2)
                                .foregroundColor(textSecondary)
                                .padding(.top, 2)
                        }
                        ForEach(Array(computedStandings.enumerated()), id: \.element.id) { rank, standing in
                            tableRow(standing: standing, rank: rank + 1)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 110)
                    .animation(Self.uiSpring, value: computedStandings)
                }

            case .stats:
                statsTabContent
            }
        }
    }

    private func matchRow(match: TournamentMatch, index: Int) -> some View {
        let isExpanded = expandedMatchId == match.id
        let isCompleted = match.isCompleted

        let accentColor: Color = {
            guard let winner = match.winner else { return textSecondary }
            return winner == match.player1
                ? royalBlue
                : DS.Palette.loss
        }()

        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MATCH \(index + 1)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(textSecondary)
                        .tracking(1.0)

                    Text("\(match.player1) vs \(match.player2)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(royalBlue)
                        .lineLimit(1)

                    if isCompleted, let score = match.scoreText, let winner = match.winner {
                        Text("\(winner) won \(score)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isCompleted {
                    HStack(spacing: 8) {
                        if let score = match.scoreText {
                            Text(score)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(royalBlue)
                                .monospacedDigit()
                        }

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(textSecondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let willExpand = !isExpanded
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            expandedMatchId = willExpand ? match.id : nil
                        }
                        if willExpand {
                            Haptics.light()
                        } else {
                            Haptics.selection()
                        }
                    }
                } else if isReadOnly {
                    Text("LIVE")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .tracking(1.0)
                        .foregroundColor(royalBlue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(royalBlue.opacity(0.08)))
                } else {
                    Button {
                        Haptics.light()
                        startFixture(index: index, match: match)
                    } label: {
                        Text("PLAY")
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(.white)
                            .tracking(0.8)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(DS.Palette.loss)
                            )
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Start match \(index + 1): \(match.player1) vs \(match.player2)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if isExpanded && isCompleted {
                matchDetailContent(match: match)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardWhite)
        )
        .overlay(
            HStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isCompleted ? accentColor : Color.clear)
                    .frame(width: 4)
                Spacer(minLength: 0)
            }
            .mask(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(stroke, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.green.opacity(recentlyCompletedIds.contains(match.id) ? 0.08 : 0))
                .animation(.easeOut(duration: 0.45), value: recentlyCompletedIds)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
        .contextMenu {
            if isCompleted && !isReadOnly {
                Button(role: .destructive) {
                    clearMatchIndex = index
                    showClearMatchConfirm = true
                } label: {
                    Label("Clear Result", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }

    @ViewBuilder
    private func matchDetailContent(match: TournamentMatch) -> some View {
        if let scores = match.gameScores, !scores.isEmpty {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(stroke)
                    .frame(height: 1)
                    .padding(.horizontal, 16)

                VStack(spacing: 0) {
                    ForEach(Array(scores.enumerated()), id: \.offset) { index, game in
                        let p1Won = game.player1 > game.player2
                        let p2Won = game.player2 > game.player1

                        HStack {
                            Text("Game \(index + 1)")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(textSecondary)
                                .frame(width: 64, alignment: .leading)

                            Spacer()

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

    private var statsTabContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                if computedStandings.isEmpty {
                    Text("Complete a match to unlock stats.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else {
                    Text("THIS TOURNAMENT")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundColor(textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(computedStandings, id: \.id) { standing in
                        playerStatsCard(standing)
                    }

                    let h2h = TournamentStatsEngine.headToHead(matches: tournamentMatches)
                    if !h2h.isEmpty {
                        Text("HEAD TO HEAD")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.2)
                            .foregroundColor(textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)

                        ForEach(h2h) { row in
                            HStack {
                                Text(row.summary)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(royalBlue)
                                    .lineLimit(2)
                                Spacer()
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(cardWhite))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(stroke, lineWidth: 1))
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 110)
        }
    }

    private func playerStatsCard(_ standing: PlayerStanding) -> some View {
        let form = TournamentStatsEngine.form(player: standing.name, matches: tournamentMatches, last: 3)
        let winPct = TournamentStatsEngine.winPercentageText(
            wins: standing.wins, losses: standing.losses, draws: standing.draws
        )
        let clutch = TournamentStatsEngine.clutchText(
            player: standing.name,
            matches: tournamentMatches,
            gamesToWin: max(1, selectedBestOf)
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(standing.name)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(royalBlue)
                Spacer()
                Text(winPct)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(royalBlue)
                    .monospacedDigit()
            }

            HStack(spacing: 6) {
                Text("FORM")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(textSecondary)
                if form.isEmpty {
                    Text("—")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(textSecondary)
                } else {
                    ForEach(Array(form.enumerated()), id: \.offset) { _, win in
                        Text(win ? "W" : "L")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundColor(win
                                ? DS.Palette.win
                                : DS.Palette.loss)
                            .frame(width: 22, height: 22)
                            .background(
                                Circle().fill(win
                                    ? DS.Palette.win.opacity(0.12)
                                    : DS.Palette.loss.opacity(0.12))
                            )
                    }
                }
                Spacer()
                if selectedBestOf >= 2 {
                    Text("CLUTCH \(clutch)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(textSecondary)
                        .monospacedDigit()
                }
            }

            Text("W \(standing.wins) · L \(standing.losses) · Diff \(standing.pointDifferential >= 0 ? "+" : "")\(standing.pointDifferential)")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(textSecondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(cardWhite))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(stroke, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
    }

    private func tableRow(standing: PlayerStanding, rank: Int) -> some View {
        HStack(spacing: 14) {
            Text("\(rank)")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundColor(rank == 1 ? .orange : royalBlue)
                .frame(width: 24)

            VStack(spacing: 2) {
                Text(standing.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(royalBlue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)

                Text("W: \(standing.wins) · D: \(standing.draws) · L: \(standing.losses) · Diff: \(standing.pointDifferential >= 0 ? "+" : "")\(standing.pointDifferential) · PF: \(standing.pointsFor)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer()

            Text("\(standing.points) PTS")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundColor(royalBlue)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(cardWhite))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(stroke, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(rank): \(standing.name). \(standing.points) points, \(standing.wins) wins, \(standing.losses) losses")
    }

    private func segmentButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                .foregroundColor(isSelected ? royalBlue : textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isSelected ? Color.white : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(stroke, lineWidth: isSelected ? 1 : 0))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(isSelected ? "\(title), selected" : title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func restoreFromSaved(_ saved: SavedTournament) {
        currentTournamentId = saved.id
        tournamentCreatedAt = saved.createdAt
        isSingles = saved.isSingles
        selectedBestOf = saved.bestOf
        targetScore = saved.targetScore
        participantCount = saved.participantCount
        tournamentName = saved.name

        tournamentMatches = saved.matches.map { m in
            TournamentMatch(
                id: m.id,
                player1: m.player1,
                player2: m.player2,
                player1GamesWon: m.player1GamesWon,
                player2GamesWon: m.player2GamesWon,
                gameScores: m.gameScores
            )
        }
        shuffledMatchOrder = saved.shuffledOrder
    }

    private func saveCurrentTournament() {
        let savedMatches = tournamentMatches.map { m in
            SavedTournament.SavedMatch(
                id: m.id,
                player1: m.player1,
                player2: m.player2,
                player1GamesWon: m.player1GamesWon,
                player2GamesWon: m.player2GamesWon,
                gameScores: m.gameScores
            )
        }

        var seen = Set<String>()
        var names: [String] = []
        for m in tournamentMatches {
            if seen.insert(m.player1).inserted { names.append(m.player1) }
            if seen.insert(m.player2).inserted { names.append(m.player2) }
        }

        let tournament = SavedTournament(
            id: currentTournamentId,
            createdAt: tournamentCreatedAt,
            sport: initialTournament.sport,
            participantNames: names,
            participants: initialTournament.participants,
            matches: savedMatches,
            shuffledOrder: shuffledMatchOrder,
            bestOf: selectedBestOf,
            targetScore: targetScore,
            isSingles: isSingles,
            participantCount: participantCount,
            name: tournamentName
        )
        tournamentStore.save(tournament)
    }

    /// Scores a fixture with the sport engine; the result comes back
    /// through `onCompleted` and is linked to its match record.
    private func startFixture(index: Int, match: TournamentMatch) {
        let lineup = Lineup(
            teamA: playersFor(label: match.player1),
            teamB: playersFor(label: match.player2)
        )
        let live = MatchCenter.shared.startMatch(rules: fixtureRules(isDoubles: lineup.isDoubles), lineup: lineup, tournamentFixture: match.id)
        let fixtureID = match.id
        live.onCompleted = { result in
            let scores = result.units.map { GameScore(player1: $0.score.a, player2: $0.score.b) }
            storeMatchResult(index: index, p1Games: result.matchScore.a, p2Games: result.matchScore.b, scores: scores)
            TournamentStore.shared.link(fixture: fixtureID, toMatch: result.id)
        }
        matchToPlay = MatchToPlay(index: index, player1: match.player1, player2: match.player2)
    }

    private func playersFor(label: String) -> [PlayerRef] {
        let known = initialTournament.players(for: label)
        if !known.isEmpty { return known }
        return label.split(separator: "/").map { PlayerDirectory.shared.resolve(typedName: String($0)) }
    }

    /// Tournament format mapped onto the sport engine. `bestOf` is the
    /// number of games in a match (1, 2 or 3).
    private func fixtureRules(isDoubles: Bool) -> MatchRules {
        switch initialTournament.sport {
        case .pickleball:
            let gamesToWin = selectedBestOf / 2 + 1
            return .pickleball(.sideOut, PickleballConfig(pointsToWin: targetScore, gamesToWin: gamesToWin, isDoubles: isDoubles))
        case .padel:
            return .padel(PadelConfig(setsToWin: selectedBestOf > 1 ? 2 : 1, isDoubles: isDoubles))
        }
    }

    private func storeMatchResult(index: Int, p1Games: Int, p2Games: Int, scores: [GameScore]) {
        guard index < tournamentMatches.count else { return }
        let matchId = tournamentMatches[index].id
        tournamentMatches[index].player1GamesWon = p1Games
        tournamentMatches[index].player2GamesWon = p2Games
        tournamentMatches[index].gameScores = scores
        triggerBloom(for: matchId)
        saveCurrentTournament()
        presentChampionIfNeeded()
    }

    private func clearMatchResult(at index: Int) {
        guard index < tournamentMatches.count else { return }
        tournamentMatches[index].player1GamesWon = nil
        tournamentMatches[index].player2GamesWon = nil
        tournamentMatches[index].gameScores = nil
        if expandedMatchId == tournamentMatches[index].id {
            expandedMatchId = nil
        }
        hasPresentedChampion = false
        showChampionScreen = false
        saveCurrentTournament()
        Haptics.medium()
    }

    private func triggerBloom(for matchId: UUID) {
        bloomTasks[matchId]?.cancel()
        withAnimation(.easeOut(duration: 0.45)) {
            _ = recentlyCompletedIds.insert(matchId)
        }
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) {
                _ = recentlyCompletedIds.remove(matchId)
            }
            bloomTasks.removeValue(forKey: matchId)
        }
        bloomTasks[matchId] = task
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    TournamentRunView(
        tournament: SavedTournament(
            id: UUID(),
            createdAt: Date(),
            sport: .pickleball,
            participantNames: ["Alice", "Bob", "Carol"],
            participants: [],
            matches: [],
            shuffledOrder: [],
            bestOf: 1,
            targetScore: 11,
            isSingles: true,
            participantCount: 3,
            name: nil
        )
    )
}
