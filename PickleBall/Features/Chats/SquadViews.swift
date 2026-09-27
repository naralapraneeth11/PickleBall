//
//  SquadViews.swift
//  PickleBall
//
//  Squads: create one from friends, invite by link, leave, and set the
//  squad's signature chant — the crowd tap only squadmates can send.
//

import SwiftUI
import CourtKit
import CourtNet

struct CreateSquadView: View {
    @Environment(\.dismiss) private var dismiss
    private let social = Social.shared
    @State private var name = ""
    @State private var members: Set<UUID> = []
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Squad name", text: $name)
                } footer: {
                    Text("Your squad gets a chat, a squad belt and tournaments.")
                }
                Section("Friends") {
                    if social.friends.isEmpty {
                        Text("Add friends first; you can also invite people with a squad link later.").foregroundStyle(.secondary)
                    }
                    ForEach(social.friends) { friend in
                        Button {
                            if members.contains(friend.id) { members.remove(friend.id) } else { members.insert(friend.id) }
                            Haptics.selection()
                        } label: {
                            HStack {
                                ProfileAvatar(userID: friend.id, size: 32)
                                Text(friend.displayName).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: members.contains(friend.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(members.contains(friend.id) ? DS.Palette.electricBlue : Color.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New squad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        isCreating = true
                        Task {
                            let id = await social.createSquad(name: name, members: Array(members))
                            isCreating = false
                            if id != nil {
                                Haptics.success()
                                dismiss()
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
            .noticeToast()
        }
    }
}

struct SquadInfoView: View {
    let squadID: UUID
    @Environment(\.dismiss) private var dismiss
    private let social = Social.shared
    @State private var inviteURL: URL?
    @State private var showAdd = false
    @State private var showChant = false
    @State private var confirmLeave = false
    @State private var renaming = false
    @State private var newName = ""

    private var squad: SquadRow? { social.squad(squadID) }

    var body: some View {
        List {
            Section {
                ForEach(social.members(of: squadID), id: \.self) { member in
                    NavigationLink {
                        ProfileView(playerID: PlayerID(rawValue: member))
                    } label: {
                        HStack(spacing: 12) {
                            ProfileAvatar(userID: member, size: 36)
                            Text(social.name(of: member))
                            if member == social.userID { Text("You").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if MatchStore.shared.belts.squadBelts(squadID).contains(where: { $0.isHeld(by: PlayerID(rawValue: member)) }) {
                                BeltBadge(tier: .gold, size: 18)
                            }
                        }
                    }
                }
                Button { showAdd = true } label: { Label("Add friends", systemImage: "person.badge.plus") }
                Button { Task { await makeInvite() } } label: { Label("Share squad link", systemImage: "link") }
            } header: {
                Text("Members")
            }

            let belts = MatchStore.shared.belts.squadBelts(squadID)
            if !belts.isEmpty {
                Section("Squad belts") {
                    ForEach(belts) { belt in
                        NavigationLink { BeltDetailView(belt: belt) } label: { BeltChip(belt: belt) }
                    }
                }
            }

            Section {
                Button { showChant = true } label: {
                    Label(squad?.signatureChant == nil ? "Create the squad chant" : "Edit the squad chant", systemImage: "waveform")
                }
            } footer: {
                Text("A haptic rhythm only squadmates can send during live matches.")
            }

            Section {
                Button("Rename squad") {
                    newName = squad?.name ?? ""
                    renaming = true
                }
                Button("Leave squad", role: .destructive) { confirmLeave = true }
            }
        }
        .navigationTitle(squad?.name ?? "Squad")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(item: Binding(get: { inviteURL.map(IdentifiedURL.init) }, set: { inviteURL = $0?.url })) { item in
            ShareSheet(items: ["Join \(squad?.name ?? "our squad") on PickleBall: \(item.url.absoluteString)", item.url])
        }
        .sheet(isPresented: $showAdd) {
            AddToSquadView(squadID: squadID)
        }
        .sheet(isPresented: $showChant) {
            ChantEditorView(squadID: squadID, initial: squad?.signatureChant ?? [])
        }
        .alert("Rename squad", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") { Task { await social.renameSquad(squadID, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Leave \(squad?.name ?? "this squad")?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                Task {
                    await social.leaveSquad(squadID)
                    dismiss()
                }
            }
        }
        .noticeToast()
    }

    private func makeInvite() async {
        guard let link = await social.inviteLink(.squad, target: squadID) else { return }
        inviteURL = social.shareURL(for: link)
    }
}

private struct AddToSquadView: View {
    let squadID: UUID
    @Environment(\.dismiss) private var dismiss
    private let social = Social.shared

    var body: some View {
        NavigationStack {
            List {
                let members = Set(social.members(of: squadID))
                let candidates = social.friends.filter { !members.contains($0.id) }
                if candidates.isEmpty {
                    Text("All your friends are already in.").foregroundStyle(.secondary)
                }
                ForEach(candidates) { friend in
                    PersonRow(userID: friend.id, name: friend.displayName, username: friend.username) {
                        PillButton(title: "Add", prominent: true) {
                            Task { await social.addToSquad(squadID, friend: friend.id) }
                        }
                    }
                }
            }
            .navigationTitle("Add friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// Tap out a rhythm (up to ten taps in three seconds) to make the chant.
struct ChantEditorView: View {
    let squadID: UUID
    let initial: [Chant.Beat]
    @Environment(\.dismiss) private var dismiss
    private let social = Social.shared
    @State private var beats: [Chant.Beat] = []
    @State private var startedAt: Date?

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Text("Tap the pad to record the squad chant.")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(0..<Chant.maxBeats, id: \.self) { index in
                        Circle()
                            .fill(index < beats.count ? DS.Palette.electricBlue : DS.Palette.fieldGrey)
                            .frame(width: 14, height: 14)
                    }
                }
                Button {
                    tap()
                } label: {
                    Circle()
                        .fill(DS.Palette.royalBlue)
                        .frame(width: 200, height: 200)
                        .overlay(Image(systemName: "hand.tap.fill").font(.system(size: 52)).foregroundStyle(.white))
                }
                .buttonStyle(.press)
                .accessibilityLabel("Tap to add a beat")
                HStack(spacing: 20) {
                    Button("Clear") {
                        beats = []
                        startedAt = nil
                    }
                    Button("Play") { preview() }.disabled(beats.isEmpty)
                }
            }
            .padding()
            .navigationTitle("Squad chant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let chant = Chant(id: "squad", name: "Squad", beats: beats)
                        Task {
                            await social.setSignatureChant(squadID, beats: chant.beats)
                            dismiss()
                        }
                    }
                    .disabled(beats.count < 2)
                }
            }
            .onAppear { beats = initial }
        }
    }

    private func tap() {
        let now = Date()
        if startedAt == nil || beats.count >= Chant.maxBeats {
            beats = []
            startedAt = now
        }
        let offset = now.timeIntervalSince(startedAt ?? now)
        guard offset <= Chant.maxDuration else { return }
        beats.append(Chant.Beat(at: offset, strength: 1))
        Haptics.medium()
    }

    private func preview() {
        for beat in beats {
            DispatchQueue.main.asyncAfter(deadline: .now() + beat.at) { Haptics.medium() }
        }
    }
}
