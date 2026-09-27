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
    @State private var hasDate = true
    @State private var startsAt = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date().addingTimeInterval(86_400)) ?? Date()
    @State private var court: CourtTag?
    @State private var isCreating = false

    private var members: [UUID] { selectedSquad.map(social.members(of:)) ?? [] }
    private var players: [PlayerRef] {
        members.filter(entrants.contains).map(social.playerRef(for:)) + guests
    }

    private var rules: MatchRules {
        switch (sport, format) {
        case (.padel, .americano):
            // Americano matches are short: to 24 points, scored by points.
            return .padel(PadelConfig(setsToWin: 1, gamesPerSet: 6, isDoubles: true))
        case (.pickleball, .kingOfTheCourt):
            return .pickleball(.rally, PickleballConfig(pointsToWin: 11, gamesToWin: 1, isDoubles: isDoubles))
        default:
            return .standard(for: sport, isDoubles: format == .americano ? true : isDoubles)
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
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Squad", selection: $selectedSquad) {
                        ForEach(social.squads) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    TextField("Name", text: $name, prompt: Text(defaultName))
                }

                Section {
                    Picker("Sport", selection: $sport) {
                        ForEach(Sport.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Format", selection: $format) {
                        ForEach(TournamentFormat.available(for: sport)) { Text($0.title).tag($0) }
                    }
                    if format != .americano {
                        Toggle("Doubles", isOn: $isDoubles)
                    }
                } footer: {
                    Text(format.blurb + (format == .roundRobin && isDoubles ? " Pairs stay together, in the order entered." : ""))
                }

                Section {
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
                } header: {
                    Text("Players (\(players.count))")
                } footer: {
                    if let problem { Text(problem).foregroundStyle(DS.Palette.loss) }
                }

                Section("Schedule") {
                    Stepper("Courts: \(courts)", value: $courts, in: 1...8)
                    Toggle("Set a start time", isOn: $hasDate)
                    if hasDate {
                        DatePicker("Starts", selection: $startsAt)
                    }
                    CourtPickerRow(court: $court)
                }
            }
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
                selectedSquad = squadID ?? social.squads.first?.id
                entrants = Set(members)
            }
            .onChange(of: selectedSquad) { _, _ in entrants = Set(members) }
            .onChange(of: sport) { _, newSport in
                if !TournamentFormat.available(for: newSport).contains(format) { format = .roundRobin }
            }
            .noticeToast()
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
        let pairs: [[PlayerRef]]? = format == .roundRobin && isDoubles
            ? stride(from: 0, to: list.count - 1, by: 2).map { [list[$0], list[$0 + 1]] }
            : nil
        Task {
            let id = await social.createTournament(
                squadID: squad, name: name.isEmpty ? defaultName : name, format: format, rules: rules,
                entrants: list, pairs: pairs, courts: courts, startsAt: hasDate ? startsAt : nil, court: court
            )
            isCreating = false
            if id != nil {
                Haptics.success()
                dismiss()
            }
        }
    }
}
