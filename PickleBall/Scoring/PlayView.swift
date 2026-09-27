//
//  PlayView.swift
//  PickleBall
//
//  Match setup. The sport badge picks the rules engine; players are chosen
//  as IDs (you, people you've played, or new guests); the format options
//  are the sport's real formats.
//

import SwiftUI
import UIKit
import CourtKit
import CourtNet

struct PlayView: View {
    @Environment(SportMode.self) private var sportMode
    @ObservedObject private var matchStore = MatchStore.shared
    @ObservedObject private var directory = PlayerDirectory.shared

    var onDismiss: (() -> Void)?
    /// A call out or tournament fixture: players, format and context set.
    var prefill: MatchPrefill?
    @Environment(\.dismiss) private var dismiss

    @State private var isSingles = false
    @State private var slots: [SlotEntry] = [.empty, .empty, .empty, .empty]   // A1, A2, B1, B2
    @State private var firstServer: Team = .a
    @State private var showScoreboard = false

    // Pickleball
    @State private var pickleballScoring: PickleballScoring = .sideOut
    @State private var pointsIndex = 0
    @State private var gamesIndex = 0
    private let pointsOptions = [11, 15, 21]
    private let gamesOptions = [1, 2, 3]

    // Padel
    @State private var setsIndex = 1
    @State private var deuceRule: PadelConfig.DeuceRule = .advantage
    @State private var superTiebreak = true

    private var sport: Sport { sportMode.sport }
    private var theme: SportTheme { sportMode.theme }

    // MARK: Body

    var body: some View {
        ZStack {
            DS.Palette.pageGrey.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        playersCard
                        formatCard
                        startMatchButton

                        if !matchStore.parked.isEmpty && prefill == nil {
                            parkedSection
                        }
                    }
                    .padding(.top, 14)
                    .padding(.bottom, 110)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .animation(DS.Motion.snappy, value: sport)
        .fullScreenCover(isPresented: $showScoreboard) {
            LiveMatchScreen()
        }
        .onAppear {
            Haptics.warm()
            if let prefill, slots[0] == .empty {
                apply(prefill)
            } else if slots[0] == .empty {
                slots[0] = .player(directory.me)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [theme.courtSurfaceAlt, theme.courtSurface], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)

            CourtArtView(sport: sport, lineWidth: 1.5, lineOpacity: 0.35, showsSurface: false)
                .rotationEffect(.degrees(90))
                .frame(height: 260)
                .opacity(0.8)
                .offset(y: 40)
                .allowsHitTesting(false)

            HStack(alignment: .center) {
                if onDismiss != nil {
                    Button {
                        Haptics.light()
                        onDismiss?()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.white.opacity(0.14)))
                    }
                    .buttonStyle(.press)
                    .accessibilityLabel("Go back")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("New match")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text(currentRules.summary)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .contentTransition(.opacity)
                }

                Spacer()

                SportSwitchBadge(sport: sport, showsHint: sportMode.showsHint) {
                    if let live = MatchCenter.shared.live, !live.isEnded {
                        // Never switch mid-match: open it so it can be ended or parked.
                        showScoreboard = true
                    } else {
                        sportMode.toggle()
                        MatchCenter.shared.publishPreferences(sport: sportMode.sport)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(height: 150)
        .clipped()
    }

    // MARK: Players

    private var playersCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            OffsetPillSegment(
                options: ["Singles", "Doubles"],
                selectedIndex: isSingles ? 0 : 1,
                height: 40,
                selectedFont: .system(size: 14, weight: .semibold),
                selectedColor: DS.Palette.royalBlue,
                unselectedColor: DS.Palette.textMuted,
                trackColor: DS.Palette.fieldGrey,
                pillColor: .white,
                pillShadow: true
            ) { index in
                Haptics.selection()
                withAnimation(DS.Motion.snappy) { isSingles = index == 0 }
            }

            teamSection(.a, title: "YOUR SIDE", placeholders: ["You", "Partner"])
            teamSection(.b, title: "OPPONENTS", placeholders: ["Opponent", "Opponent 2"])

            VStack(alignment: .leading, spacing: 8) {
                Text("SERVING FIRST").eyebrowStyle()
                OffsetPillSegment(
                    options: [teamLabel(.a), teamLabel(.b)],
                    selectedIndex: firstServer.rawValue,
                    height: 38,
                    selectedFont: .system(size: 12.5, weight: .semibold),
                    selectedColor: DS.Palette.royalBlue,
                    unselectedColor: DS.Palette.textMuted,
                    trackColor: DS.Palette.fieldGrey,
                    pillColor: .white,
                    pillStroke: DS.Palette.stroke,
                    minScale: 0.7
                ) { index in
                    Haptics.selection()
                    withAnimation(DS.Motion.snappy) { firstServer = index == 0 ? .a : .b }
                }
            }
        }
        .padding(16)
        .cardSurface()
        .padding(.horizontal, 16)
    }

    private func teamSection(_ team: Team, title: String, placeholders: [String]) -> some View {
        let base = team == .a ? 0 : 2
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).eyebrowStyle()
            PlayerSlotField(entry: $slots[base], placeholder: placeholders[0], accent: theme.accent, excluded: usedIDs(except: base))
            if !isSingles {
                PlayerSlotField(entry: $slots[base + 1], placeholder: placeholders[1], accent: theme.accent, excluded: usedIDs(except: base + 1))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func usedIDs(except index: Int) -> Set<PlayerID> {
        Set(slots.enumerated().compactMap { $0.offset == index ? nil : $0.element.player?.id })
    }

    private func teamLabel(_ team: Team) -> String {
        let indices = team == .a ? [0, 1] : [2, 3]
        let names = indices.prefix(isSingles ? 1 : 2).map { index -> String in
            let text = slots[index].player?.shortName ?? slots[index].text
            return text.isEmpty ? (team == .a ? "Your side" : "Opponents") : text
        }
        return Array(Set(names)).count == 1 ? names[0] : names.joined(separator: " / ")
    }

    // MARK: Format

    private var formatCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            if sport == .pickleball {
                pickleballOptions
            } else {
                padelOptions
            }
        }
        .padding(16)
        .cardSurface()
        .padding(.horizontal, 16)
        .transition(.opacity)
    }

    private var pickleballOptions: some View {
        VStack(alignment: .leading, spacing: 18) {
            segmentRow(
                "SCORING",
                options: PickleballScoring.allCases.map(\.title),
                selected: pickleballScoring == .sideOut ? 0 : 1
            ) { pickleballScoring = $0 == 0 ? .sideOut : .rally }

            segmentRow(
                "POINTS TO WIN",
                options: pointsOptions.map(String.init),
                selected: pointsIndex
            ) { pointsIndex = $0 }

            segmentRow(
                "MATCH",
                options: ["1 game", "Best of 3", "Best of 5"],
                selected: gamesIndex
            ) { gamesIndex = $0 }

            Text(pickleballScoring == .sideOut
                 ? "Only the serving side scores. Doubles calls the server number: 4-2-1."
                 : "Every rally scores a point. The rally winner serves next.")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
        }
    }

    private var padelOptions: some View {
        VStack(alignment: .leading, spacing: 18) {
            segmentRow("MATCH", options: ["1 set", "Best of 3"], selected: setsIndex) { setsIndex = $0 }

            segmentRow(
                "AT DEUCE",
                options: PadelConfig.DeuceRule.allCases.map(\.title),
                selected: PadelConfig.DeuceRule.allCases.firstIndex(of: deuceRule) ?? 0
            ) { deuceRule = PadelConfig.DeuceRule.allCases[$0] }

            if setsIndex == 1 {
                segmentRow("DECIDING SET", options: ["Super tiebreak", "Full set"], selected: superTiebreak ? 0 : 1) {
                    superTiebreak = $0 == 0
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Text(deuceExplanation)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
        }
    }

    private var deuceExplanation: String {
        switch deuceRule {
        case .advantage: return "Classic deuce and advantage. Sets to 6 with a tiebreak at 6-6."
        case .goldenPoint: return "At 40-40 the next point wins the game."
        case .starPoint: return "Two advantage cycles, then a deciding star point (FIP 2026)."
        }
    }

    private func segmentRow(_ title: String, options: [String], selected: Int, onSelect: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).eyebrowStyle()
            OffsetPillSegment(
                options: options,
                selectedIndex: selected,
                height: 38,
                selectedFont: .system(size: 13, weight: .bold),
                selectedColor: DS.Palette.royalBlue,
                unselectedColor: DS.Palette.textMuted,
                trackColor: DS.Palette.fieldGrey,
                pillColor: .white,
                pillStroke: DS.Palette.stroke,
                minScale: 0.75
            ) { index in
                Haptics.selection()
                withAnimation(DS.Motion.snappy) { onSelect(index) }
            }
        }
    }

    // MARK: Rules and lineup

    private var currentRules: MatchRules {
        switch sport {
        case .pickleball:
            let config = PickleballConfig(
                pointsToWin: pointsOptions[pointsIndex],
                gamesToWin: gamesOptions[gamesIndex],
                isDoubles: !isSingles,
                firstServer: firstServer
            )
            return .pickleball(pickleballScoring, config)
        case .padel:
            let config = PadelConfig(
                setsToWin: setsIndex == 0 ? 1 : 2,
                deuceRule: deuceRule,
                decidingSet: superTiebreak ? .superTiebreak(points: 10) : .fullSet,
                isDoubles: !isSingles,
                firstServer: firstServer
            )
            return .padel(config)
        }
    }

    /// Sets players and format from a call out or tournament fixture.
    private func apply(_ prefill: MatchPrefill) {
        if prefill.rules.sport != sportMode.sport { sportMode.toggle() }
        isSingles = !prefill.rules.isDoubles
        let a = prefill.lineup.teams.a, b = prefill.lineup.teams.b
        slots = [a.first.map(SlotEntry.player) ?? .empty, a.dropFirst().first.map(SlotEntry.player) ?? .empty,
                 b.first.map(SlotEntry.player) ?? .empty, b.dropFirst().first.map(SlotEntry.player) ?? .empty]
        switch prefill.rules {
        case .pickleball(let scoring, let config):
            pickleballScoring = scoring
            pointsIndex = pointsOptions.firstIndex(of: config.pointsToWin) ?? 0
            gamesIndex = gamesOptions.firstIndex(of: config.gamesToWin) ?? 0
        case .padel(let config):
            setsIndex = config.setsToWin == 1 ? 0 : 1
            deuceRule = config.deuceRule
            if case .fullSet = config.decidingSet { superTiebreak = false } else { superTiebreak = true }
        }
    }

    private func buildLineup() -> Lineup {
        let placeholders = ["You", "Partner", "Opponent", "Opponent 2"]
        var players: [PlayerRef] = []
        for index in 0..<4 {
            if isSingles && (index == 1 || index == 3) { continue }
            var ref = slots[index].resolved(placeholder: placeholders[index])
            // Never put the same person on court twice.
            if players.contains(where: { $0.id == ref.id }) {
                ref = PlayerDirectory.shared.addGuest(named: placeholders[index])
            }
            slots[index] = .player(ref)
            players.append(ref)
        }
        return isSingles
            ? Lineup(teamA: [players[0]], teamB: [players[1]])
            : Lineup(teamA: [players[0], players[1]], teamB: [players[2], players[3]])
    }

    // MARK: Buttons

    private var startMatchButton: some View {
        Button {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            Haptics.medium()
            MatchCenter.shared.startMatch(rules: currentRules, lineup: buildLineup(), context: prefill?.context ?? MatchContext())
            showScoreboard = true
        } label: {
            HStack(spacing: 10) {
                BallIcon(sport: sport, size: 20)
                Text("START \(sport.displayName.uppercased()) MATCH")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .tracking(1)
            }
            .foregroundStyle(theme.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(theme.accent)
                    .shadow(color: theme.accent.opacity(0.35), radius: 12, x: 0, y: 6)
            )
        }
        .buttonStyle(.press)
        .padding(.horizontal, 16)
        .accessibilityLabel("Start \(sport.displayName) match")
    }

    // MARK: Parked matches

    private var parkedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PARKED MATCHES").eyebrowStyle().padding(.horizontal, 16)
            ForEach(matchStore.parked) { setup in
                HStack(spacing: 12) {
                    BallIcon(sport: setup.rules.sport, size: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(setup.lineup.name(of: .a)) vs \(setup.lineup.name(of: .b))")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Palette.royalBlue)
                            .lineLimit(1)
                        Text("\(setup.rules.summary) · \(setup.startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        Haptics.medium()
                        if MatchCenter.shared.resume(matchID: setup.matchID) != nil {
                            showScoreboard = true
                        }
                    } label: {
                        Text("Resume")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.Palette.royalBlue))
                    }
                    .buttonStyle(.press)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .cardSurface(radius: DS.Radius.control)
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - OffsetPillSegment
//
// Sliding-pill segmented control built on a single rendered pill that
// moves via .offset() instead of matchedGeometryEffect: one view, no
// source ambiguity on first render, GPU-animated, no flicker on rapid taps.
struct OffsetPillSegment: View {
    let options: [String]
    let selectedIndex: Int
    let height: CGFloat
    let selectedFont: Font
    let selectedColor: Color
    let unselectedColor: Color
    let trackColor: Color
    let pillColor: Color
    var pillShadow: Bool = false
    var pillStroke: Color? = nil
    var minScale: CGFloat = 1.0
    let onSelect: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let pillWidth = geo.size.width / CGFloat(max(options.count, 1))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(pillColor)
                    .overlay(
                        Group {
                            if let pillStroke {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(pillStroke, lineWidth: 1)
                            }
                        }
                    )
                    .shadow(color: pillShadow ? .black.opacity(0.06) : .clear, radius: 5, x: 0, y: 2)
                    .frame(width: max(0, pillWidth - 8), height: max(0, height - 8))
                    .offset(x: CGFloat(selectedIndex) * pillWidth + 4)

                HStack(spacing: 0) {
                    ForEach(options.indices, id: \.self) { i in
                        Button {
                            // Resign the active text field before state mutates.
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            onSelect(i)
                        } label: {
                            Text(options[i])
                                .font(selectedFont)
                                .foregroundStyle(i == selectedIndex ? selectedColor : unselectedColor)
                                .lineLimit(1)
                                .minimumScaleFactor(minScale)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.press)
                        .accessibilityAddTraits(i == selectedIndex ? .isSelected : [])
                    }
                }
            }
        }
        .frame(height: height)
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(trackColor))
    }
}

#Preview {
    PlayView()
        .environment(SportMode())
}
