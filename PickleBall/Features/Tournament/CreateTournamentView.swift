//
//  CreateTournamentView.swift
//  PickleBall
//
//  One tap from a squad: everyone in it is entered. Add guests by name,
//  pick the format and the date, and the schedule is generated.
//

import SwiftUI
import CourtKit
import CourtNet

struct CreateTournamentView: View {
    var squadID: UUID?
    /// "Run it again": a finished tournament to copy the setup from.
    var template: TournamentRow?
    @Environment(\.dismiss) private var dismiss
    @Environment(SportMode.self) private var sportMode
    private let social = Social.shared

    @State private var selectedSquad: UUID?
    @State private var name = ""
    @State private var sport: Sport = .pickleball
    @State private var format: TournamentFormat = .roundRobin
    @State private var isDoubles = false
    @State private var entrants: Set<UUID> = []
    @State private var guests: [PlayerRef] = []
    @State private var guestName = ""
    @State private var courts = 1
    @State private var mexicanoRounds = 6
    @State private var poolCount = 2
    @State private var advancing = 2
    @State private var hasDate = true
    @State private var startsAt = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date().addingTimeInterval(86_400)) ?? Date()
    @State private var court: CourtTag?
    @State private var isCreating = false
    @State private var pairing: Pairing = .balanced
    @State private var pendingEntrants: Set<UUID>?

    /// How doubles pairs are made.
    enum Pairing: String, CaseIterable, Identifiable {
        case balanced, random, inOrder
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .balanced: return "Balanced"
            case .random: return "Random"
            case .inOrder: return "As listed"
            }
        }
    }

    private var members: [UUID] { selectedSquad.map(social.members(of:)) ?? [] }
    private var players: [PlayerRef] {
        members.filter(entrants.contains).map(social.playerRef(for:)) + guests
    }

    private var rules: MatchRules {
        switch (sport, format) {
        case (.padel, .americano), (.padel, .mexicano):
            // Americano and Mexicano matches are short, scored by points.
            return .padel(PadelConfig(setsToWin: 1, gamesPerSet: 6, isDoubles: true))
        case (.pickleball, .kingOfTheCourt):
            return .pickleball(.rally, PickleballConfig(pointsToWin: 11, gamesToWin: 1, isDoubles: isDoubles))
        default:
            return .standard(for: sport, isDoubles: format.ranksIndividuals && format != .kingOfTheCourt ? true : isDoubles)
        }
    }

    /// Players each format needs.
    private var problem: String? {
        let count = players.count
        switch format {
        case .roundRobin:
            if isDoubles { return count >= 4 && count.isMultiple(of: 2) ? nil : "Doubles round robin needs an even number of players (4+)." }
            return count >= 3 ? nil : "Round robin needs at least 3 players."
        case .kingOfTheCourt:
            let size = KingOfTheCourt.courtSize(doubles: isDoubles)
            return count >= size * 2 ? nil : "King of the Court needs at least \(size * 2) players."
        case .americano:
            return count >= 4 ? nil : "Americano needs at least 4 players."
        case .mexicano:
            return count >= 4 ? nil : "Mexicano needs at least 4 players."
        case .singleElimination, .doubleElimination, .pools:
            let entrants = isDoubles ? count / 2 : count
            if isDoubles, !count.isMultiple(of: 2) { return "Doubles needs an even number of players." }
            if format == .pools { return entrants >= 4 ? nil : "Pools need at least 4 entrants." }
            return entrants >= (format == .doubleElimination ? 3 : 2) ? nil : "A knockout needs more entrants."
        }
    }

    private var needsPairs: Bool {
        isDoubles && (format == .roundRobin || format.isBracket || format == .pools)
    }

    private var entrantCount: Int { isDoubles && needsPairs ? players.count / 2 : players.count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Group {
                        Picker("Squad", selection: $selectedSquad) {
                            ForEach(social.squads) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                        TextField("Name", text: $name, prompt: Text(defaultName))
                    }
                    .courtRows()
                }

                Section {
                    Group {
                        Picker("Sport", selection: $sport) {
                            ForEach(Sport.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Picker("Format", selection: $format) {
                            ForEach(TournamentFormat.available(for: sport)) { Text($0.title).tag($0) }
                        }
                        if !format.ranksByPoints {
                            Toggle("Doubles", isOn: $isDoubles)
                        }
                        if format == .mexicano {
                            Stepper("Rounds: \(mexicanoRounds)", value: $mexicanoRounds, in: 3...12)
                        }
                        if format == .pools {
                            Stepper("Pools: \(poolCount)", value: $poolCount, in: 1...max(1, entrantCount / 3))
                            Stepper("Through from each pool: \(advancing)", value: $advancing, in: 1...max(1, entrantCount / max(poolCount, 1)))
                        }
                    }
                    .courtRows()
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(format.blurb)
                        if format.isBracket || format == .pools || format == .mexicano {
                            Text("Seeded by level, so the strongest meet last.")
                        }
                    }
                }

                Section {
                    Group {
                        ForEach(members, id: \.self) { member in
                            Button {
                                if entrants.contains(member) { entrants.remove(member) } else { entrants.insert(member) }
                            } label: {
                                HStack {
                                    ProfileAvatar(userID: member, size: 30)
                                    Text(social.name(of: member)).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: entrants.contains(member) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(entrants.contains(member) ? DS.Palette.electricBlue : Color.secondary)
                                }
                            }
                        }
                        ForEach(guests) { guest in
                            HStack {
                                Avatar(name: guest.displayName, color: DS.Palette.textMuted, size: 30)
                                Text(guest.displayName)
                                Text("Guest").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { guests.remove(atOffsets: $0) }
                        HStack {
                            TextField("Add a guest", text: $guestName)
                                .onSubmit(addGuest)
                            Button("Add", action: addGuest).disabled(guestName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        if needsPairs {
                            Picker("Pairs", selection: $pairing) {
                                ForEach(Pairing.allCases) { Text($0.title).tag($0) }
                            }
                        }
                    }
                    .courtRows()
                } header: {
                    Text("Players (\(players.count))")
                } footer: {
                    if let problem {
                        Text(problem).foregroundStyle(DS.Palette.loss)
                    } else if needsPairs {
                        Text(pairingNote)
                    }
                }

                Section {
                    Group {
                        Stepper("Courts: \(courts)", value: $courts, in: 1...8)
                        Toggle("Set a start time", isOn: $hasDate)
                        if hasDate {
                            DatePicker("Starts", selection: $startsAt)
                        }
                        CourtPickerRow(court: $court)
                    }
                    .courtRows()
                } header: {
                    Text("Schedule")
                } footer: {
                    if let estimate { Text(estimate) }
                }
            }
            .courtList()
            .navigationTitle("New tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .fontWeight(.semibold)
                        .disabled(problem != nil || selectedSquad == nil || isCreating)
                }
            }
            .onAppear {
                sport = sportMode.sport
                if sport == .padel { format = .americano }
                poolCount = Pools.suggestedCount(entrants: max(players.count, 4))
                selectedSquad = squadID ?? social.squads.first?.id
                entrants = Set(members)
                if let template { apply(template) }
            }
            .onChange(of: selectedSquad) { _, _ in
                if let pendingEntrants {
                    entrants = pendingEntrants
                    self.pendingEntrants = nil
                } else {
                    entrants = Set(members)
                }
            }
            .onChange(of: sport) { _, newSport in
                if !TournamentFormat.available(for: newSport).contains(format) { format = .roundRobin }
            }
            .noticeToast()
        }
    }

    /// Same squad, sport, format and courts; the same players where they're
    /// still in the squad.
    private func apply(_ template: TournamentRow) {
        let squadChanges = selectedSquad != template.squadID
        selectedSquad = template.squadID
        sport = template.sport
        format = template.format
        isDoubles = template.rules.isDoubles
        courts = template.settings?.courts ?? courts
        mexicanoRounds = template.settings?.rounds ?? mexicanoRounds
        poolCount = template.settings?.pools ?? poolCount
        advancing = template.settings?.advancing ?? advancing
        let previous = Set(social.entrants(of: template))
        let squadMembers = social.members(of: template.squadID)
        let returning = Set(squadMembers.filter(previous.contains))
        let chosen = returning.isEmpty ? Set(squadMembers) : returning
        entrants = chosen
        // Switching squad resets the entrants; keep these instead.
        if squadChanges { pendingEntrants = chosen }
    }

    private var pairingNote: LocalizedStringKey {
        switch pairing {
        case .balanced: return "The strongest player is paired with the weakest, and so on, by level."
        case .random: return "Pairs are drawn at random when you tap Create."
        case .inOrder: return "Pairs stay together in the order listed: first and second, third and fourth."
        }
    }

    private func makePairs(_ list: [PlayerRef]) -> [[PlayerRef]] {
        var ordered = list
        switch pairing {
        case .inOrder:
            break
        case .random:
            ordered.shuffle()
        case .balanced:
            let levels = Dictionary(list.map { ($0.id, social.level(of: $0.id.rawValue, in: sport) ?? PlayerLevel().level) },
                                    uniquingKeysWith: { first, _ in first })
            let byLevel = list.sorted { (levels[$0.id] ?? 0) > (levels[$1.id] ?? 0) }
            ordered = []
            var low = 0, high = byLevel.count - 1
            while low < high {
                ordered.append(byLevel[low])
                ordered.append(byLevel[high])
                low += 1
                high -= 1
            }
        }
        return stride(from: 0, to: ordered.count - 1, by: 2).map { [ordered[$0], ordered[$0 + 1]] }
    }

    // MARK: Estimate

    /// "About 7 rounds · 1 hr 45 min": from the real schedule generators.
    private var estimate: String? {
        guard problem == nil, !players.isEmpty else { return nil }
        let ids = players.map { _ in PlayerID() }
        let units: [[PlayerID]] = needsPairs
            ? stride(from: 0, to: ids.count - 1, by: 2).map { [ids[$0], ids[$0 + 1]] }
            : ids.map { [$0] }
        let rounds: Int
        switch format {
        case .roundRobin:
            rounds = RoundRobin.schedule(units, courts: courts).map(\.round).max() ?? 0
        case .americano:
            rounds = Americano.schedule(ids, courts: courts).map(\.round).max() ?? 0
        case .mexicano:
            rounds = mexicanoRounds
        case .kingOfTheCourt:
            return String(localized: "King of the Court runs as long as you like: end it from the tournament screen.")
        case .singleElimination, .doubleElimination:
            let depth = Int(log2(Double(Bracket.size(for: units.count))).rounded(.up))
            let perRound = Int((Double(Bracket.size(for: units.count)) / 2 / Double(courts)).rounded(.up))
            let base = depth * max(1, min(perRound, 2))
            rounds = format == .doubleElimination ? base * 2 + 1 : base
        case .pools:
            let split = Pools.split(units, pools: poolCount)
            let poolRounds = Pools.schedule(split).map(\.round).max() ?? 0
            let knockout = Int(log2(Double(max(2, poolCount * advancing))).rounded(.up))
            rounds = poolRounds + knockout
        }
        guard rounds > 0 else { return nil }
        let minutes = rounds * minutesPerMatch
        let time = Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        return String(localized: "About \(rounds) rounds · \(time) on \(courts) courts")
    }

    /// A rough match length, with time to change over.
    private var minutesPerMatch: Int {
        switch rules {
        case .pickleball(_, let config):
            return config.gamesToWin <= 1 ? (config.pointsToWin <= 11 ? 15 : 22) : 40
        case .padel(let config):
            return config.setsToWin <= 1 ? 35 : 80
        }
    }

    private var defaultName: String {
        "\(social.squad(selectedSquad)?.name ?? "Squad") \(format.title)"
    }

    private func addGuest() {
        let trimmed = guestName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guests.append(PlayerDirectory.shared.addGuest(named: trimmed))
        guestName = ""
    }

    private func create() {
        guard let squad = selectedSquad else { return }
        isCreating = true
        let list = players
        let pairs: [[PlayerRef]]? = needsPairs ? makePairs(list) : nil
        let options = Social.TournamentOptions(courts: courts, mexicanoRounds: mexicanoRounds,
                                               pools: format == .pools ? poolCount : nil,
                                               advancing: format == .pools ? advancing : nil,
                                               startsAt: hasDate ? startsAt : nil, court: court)
        Task {
            let id = await social.createTournament(
                squadID: squad, name: name.isEmpty ? defaultName : name, format: format, rules: rules,
                entrants: list, pairs: pairs, options: options
            )
            isCreating = false
            if id != nil {
                Haptics.success()
                dismiss()
            }
        }
    }
}
