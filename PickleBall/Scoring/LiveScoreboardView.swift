//
//  LiveScoreboardView.swift
//  PickleBall
//
//  The live scoreboard. Robinhood clarity, scoreboard soul: one giant
//  number per side on a dark court, almost no chrome. Tap the half of the
//  screen that won the rally; the engine works out points, serve and ends.
//  Rules live in CourtKit — this view only renders `ScoreDisplay`.
//

import SwiftUI
import UIKit
import CourtKit
import CourtNet

/// Presents whatever match `MatchCenter` is running and dismisses itself
/// when the match goes away (parked, abandoned, or saved).
struct LiveMatchScreen: View {
    @Environment(\.dismiss) private var dismiss
    private let center = MatchCenter.shared

    var body: some View {
        Group {
            if let match = center.live {
                LiveScoreboardView(match: match) {
                    center.dismissEnded()
                    dismiss()
                }
            } else {
                DS.Palette.night
                    .ignoresSafeArea()
                    .onAppear { dismiss() }
            }
        }
        .sharePromptHost()
    }
}

struct LiveScoreboardView: View {
    let match: LiveMatch
    var onClose: () -> Void

    @State private var flipped = false
    @State private var showEndOptions = false
    @State private var banner: String?
    @State private var sweepProgress: CGFloat = 0
    @State private var sweepVisible = false
    @State private var showCamera = false
    @State private var liveLink: IdentifiedURL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var center: MatchCenter { .shared }
    private var display: ScoreDisplay { match.display }
    private var theme: SportTheme { match.sport.theme }
    private var isLocked: Bool { match.isFinished || match.isEnded }

    /// The team drawn at the top of the screen. Team A starts nearest the
    /// phone; real end changes swap the sides so each team stays on its
    /// own half of the court.
    private var topTeam: Team {
        let swappedByEnds = display.endChanges % 2 == 1
        return swappedByEnds != flipped ? .a : .b
    }

    var body: some View {
        ZStack {
            DS.Palette.night.ignoresSafeArea()

            CourtArtView(sport: match.sport, lineWidth: 1.5, lineOpacity: 0.12, showsSurface: false)
                .padding(.horizontal, 36)
                .padding(.vertical, 90)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                crowdAndPhotoStrip
                teamPanel(topTeam, isTop: true)
                centerStrip
                teamPanel(topTeam.opponent, isTop: false)
                historyBar
                if match.isWatchOwned || match.isWatchHosted {
                    WatchMetricsLine(matchID: match.id)
                }
            }

            if sweepVisible {
                sweepLine
            }

            if let banner {
                bannerView(banner)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            if match.isFinished {
                MatchResultCard(match: match, onUndo: undoLast, onSave: save)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .animation(DS.Motion.snappy, value: match.isFinished)
        .animation(DS.Motion.snappy, value: topTeam)
        .onChange(of: match.revision) { _, _ in react(to: match.lastEvents) }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            Haptics.warm()
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(item: $liveLink) { item in
            ShareSheet(items: [String(localized: "Watch us play live"), item.url])
                .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in
                if let data { center.savePhoto(data, for: match.id) }
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: match.lastTap) { _, tap in
            guard let tap else { return }
            let chant = Chant.preset(id: tap.chantID)?.name ?? "Squad chant"
            show(banner: "\(tap.fromName.split(separator: " ").first.map(String.init) ?? tap.fromName): \(chant)")
        }
        .confirmationDialog("End this match?", isPresented: $showEndOptions, titleVisibility: .visible) {
            Button("Park and resume later") {
                center.park()
                onClose()
            }
            Button("End without saving", role: .destructive) {
                center.abandon()
                onClose()
            }
            Button("Keep playing", role: .cancel) {}
        } message: {
            Text("Parked matches wait on Home. Ending discards this match.")
        }
    }

    // MARK: - Crowd and changeover photos

    @ViewBuilder
    private var crowdAndPhotoStrip: some View {
        HStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let level = match.crowd.level(at: context.date)
                if level > 0.03 {
                    HStack(spacing: 6) {
                        Image(systemName: "hands.clap.fill")
                        Capsule()
                            .fill(DS.Palette.hairline)
                            .frame(width: 70, height: 6)
                            .overlay(alignment: .leading) {
                                Capsule().fill(theme.accent).frame(width: 70 * level, height: 6)
                            }
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .accessibilityLabel("Crowd \(Int(level * 100)) percent")
                    .transition(.opacity)
                }
            }
            Spacer(minLength: 0)
            if match.photoPromptVisible, !isLocked, CameraPicker.isAvailable {
                Button {
                    Haptics.light()
                    showCamera = true
                } label: {
                    Label("Changeover photo", systemImage: "camera.fill")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(theme.accent))
                }
                .buttonStyle(.press)
                Button {
                    match.photoPromptVisible = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.Palette.nightMuted)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("No photo")
            }
        }
        .frame(height: 30)
        .padding(.horizontal, 20)
        .animation(DS.Motion.snappy, value: match.photoPromptVisible)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            circleButton("xmark", label: "End match") {
                if match.isEnded { onClose() } else { showEndOptions = true }
            }

            Spacer(minLength: 0)

            VStack(spacing: 4) {
                // Switching sport mid-match isn't allowed: the badge asks to
                // end or park instead.
                SportSwitchBadge(sport: match.sport, showsHint: false, compact: true) {
                    showEndOptions = true
                }
                Text(match.rules.summary)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Palette.nightMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if Social.shared.phase == .ready, !isLocked {
                circleButton("dot.radiowaves.left.and.right", label: "Share the live score") {
                    Task {
                        if let url = await Social.shared.shareLink(.match, target: match.id) { liveLink = IdentifiedURL(url: url) }
                    }
                }
            }

            circleButton("arrow.uturn.backward", label: "Undo last rally", dimmed: !match.canUndo) {
                undoLast()
            }
            .disabled(!match.canUndo)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func circleButton(_ symbol: String, label: String, dimmed: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(dimmed ? 0.25 : 0.9))
                .frame(width: 44, height: 44)
                .background(Circle().fill(DS.Palette.nightRaised))
                .overlay(Circle().stroke(DS.Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.press)
        .accessibilityLabel(LocalizedStringKey(label))
    }

    // MARK: - Team panels

    private func teamPanel(_ team: Team, isTop: Bool) -> some View {
        let serving = display.servingTeam == team
        let name = match.lineup.name(of: team)
        return Button {
            center.record(team)
        } label: {
            VStack(spacing: 6) {
                if !isTop { Spacer(minLength: 0) }

                HStack(spacing: 8) {
                    if serving {
                        BallIcon(sport: match.sport, size: 14)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Text(name.uppercased())
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(serving ? Color.white : DS.Palette.nightMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Text(display.points[team])
                    .font(DS.Typography.score(display.points[team].count > 2 ? 110 : 150))
                    .foregroundStyle(serving ? Color.white : Color.white.opacity(0.42))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .shadow(color: serving ? theme.accent.opacity(0.25) : .clear, radius: 24)

                HStack(spacing: 10) {
                    matchPips(for: team)
                    if match.sport == .padel {
                        Text("GAMES \(display.games[team])")
                            .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                            .tracking(1)
                            .foregroundStyle(DS.Palette.nightMuted)
                    }
                    if serving, let server = serverLabel {
                        Text(server)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(theme.accent)
                    }
                }

                if isTop { Spacer(minLength: 0) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(
                LinearGradient(
                    colors: [theme.accent.opacity(serving ? 0.10 : 0), .clear],
                    startPoint: isTop ? .top : .bottom,
                    endPoint: isTop ? .bottom : .top
                )
            )
        }
        .buttonStyle(PressStyle(scale: 0.985))
        .disabled(isLocked)
        .animation(DS.Motion.score, value: display.points[team])
        .animation(DS.Motion.snappy, value: serving)
        .accessibilityLabel("Rally won by \(name)")
        .accessibilityValue("\(display.points[team]). \(serving ? "Serving." : "")")
        .accessibilityHint("Double-tap when \(name) wins the rally")
    }

    /// "SAM · 2" in pickleball doubles, "PRIYA SERVING" otherwise.
    private var serverLabel: String? {
        guard let slot = display.server, let player = match.lineup.player(at: slot) else {
            if let number = display.serverNumber { return "SERVER \(number)" }
            return nil
        }
        if let number = display.serverNumber {
            return "\(player.shortName.uppercased()) · \(number)"
        }
        return match.lineup.isDoubles ? "\(player.shortName.uppercased()) SERVING" : nil
    }

    /// Filled pips for games (pickleball) or sets (padel) won.
    @ViewBuilder
    private func matchPips(for team: Team) -> some View {
        let needed = pipCount
        if needed > 1 {
            HStack(spacing: 5) {
                ForEach(0..<needed, id: \.self) { index in
                    Capsule()
                        .fill(index < display.matchScore[team] ? theme.accent : Color.white.opacity(0.15))
                        .frame(width: 16, height: 5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(display.matchScore[team]) \(match.sport == .padel ? "sets" : "games") won")
        }
    }

    private var pipCount: Int {
        switch match.rules {
        case .pickleball(_, let config): return config.gamesToWin
        case .padel(let config): return config.setsToWin
        }
    }

    // MARK: - Centre strip

    private var centerStrip: some View {
        HStack(spacing: 12) {
            Text(display.phaseTitle.uppercased())
                .font(DS.Typography.eyebrow)
                .tracking(1.4)
                .foregroundStyle(DS.Palette.nightMuted)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(display.call)
                .font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule(style: .continuous).fill(theme.accent))
                .contentTransition(.numericText())
                .accessibilityLabel("Score call \(display.spokenCall)")

            Group {
                if let pressure = match.topPressure {
                    Text(pressure.pressure.title.uppercased())
                        .font(DS.Typography.eyebrow)
                        .tracking(1.2)
                        .foregroundStyle(theme.accent)
                        .transition(.opacity)
                } else {
                    Button {
                        Haptics.selection()
                        withAnimation(DS.Motion.snappy) { flipped.toggle() }
                    } label: {
                        Label("Swap", systemImage: "arrow.up.arrow.down")
                            .font(DS.Typography.eyebrow)
                            .foregroundStyle(DS.Palette.nightMuted)
                    }
                    .buttonStyle(.press)
                    .accessibilityLabel("Swap sides on screen")
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(DS.Palette.nightRaised.opacity(0.9))
                .overlay(Rectangle().fill(DS.Palette.hairline).frame(height: 1), alignment: .top)
                .overlay(Rectangle().fill(DS.Palette.hairline).frame(height: 1), alignment: .bottom)
        )
        .animation(DS.Motion.snappy, value: display.call)
    }

    // MARK: - History

    private var historyBar: some View {
        HStack(spacing: 8) {
            if display.completed.isEmpty {
                Text(match.isWatchHosted ? "Scored with Apple Watch" : "Tap the side that won the rally")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.nightMuted)
            } else {
                ForEach(Array(display.completed.enumerated()), id: \.offset) { _, unit in
                    VStack(spacing: 2) {
                        Text(unitScore(unit, for: topTeam))
                        Text(unitScore(unit, for: topTeam.opponent))
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.Palette.nightRaised))
                }
            }
        }
        .frame(height: 52)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }

    private func unitScore(_ unit: CompletedUnit, for team: Team) -> String {
        if unit.isSuperTiebreak, let tiebreak = unit.tiebreak { return "\(tiebreak[team])" }
        return "\(unit.score[team])"
    }

    // MARK: - Moments

    private var sweepLine: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(LinearGradient(colors: [.clear, theme.accent, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 3)
                .shadow(color: theme.accent, radius: 8)
                .offset(y: geo.size.height * sweepProgress)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func bannerView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .tracking(1.5)
            .foregroundStyle(theme.onAccent)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Capsule(style: .continuous).fill(theme.accent))
            .shadow(color: theme.accent.opacity(0.4), radius: 16)
            .allowsHitTesting(false)
    }

    private func react(to events: [ScoreEvent]) {
        let gameWon = events.contains { event in
            switch event {
            case .gameWon, .setWon: return true
            default: return false
            }
        }
        if gameWon, !match.isFinished { runSweep() }

        if events.contains(.changeEnds), !match.isFinished {
            show(banner: "CHANGE ENDS")
        } else if events.contains(.tiebreakStarted) {
            show(banner: display.phase == .superTiebreak ? "SUPER TIEBREAK" : "TIEBREAK")
        }

        AccessibilityNotification.Announcement(display.spokenCall).post()
    }

    private func runSweep() {
        guard !reduceMotion else { return }
        sweepProgress = 0
        sweepVisible = true
        withAnimation(.easeInOut(duration: 0.7)) { sweepProgress = 1 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 750_000_000)
            sweepVisible = false
        }
    }

    private func show(banner text: String) {
        withAnimation(DS.Motion.snappy) { banner = text }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation(DS.Motion.snappy) {
                if banner == text { banner = nil }
            }
        }
    }

    private func undoLast() {
        withAnimation(DS.Motion.snappy) { center.undo() }
    }

    private func save() {
        center.finish()
        onClose()
    }
}

// MARK: - Result card

private struct MatchResultCard: View {
    let match: LiveMatch
    let onUndo: () -> Void
    let onSave: () -> Void

    @State private var appeared = false
    @State private var replayPosted = false
    @State private var isPosting = false
    @State private var showServe = false

    private func postReplay() async {
        guard let record = MatchStore.shared.record(id: match.id) else { return }
        isPosting = true
        replayPosted = await Social.shared.postReplay(for: record) != nil
        isPosting = false
    }

    var body: some View {
        let display = match.display
        let winner = display.winner ?? .a
        let theme = match.sport.theme
        let points = match.scorer.ralliesWon

        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()

            VStack(spacing: 22) {
                Text("FINAL")
                    .font(DS.Typography.eyebrow)
                    .tracking(3)
                    .foregroundStyle(DS.Palette.nightMuted)

                VStack(spacing: 6) {
                    Text(match.lineup.name(of: winner))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text("WIN")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(4)
                        .foregroundStyle(theme.accent)
                }

                Text("\(display.matchScore[winner])–\(display.matchScore[winner.opponent])")
                    .font(DS.Typography.hero(72))
                    .foregroundStyle(.white)

                Text(display.completed.map { unit in orientedLabel(unit, winner: winner) }.joined(separator: "   "))
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(DS.Palette.nightText)

                if let headline = match.drama.moments.isEmpty ? nil : match.drama.headline(match.lineup) {
                    Text(headline)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.accent)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 0) {
                    stat("POINTS", "\(points[winner])–\(points[winner.opponent])")
                    Rectangle().fill(DS.Palette.hairline).frame(width: 1, height: 34)
                    stat("RALLIES", "\(match.scorer.rallies.count)")
                    Rectangle().fill(DS.Palette.hairline).frame(width: 1, height: 34)
                    stat("TIME", durationText)
                }
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DS.Palette.nightRaised))

                VStack(spacing: 10) {
                    Button(action: onSave) {
                        Text(match.isEnded ? "Done" : "Save match")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.onAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.accent))
                    }
                    .buttonStyle(.press)

                    if match.isEnded, Social.shared.phase == .ready {
                        HStack(spacing: 10) {
                            Button {
                                Task { await postReplay() }
                            } label: {
                                Label(replayPosted ? "Posted" : "Post Replay", systemImage: replayPosted ? "checkmark" : "play.rectangle.on.rectangle")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 46)
                                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.nightRaised))
                            }
                            .disabled(replayPosted || isPosting)
                            Button {
                                showServe = true
                            } label: {
                                Label("Serve it", systemImage: "arrow.up.forward.circle")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 46)
                                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.nightRaised))
                            }
                        }
                        .buttonStyle(.press)
                    }

                    if !match.isEnded {
                        Button(action: onUndo) {
                            Label("Undo last rally", systemImage: "arrow.uturn.backward")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(DS.Palette.nightText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                        }
                        .buttonStyle(.press)
                    }
                }
            }
            .padding(26)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(DS.Palette.night)
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(theme.accent.opacity(0.35), lineWidth: 1))
            )
            .padding(20)
            .scaleEffect(appeared ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { appeared = true }
        }
        .sheet(isPresented: $showServe) {
            ServeComposerView(matchID: match.id, matchSummary: "\(match.lineup.name(of: .a, separator: " & ")) vs \(match.lineup.name(of: .b, separator: " & ")) · \(match.result.scoreLine)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(match.lineup.name(of: winner)) win \(display.matchScore[winner]) to \(display.matchScore[winner.opponent])")
    }

    private var durationText: String {
        guard let first = match.scorer.rallies.first?.at, let last = match.scorer.rallies.last?.at else { return "—" }
        let minutes = max(1, Int(last.timeIntervalSince(first) / 60))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private func orientedLabel(_ unit: CompletedUnit, winner: Team) -> String {
        if unit.isSuperTiebreak, let tiebreak = unit.tiebreak {
            return "[\(tiebreak[winner])-\(tiebreak[winner.opponent])]"
        }
        if let tiebreak = unit.tiebreak {
            return "\(unit.score[winner])-\(unit.score[winner.opponent])(\(min(tiebreak.a, tiebreak.b)))"
        }
        return "\(unit.score[winner])-\(unit.score[winner.opponent])"
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(DS.Palette.nightMuted)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }
}
