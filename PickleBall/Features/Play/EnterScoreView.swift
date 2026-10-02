//
//  EnterScoreView.swift
//  PickleBall
//
//  "Enter a score": for matches scored on paper, or with no Watch. Pick
//  friends or guests, shuffle doubles teams, type the game scores, tag the
//  court. The other side confirms before it counts.
//

import SwiftUI
import SwiftData
import PhotosUI
import CourtKit
import CourtNet

struct EnterScoreView: View {
    var prefill: MatchPrefill?

    @Environment(\.dismiss) private var dismiss
    @Environment(SportMode.self) private var sportMode
    @ObservedObject private var directory = PlayerDirectory.shared
    private let social = Social.shared

    @State private var sport: Sport = .pickleball
    @State private var isSingles = false
    @State private var slots: [SlotEntry] = [.empty, .empty, .empty, .empty]
    // Pickleball
    @State private var pointsToWin = 11
    @State private var gamesToWin = 1
    // Padel
    @State private var setsToWin = 2
    @State private var superTiebreak = true

    @State private var units: [UnitEntry] = [UnitEntry()]
    @State private var playedAt = Date()
    @State private var court: CourtTag?
    @State private var squadID: UUID?
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: Data?
    @State private var showCourtSearch = false
    @State private var lastShuffle: Lineup?
    @State private var saved: MatchRecord?

    struct UnitEntry: Identifiable, Equatable {
        let id = UUID()
        var a = ""
        var b = ""
        var tiebreakA = ""
        var tiebreakB = ""
        var isSuperTiebreak = false
    }

    private var rules: MatchRules {
        switch sport {
        case .pickleball:
            return .pickleball(.sideOut, PickleballConfig(pointsToWin: pointsToWin, gamesToWin: gamesToWin, isDoubles: !isSingles))
        case .padel:
            return .padel(PadelConfig(setsToWin: setsToWin, decidingSet: superTiebreak ? .superTiebreak(points: 10) : .fullSet, isDoubles: !isSingles))
        }
    }

    private var completedUnits: [CompletedUnit] {
        units.compactMap { entry in
            guard let a = Int(entry.a), let b = Int(entry.b) else {
                guard entry.isSuperTiebreak, let ta = Int(entry.tiebreakA), let tb = Int(entry.tiebreakB) else { return nil }
                return CompletedUnit(score: .zero, tiebreak: TeamPair(a: ta, b: tb), isSuperTiebreak: true)
            }
            var tiebreak: TeamPair<Int>?
            if let ta = Int(entry.tiebreakA), let tb = Int(entry.tiebreakB) { tiebreak = TeamPair(a: ta, b: tb) }
            return CompletedUnit(score: TeamPair(a: a, b: b), tiebreak: tiebreak)
        }
    }

    private var validation: Result<EnteredScore, ScoreEntryProblem> {
        ScoreEntry.validate(completedUnits, rules: rules)
    }

    private var unitName: String { sport == .padel ? "Set" : "Game" }

    var body: some View {
        NavigationStack {
            Form {
                if prefill == nil {
                    Section {
                        Group {
                            Picker("Sport", selection: $sport) {
                                ForEach(Sport.allCases) { Text($0.displayName).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            Picker("Format", selection: $isSingles) {
                                Text("Singles").tag(true)
                                Text("Doubles").tag(false)
                            }
                            .pickerStyle(.segmented)
                        }
                        .courtRows()
                    }
                }

                playersSection
                formatSection
                scoresSection

                Section {
                    Group {
                        DatePicker("Played", selection: $playedAt, in: ...Date())
                        Button {
                            showCourtSearch = true
                        } label: {
                            LabeledContent("Court") {
                                Text(court?.name ?? "Add").foregroundStyle(court == nil ? .secondary : .primary)
                            }
                        }
                        .foregroundStyle(.primary)
                        if !social.squads.isEmpty {
                            Picker("Squad", selection: $squadID) {
                                Text("None").tag(UUID?.none)
                                ForEach(social.squads) { squad in
                                    Text(squad.name).tag(UUID?.some(squad.id))
                                }
                            }
                        }
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            LabeledContent("Photo") {
                                if let photo, let image = UIImage(data: photo) {
                                    Image(uiImage: image).resizable().scaledToFill().frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 6))
                                } else {
                                    Text("Optional").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .courtRows()
                } footer: {
                    Text("A squad match counts for the squad belt and shows up in the squad chat.")
                }
            }
            .courtList()
            .navigationTitle("Enter a score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled((try? validation.get()) == nil)
                }
            }
            .sheet(isPresented: $showCourtSearch) {
                CourtSearchView { court = $0 }
            }
            .sheet(item: $saved, onDismiss: { dismiss() }) { record in
                MatchSavedView(record: record)
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                    photo = ImageResizer.jpeg(data)
                }
            }
            .onChange(of: slots) { _, _ in suggestSquad() }
            .onAppear(perform: setUp)
        }
        .noticeToast()
    }

    // MARK: Sections

    private var playersSection: some View {
        Section {
            Group {
                teamRows(.a, placeholders: ["You", "Partner"])
                teamRows(.b, placeholders: ["Opponent", "Opponent 2"])
                if !isSingles && prefill == nil {
                    Button {
                        shuffle()
                    } label: {
                        Label("Shuffle teams", systemImage: "shuffle")
                    }
                }
            }
            .courtRows()
        } header: {
            Text("Players")
        } footer: {
            Text("Pick friends so they can confirm, or type a name to add a guest. Guests can claim their stats later.")
        }
    }

    @ViewBuilder
    private func teamRows(_ team: Team, placeholders: [String]) -> some View {
        let base = team == .a ? 0 : 2
        PlayerSlotField(entry: $slots[base], placeholder: placeholders[0], accent: sport.theme.accent, excluded: usedIDs(except: base))
        if !isSingles {
            PlayerSlotField(entry: $slots[base + 1], placeholder: placeholders[1], accent: sport.theme.accent, excluded: usedIDs(except: base + 1))
        }
    }

    @ViewBuilder
    private var formatSection: some View {
        if prefill == nil {
            Section("Format") {
                Group {
                    switch sport {
                    case .pickleball:
                        Picker("Points to win", selection: $pointsToWin) {
                            ForEach([11, 15, 21], id: \.self) { Text("\($0)").tag($0) }
                        }
                        Picker("Match", selection: $gamesToWin) {
                            Text("1 game").tag(1)
                            Text("Best of 3").tag(2)
                            Text("Best of 5").tag(3)
                        }
                    case .padel:
                        Picker("Match", selection: $setsToWin) {
                            Text("1 set").tag(1)
                            Text("Best of 3").tag(2)
                        }
                        if setsToWin == 2 {
                            Toggle("Match tiebreak instead of a third set", isOn: $superTiebreak)
                        }
                    }
                }
                .courtRows()
            }
        }
    }

    private var scoresSection: some View {
        Section {
            Group {
                ForEach($units) { $unit in
                    let index = units.firstIndex(where: { $0.id == unit.id }) ?? 0
                    UnitScoreRow(title: unit.isSuperTiebreak ? "Match tiebreak" : "\(unitName) \(index + 1)",
                                 entry: $unit, teamA: sideName(.a), teamB: sideName(.b), showsTiebreak: sport == .padel)
                }
                .onDelete { offsets in
                    units.remove(atOffsets: offsets)
                    if units.isEmpty { units = [UnitEntry()] }
                }
                HStack {
                    Button {
                        units.append(UnitEntry())
                    } label: {
                        Label("Add \(unitName.lowercased())", systemImage: "plus")
                    }
                    if sport == .padel && superTiebreak && setsToWin == 2 && units.count == 2 {
                        Spacer()
                        Button("Add match tiebreak") {
                            units.append(UnitEntry(isSuperTiebreak: true))
                        }
                    }
                }
            }
            .courtRows()
        } header: {
            Text("Score")
        } footer: {
            switch validation {
            case .success(let score):
                Text("\(sideName(score.winner)) win \(score.matchScore[score.winner])–\(score.matchScore[score.winner.opponent]).")
                    .foregroundStyle(DS.Palette.win)
            case .failure(let problem):
                if completedUnits.isEmpty { Text("Type each \(unitName.lowercased())’s score.") } else {
                    Text(problem.message(for: sport)).foregroundStyle(DS.Palette.loss)
                }
            }
        }
    }

    // MARK: Actions

    private func setUp() {
        guard slots[0] == .empty else { return }
        if let prefill {
            sport = prefill.rules.sport
            isSingles = !prefill.rules.isDoubles
            let a = prefill.lineup.teams.a, b = prefill.lineup.teams.b
            slots = [a.first.map(SlotEntry.player) ?? .empty, a.dropFirst().first.map(SlotEntry.player) ?? .empty,
                     b.first.map(SlotEntry.player) ?? .empty, b.dropFirst().first.map(SlotEntry.player) ?? .empty]
            switch prefill.rules {
            case .pickleball(_, let config):
                pointsToWin = config.pointsToWin
                gamesToWin = config.gamesToWin
            case .padel(let config):
                setsToWin = config.setsToWin
                if case .fullSet = config.decidingSet { superTiebreak = false }
            }
            court = prefill.context.court
            squadID = prefill.context.squadID
        } else {
            sport = sportMode.sport
            slots[0] = .player(directory.me)
        }
    }

    private func usedIDs(except index: Int) -> Set<PlayerID> {
        Set(slots.enumerated().compactMap { $0.offset == index ? nil : $0.element.player?.id })
    }

    private func sideName(_ team: Team) -> String {
        let indices = (team == .a ? [0, 1] : [2, 3]).prefix(isSingles ? 1 : 2)
        let names = indices.map { slots[$0].player?.shortName ?? (slots[$0].text.isEmpty ? nil : slots[$0].text) }.compactMap { $0 }
        return names.isEmpty ? (team == .a ? "Your side" : "Opponents") : names.joined(separator: " & ")
    }

    private func shuffle() {
        let players = (0..<4).map { slots[$0].resolved(placeholder: ["You", "Partner", "Opponent", "Opponent 2"][$0]) }
        guard Set(players.map(\.id)).count == 4, let lineup = TeamShuffle.shuffle(players, avoiding: lastShuffle ?? currentLineup()) else { return }
        Haptics.medium()
        lastShuffle = lineup
        withAnimation(DS.Motion.snappy) {
            slots = (lineup.teams.a + lineup.teams.b).map(SlotEntry.player)
        }
    }

    private func currentLineup() -> Lineup? {
        let players = slots.compactMap(\.player)
        guard players.count == 4 else { return nil }
        return Lineup(teamA: [players[0], players[1]], teamB: [players[2], players[3]])
    }

    private func suggestSquad() {
        guard squadID == nil, prefill == nil else { return }
        squadID = social.sharedSquad(for: slots.compactMap(\.player?.id))?.id
    }

    private func buildLineup() -> Lineup {
        let placeholders = ["You", "Partner", "Opponent", "Opponent 2"]
        var players: [PlayerRef] = []
        for index in 0..<4 {
            if isSingles && (index == 1 || index == 3) { continue }
            var ref = slots[index].resolved(placeholder: placeholders[index])
            if players.contains(where: { $0.id == ref.id }) { ref = directory.addGuest(named: placeholders[index]) }
            players.append(ref)
        }
        return isSingles
            ? Lineup(teamA: [players[0]], teamB: [players[1]])
            : Lineup(teamA: [players[0], players[1]], teamB: [players[2], players[3]])
    }

    private func save() {
        guard let score = try? validation.get() else { return }
        let lineup = buildLineup()
        var context = prefill?.context ?? MatchContext()
        context.court = court
        context.squadID = squadID
        let record = MatchRecord(entered: score, rules: rules, lineup: lineup, playedAt: playedAt, context: context)
        AppDatabase.context.insert(record)
        AppDatabase.save()
        directory.adopt(lineup)
        directory.markPlayed(lineup, at: playedAt)
        if let photo { MatchCenter.shared.savePhoto(photo, for: record.id) }
        MatchStore.shared.reload()
        Haptics.success()
        Task { await social.upload(record) }
        saved = record
    }
}

/// One game or set: two score fields, plus tiebreak points for a padel 7-6.
private struct UnitScoreRow: View {
    let title: String
    @Binding var entry: EnterScoreView.UnitEntry
    let teamA: String
    let teamB: String
    let showsTiebreak: Bool

    private var needsTiebreak: Bool {
        showsTiebreak && !entry.isSuperTiebreak && ((entry.a == "7" && entry.b == "6") || (entry.a == "6" && entry.b == "7"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            if entry.isSuperTiebreak {
                scoreFields(a: $entry.tiebreakA, b: $entry.tiebreakB)
            } else {
                scoreFields(a: $entry.a, b: $entry.b)
                if needsTiebreak {
                    HStack {
                        Text("Tiebreak").font(.caption).foregroundStyle(.secondary)
                        scoreFields(a: $entry.tiebreakA, b: $entry.tiebreakB)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func scoreFields(a: Binding<String>, b: Binding<String>) -> some View {
        HStack(spacing: 10) {
            field(teamA, text: a)
            Text("–").foregroundStyle(.secondary)
            field(teamB, text: b)
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(spacing: 2) {
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(DS.Typography.score(24))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .courtField(cornerRadius: 10)
                .onChange(of: text.wrappedValue) { _, value in
                    let digits = String(value.filter(\.isNumber).prefix(2))
                    if digits != value { text.wrappedValue = digits }
                }
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
