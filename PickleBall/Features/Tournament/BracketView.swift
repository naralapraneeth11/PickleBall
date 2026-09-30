//
//  BracketView.swift
//  PickleBall
//
//  A knockout bracket that scrolls sideways, round by round: winners'
//  side, then the losers' side and the finals in double elimination. Each
//  match is a card; tap one that's ready to score it.
//

import SwiftUI
import CourtKit
import CourtNet

struct BracketView: View {
    let state: Bracket.State
    let fixtures: [FixtureRow]
    let scores: [UUID: FixtureScore]
    var isActive = true
    var onPlay: (FixtureRow) -> Void = { _ in }
    var onEnter: (FixtureRow) -> Void = { _ in }
    var onSchedule: (FixtureRow) -> Void = { _ in }

    private let social = Social.shared
    private static let cardHeight: CGFloat = 60
    private static let gap: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if state.isDouble { label("Winners’ bracket") }
            columns(stage: .winners, rounds: state.winnersRounds, doubling: true)
            if state.isDouble {
                label("Losers’ bracket")
                columns(stage: .losers, rounds: state.losersRounds, doubling: false)
                label("Final")
                HStack(alignment: .top, spacing: 16) {
                    ForEach(state.nodes.filter { $0.stage == .final || $0.stage == .reset }) { node in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Self.title(state.name(of: node))).font(DS.Typography.caption).foregroundStyle(.secondary)
                            card(node)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
    }

    private func columns(stage: FixtureStage, rounds: Int, doubling: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(1...max(rounds, 1), id: \.self) { round in
                    let nodes = state.nodes(stage, round: round)
                    let step = doubling ? pow(2, Double(round - 1)) : 1
                    let unit = Self.cardHeight + Self.gap
                    VStack(alignment: .leading, spacing: 0) {
                        if let first = nodes.first {
                            Text(Self.title(state.name(of: first)))
                                .font(DS.Typography.caption)
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 8)
                        }
                        VStack(spacing: CGFloat(step) * unit - Self.cardHeight) {
                            ForEach(nodes) { card($0) }
                        }
                        .padding(.top, CGFloat(step - 1) * unit / 2)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func card(_ node: Bracket.Node) -> some View {
        let row = node.fixture.flatMap { f in fixtures.first { $0.id == f.id } }
        let score = row.flatMap { scores[$0.id] }
        let content = VStack(alignment: .leading, spacing: 4) {
            line(node.a, won: node.isDecided && node.winner == node.a && node.a != .bye, points: score.map { oriented($0, row: row, occupant: node.a) } ?? nil)
            Divider().opacity(0.4)
            line(node.b, won: node.isDecided && node.winner == node.b && node.b != .bye, points: score.map { oriented($0, row: row, occupant: node.b) } ?? nil)
        }
        .padding(.horizontal, 10)
        .frame(width: 168, height: Self.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(node.isReady ? DS.Palette.electricBlue.opacity(0.6) : Color.clear, lineWidth: 1.5)
        )

        if let row, score == nil, isActive, node.isReady {
            Menu {
                Button { onPlay(row) } label: { Label("Score it live", systemImage: "play.fill") }
                Button { onEnter(row) } label: { Label("Enter the score", systemImage: "square.and.pencil") }
                Button { onSchedule(row) } label: { Label("Set time or court", systemImage: "calendar") }
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    /// The score for this side, whichever way round the fixture was saved.
    private func oriented(_ score: FixtureScore, row: FixtureRow?, occupant: Bracket.Occupant) -> Int? {
        guard let row, let entrant = occupant.entrant else { return nil }
        let ids = Set(entrant.map(\.rawValue))
        if Set(row.teamA) == ids { return score.score.a }
        if Set(row.teamB) == ids { return score.score.b }
        return nil
    }

    private func line(_ occupant: Bracket.Occupant, won: Bool, points: Int?) -> some View {
        HStack(spacing: 6) {
            switch occupant {
            case .entrant(let ids):
                Text(ids.map { social.firstName(of: $0.rawValue) }.joined(separator: " & "))
                    .font(.system(size: 14, weight: won ? .bold : .medium, design: .rounded))
                    .foregroundStyle(won ? Color.primary : Color.primary.opacity(0.8))
                    .lineLimit(1)
            case .bye:
                Text("Bye").font(.system(size: 14, weight: .regular, design: .rounded)).foregroundStyle(.tertiary)
            case .pending:
                Text("—").font(.system(size: 14, weight: .regular, design: .rounded)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            if let points {
                Text("\(points)")
                    .font(.system(size: 14, weight: won ? .heavy : .medium, design: .rounded).monospacedDigit())
            }
            if won {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(DS.Palette.win)
            }
        }
    }

    static func title(_ name: Bracket.RoundName) -> String {
        switch name {
        case .roundOf(let n): return String(localized: "Round of \(n)")
        case .quarterfinal: return String(localized: "Quarterfinals")
        case .semifinal: return String(localized: "Semifinals")
        case .final: return String(localized: "Final")
        case .winnersFinal: return String(localized: "Winners’ final")
        case .losers(let round): return String(localized: "Losers’ round \(round)")
        case .losersFinal: return String(localized: "Losers’ final")
        case .grandFinal: return String(localized: "Grand final")
        case .reset: return String(localized: "Reset final")
        }
    }
}
