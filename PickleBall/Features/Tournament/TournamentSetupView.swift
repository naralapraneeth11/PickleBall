//
//  TournamentSetupView.swift
//  PickleBall
//
//  Created by sai praneeth reddy narala on 8/24/26.
//

import SwiftUI
import CourtKit
import UIKit

// MARK: - Tournament Setup View (setup only)

struct TournamentSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tournamentStore = TournamentStore.shared
    @Environment(SportMode.self) private var sportMode

    /// After Start succeeds, we present the run screen with this tournament.
    @State private var tournamentToRun: SavedTournament?

    @State private var isSingles: Bool = true
    @State private var numberOfPlayers: Int = 3
    @State private var numberOfTeams: Int = 2
    @State private var playerNames: [String] = ["", "", "", ""]
    @State private var tournamentName: String = ""
    @State private var selectedBestOf: Int = 1
    @State private var pointsSelectionIndex: Int = 0
    @State private var customPointsInput: String = "15"
    @State private var numberOfMatches: Int = 1

    @State private var showUnfairAlert = false
    @State private var showDuplicateAlert = false

    private let bestOfOptions = [1, 2, 3]
    private let pointsOptions = [11, 21, 31]
    private let playerRange = 2...12
    private let teamRange = 2...8

    // Styling tokens
    private let lightGrey     = DS.Palette.pageGrey
    private let cardWhite     = Color.white
    private let royalBlue     = DS.Palette.royalBlue
    private let fieldGrey     = DS.Palette.fieldGrey
    private let textSecondary = DS.Palette.textSecondary
    private let warning       = DS.Palette.warning
    private let stroke        = Color.black.opacity(0.08)

    private var effectivePoints: Int {
        if pointsSelectionIndex == 3 {
            let n = Int(customPointsInput) ?? 11
            return max(1, min(99, n))
        }
        return pointsOptions[pointsSelectionIndex]
    }

    private var customPointsInvalid: Bool {
        guard pointsSelectionIndex == 3 else { return false }
        let trimmed = customPointsInput.trimmingCharacters(in: .whitespaces)
        guard let n = Int(trimmed) else { return true }
        return n < 1
    }

    private var requiredNameCount: Int { isSingles ? numberOfPlayers : numberOfTeams * 2 }
    private var participantCount: Int { isSingles ? numberOfPlayers : numberOfTeams }
    private var maxMatchesPerPlayer: Int { 99 }
    private var minMatchesPerPlayer: Int { 1 }

    private var isSchedulePossible: Bool {
        TournamentSchedule.isSchedulePossible(
            participantCount: participantCount,
            matchesPerPlayer: numberOfMatches
        )
    }

    private var totalMatches: Int? {
        TournamentSchedule.totalMatches(
            participantCount: participantCount,
            matchesPerPlayer: numberOfMatches
        )
    }

    private var canStartTournament: Bool {
        isSchedulePossible && participantCount >= 2 && !customPointsInvalid
    }
    
    // MARK: - Body

    var body: some View {
        ZStack {
            lightGrey.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        setupTitle
                        mainCard
                        startTournamentButton
                    }
                    .padding(.top, 80)
                    .padding(.bottom, 100)
                }
            }

            // Floating back only
            VStack {
                HStack {
                    backButton
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                Spacer()
            }
        }
        .fullScreenCover(item: $tournamentToRun, onDismiss: {
            // User left the run screen → leave setup entirely (progress is saved).
            dismiss()
        }) { saved in
            TournamentRunView(tournament: saved)
        }
        .alert("Duplicate Names", isPresented: $showDuplicateAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Each \(isSingles ? "player" : "team") needs a different name so results and standings stay correct.")
        }
        .alert("Can't Make Fair Matches", isPresented: $showUnfairAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("It's not possible to fairly give each \(isSingles ? "player" : "team") exactly \(numberOfMatches) match\(numberOfMatches == 1 ? "" : "es") with \(participantCount) \(isSingles ? "players" : "teams"). Try different settings.")
        }
        .onAppear {
            Haptics.warm()
            resizePlayerNames()
        }
        .onChange(of: numberOfPlayers) { _, _ in
            resizePlayerNames()
            numberOfMatches = min(max(numberOfMatches, minMatchesPerPlayer), maxMatchesPerPlayer)
        }
        .onChange(of: numberOfTeams) { _, _ in
            resizePlayerNames()
            numberOfMatches = min(max(numberOfMatches, minMatchesPerPlayer), maxMatchesPerPlayer)
        }
        .onChange(of: isSingles) { _, _ in
            resizePlayerNames()
            numberOfMatches = min(max(numberOfMatches, minMatchesPerPlayer), maxMatchesPerPlayer)
        }
        .onChange(of: numberOfMatches) { _, _ in
            if !isSchedulePossible { showUnfairAlert = true }
        }
    }

    // MARK: - Floating Controls

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
        .accessibilityLabel("Dismiss tournament setup")
    }

    // MARK: - Setup Title

    private var setupTitle: some View {
        VStack(spacing: 2) {
            Text("TOURNAMENT")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .tracking(1.4)
                .foregroundColor(royalBlue)
            Text("SETUP")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(2.0)
                .foregroundColor(textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tournament setup")
    }

    // MARK: - Main Card

    private var mainCard: some View {
        VStack(spacing: 20) {
            tournamentNameSection
            singlesDoublesToggle
            pointsSection
            setsSection
            matchesSection
            numberOfPlayersSection
            playerNamesSection
        }
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(cardWhite)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(stroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 16, x: 0, y: 8)
        .padding(.horizontal, 16)
    }

    // MARK: - Setup Subsections

    private var singlesDoublesToggle: some View {
        HStack(spacing: 4) {
            segmentButton(title: "Singles", isSelected: isSingles) { isSingles = true }
            segmentButton(title: "Doubles", isSelected: !isSingles) { isSingles = false }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fieldGrey))
        .padding(.horizontal, 16)
        .padding(.top, 18)
    }
    private var tournamentNameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOURNAMENT NAME")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(textSecondary)
                .tracking(1.2)

            TextField("Optional", text: $tournamentName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(royalBlue)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fieldGrey))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(stroke, lineWidth: 1))
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .onChange(of: tournamentName) { _, newValue in
                    if newValue.count > 24 {
                        tournamentName = String(newValue.prefix(24))
                    }
                }
                .accessibilityLabel("Tournament name")
                .accessibilityHint("Optional, up to 24 characters")
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
    }
    private var pointsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GAME POINTS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(textSecondary)
                .tracking(1.2)

            HStack(spacing: 6) {
                ForEach([11, 21, 31].indices, id: \.self) { i in
                    let val = [11, 21, 31][i]
                    let isSelected = pointsSelectionIndex == i
                    Button {
                        Haptics.selection()
                        pointsSelectionIndex = i
                    } label: {
                        Text("\(val)")
                            .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                            .foregroundColor(isSelected ? royalBlue : textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isSelected ? Color.white : fieldGrey))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(stroke, lineWidth: isSelected ? 1 : 0))
                    }
                    .accessibilityLabel(isSelected ? "\(val) points, selected" : "\(val) points")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }

                let customSelected = pointsSelectionIndex == 3
                Button {
                    Haptics.selection()
                    pointsSelectionIndex = 3
                } label: {
                    Text("Custom")
                        .font(.system(size: 13, weight: customSelected ? .bold : .semibold))
                        .foregroundColor(customSelected ? royalBlue : textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(customSelected ? Color.white : fieldGrey))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(stroke, lineWidth: customSelected ? 1 : 0))
                }
                .accessibilityLabel(customSelected ? "Custom points, selected" : "Custom points")
                .accessibilityAddTraits(customSelected ? .isSelected : [])
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fieldGrey))

            if pointsSelectionIndex == 3 {
                HStack(spacing: 10) {
                    Text("Points:")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(royalBlue)

                    TextField("15", text: $customPointsInput)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(customPointsInvalid ? Color.red : royalBlue)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fieldGrey))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(customPointsInvalid ? Color.red.opacity(0.55) : stroke, lineWidth: customPointsInvalid ? 1.2 : 1)
                        )
                        .frame(width: 80)
                        .onChange(of: customPointsInput) { _, newValue in
                            let filtered = newValue.filter { $0.isNumber }
                            let clamped = filtered.count > 2 ? String(filtered.prefix(2)) : filtered
                            if clamped != newValue { customPointsInput = clamped }
                        }
                        .accessibilityLabel("Custom points value")
                        .accessibilityHint("Enter a number between 1 and 99")

                    if customPointsInvalid {
                        Text("Required")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.red.opacity(0.85))
                    }
                    Spacer()
                }
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 16)
    }

    private var setsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GAMES TO WIN MATCH")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(textSecondary)
                .tracking(1.2)

            HStack(spacing: 6) {
                ForEach(bestOfOptions.indices, id: \.self) { i in
                    let val = bestOfOptions[i]
                    let isSelected = selectedBestOf == val
                    Button {
                        Haptics.selection()
                        selectedBestOf = val
                    } label: {
                        Text("\(val)")
                            .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                            .foregroundColor(isSelected ? royalBlue : textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isSelected ? Color.white : fieldGrey))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(stroke, lineWidth: isSelected ? 1 : 0))
                    }
                    .accessibilityLabel(isSelected ? "\(val) game\(val == 1 ? "" : "s") to win, selected" : "\(val) game\(val == 1 ? "" : "s") to win")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fieldGrey))
        }
        .padding(.horizontal, 16)
    }

    private var matchesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MATCHES PER \(isSingles ? "PLAYER" : "TEAM")")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(textSecondary)
                .tracking(1.2)

            Stepper(value: Binding(
                get: { numberOfMatches },
                set: { numberOfMatches = min(max($0, minMatchesPerPlayer), maxMatchesPerPlayer) }
            ), in: minMatchesPerPlayer...maxMatchesPerPlayer) {
                HStack(spacing: 5) {
                    Text("\(numberOfMatches)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(royalBlue)
                    if participantCount >= 2 {
                        if let totalMatches {
                            Text("(\(totalMatches) total)")
                                .font(.system(size: 13))
                                .foregroundColor(textSecondary)
                        } else {
                            Text("(not possible)")
                                .font(.system(size: 13))
                                .foregroundColor(warning)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fieldGrey))
            .accessibilityLabel("Matches per \(isSingles ? "player" : "team"): \(numberOfMatches)")

            if participantCount < 2 {
                Text("Add at least 2 \(isSingles ? "players" : "teams")")
                    .font(.system(size: 13))
                    .foregroundColor(warning)
            }
        }
        .padding(.horizontal, 16)
    }

    private var numberOfPlayersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isSingles ? "HOW MANY PLAYERS?" : "HOW MANY TEAMS?")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(textSecondary)
                .tracking(1.2)

            Stepper(
                value: isSingles ? $numberOfPlayers : $numberOfTeams,
                in: isSingles ? playerRange : teamRange
            ) {
                Text("\(isSingles ? numberOfPlayers : numberOfTeams)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(royalBlue)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fieldGrey))
            .accessibilityLabel(isSingles ? "Number of players: \(numberOfPlayers)" : "Number of teams: \(numberOfTeams)")
        }
        .padding(.horizontal, 16)
    }

    private var playerNamesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isSingles ? "PLAYER NAMES" : "TEAM NAMES")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(textSecondary)
                .tracking(1.2)

            if isSingles {
                LazyVStack(spacing: 8) {
                    ForEach(0..<numberOfPlayers, id: \.self) { i in
                        playerNameField(index: i, label: "Player \(i + 1)")
                    }
                }
            } else {
                VStack(spacing: 14) {
                    ForEach(0..<numberOfTeams, id: \.self) { team in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Team \(team + 1)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(royalBlue.opacity(0.7))
                                .tracking(0.8)
                            HStack(spacing: 10) {
                                playerNameField(index: team * 2, label: "Player A")
                                playerNameField(index: team * 2 + 1, label: "Player B")
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func playerNameField(index: Int, label: String) -> some View {
        Group {
            if index < playerNames.count {
                TextField(label, text: Binding(
                    get: { playerNames[index] },
                    set: { newVal in
                        if index < playerNames.count {
                            playerNames[index] = String(newVal.prefix(7))
                        }
                    }
                ))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(royalBlue)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fieldGrey))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(stroke, lineWidth: 1))
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .accessibilityLabel(label)
                .accessibilityHint("Enter name, up to 7 characters")
            }
        }
    }

    private var startTournamentButton: some View {
        Button(action: startTournamentTapped) {
            Text("START TOURNAMENT")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .tracking(0.9)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(canStartTournament ? royalBlue : royalBlue.opacity(0.4))
                        .shadow(color: royalBlue.opacity(canStartTournament ? 0.35 : 0.0), radius: 12, x: 0, y: 7)
                )
        }
        .buttonStyle(PressStyle())
        .padding(.horizontal, 16)
        .disabled(!canStartTournament)
        .accessibilityLabel("Start tournament")
        .accessibilityHint(canStartTournament ? "Double-tap to generate the schedule and begin" : "Fix the configuration above first")
    }

    // MARK: - Segment Button

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

    // MARK: - Helpers

    private func resizePlayerNames() {
        let count = requiredNameCount
        if playerNames.count < count {
            playerNames.append(contentsOf: Array(repeating: "", count: count - playerNames.count))
        } else if playerNames.count > count {
            playerNames = Array(playerNames.prefix(count))
        }
    }

    private var participantNames: [String] {
        if isSingles {
            return Array(playerNames.prefix(numberOfPlayers))
        } else {
            return (0..<numberOfTeams).map { team in
                let idx1 = team * 2
                let idx2 = team * 2 + 1
                let a = idx1 < playerNames.count ? playerNames[idx1] : ""
                let b = idx2 < playerNames.count ? playerNames[idx2] : ""
                let nameA = a.isEmpty ? "Team\(team+1)A" : a
                let nameB = b.isEmpty ? "Team\(team+1)B" : b
                return "\(nameA)/\(nameB)"
            }
        }
    }

    // MARK: - Start → Run

    private func startTournamentTapped() {
        let labels = participantNames.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if Set(labels.map { $0.lowercased() }).count != labels.count {
            showDuplicateAlert = true
            return
        }

        let matchups = TournamentSchedule.generateMatchups(
            participantNames: participantNames,
            matchesPerPlayer: numberOfMatches
        )

        guard !matchups.isEmpty else {
            showUnfairAlert = true
            return
        }

        let tournamentId = UUID()
        let createdAt = Date()

        let tournamentMatches = matchups.map {
            TournamentMatch(
                id: UUID(),
                player1: $0.0,
                player2: $0.1,
                player1GamesWon: nil,
                player2GamesWon: nil,
                gameScores: nil
            )
        }
        let shuffledOrder = tournamentMatches.map { $0.id }.shuffled()

        var seen = Set<String>()
        var names: [String] = []
        for m in tournamentMatches {
            if seen.insert(m.player1).inserted { names.append(m.player1) }
            if seen.insert(m.player2).inserted { names.append(m.player2) }
        }

        let savedMatches = tournamentMatches.map { m in
            SavedTournament.SavedMatch(
                id: m.id,
                player1: m.player1,
                player2: m.player2,
                player1GamesWon: nil,
                player2GamesWon: nil,
                gameScores: nil
            )
        }

        // Every label resolves to real players ("SAM/PRIYA" → two IDs), so
        // tournament matches land in history and head-to-head records.
        let directory = PlayerDirectory.shared
        let participants = names.map { label in
            TournamentParticipant(
                label: label,
                players: label.split(separator: "/").map { directory.resolve(typedName: String($0)) }
            )
        }

        let tournament = SavedTournament(
            id: tournamentId,
            createdAt: createdAt,
            sport: sportMode.sport,
            participantNames: names,
            participants: participants,
            matches: savedMatches,
            shuffledOrder: shuffledOrder,
            bestOf: selectedBestOf,
            targetScore: effectivePoints,
            isSingles: isSingles,
            participantCount: participantCount,
            name: {
                let t = tournamentName.trimmingCharacters(in: .whitespaces)
                return t.isEmpty ? nil : t
            }()
        )
        tournamentStore.save(tournament)
        tournamentToRun = tournament   // presents TournamentRunView
    }
}

#Preview {
    TournamentSetupView()
        .environment(SportMode())
}
