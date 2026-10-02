//
//  SeasonRecapView.swift
//  PickleBall
//
//  Your season, Wrapped-style: a stack of full-screen cards you swipe
//  through — matches, record, belts, your nemesis, your best partner —
//  ending on one card made for sharing.
//

import SwiftUI
import CourtKit
import CourtNet

struct SeasonRecapView: View {
    @ObservedObject private var matchStore = MatchStore.shared
    private let social = Social.shared
    @State private var season = Season(containing: Date())
    @State private var page = 0
    @State private var shareImage: UIImage?

    private var me: PlayerID { PlayerDirectory.shared.me.id }

    private var recap: SeasonRecap {
        let trophies = social.trophies.filter {
            $0.ownerID == social.userID && $0.kind == .tournament && Season(containing: $0.awardedAt) == season
        }.count
        return SeasonRecap.compute(for: me, season: season, results: matchStore.confirmedResults,
                                   ledger: matchStore.belts, tournamentsWon: trophies)
    }

    private var seasons: [Season] {
        let years = Set(matchStore.confirmedResults.map { Season(containing: $0.date) }) .union([Season(containing: Date())])
        return years.sorted { $0.year > $1.year }
    }

    var body: some View {
        let current = self.recap
        let pages = cards(for: current)
        return ZStack {
            Color(hex: 0x1C1D1F).ignoresSafeArea()
            if current.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("No matches yet in \(season.title)")
                    } icon: {
                        SeasonBadge(year: season.year, size: 56)
                    }
                } description: {
                    Text("Your season story fills in as friends confirm your results.")
                }
                .foregroundStyle(.white)
            } else {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, card in
                        card.padding(28).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            }
        }
        .environment(\.colorScheme, .dark)
        .navigationTitle(season.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if seasons.count > 1 {
                ToolbarItem(placement: .principal) {
                    Menu {
                        ForEach(seasons) { option in
                            Button(option.title) { season = option; page = 0 }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(season.title).font(.headline)
                            Image(systemName: "chevron.down").font(.caption.bold())
                        }
                    }
                }
            }
            if !current.isEmpty, let shareImage {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: Image(uiImage: shareImage), preview: SharePreview(String(localized: "My \(season.title) season"), image: Image(uiImage: shareImage))) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .task(id: season) { render(current) }
    }

    // MARK: Cards

    private func cards(for recap: SeasonRecap) -> [AnyView] {
        var list: [AnyView] = []
        list.append(AnyView(VStack(alignment: .leading, spacing: 0) {
            SeasonBadge(year: season.year, size: 72).padding(.top, 40)
            RecapCard(eyebrow: "Your \(season.title)", big: "\(recap.matches)", caption: recap.matches == 1 ? "match played" : "matches played",
                      footnote: String(localized: "against \(recap.peoplePlayed) people"))
        }))
        list.append(AnyView(RecapCard(eyebrow: "Record", big: "\(recap.wins)–\(recap.losses)",
                                      caption: String(localized: "\(Int((recap.winRate * 100).rounded()))% won"),
                                      footnote: recap.longestWinStreak > 1 ? String(localized: "Longest streak: \(recap.longestWinStreak) in a row") : nil)))
        if recap.beltsWon > 0 || recap.titleDefenses > 0 {
            list.append(AnyView(RecapCard(eyebrow: "Belts", big: "\(recap.beltsWon)", caption: recap.beltsWon == 1 ? "belt won" : "belts won",
                                          footnote: String(localized: "\(recap.titleDefenses) defenses · longest reign \(recap.longestReignDays)d"),
                                          symbol: "crown.fill")))
        }
        if let nemesis = recap.nemesis {
            list.append(AnyView(RecapPersonCard(eyebrow: "Your nemesis", person: nemesis, line: String(localized: "\(nemesis.wins)–\(nemesis.losses) against"))))
        }
        if let partner = recap.bestPartner {
            list.append(AnyView(RecapPersonCard(eyebrow: "Best partner", person: partner, line: String(localized: "\(partner.wins)–\(partner.losses) together"))))
        }
        if let month = recap.busiestMonth {
            let name = Calendar.current.monthSymbols[month - 1]
            list.append(AnyView(RecapCard(eyebrow: "Busiest month", big: name.capitalized, caption: String(localized: "\(recap.busiestMonthMatches) matches"),
                                          footnote: recap.tournamentsWon > 0 ? String(localized: "\(recap.tournamentsWon) tournaments won") : nil)))
        }
        list.append(AnyView(VStack(spacing: 18) {
            RecapShareCard(recap: recap, name: PlayerDirectory.shared.me.displayName)
                .frame(width: 300, height: 480)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
            if let shareImage {
                ShareLink(item: Image(uiImage: shareImage), preview: SharePreview(String(localized: "My \(season.title) season"), image: Image(uiImage: shareImage))) {
                    Label("Share my season", systemImage: "square.and.arrow.up")
                        .courtBigButton()
                        .frame(width: 300)
                }
            }
        }))
        return list
    }

    private func render(_ recap: SeasonRecap) {
        let renderer = ImageRenderer(content: RecapShareCard(recap: recap, name: PlayerDirectory.shared.me.displayName)
            .frame(width: 300, height: 480)
            .environment(\.colorScheme, .dark))
        renderer.scale = 3
        shareImage = renderer.uiImage
    }
}

private struct RecapCard: View {
    let eyebrow: LocalizedStringKey
    let big: String
    let caption: LocalizedStringKey
    var footnote: String?
    var symbol: String?

    init(eyebrow: LocalizedStringKey, big: String, caption: String, footnote: String? = nil, symbol: String? = nil) {
        self.eyebrow = eyebrow
        self.big = big
        self.caption = LocalizedStringKey(caption)
        self.footnote = footnote
        self.symbol = symbol
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer()
            Text(eyebrow).font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(1.8).textCase(.uppercase).foregroundStyle(Color(hex: 0xA9AAAB))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 44, weight: .bold)).foregroundStyle(DS.Palette.gold)
                }
                Text(big)
                    .font(.system(size: big.count > 6 ? 56 : 96, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
            }
            Text(caption).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            if let footnote {
                Text(footnote).font(.system(size: 16, weight: .medium)).foregroundStyle(DS.Palette.nightMuted)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct RecapPersonCard: View {
    let eyebrow: LocalizedStringKey
    let person: RecapPerson
    let line: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            Text(eyebrow).font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(1.8).textCase(.uppercase).foregroundStyle(Color(hex: 0xA9AAAB))
            if person.player.kind == .user {
                ProfileAvatar(userID: person.player.id.rawValue, size: 120)
            } else {
                Avatar(name: person.player.displayName, color: ProfileAvatar.color(for: person.player.id.rawValue), size: 120)
            }
            Text(person.player.displayName)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(line).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The one card made for sharing: the season on a single image.
struct RecapShareCard: View {
    let recap: SeasonRecap
    let name: String

    var body: some View {
        ZStack {
            Color(hex: 0x1C1D1F)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SeasonBadge(year: recap.season.year, size: 44, night: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "SEASON \(recap.season.title)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .tracking(1.8)
                            .foregroundStyle(Color(hex: 0xA9AAAB))
                        Text(verbatim: "PickleBall").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    }
                    Spacer()
                }
                Spacer()
                Text(name).font(.system(size: 30, weight: .heavy)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5)
                row("Matches", "\(recap.matches)")
                row("Record", "\(recap.wins)–\(recap.losses)")
                if recap.beltsWon > 0 { row("Belts won", "\(recap.beltsWon)") }
                if recap.longestWinStreak > 1 { row("Best streak", "\(recap.longestWinStreak)") }
                if let nemesis = recap.nemesis { row("Nemesis", nemesis.player.shortName) }
                if let partner = recap.bestPartner { row("Best partner", partner.player.shortName) }
                Spacer()
                Text("Come for the belt.").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
            }
            .padding(26)
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value).font(.system(size: 20, weight: .heavy).monospacedDigit()).foregroundStyle(.white)
        }
    }
}

/// The season mark: a small court seen from above on a raised patch, with
/// the year's last two digits on the net. Ours, not a borrowed symbol.
struct SeasonBadge: View {
    let year: Int
    var size: CGFloat = 28
    /// Fixed night colours (for share images) instead of the adaptive ones.
    var night = false

    var body: some View {
        let corner = size * 0.3
        let line = max(1, size * 0.045)
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(night ? Color(hex: 0x26282B) : Court.raised)
                .shadow(color: .black.opacity(night ? 0.5 : 0.12), radius: size * 0.08, x: size * 0.05, y: size * 0.07)
            // The court: outline, kitchen lines either side of the net, centre line.
            ZStack {
                RoundedRectangle(cornerRadius: corner * 0.45, style: .continuous)
                    .fill(night ? Color(hex: 0x17181A) : Court.sunken)
                RoundedRectangle(cornerRadius: corner * 0.45, style: .continuous)
                    .strokeBorder(ink.opacity(0.55), lineWidth: line)
                VStack(spacing: 0) {
                    Rectangle().fill(ink.opacity(0.4)).frame(width: line).frame(maxHeight: .infinity)
                    Spacer().frame(height: size * 0.36)
                    Rectangle().fill(ink.opacity(0.4)).frame(width: line).frame(maxHeight: .infinity)
                }
                .padding(.vertical, line)
                VStack(spacing: size * 0.3) {
                    Rectangle().fill(ink.opacity(0.4)).frame(height: line)
                    Rectangle().fill(ink.opacity(0.4)).frame(height: line)
                }
            }
            .padding(size * 0.14)
            Text(verbatim: "’" + String(format: "%02d", year % 100))
                .font(.system(size: size * 0.3, weight: .bold, design: .monospaced))
                .foregroundStyle(ink)
                .padding(.horizontal, size * 0.05)
                .background(Capsule().fill(night ? Color(hex: 0x26282B) : Court.raised))
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text(verbatim: "\(year)"))
    }

    private var ink: Color { night ? Color(hex: 0xF2F2F0) : Court.text }
}
