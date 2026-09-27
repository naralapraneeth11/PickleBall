//
//  WatchSetupView.swift
//  Pickleball watch Watch App
//
//  Match setup on the wrist in a few taps: each page auto-advances. The
//  format pages match the sport; opponents come from the players the phone
//  has synced, so Watch matches are recorded with real player IDs.
//

import SwiftUI
import WatchKit
import CourtKit

struct WatchSetupView: View {
    let sport: Sport
    let onComplete: (MatchRules, Lineup) -> Void
    let onCancel: () -> Void

    @Environment(WatchMatchSession.self) private var session

    private enum Step: Int, CaseIterable {
        case format, scoring, length, opponent, serve
    }

    @State private var step: Step = .format
    @State private var isDoubles = true
    // Pickleball
    @State private var scoring: PickleballScoring = .sideOut
    @State private var points = 11
    @State private var gamesToWin = 1
    // Padel
    @State private var setsToWin = 2
    @State private var deuceRule: PadelConfig.DeuceRule = .advantage
    // Players
    @State private var opponent: PlayerRef?

    private var theme: SportTheme { sport.theme }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button(action: back) {
                    Image(systemName: step == .format ? "xmark" : "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(DS.Palette.nightRaised))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(step == .format ? "Cancel" : "Back")
                Spacer()
                Text(title)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(theme.accent)
                Spacer()
                Color.clear.frame(width: 28, height: 28)
            }

            page
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
                .id(step)
        }
        .padding(.horizontal, 6)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: step)
    }

    private var title: String {
        switch step {
        case .format: return sport.displayName.uppercased()
        case .scoring: return sport == .pickleball ? "SCORING" : "AT DEUCE"
        case .length: return sport == .pickleball ? "POINTS · GAMES" : "SETS"
        case .opponent: return "OPPONENT"
        case .serve: return "SERVE FIRST?"
        }
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case .format:
            options([("Singles", false), ("Doubles", true)], selected: isDoubles) { isDoubles = $0 }
        case .scoring:
            if sport == .pickleball {
                options([("Side-out", PickleballScoring.sideOut), ("Rally", PickleballScoring.rally)], selected: scoring) {
                    scoring = $0
                    points = $0 == .rally ? 21 : 11
                }
            } else {
                options(PadelConfig.DeuceRule.allCases.map { ($0.title, $0) }, selected: deuceRule) { deuceRule = $0 }
            }
        case .length:
            if sport == .pickleball {
                options([("11 · 1 game", 1), ("11 · Best of 3", 2), ("\(scoring == .rally ? 21 : 15) · 1 game", 3)], selected: lengthSelection) { choice in
                    switch choice {
                    case 1: points = 11; gamesToWin = 1
                    case 2: points = 11; gamesToWin = 2
                    default: points = scoring == .rally ? 21 : 15; gamesToWin = 1
                    }
                }
            } else {
                options([("1 set", 1), ("Best of 3", 2)], selected: setsToWin) { setsToWin = $0 }
            }
        case .opponent:
            opponentPage
        case .serve:
            options([("We serve", Team.a), ("They serve", Team.b)], selected: nil as Team?) { team in
                finish(firstServer: team)
            }
        }
    }

    private var lengthSelection: Int {
        if gamesToWin == 2 { return 2 }
        return points == 11 ? 1 : 3
    }

    private var opponentPage: some View {
        ScrollView {
            VStack(spacing: 6) {
                Button {
                    opponent = nil
                    advance()
                } label: {
                    row("Guest", highlighted: opponent == nil)
                }
                .buttonStyle(.press)
                ForEach(session.recentPlayers.prefix(8)) { player in
                    Button {
                        opponent = player
                        advance()
                    } label: {
                        row(player.displayName, highlighted: opponent?.id == player.id)
                    }
                    .buttonStyle(.press)
                }
            }
        }
    }

    private func options<T: Equatable>(_ items: [(String, T)], selected: T?, onSelect: @escaping (T) -> Void) -> some View {
        VStack(spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                Button {
                    Haptics.selection()
                    onSelect(items[index].1)
                    if step != .serve { advance() }
                } label: {
                    row(items[index].0, highlighted: items[index].1 == selected)
                }
                .buttonStyle(.press)
            }
        }
    }

    private func row(_ text: String, highlighted: Bool) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(highlighted ? theme.onAccent : .white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(highlighted ? theme.accent : DS.Palette.nightRaised)
            )
    }

    // MARK: Navigation

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    private func back() {
        if let previous = Step(rawValue: step.rawValue - 1) {
            step = previous
        } else {
            onCancel()
        }
    }

    private func finish(firstServer: Team) {
        Haptics.success()
        let rules: MatchRules
        switch sport {
        case .pickleball:
            rules = .pickleball(scoring, PickleballConfig(pointsToWin: points, gamesToWin: gamesToWin, isDoubles: isDoubles, firstServer: firstServer))
        case .padel:
            rules = .padel(PadelConfig(setsToWin: setsToWin, deuceRule: deuceRule, isDoubles: isDoubles, firstServer: firstServer))
        }

        let me = session.me
        let rival = opponent ?? session.anonymousPlayer("Opponent")
        let lineup: Lineup
        if isDoubles {
            lineup = Lineup(
                teamA: [me, session.anonymousPlayer("Partner")],
                teamB: [rival, session.anonymousPlayer(opponent == nil ? "Opponent 2" : "\(rival.shortName)'s partner")]
            )
        } else {
            lineup = Lineup(teamA: [me], teamB: [rival])
        }
        onComplete(rules, lineup)
    }
}
