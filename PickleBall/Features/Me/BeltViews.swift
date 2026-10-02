//
//  BeltViews.swift
//  PickleBall
//
//  The Belt, drawn: a strap and a plate. Plain steel, gold after three
//  defenses, undisputed (gold, jewels and a glow) after five.
//

import SwiftUI
import CourtKit
import CourtNet

struct BeltBadge: View {
    let tier: BeltTier
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Capsule()
                .fill(strap)
                .frame(width: size * 1.6, height: size * 0.42)
            Circle()
                .fill(plate)
                .frame(width: size * 0.82, height: size * 0.82)
                .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: max(1, size * 0.04)))
            Image(systemName: "crown.fill")
                .font(.system(size: size * 0.36, weight: .black))
                .foregroundStyle(tier == .plain ? Color.white : Color(red: 0.45, green: 0.3, blue: 0.02))
            if tier == .undisputed {
                ForEach([-1.0, 1.0], id: \.self) { side in
                    Circle()
                        .fill(Color(red: 0.85, green: 0.1, blue: 0.25))
                        .frame(width: size * 0.16, height: size * 0.16)
                        .offset(x: side * size * 0.58)
                }
            }
        }
        .frame(width: size * 1.6, height: size)
        .shadow(color: tier == .undisputed ? DS.Palette.gold.opacity(0.7) : .clear, radius: size * 0.3)
        .accessibilityLabel(tier.title)
    }

    private var strap: LinearGradient {
        switch tier {
        case .plain: return LinearGradient(colors: [Color(white: 0.25), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
        case .gold, .undisputed: return LinearGradient(colors: [Color(red: 0.2, green: 0.12, blue: 0.05), Color.black], startPoint: .top, endPoint: .bottom)
        }
    }

    private var plate: LinearGradient {
        switch tier {
        case .plain: return LinearGradient(colors: [Color(white: 0.85), Color(white: 0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .gold, .undisputed: return LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.45), Color(red: 0.85, green: 0.62, blue: 0.1)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

/// A belt on a player card.
struct BeltTile: View {
    let belt: Belt
    let isHeld: Bool
    private let social = Social.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BeltBadge(tier: belt.tier, size: 30)
                .opacity(isHeld ? 1 : 0.45)
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Court.text)
                .lineLimit(2)
            Text(isHeld ? "\(belt.defenses) defense\(belt.defenses == 1 ? "" : "s")" : "Held by \(holderName)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Court.muted)
                .lineLimit(1)
        }
        .frame(width: 150, alignment: .leading)
        .padding(14)
        .courtRaised(cornerRadius: 16)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(isHeld && belt.tier != .plain ? DS.Palette.gold.opacity(0.5) : .clear))
    }

    private var holderName: String {
        (belt.holder ?? []).map { social.firstName(of: $0.rawValue) }.joined(separator: " & ")
    }

    private var title: String { BeltNaming.title(belt, social: social) }
}

enum BeltNaming {
    /// "Squad pickleball belt · Tuesday Night", "Padel belt vs Priya".
    @MainActor
    static func title(_ belt: Belt, social: Social) -> String {
        let sport = belt.key.sport.displayName
        switch belt.key.kind {
        case .squadSingles, .squadDoubles:
            let squad = social.squad(belt.key.squadID)?.name ?? "Squad"
            return "\(squad) \(sport.lowercased())\(belt.key.kind == .squadDoubles ? " doubles" : "")"
        case .singles, .doubles:
            let me = social.userID.map(PlayerID.init(rawValue:))
            let others = belt.key.sides.flatMap { $0 }.filter { $0 != me }.map { social.firstName(of: $0.rawValue) }
            return "\(sport) · \(others.joined(separator: ", "))"
        }
    }
}

struct BeltDetailView: View {
    let belt: Belt
    private let social = Social.shared

    var body: some View {
        let now = Date()
        List {
            Section {
                VStack(spacing: 14) {
                    BeltBadge(tier: belt.tier, size: 70)
                        .padding(.top, 12)
                    Text(belt.tier.title).font(.system(size: 24, weight: .heavy, design: .rounded))
                    Text("Held by \(names(belt.holder ?? []))")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    if let next = BeltTier.defensesToNextTier(from: belt.defenses) {
                        Text("\(next) more defense\(next == 1 ? "" : "s") to \(BeltTier(defenses: belt.defenses + next).title.lowercased())")
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("Reign") {
                if let current = belt.currentReign {
                    LabeledContent("Current reign", value: "\(current.days(asOf: now)) day\(current.days(asOf: now) == 1 ? "" : "s")")
                    LabeledContent("Defenses", value: "\(current.defenses)")
                }
                if let longest = belt.longestReign(asOf: now) {
                    LabeledContent("Longest reign", value: "\(names(longest.holder)) · \(longest.days(asOf: now))d")
                }
                LabeledContent("Most defenses", value: "\(belt.mostDefenses)")
            }

            Section("Total reigns") {
                let holders = Set(belt.reigns.flatMap(\.holder))
                ForEach(Array(holders).sorted { belt.totalReigns(of: $0) > belt.totalReigns(of: $1) }, id: \.self) { player in
                    let record = belt.record(of: player)
                    LabeledContent(social.name(of: player.rawValue), value: "\(belt.totalReigns(of: player)) · \(record.wins)–\(record.losses)")
                }
            }

            Section("Title matches") {
                ForEach(belt.bouts.reversed(), id: \.matchID) { bout in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(names(bout.winners)) beat \(names(bout.losers))")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("\(outcome(bout.outcome)) · \(bout.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(BeltNaming.title(belt, social: social))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func names(_ ids: [PlayerID]) -> String {
        ids.map { social.firstName(of: $0.rawValue) }.joined(separator: " & ")
    }

    private func outcome(_ outcome: TitleBout.Outcome) -> String {
        switch outcome {
        case .created: return "Belt created"
        case .defended: return "Defended"
        case .changedHands: return "New holder"
        }
    }
}
