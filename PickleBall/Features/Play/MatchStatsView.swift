//
//  MatchStatsView.swift
//  PickleBall
//
//  Point-by-point stats for one match, worked out from the rally log:
//  serve and return points, side outs or breaks, runs, comebacks and big
//  points. Works for any match scored live, on the phone or the Watch.
//

import SwiftUI
import CourtKit

struct MatchStatsCard: View {
    let insights: MatchInsights
    let lineup: Lineup?
    let rules: MatchRules

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Match stats").courtEyebrow()
                Spacer()
            }
            HStack {
                Spacer().frame(maxWidth: .infinity)
                teamHeader(.a)
                teamHeader(.b)
            }
            VStack(spacing: 10) {
                ForEach(rows, id: \.title) { row in
                    statRow(row)
                }
            }
            if !playerRows.isEmpty {
                Rectangle().fill(Court.hairline).frame(height: 1)
                Text("Serve by player").courtEyebrow()
                VStack(spacing: 8) {
                    ForEach(playerRows, id: \.name) { row in
                        HStack {
                            Text(row.name)
                                .font(.system(size: 14))
                                .foregroundStyle(Court.text)
                                .lineLimit(1)
                            Spacer()
                            Text(row.value)
                                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Court.text)
                        }
                    }
                }
            }
            if let footer {
                Text(footer)
                    .font(DS.Typography.caption)
                    .foregroundStyle(Court.muted)
            }
        }
        .padding(16)
        .courtRaised()
    }

    // MARK: Rows

    private struct Row {
        let title: String
        let a: String
        let b: String
        /// Which side did better, for the bold value.
        let better: Team?
    }

    private var rows: [Row] {
        let a = insights.teams.a
        let b = insights.teams.b
        var list: [Row] = []
        list.append(row(String(localized: "Rallies won"), a.ralliesWon, b.ralliesWon))
        list.append(Row(title: String(localized: "Won on serve"), a: fraction(a.serveWon, a.servePlayed),
                        b: fraction(b.serveWon, b.servePlayed),
                        better: compare(a.servePercent, b.servePercent)))
        list.append(Row(title: String(localized: "Won on return"), a: fraction(a.returnWon, a.returnPlayed),
                        b: fraction(b.returnWon, b.returnPlayed),
                        better: compare(a.returnPercent, b.returnPercent)))
        switch rules {
        case .pickleball(.sideOut, _):
            list.append(row(String(localized: "Side outs won"), a.breaks, b.breaks))
        case .padel:
            if a.serviceGames + b.serviceGames > 0 {
                list.append(Row(title: String(localized: "Service games held"),
                                a: fraction(a.serviceGamesHeld, a.serviceGames),
                                b: fraction(b.serviceGamesHeld, b.serviceGames),
                                better: compare(a.holdPercent, b.holdPercent)))
                list.append(row(String(localized: "Breaks of serve"), a.breaks, b.breaks))
            }
        default:
            break
        }
        list.append(row(String(localized: "Longest run"), a.longestRun, b.longestRun))
        if a.pressureChances + b.pressureChances > 0 {
            list.append(Row(title: String(localized: "Big points won"),
                            a: "\(a.pressureConverted)/\(a.pressureChances)",
                            b: "\(b.pressureConverted)/\(b.pressureChances)",
                            better: nil))
        }
        if a.pressureFaced + b.pressureFaced > 0 {
            list.append(row(String(localized: "Big points saved"), a.pressureSaved, b.pressureSaved))
        }
        if a.biggestComeback + b.biggestComeback > 0 {
            list.append(row(rules.sport == .padel ? String(localized: "Biggest comeback (games)")
                                                  : String(localized: "Biggest comeback (points)"),
                            a.biggestComeback, b.biggestComeback))
        }
        return list
    }

    private var playerRows: [(name: String, value: String)] {
        guard let lineup, lineup.teams.a.count + lineup.teams.b.count > 2 else { return [] }
        return insights.players
            .sorted { ($0.key.team == .a ? 0 : 1, $0.key.index) < ($1.key.team == .a ? 0 : 1, $1.key.index) }
            .compactMap { slot, stats in
                let team = lineup.teams[slot.team]
                guard slot.index < team.count, stats.pointsServed > 0 else { return nil }
                return (team[slot.index].shortName, fraction(stats.pointsWonOnServe, stats.pointsServed))
            }
    }

    private var footer: String? {
        var parts: [String] = []
        if insights.leadChanges > 0 {
            parts.append(String(localized: "Lead changed hands \(insights.leadChanges) times"))
        }
        if let duration = insights.duration, duration >= 60 {
            let minutes = Int((duration / 60).rounded())
            parts.append(String(localized: "\(minutes) min"))
        }
        if let seconds = insights.secondsPerRally, insights.duration ?? 0 >= 60 {
            parts.append(String(localized: "\(Int(seconds.rounded())) s per rally"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Pieces

    private func teamHeader(_ team: Team) -> some View {
        Text(teamName(team))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Court.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 92, alignment: .trailing)
    }

    private func statRow(_ row: Row) -> some View {
        HStack {
            Text(row.title)
                .font(.system(size: 14))
                .foregroundStyle(Court.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            value(row.a, bold: row.better == .a)
            value(row.b, bold: row.better == .b)
        }
        .accessibilityElement(children: .combine)
    }

    private func value(_ text: String, bold: Bool) -> some View {
        Text(text)
            .font(.system(size: 14, weight: bold ? .bold : .regular).monospacedDigit())
            .foregroundStyle(bold ? Court.text : Court.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: 92, alignment: .trailing)
    }

    private func teamName(_ team: Team) -> String {
        guard let players = lineup?.teams[team], !players.isEmpty else {
            return team == .a ? String(localized: "Team A") : String(localized: "Team B")
        }
        return players.map(\.shortName).joined(separator: " & ")
    }

    private func row(_ title: String, _ a: Int, _ b: Int) -> Row {
        Row(title: title, a: "\(a)", b: "\(b)", better: a == b ? nil : (a > b ? .a : .b))
    }

    private func fraction(_ won: Int, _ played: Int) -> String {
        guard played > 0 else { return "–" }
        let percent = Int((Double(won) / Double(played) * 100).rounded())
        return "\(won)/\(played) · \(percent)%"
    }

    private func compare(_ a: Int?, _ b: Int?) -> Team? {
        guard let a, let b, a != b else { return nil }
        return a > b ? .a : .b
    }
}
