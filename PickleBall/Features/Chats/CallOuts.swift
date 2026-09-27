//
//  CallOuts.swift
//  PickleBall
//
//  Call out a friend or a pair: sport, format, and optionally when and
//  where. They accept, counter or decline. The result closes it.
//

import SwiftUI
import CourtKit
import CourtNet

struct CallOutComposerView: View {
    /// Friends to challenge (one for singles, two for doubles).
    var opponents: [UUID] = []
    var squadID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(SportMode.self) private var sportMode
    private let social = Social.shared

    @State private var sport: Sport = .pickleball
    @State private var isDoubles = false
    @State private var challenged: [UUID] = []
    @State private var partner: UUID?
    @State private var hasTime = false
    @State private var time = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var court: CourtTag?
    @State private var showCourtSearch = false
    @State private var isSending = false

    private var rules: MatchRules { .standard(for: sport, isDoubles: isDoubles) }
    private var canSend: Bool {
        challenged.count == (isDoubles ? 2 : 1) && (!isDoubles || partner != nil) && !isSending
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Sport", selection: $sport) {
                        ForEach(Sport.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Format", selection: $isDoubles) {
                        Text("Singles").tag(false)
                        Text("Doubles").tag(true)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(rules.summary)
                }

                if isDoubles {
                    Section("Your partner") {
                        friendPicker(selection: Binding(get: { partner.map { [$0] } ?? [] }, set: { partner = $0.last }), limit: 1,
                                     excluding: Set(challenged))
                    }
                }

                Section(isDoubles ? "Call out a pair" : "Call out") {
                    friendPicker(selection: $challenged, limit: isDoubles ? 2 : 1, excluding: Set([partner].compactMap { $0 }))
                }

                Section {
                    Toggle("Set a time", isOn: $hasTime)
                    if hasTime {
                        DatePicker("When", selection: $time, in: Date()...)
                    }
                    Button {
                        showCourtSearch = true
                    } label: {
                        LabeledContent("Court") { Text(court?.name ?? "Optional").foregroundStyle(court == nil ? .secondary : .primary) }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Call out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { send() }.fontWeight(.semibold).disabled(!canSend)
                }
            }
            .sheet(isPresented: $showCourtSearch) { CourtSearchView { court = $0 } }
            .onAppear {
                sport = sportMode.sport
                if challenged.isEmpty { challenged = opponents.filter { social.friendIDs.contains($0) } }
                isDoubles = challenged.count == 2
            }
            .onChange(of: isDoubles) { _, doubles in
                if !doubles { challenged = Array(challenged.prefix(1)); partner = nil }
            }
            .noticeToast()
        }
    }

    private func friendPicker(selection: Binding<[UUID]>, limit: Int, excluding: Set<UUID>) -> some View {
        ForEach(social.friends.filter { !excluding.contains($0.id) }) { friend in
            Button {
                var list = selection.wrappedValue
                if let index = list.firstIndex(of: friend.id) {
                    list.remove(at: index)
                } else {
                    list.append(friend.id)
                    if list.count > limit { list.removeFirst() }
                }
                selection.wrappedValue = list
                Haptics.selection()
            } label: {
                HStack {
                    ProfileAvatar(userID: friend.id, size: 32)
                    Text(friend.displayName).foregroundStyle(.primary)
                    Spacer()
                    if selection.wrappedValue.contains(friend.id) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.Palette.electricBlue)
                    }
                }
            }
        }
    }

    private func send() {
        guard let me = social.userID else { return }
        isSending = true
        let draft = CallOutDraft(challengers: [me] + [partner].compactMap { $0 }, challenged: challenged, rules: rules,
                                 proposedAt: hasTime ? time : nil, court: court, squadID: squadID)
        Task {
            let ok = await social.createCallOut(draft)
            isSending = false
            if ok {
                Haptics.success()
                dismiss()
            }
        }
    }
}

/// A call out with the moves the viewer can make.
struct CallOutCard: View {
    let callOut: CallOutRow
    var onPlay: (() -> Void)?
    var onEnterScore: (() -> Void)?

    private let social = Social.shared
    @State private var showCounter = false
    @State private var counterTime = Date()
    @State private var counterCourt: CourtTag?

    var body: some View {
        let model = callOut.callOut
        let me = social.userID.map(PlayerID.init(rawValue:)) ?? PlayerID()
        let moves = model.moves(for: me)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "flag.2.crossed.fill").foregroundStyle(DS.Palette.loss)
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Text(statusText(model.status)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(details(model))
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if moves.contains(.accept) {
                    PillButton(title: "Accept", systemImage: "checkmark", prominent: true, tint: DS.Palette.win) { respond(.accept) }
                    PillButton(title: "Counter", systemImage: "arrow.left.arrow.right") { showCounter = true }
                    PillButton(title: "Decline", tint: DS.Palette.loss) { respond(.decline) }
                } else if model.status == .accepted {
                    if let onPlay { PillButton(title: "Start match", systemImage: "play.fill", prominent: true, action: onPlay) }
                    if let onEnterScore { PillButton(title: "Enter score", systemImage: "square.and.pencil", action: onEnterScore) }
                }
                if moves.contains(.cancel), !moves.contains(.accept) {
                    PillButton(title: "Cancel", tint: DS.Palette.textMuted) { respond(.cancel) }
                }
            }
        }
        .sheet(isPresented: $showCounter) {
            NavigationStack {
                Form {
                    DatePicker("When", selection: $counterTime, in: Date()...)
                    CourtPickerRow(court: $counterCourt)
                }
                .navigationTitle("Counter")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showCounter = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") {
                            respond(.counter(.init(proposedAt: counterTime, court: counterCourt)))
                            showCounter = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var title: String {
        let challengers = callOut.challengers.map(social.firstName(of:)).joined(separator: " & ")
        let challenged = callOut.challenged.map(social.firstName(of:)).joined(separator: " & ")
        return "\(challengers) vs \(challenged)"
    }

    private func details(_ model: CallOut) -> String {
        let terms = model.currentTerms
        var parts = ["\(model.sport.displayName) · \(model.rules.summary)"]
        parts.append(terms.proposedAt.map { RelativeTime.upcoming($0) } ?? "Any time")
        if let court = terms.court { parts.append(court.name) }
        if model.status == .countered, let by = model.counterBy { parts.append("Counter from \(social.firstName(of: by.rawValue))") }
        return parts.joined(separator: " · ")
    }

    private func statusText(_ status: CallOut.Status) -> String {
        switch status {
        case .pending: return "Waiting"
        case .countered: return "Countered"
        case .accepted: return "On"
        case .declined: return "Declined"
        case .completed: return "Played"
        case .cancelled: return "Called off"
        }
    }

    private func respond(_ move: CallOut.Move) {
        Haptics.medium()
        Task { await social.respond(to: callOut, with: move) }
    }
}

/// A form row that opens court search.
struct CourtPickerRow: View {
    @Binding var court: CourtTag?
    @State private var showSearch = false

    var body: some View {
        Button {
            showSearch = true
        } label: {
            LabeledContent("Court") { Text(court?.name ?? "Optional").foregroundStyle(court == nil ? .secondary : .primary) }
        }
        .foregroundStyle(.primary)
        .sheet(isPresented: $showSearch) { CourtSearchView { court = $0 } }
    }
}
