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
import CourtNet

/// The player card: yours on the Me tab, a friend's anywhere else.
struct ProfileView: View {
    /// Nil for the device owner.
    var playerID: PlayerID?

    @Environment(SportMode.self) private var sportMode
    @ObservedObject private var matchStore = MatchStore.shared
    @ObservedObject private var directory = PlayerDirectory.shared
    private let social = Social.shared

    @State private var filter: SportFilter = .all
    @State private var window: FormWindow = .thirty
    @State private var selection: Int?
    @State private var showEdit = false
    @State private var showSettings = false
    @State private var showShare = false
    @State private var showCallOut = false
    @State private var confirmBlock = false
    @State private var openChat: ConversationRow?

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

    private var isMe: Bool { playerID == nil || playerID == directory.me.id }
    /// Whose card this is.
    private var me: PlayerRef {
        guard let playerID, !isMe else { return directory.me }
        return social.playerRef(for: playerID.rawValue)
    }
    private var profile: ProfileRow? {
        isMe ? social.profile : social.profiles[me.id.rawValue]
    }
    /// Charts and highlights stay in ink: the sport colour is kept for the
    /// tab bar. Good news (a rising level) uses the win green.
    private var accent: Color { Court.text }

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
                if !isMe { friendActions }
                hero
                chartSection
                statsRow
                levelSection
                beltsSection
                trophySection
                if !isMe { RivalrySection(friend: me) }
                if isMe && !rivals.isEmpty { rivalsSection }
                if !partners.isEmpty { partnersSection }
                if isMe { moreSection }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .courtGround()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showEdit) {
            if social.phase == .ready {
                ProfileSetupView(isEditing: true)
            } else {
                ProfileEditView()
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showShare) {
            ShareCardSheet(content: playerCardContent)
        }
        .sheet(isPresented: $showCallOut) {
            CallOutComposerView(opponents: [me.id.rawValue])
        }
        .navigationDestination(item: $openChat) { conversation in
            ChatView(conversationID: conversation.id)
        }
        .confirmationDialog("Block \(me.shortName)?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { Task { await social.block(me.id.rawValue) } }
        } message: {
            Text("They won’t be able to message you, see your Serves or call you out. They aren’t told.")
        }
        .onChange(of: filter) { _, _ in selection = nil }
        .onChange(of: window) { _, _ in selection = nil }
        .onAppear { matchStore.reload() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            if me.kind == .user, social.phase == .ready {
                ProfileAvatar(userID: me.id.rawValue, size: 52)
            } else {
                Avatar(name: me.displayName, color: ProfileAvatar.color(for: me.id.rawValue), size: 52)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(me.displayName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Court.text)
                Text(subtitle)
                    .font(DS.Typography.caption)
                    .foregroundStyle(Court.muted)
            }
            Spacer()
            if isMe {
                headerButton("square.and.arrow.up", label: "Share my card") { showShare = true }
                headerButton("pencil", label: "Edit profile") { showEdit = true }
                headerButton("gearshape.fill", label: "Settings") { showSettings = true }
            }
        }
        .padding(.top, 8)
    }

    private var subtitle: String {
        if let profile {
            let courts = profile.homeCourts.first.map { " · \($0.name)" } ?? ""
            return "@\(profile.username)\(courts)"
        }
        return "\(results.count) match\(results.count == 1 ? "" : "es")"
    }

    private func headerButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Court.text)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Court.raised).shadow(Court.raisedDark).shadow(Court.raisedLight))
        }
        .buttonStyle(.press)
        .accessibilityLabel(LocalizedStringKey(label))
    }

    // MARK: Friend actions

    @ViewBuilder
    private var friendActions: some View {
        let id = me.id.rawValue
        HStack(spacing: 10) {
            switch social.relationship(with: id) {
            case .friend:
                darkPill("Message", "bubble.left.fill") { openChat = social.directConversation(with: id) }
                darkPill("Call out", "flag.2.crossed.fill") { showCallOut = true }
            case .incoming:
                darkPill("Accept request", "person.badge.plus") { Task { await social.respondToRequest(from: id, accept: true) } }
            case .outgoing:
                darkPill("Requested", "clock") {}
            case .none:
                if me.kind == .user { darkPill("Add friend", "person.badge.plus") { Task { await social.requestFriend(id) } } }
            case .blocked:
                darkPill("Unblock", "hand.raised.slash") { Task { await social.unblock(id) } }
            case .me:
                EmptyView()
            }
            Spacer()
            if me.kind == .user {
                Menu {
                    if social.relationship(with: id) == .friend {
                        Button("Remove friend", role: .destructive) { Task { await social.removeFriend(id) } }
                    }
                    Button("Report", role: .destructive) { Task { _ = await social.report(.user, id: id, reason: "Reported from player card") } }
                    if social.relationship(with: id) != .blocked {
                        Button("Block", role: .destructive) { confirmBlock = true }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Court.text)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Court.raised).shadow(Court.raisedDark).shadow(Court.raisedLight))
                }
                .accessibilityLabel("More")
            }
        }
    }

    private func darkPill(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Court.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .courtRaisedCapsule()
        }
        .buttonStyle(.press)
    }

    // MARK: Belts and trophies

    @ViewBuilder
    private var beltsSection: some View {
        let held = matchStore.belts.held(by: me.id)
        let involved = matchStore.belts.belts(involving: me.id).filter { !$0.isHeld(by: me.id) }
        if !held.isEmpty || !involved.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("BELTS").eyebrowStyle(Court.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(held + involved) { belt in
                            NavigationLink { BeltDetailView(belt: belt) } label: {
                                BeltTile(belt: belt, isHeld: belt.isHeld(by: me.id))
                            }
                            .buttonStyle(.press)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var trophySection: some View {
        let trophies = social.trophies.filter { $0.ownerID == me.id.rawValue }
        if !trophies.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("TROPHY CASE").eyebrowStyle(Court.muted)
                TrophyCase(trophies: trophies)
            }
        }
    }

    // MARK: More

    private var moreSection: some View {
        VStack(spacing: 0) {
            moreRow("Your \(Season(containing: Date()).title) season", "sparkles") { SeasonRecapView() }
            moreRow("Stats", "chart.bar.fill") { StatsView() }
            moreRow("Apple Watch workouts", "applewatch") { WatchStatsDetailView() }
            if social.phase == .ready {
                moreRow("Friends", "person.2.fill") { FriendsView() }
            }
        }
        .courtRaised()
    }

    private func moreRow<Destination: View>(_ title: String, _ symbol: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 24).foregroundStyle(accent)
                Text(LocalizedStringKey(title)).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(Court.text)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Court.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press)
    }

    /// The card shared outside the app.
    private var playerCardContent: ShareCardContent {
        let held = matchStore.belts.held(by: me.id)
        if let belt = held.first {
            return ShareCards.beltDefended(holderName: me.displayName, sport: belt.key.sport, defenses: belt.defenses, tier: belt.tier)
        }
        let form = FormLine.compute(for: me.id, results: matchStore.results)
        return ShareCardContent(kind: .result, title: me.displayName, subtitle: "\(form.wins)–\(form.losses) · form \(Int(form.current ?? 50))",
                                callToAction: "Think you can beat \(me.shortName)?", scoreLine: nil, tier: nil)
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
            Text("FORM").eyebrowStyle(Court.muted)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(point.map { String(format: "%.1f", $0.value) } ?? "—")
                    .font(DS.Typography.hero(64))
                    .foregroundStyle(Court.text)
                    .contentTransition(.numericText())
                if point != nil {
                    Text("%")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Court.muted)
                }
            }

            if let point {
                HStack(spacing: 8) {
                    if let change {
                        Text("\(change >= 0 ? "▲" : "▼") \(String(format: "%.1f", abs(change)))")
                            .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(change >= 0 ? DS.Palette.win : Court.muted)
                    }
                    Text(caption(for: point))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Court.muted)
                        .lineLimit(1)
                }
                .animation(DS.Motion.snappy, value: point.id)
            } else {
                Text("Share of points you win, smoothed over recent matches. Finish a match to start your line.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(Court.muted)
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
                    .fill(Court.raised)
                    .frame(height: 120)
                    .overlay(
                        Text("Your form line appears after two matches.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(Court.muted)
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
            Text(LocalizedStringKey(title))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(isOn ? Court.ground : Court.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(isOn ? Court.text : Court.raised))
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
        .courtRaised()
    }

    private var divider: some View {
        Rectangle().fill(Court.hairline).frame(width: 1, height: 30)
    }

    // MARK: Level

    /// Level per sport: worked out on this phone for me, as published for
    /// friends (they can't see every match I play, and vice versa).
    private var levels: [(sport: Sport, level: Double, change: Double?, provisional: Bool)] {
        Sport.allCases.compactMap { sport in
            if isMe {
                guard let level = matchStore.levels.level(of: me.id, in: sport) else { return nil }
                return (sport, level.level, level.recentChange, level.isProvisional)
            }
            guard let published = profile?.level(in: sport) else { return nil }
            return (sport, published, nil, false)
        }
    }

    @ViewBuilder
    private var levelSection: some View {
        let list = levels
        if !list.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.offset) { index, item in
                    if index > 0 { divider }
                    VStack(spacing: 4) {
                        Text(item.sport == .padel ? "PADEL LEVEL" : "PICKLEBALL LEVEL")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(Court.muted)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(PlayerLevel.format(item.level))
                                .font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
                                .foregroundStyle(Court.text)
                            if let change = item.change, abs(change) >= 0.01 {
                                Text("\(change >= 0 ? "▲" : "▼")\(String(format: "%.2f", abs(change)))")
                                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(change >= 0 ? DS.Palette.win : Court.muted)
                            }
                        }
                        if item.provisional {
                            Text("Provisional").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(Court.muted)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 14)
            .courtRaised()
        }
    }

    private func statCell(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(Court.muted)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Court.text)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Rivals

    private var rivalsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RIVALS").eyebrowStyle(Court.muted)
                .padding(.bottom, 6)
            ForEach(rivals.prefix(12)) { rival in
                NavigationLink {
                    HeadToHeadView(opponent: rival.opponent, sport: filter.sport)
                } label: {
                    rivalRow(rival)
                }
                .buttonStyle(.press)
                if rival.id != rivals.prefix(12).last?.id {
                    Rectangle().fill(Court.hairline).frame(height: 1).padding(.leading, 50)
                }
            }
        }
    }

    private func rivalRow(_ rival: OpponentSummary) -> some View {
        HStack(spacing: 12) {
            Avatar(name: rival.opponent.displayName, color: ProfileAvatar.color(for: rival.opponent.id.rawValue), size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(rival.opponent.displayName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Court.text)
                    .lineLimit(1)
                Text("\(rival.played) match\(rival.played == 1 ? "" : "es") · \(rival.lastPlayed.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(DS.Typography.caption)
                    .foregroundStyle(Court.muted)
            }
            Spacer(minLength: 8)
            FormSparkline(results: rival.recentForm, accent: accent)
                .frame(width: 56, height: 22)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(rival.wins)–\(rival.losses)")
                    .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Court.text)
                Text(rival.trend > 0 ? "▲ won last" : "▼ lost last")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(rival.trend > 0 ? DS.Palette.win : Court.muted)
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
            Text("BEST PARTNERS").eyebrowStyle(Court.muted)
            ForEach(partners.prefix(5)) { record in
                HStack(spacing: 12) {
                    Avatar(name: record.partner.displayName, color: ProfileAvatar.color(for: record.partner.id.rawValue), size: 32)
                    Text(record.partner.displayName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Court.text)
                    Spacer()
                    Text("\(Int((record.winRate * 100).rounded()))%")
                        .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(accent)
                    Text("\(record.wins)–\(record.losses)")
                        .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(Court.muted)
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
