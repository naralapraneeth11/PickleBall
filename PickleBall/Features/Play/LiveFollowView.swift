//
//  LiveFollowView.swift
//  PickleBall
//
//  Follow a friend's live match and be the crowd: every tap sends a haptic
//  chant to the players' Watches (politely — the Watch spaces them out)
//  and fills their crowd meter. Squadmates get the squad's own chant.
//

import SwiftUI
import CourtKit
import CourtNet

struct LiveFollowView: View {
    let live: LiveMatchRow
    @Environment(\.dismiss) private var dismiss
    private let social = Social.shared
    @State private var meter = CrowdMeter()
    @State private var lastSent: Date = .distantPast

    /// The freshest copy of the row (Realtime keeps the list current).
    private var current: LiveMatchRow {
        social.liveMatches.first { $0.matchID == live.matchID } ?? live
    }

    private var chants: [Chant] {
        var list = Chant.presets
        if let squad = social.signatureChant(for: live) { list.insert(squad, at: 0) }
        return list
    }

    var body: some View {
        let row = current
        let theme = row.sport.theme
        ZStack {
            DS.Palette.night.ignoresSafeArea()
            CourtArtView(sport: row.sport, lineWidth: 1.5, lineOpacity: 0.1, showsSurface: false)
                .padding(40)
                .allowsHitTesting(false)

            VStack(spacing: 24) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(DS.Palette.nightRaised))
                    }
                    .accessibilityLabel("Close")
                    Spacer()
                    Label("LIVE", systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(DS.Palette.loss)
                }

                Spacer()

                VStack(spacing: 18) {
                    ForEach(Team.allCases, id: \.self) { team in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.lineup.name(of: team, separator: " & "))
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                if row.score.servingTeam == team {
                                    Text("SERVING").font(DS.Typography.eyebrow).foregroundStyle(theme.accent)
                                }
                            }
                            Spacer()
                            Text("\(row.score.games[team])")
                                .font(DS.Typography.score(22))
                                .foregroundStyle(DS.Palette.nightMuted)
                                .frame(width: 34)
                            Text(row.score.points[team])
                                .font(DS.Typography.hero(56))
                                .foregroundStyle(.white)
                                .contentTransition(.numericText())
                                .frame(minWidth: 80, alignment: .trailing)
                        }
                    }
                    Text([row.score.phaseTitle, row.score.pressure, row.score.history].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Palette.nightMuted)
                }
                .padding(22)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(DS.Palette.nightRaised))
                .animation(DS.Motion.score, value: row.score)

                Spacer()

                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let level = meter.level(at: context.date)
                    VStack(spacing: 8) {
                        Text("CROWD").font(DS.Typography.eyebrow).tracking(2).foregroundStyle(DS.Palette.nightMuted)
                        Capsule()
                            .fill(DS.Palette.hairline)
                            .frame(height: 10)
                            .overlay(alignment: .leading) {
                                GeometryReader { geo in
                                    Capsule().fill(theme.accent).frame(width: geo.size.width * level)
                                }
                            }
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(chants) { chant in
                        Button {
                            tap(chant)
                        } label: {
                            Text(chant.name)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(chant.id == "squad" ? .black : .white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 58)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(chant.id == "squad" ? theme.accent : DS.Palette.nightRaised))
                        }
                        .buttonStyle(.press)
                        .accessibilityHint("Sends a haptic cheer to the players")
                    }
                }

                Text("Cheers buzz the players’ Apple Watch between points.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.nightMuted)
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
        .task {
            await social.follow(live)
        }
        .onDisappear {
            Task { await social.stopFollowing() }
        }
    }

    private func tap(_ chant: Chant) {
        // A cheer a second is plenty from one phone.
        guard Date().timeIntervalSince(lastSent) > 1 else { return }
        lastSent = Date()
        Haptics.light()
        meter.add(at: Date())
        Task { await social.sendTap(chantID: chant.id, to: current) }
    }
}
