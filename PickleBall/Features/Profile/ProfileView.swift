//
//  ProfileView.swift
//  PickleBall
//
//  Profile, Robinhood-inspired: one hero number (your form), one living
//  chart, and a rivals list that reads like a watchlist. Built entirely
//  from matches on this phone, keyed by player ID.
//

import SwiftUI
import CourtKit

struct ProfileView: View {
    @Environment(SportMode.self) private var sportMode
    @ObservedObject private var matchStore = MatchStore.shared
    @ObservedObject private var directory = PlayerDirectory.shared

    @State private var filter: SportFilter = .all
    @State private var window: FormWindow = .thirty
    @State private var selection: Int?
    @State private var showEdit = false

    enum SportFilter: String, CaseIterable, Identifiable {
        case all, pickleball, padel
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "All"
            case .pickleball: return "Pickleball"
            case .padel: return "Padel"
            }
        }
        var sport: Sport? {
            switch self {
            case .all: return nil
            case .pickleball: return .pickleball
            case .padel: return .padel
            }
        }
    }

    enum FormWindow: Int, CaseIterable, Identifiable {
        case ten = 10, thirty = 30, all = 500
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .ten: return "10"
            case .thirty: return "30"
            case .all: return "All"
            }
        }
    }

    private var me: PlayerRef { directory.me }
    private var accent: Color { (filter.sport ?? sportMode.sport).theme.accent }

    private var results: [MatchResult] {
        guard let sport = filter.sport else { return matchStore.results }
        return matchStore.results.filter { $0.sport == sport }
    }

    private var form: FormLine {
        FormLine.compute(for: me.id, results: results, limit: window.rawValue)
    }

    private var rivals: [OpponentSummary] {
        OpponentSummary.list(for: me.id, results: results)
    }

    private var partners: [PartnerRecord] {
        PartnerRecord.all(for: me.id, results: results).filter { $0.played >= 1 }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                header
                hero
                chartSection
                statsRow
                if !rivals.isEmpty { rivalsSection }
                if !partners.isEmpty { partnersSection }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .background(DS.Palette.night.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showEdit) {
            ProfileEditView()
        }
        .onChange(of: filter) { _, _ in selection = nil }
        .onChange(of: window) { _, _ in selection = nil }
        .onAppear { matchStore.reload() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Avatar(name: me.displayName, color: accent, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(me.displayName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(results.count) match\(results.count == 1 ? "" : "es") on this phone")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.nightMuted)
            }
            Spacer()
            Button {
                Haptics.light()
                showEdit = true
            } label: {
                Text("Edit")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(DS.Palette.nightRaised))
            }
            .buttonStyle(.press)
            .accessibilityLabel("Edit profile")
        }
        .padding(.top, 8)
    }

    // MARK: Hero

    private var selectedPoint: FormPoint? {
        guard let selection, !form.points.isEmpty else { return nil }
        return form.points[min(max(selection, 0), form.points.count - 1)]
    }

    private var hero: some View {
        let point = selectedPoint ?? form.points.last
        let change: Double? = {
            guard let point, let index = form.points.firstIndex(of: point), index > 0 else { return nil }
            return point.value - form.points[index - 1].value
        }()

        return VStack(alignment: .leading, spacing: 6) {
            Text("FORM").eyebrowStyle(DS.Palette.nightMuted)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(point.map { String(format: "%.1f", $0.value) } ?? "—")
                    .font(DS.Typography.hero(64))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                if point != nil {
                    Text("%")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Palette.nightMuted)
                }
            }

            if let point {
                HStack(spacing: 8) {
                    if let change {
                        Text("\(change >= 0 ? "▲" : "▼") \(String(format: "%.1f", abs(change)))")
                            .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(change >= 0 ? accent : Color.white.opacity(0.55))
                    }
                    Text(caption(for: point))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.Palette.nightMuted)
                        .lineLimit(1)
                }
                .animation(DS.Motion.snappy, value: point.id)
            } else {
                Text("Share of points you win, smoothed over recent matches. Finish a match to start your line.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.nightMuted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func caption(for point: FormPoint) -> String {
        let opponents = point.opponents.map(\.shortName).joined(separator: " & ")
        let result = point.didWin ? "W" : "L"
        let date = point.date.formatted(.dateTime.month(.abbreviated).day())
        return "\(result) \(point.scoreLine) vs \(opponents) · \(date)"
    }

    // MARK: Chart

    private var chartSection: some View {
        VStack(spacing: 14) {
            if form.points.count >= 2 {
                FormChartView(points: form.points, accent: accent, selection: $selection)
                    .frame(height: 190)
            } else {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.Palette.nightRaised)
                    .frame(height: 120)
                    .overlay(
                        Text("Your form line appears after two matches.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.nightMuted)
                    )
            }

            HStack(spacing: 6) {
                ForEach(SportFilter.allCases) { option in
                    chip(option.title, isOn: filter == option) { filter = option }
                }
                Spacer(minLength: 8)
                ForEach(FormWindow.allCases) { option in
                    chip(option.title, isOn: window == option) { window = option }
                }
            }
        }
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            withAnimation(DS.Motion.snappy) { action() }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(isOn ? Color.black : DS.Palette.nightMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(isOn ? accent : DS.Palette.nightRaised))
        }
        .buttonStyle(.press)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Stats

    private var statsRow: some View {
        let wins = form.wins
        let losses = form.losses
        let total = wins + losses
        let streak = form.streak
        let points = results.compactMap { $0.perspective(of: me.id) }
        let pointsFor = points.reduce(0) { $0 + $1.pointsFor }
        let pointsAgainst = points.reduce(0) { $0 + $1.pointsAgainst }
        let share = pointsFor + pointsAgainst > 0 ? Int((Double(pointsFor) / Double(pointsFor + pointsAgainst) * 100).rounded()) : nil

        return HStack(spacing: 0) {
            statCell("RECORD", "\(wins)–\(losses)")
            divider
            statCell("WIN RATE", total > 0 ? "\(Int((Double(wins) / Double(total) * 100).rounded()))%" : "—")
            divider
            statCell("STREAK", streak == 0 ? "—" : (streak > 0 ? "W\(streak)" : "L\(-streak)"))
            divider
            statCell("POINTS", share.map { "\($0)%" } ?? "—")
        }
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(DS.Palette.nightRaised))
    }

    private var divider: some View {
        Rectangle().fill(DS.Palette.hairline).frame(width: 1, height: 30)
    }

    private func statCell(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(DS.Palette.nightMuted)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Rivals

    private var rivalsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RIVALS").eyebrowStyle(DS.Palette.nightMuted)
                .padding(.bottom, 6)
            ForEach(rivals.prefix(12)) { rival in
                NavigationLink {
                    HeadToHeadView(opponent: rival.opponent, sport: filter.sport)
                } label: {
                    rivalRow(rival)
                }
                .buttonStyle(.press)
                if rival.id != rivals.prefix(12).last?.id {
                    Rectangle().fill(DS.Palette.hairline).frame(height: 1).padding(.leading, 50)
                }
            }
        }
    }

    private func rivalRow(_ rival: OpponentSummary) -> some View {
        HStack(spacing: 12) {
            Avatar(name: rival.opponent.displayName, color: DS.Palette.nightRaised, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(rival.opponent.displayName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(rival.played) match\(rival.played == 1 ? "" : "es") · \(rival.lastPlayed.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.nightMuted)
            }
            Spacer(minLength: 8)
            FormSparkline(results: rival.recentForm, accent: accent)
                .frame(width: 56, height: 22)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(rival.wins)–\(rival.losses)")
                    .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                Text(rival.trend > 0 ? "▲ won last" : "▼ lost last")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(rival.trend > 0 ? accent : Color.white.opacity(0.5))
            }
            .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rival.opponent.displayName). Record \(rival.wins) wins, \(rival.losses) losses.")
        .accessibilityHint("Opens head-to-head")
    }

    // MARK: Partners

    private var partnersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BEST PARTNERS").eyebrowStyle(DS.Palette.nightMuted)
            ForEach(partners.prefix(5)) { record in
                HStack(spacing: 12) {
                    Avatar(name: record.partner.displayName, color: DS.Palette.nightRaised, size: 32)
                    Text(record.partner.displayName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(Int((record.winRate * 100).rounded()))%")
                        .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(accent)
                    Text("\(record.wins)–\(record.losses)")
                        .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(DS.Palette.nightMuted)
                        .frame(width: 44, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Initials in a circle.
struct Avatar: View {
    let name: String
    let color: Color
    let size: CGFloat

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color))
            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .accessibilityHidden(true)
    }

    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

#Preview {
    NavigationStack { ProfileView() }
        .environment(SportMode())
}
