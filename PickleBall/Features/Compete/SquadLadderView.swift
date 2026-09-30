//
//  SquadLadderView.swift
//  PickleBall
//
//  The squad ladder: one ranking per sport you climb by beating people
//  above you. Built from the squad's confirmed matches, so it's the same on
//  every phone and nobody has to keep score of the scores.
//

import SwiftUI
import CourtKit
import CourtNet

struct SquadLadderView: View {
    let squadID: UUID
    @Environment(SportMode.self) private var sportMode
    @ObservedObject private var matchStore = MatchStore.shared
    private let social = Social.shared
    @State private var sport: Sport = .pickleball
    @State private var callOut: UUID?

    private var members: [UUID] {
        social.squadMembers.filter { $0.squadID == squadID }
            .sorted { ($0.joinedAt ?? .distantPast, $0.userID.uuidString) < ($1.joinedAt ?? .distantPast, $1.userID.uuidString) }
            .map(\.userID)
    }

    private var rungs: [LadderRung] {
        let results = matchStore.confirmedResults.filter { $0.squadID == squadID && $0.sport == sport }
        return Ladder.compute(members: members.map(PlayerID.init(rawValue:)), results: results)
    }

    var body: some View {
        List {
            Section {
                Picker("Sport", selection: $sport) {
                    ForEach(Sport.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(rungs) { rung in
                    row(rung)
                }
            } footer: {
                Text("Beat someone above you and you take their rung; everyone in between steps down one. Squad matches only.")
            }
        }
        .navigationTitle("Ladder")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { sport = sportMode.sport }
        .sheet(item: Binding(get: { callOut.map(IdentifiedUUID.init) }, set: { callOut = $0?.id })) { target in
            CallOutComposerView(opponents: [target.id], squadID: squadID)
        }
    }

    private func row(_ rung: LadderRung) -> some View {
        let id = rung.player.rawValue
        let isMe = id == social.userID
        return HStack(spacing: 12) {
            Text("\(rung.rank)")
                .font(.system(size: 17, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(rung.rank == 1 ? DS.Palette.gold : .secondary)
                .frame(width: 26)
            ProfileAvatar(userID: id, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(social.name(of: id)).font(.system(size: 16, weight: .semibold, design: .rounded))
                    if isMe { Text("You").font(.caption).foregroundStyle(.secondary) }
                }
                Text(detail(rung)).font(DS.Typography.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if rung.lastMove != 0 {
                Label("\(abs(rung.lastMove))", systemImage: rung.lastMove > 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(rung.lastMove > 0 ? DS.Palette.win : DS.Palette.loss)
                    .labelStyle(.titleAndIcon)
            }
        }
        .swipeActions {
            if !isMe, social.relationship(with: id) == .friend {
                Button("Call out") { callOut = id }.tint(DS.Palette.electricBlue)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func detail(_ rung: LadderRung) -> String {
        var parts = [String(localized: "\(rung.wins)–\(rung.losses)")]
        if let since = rung.topSince {
            parts.append(String(localized: "top for \(max(0, Int(Date().timeIntervalSince(since) / 86_400)))d"))
        } else if rung.lastPlayed == nil {
            parts.append(String(localized: "no ladder matches yet"))
        }
        return parts.joined(separator: " · ")
    }
}

struct IdentifiedUUID: Identifiable {
    let id: UUID
}
