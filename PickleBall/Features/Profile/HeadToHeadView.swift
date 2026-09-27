//
//  HeadToHeadView.swift
//  PickleBall
//
//  "You vs Sam: 7–5". Lifetime record, current streak, last five, point
//  differential, closest match and best partner — all computed from the
//  matches on this phone by player ID, so two people called Alex never
//  get merged.
//

import SwiftUI
import CourtKit

struct HeadToHeadView: View {
    let opponent: PlayerRef
    /// Restrict to one sport, or nil for both.
    let sport: Sport?

    @Environment(SportMode.self) private var sportMode
    @ObservedObject private var matchStore = MatchStore.shared
    @ObservedObject private var directory = PlayerDirectory.shared

    private var me: PlayerRef { directory.me }
    private var accent: Color { (sport ?? sportMode.sport).theme.accent }

    private var h2h: HeadToHead {
        let results = sport.map { s in matchStore.results.filter { $0.sport == s } } ?? matchStore.results
        return HeadToHead.compute(me: me.id, opponent: opponent.id, results: results)
    }

    var body: some View {
        let record = h2h
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                faceOff
                hero(record)
                if !record.matches.isEmpty {
                    lastFive(record)
                    factsGrid(record)
                    if !record.partners.isEmpty { partnerSection(record) }
                    meetings(record)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 60)
        }
        .background(DS.Palette.night.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .navigationTitle("Head-to-head")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Face-off

    private var faceOff: some View {
        HStack(spacing: 14) {
            VStack(spacing: 6) {
                Avatar(name: me.displayName, color: accent.opacity(0.85), size: 56)
                Text("You")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)

            Text("VS")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundStyle(DS.Palette.nightMuted)

            VStack(spacing: 6) {
                Avatar(name: opponent.displayName, color: DS.Palette.nightRaised, size: 56)
                Text(opponent.displayName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You versus \(opponent.displayName)")
    }

    // MARK: Hero

    private func hero(_ record: HeadToHead) -> some View {
        VStack(spacing: 6) {
            Text("LIFETIME").eyebrowStyle(DS.Palette.nightMuted)
            Text("\(record.wins)–\(record.losses)")
                .font(DS.Typography.hero(72))
                .foregroundStyle(.white)
            Text(leadText(record))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(record.wins >= record.losses ? accent : Color.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func leadText(_ record: HeadToHead) -> String {
        if record.matches.isEmpty { return "No meetings yet" }
        if record.wins == record.losses { return "All square" }
        return record.wins > record.losses ? "You lead" : "\(opponent.shortName) leads"
    }

    // MARK: Last five

    private func lastFive(_ record: HeadToHead) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LAST 5").eyebrowStyle(DS.Palette.nightMuted)
                Spacer()
                if let streak = record.streak, streak.count >= 2 {
                    Text(streak.winner == me.id
                         ? "You've won the last \(streak.count)"
                         : "\(opponent.shortName) has won the last \(streak.count)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(streak.winner == me.id ? accent : Color.white.opacity(0.7))
                }
            }
            HStack(spacing: 8) {
                ForEach(Array(record.lastFive.enumerated()), id: \.offset) { _, won in
                    Text(won ? "W" : "L")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(won ? Color.black : Color.white.opacity(0.8))
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(won ? accent : DS.Palette.nightRaised)
                        )
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Last five, newest first: " + record.lastFive.map { $0 ? "win" : "loss" }.joined(separator: ", "))
        }
    }

    // MARK: Facts

    private func factsGrid(_ record: HeadToHead) -> some View {
        let diff = record.pointDifferential
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            fact("POINT DIFFERENTIAL", "\(diff >= 0 ? "+" : "")\(diff)", "over \(record.matches.count) match\(record.matches.count == 1 ? "" : "es")")
            if let closest = record.closest {
                fact("CLOSEST MATCH", closest.scoreLine, closest.result.date.formatted(.dateTime.day().month(.abbreviated)))
            }
        }
    }

    private func fact(_ title: String, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(DS.Palette.nightMuted)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.nightMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(DS.Palette.nightRaised))
        .accessibilityElement(children: .combine)
    }

    // MARK: Partners

    private func partnerSection(_ record: HeadToHead) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR PARTNERS AGAINST \(opponent.shortName.uppercased())").eyebrowStyle(DS.Palette.nightMuted)
            ForEach(record.partners.prefix(3)) { partner in
                HStack {
                    Text(partner.partner.displayName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(Int((partner.winRate * 100).rounded()))% · \(partner.wins)–\(partner.losses)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(partner.winRate >= 0.5 ? accent : DS.Palette.nightMuted)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Meetings

    private func meetings(_ record: HeadToHead) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MEETINGS").eyebrowStyle(DS.Palette.nightMuted)
                .padding(.bottom, 6)
            ForEach(record.matches, id: \.result.id) { meeting in
                HStack(spacing: 12) {
                    BallIcon(sport: meeting.result.sport, size: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meeting.scoreLine.isEmpty ? "\(meeting.matchScoreFor)–\(meeting.matchScoreAgainst)" : meeting.scoreLine)
                            .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                        Text(meeting.result.date.formatted(.dateTime.day().month(.abbreviated).year()))
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.nightMuted)
                    }
                    Spacer()
                    Text(meeting.didWin ? "W" : "L")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(meeting.didWin ? accent : Color.white.opacity(0.55))
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(meeting.didWin ? "Win" : "Loss"), \(meeting.scoreLine), \(meeting.result.date.formatted(date: .abbreviated, time: .omitted))")
            }
        }
    }
}
