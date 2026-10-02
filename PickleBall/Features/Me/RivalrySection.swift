//
//  RivalrySection.swift
//  PickleBall
//
//  On a friend's card: you against them (head-to-head, recent meetings),
//  and how you do together as partners.
//

import SwiftUI
import CourtKit

struct RivalrySection: View {
    let friend: PlayerRef
    @ObservedObject private var matchStore = MatchStore.shared
    @ObservedObject private var directory = PlayerDirectory.shared

    var body: some View {
        let me = directory.me.id
        let h2h = HeadToHead.compute(me: me, opponent: friend.id, results: matchStore.results)
        let together = PartnerRecord.all(for: me, results: matchStore.results).first { $0.partner.id == friend.id }
        VStack(alignment: .leading, spacing: 12) {
            Text("RIVALRY").eyebrowStyle(Court.muted)
            NavigationLink {
                HeadToHeadView(opponent: friend, sport: nil)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("You vs \(friend.shortName)")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Court.text)
                        HStack(spacing: 4) {
                            ForEach(Array(h2h.lastFive.reversed().enumerated()), id: \.offset) { _, won in
                                Circle().fill(won ? DS.Palette.win : DS.Palette.loss).frame(width: 8, height: 8)
                            }
                            if h2h.matches.isEmpty {
                                Text("No meetings yet").font(DS.Typography.caption).foregroundStyle(Court.muted)
                            }
                        }
                    }
                    Spacer()
                    Text("\(h2h.wins)–\(h2h.losses)")
                        .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(Court.text)
                    Image(systemName: "chevron.right").foregroundStyle(Court.muted)
                }
                .padding(16)
                .courtRaised()
            }
            .buttonStyle(.press)

            if let together {
                HStack {
                    Image(systemName: "person.2.fill").foregroundStyle(DS.Palette.electricBlue)
                    Text("As partners")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Court.text)
                    Spacer()
                    Text("\(Int((together.winRate * 100).rounded()))% · \(together.wins)–\(together.losses)")
                        .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Court.text)
                }
                .padding(16)
                .courtRaised()
            }

            ForEach(h2h.matches.prefix(3), id: \.result.id) { meeting in
                HStack {
                    Text(meeting.didWin ? "W" : "L")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(meeting.didWin ? DS.Palette.win : DS.Palette.loss)
                        .frame(width: 20)
                    Text(meeting.scoreLine)
                        .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Court.text)
                    Spacer()
                    Text(meeting.result.date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(DS.Typography.caption)
                        .foregroundStyle(Court.muted)
                }
                .padding(.horizontal, 4)
            }
        }
    }
}
