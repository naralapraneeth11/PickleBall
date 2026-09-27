import SwiftUI
import UIKit
import CourtKit

struct LatestMatchData {
    let dateText:          String
    let durationText:      String
    let opponentLabel:     String
    let yourScoreText:     String
    let opponentScoreText: String
    let didWin:            Bool?
    let totalShots:        Int
    let forehandCount:     Int
    let backhandCount:     Int
    let volleyCount:       Int
    let serveCount:        Int
    let peakRally:         Int
    let avgHeartRate:      Double
    let totalCalories:     Double
    /// Share of the match at heart-rate zone 4 or 5 (0…1).
    let hardShare:         Double

    func pct(_ count: Int) -> Int {
        guard totalShots > 0 else { return 0 }
        return Int((Double(count) / Double(totalShots) * 100).rounded())
    }

    static let sample = LatestMatchData(
        dateText:          "Mar 12, 4:30 PM",
        durationText:      "42m",
        opponentLabel:     "Arjun",
        yourScoreText:     "11",
        opponentScoreText: "8",
        didWin:            true,
        totalShots:        124,
        forehandCount:     71,
        backhandCount:     40,
        volleyCount:       10,
        serveCount:        3,
        peakRally:         18,
        avgHeartRate:      148.0,
        totalCalories:     340.0,
        hardShare:         0.38
    )

    static let empty = LatestMatchData(
        dateText:          "No matches yet",
        durationText:      "—",
        opponentLabel:     "—",
        yourScoreText:     "—",
        opponentScoreText: "—",
        didWin:            nil,
        totalShots:        0,
        forehandCount:     0,
        backhandCount:     0,
        volleyCount:       0,
        serveCount:        0,
        peakRally:         0,
        avgHeartRate:      0,
        totalCalories:     0,
        hardShare:         0
    )

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// Latest Watch session joined to its match by match ID.
    @MainActor
    static func load() -> LatestMatchData {
        guard let session = WorkoutStore.shared.latest else { return .empty }

        var opponentLabel = "Opponent"
        var yourScoreText = "--"
        var oppScoreText  = "--"
        var didWin: Bool? = nil
        var dateText      = dateFmt.string(from: session.date)

        if let matchID = session.matchID,
           let stored = MatchStore.shared.matches.first(where: { $0.id == matchID }) {
            opponentLabel = stored.opponent
            yourScoreText = "\(stored.myScore)"
            oppScoreText  = "\(stored.opponentScore)"
            didWin        = stored.didWin
            dateText      = dateFmt.string(from: stored.date)
        }

        let h = Int(session.duration) / 3600
        let m = (Int(session.duration) % 3600) / 60
        return LatestMatchData(
            dateText:          dateText,
            durationText:      h > 0 ? "\(h)h \(m)m" : "\(m)m",
            opponentLabel:     opponentLabel,
            yourScoreText:     yourScoreText,
            opponentScoreText: oppScoreText,
            didWin:            didWin,
            totalShots:        max(0, session.totalShots),
            forehandCount:     session.forehandCount,
            backhandCount:     session.backhandCount,
            volleyCount:       session.volleyCount,
            serveCount:        session.serveCount,
            peakRally:         session.maxRallyLength,
            avgHeartRate:      session.avgHeartRate,
            totalCalories:     session.caloriesBurned,
            hardShare:         max(0, min(1, session.hardShare))
        )
    }
}

// MARK: - Shutter Panel ───────────────────────────────────────

struct ShutterPanel: View {

    /// Override the panel + content background. When nil, uses
    /// .ultraThinMaterial (glass) — correct on the dark MainMenu.
    /// StatsView passes an opaque navy so the panel reads dark over a
    /// white page and the white text/cards inside stay readable.
    var backgroundOverride: AnyShapeStyle? = nil

    let closedHeight: CGFloat         = 90
    let stateChangeThreshold: CGFloat = 0.30
    @State private var currentHeight: CGFloat = 90
    @State private var idleHeight:    CGFloat = 90
    @State private var willChangeState = false
    // Modern window scene height computation bypassing global UIScreen.main
    @State private var screenHeight: CGFloat = {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return windowScene.screen.bounds.height
        }
        return 812 // Safe layout baseline fallback for modern notched iPhones
    }()

    @State private var matchData   = LatestMatchData.sample
    @State private var animateBars = false


    private var isOpen: Bool { idleHeight > closedHeight + 20 }

    private var openProgress: CGFloat {
        let span = max(1, screenHeight - closedHeight)
        return max(0, min(1, (currentHeight - closedHeight) / span))
    }

    private let navy        = DS.Palette.navy
    private let muted       = DS.Palette.textSecondary
    private let shutterSideBlue   = Color(red: 0.086, green: 0.325, blue: 0.522)
    private let shutterCenterNavy = Color(red: 0.082, green: 0.133, blue: 0.310)
    private let shutterDivider    = Color.white

    /// Resolved fill for the panel bar. Glass by default, override if given.
    private var panelFill: AnyShapeStyle {
        backgroundOverride ?? AnyShapeStyle(.ultraThinMaterial)
    }

    /// True when a custom (opaque) background is in play — i.e. StatsView.
    /// Used to also paint the expanded content area dark so nothing reads
    /// as a white void behind the shot tiles.
    private var hasOpaqueOverride: Bool { backgroundOverride != nil }

    // MARK: Gestures ──────────────────────────────────────────

    private var mainGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let openH = screenHeight
                let newH  = idleHeight + value.translation.height
                if newH > openH {
                    currentHeight = min(openH + pow(abs(newH - openH), 0.85), openH * 1.4)
                } else if newH < closedHeight {
                    currentHeight = max(
                        closedHeight - pow(abs(closedHeight - newH), 0.6),
                        closedHeight * 0.6
                    )
                } else {
                    currentHeight = newH
                }
                let normalized = (currentHeight - closedHeight) / (openH - closedHeight)
                let crossed = (!isOpen && normalized > stateChangeThreshold)
                           || ( isOpen && normalized < 1 - stateChangeThreshold)
                if crossed && !willChangeState {
                    Haptics.light()
                    willChangeState = true
                } else if !crossed {
                    willChangeState = false
                }
            }
            .onEnded { _ in
                let openH      = screenHeight
                let normalized = (currentHeight - closedHeight) / (openH - closedHeight)
                let wasOpen    = isOpen
                let shouldOpen  = !wasOpen && normalized > stateChangeThreshold
                let shouldClose =  wasOpen && normalized < 1 - stateChangeThreshold
                let willBeOpen  = (shouldOpen || shouldClose) ? shouldOpen : wasOpen

                Haptics.warm()

                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                    if shouldOpen || shouldClose {
                        currentHeight = willBeOpen ? openH : closedHeight
                        Haptics.medium()
                    } else {
                        currentHeight = wasOpen ? openH : closedHeight
                        Haptics.light()
                    }
                    idleHeight = currentHeight
                }

                willChangeState = false

                if willBeOpen && !wasOpen {
                    loadStatsAsynchronously()
                    animateBars = true
                } else if !willBeOpen {
                    animateBars = false
                }
            }
    }

    private var swipeUpToClose: some Gesture {
        DragGesture(minimumDistance: 50)
            .onEnded { value in
                guard value.translation.height < -50 else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                    currentHeight = closedHeight
                    idleHeight    = closedHeight
                }
                Haptics.medium()
                animateBars = false
            }
    }

    // MARK: Body ──────────────────────────────────────────────

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {

                VStack(spacing: 0) {
                    UnevenRoundedRectangle(
                        topLeadingRadius:     0,
                        bottomLeadingRadius:  28,
                        bottomTrailingRadius: 28,
                        topTrailingRadius:    0,
                        style: .continuous
                    )
                    .fill(panelFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.16), radius: 20, x: 0, y: 12)
                    .frame(height: currentHeight)
                    .overlay(alignment: .bottom) { handlePill }
                    .shadow(color: navy.opacity(0.14), radius: 22, x: 0, y: 14)
                    .simultaneousGesture(mainGesture)

                    Spacer()
                }
                .ignoresSafeArea(edges: .top)
                .ignoresSafeArea(.container, edges: .bottom)

                // Stats follow the drag via openProgress instead of flashing
                // in at the end.
                if openProgress > 0.02 {
                    statsLayout
                        // When an opaque override is set (StatsView), paint a
                        // dark backdrop sized to EXACTLY the shutter's current
                        // dragged height (currentHeight) and pinned to the top.
                        // This makes the navy fill grow/shrink with the drag
                        // instead of covering the whole screen.
                        .background(alignment: .top) {
                            if hasOpaqueOverride {
                                Rectangle()
                                    .fill(panelFill)
                                    .frame(height: currentHeight)
                                    .frame(maxHeight: .infinity, alignment: .top)
                                    .ignoresSafeArea(edges: .top)
                            } else {
                                Color.clear
                            }
                        }
                        .opacity(Double(openProgress))
                        .allowsHitTesting(isOpen)
                }
            }
            .onAppear {
                if geo.size.height > 0 { screenHeight = geo.size.height }
                Haptics.warm()
            }
            .onChange(of: geo.size.height) { _, newValue in
                if newValue > 0 { screenHeight = newValue }
            }
        }
        // Force dark-mode rendering inside the panel so SF Symbols / system
        // materials inside read correctly against the dark surface. This is
        // scoped to the shutter subtree only — it does not flip the app theme.
        .environment(\.colorScheme, .dark)
    }

    /// Reads the latest session from the SwiftData read models.
    private func loadStatsAsynchronously() {
        let loaded = LatestMatchData.load()
        withAnimation(.easeOut(duration: 0.18)) {
            matchData = loaded
        }
    }

    // MARK: Handle Pill ───────────────────────────────────────

    private var handlePill: some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.55),
                        Color.white.opacity(0.80)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.8), lineWidth: 0.5)
            )
            .frame(width: 40, height: 6)
            .padding(.bottom, 12)
            .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 2)
            .accessibilityLabel("Drag to expand match stats")
    }

    // MARK: Tri-column shutter header ────────────────────────

    private var triColumnShutterHeader: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let sideW = w * 0.28
            let centerW = w - (sideW * 2)

            HStack(spacing: 0) {
                scoreColumn(score: matchData.yourScoreText, width: sideW)
                shutterDividerLine
                centerColumn(width: centerW)
                shutterDividerLine
                scoreColumn(score: matchData.opponentScoreText, width: sideW)
            }
            .frame(width: w, height: geo.size.height)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 24,
                    bottomTrailingRadius: 24,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
        }
        .frame(height: 170)
    }

    private var shutterDividerLine: some View {
        Rectangle()
            .fill(shutterDivider)
            .frame(width: 2)
    }

    private func scoreColumn(score: String, width: CGFloat) -> some View {
        ZStack {
            shutterSideBlue
            Text(score)
                .font(.system(size: 64, weight: .black, design: .default))
                .tracking(-1)
                .foregroundColor(.white)
                .monospacedDigit()
                .minimumScaleFactor(0.45)
                .lineLimit(1)
                .padding(.top, 48)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
    }

    private func centerColumn(width: CGFloat) -> some View {
        ZStack {
            shutterCenterNavy
            VStack(spacing: 8) {
                if let won = matchData.didWin {
                    Text(won ? "WIN" : "LOSS")
                        .font(.system(size: 22, weight: .black, design: .default))
                        .tracking(3)
                        .foregroundColor(.white)
                } else {
                    Text("—")
                        .font(.system(size: 22, weight: .black, design: .default))
                        .foregroundColor(.white.opacity(0.55))
                }
                Text(matchData.dateText.uppercased())
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 6)
            }
            .padding(.top, 48)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
    }

    // MARK: Stats Layout ──────────────────────────────────────

    private var statsLayout: some View {
        VStack(spacing: 0) {

            triColumnShutterHeader
                .accessibilityElement(children: .combine)
                .accessibilityLabel({
                    let result = matchData.didWin == true ? "You won" :
                                 matchData.didWin == false ? "You lost" : "Result unknown"
                    return "Latest match against \(matchData.opponentLabel). \(result) \(matchData.yourScoreText) to \(matchData.opponentScoreText)"
                }())

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 14)

            heroMetricsSection
                .padding(.horizontal, 20)

            HStack(spacing: 8) {
                Text("SHOT BREAKDOWN")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(2.2)
                    .foregroundColor(Color.white.opacity(0.50))

                BetaBadge()

                if matchData.totalShots > 0 {
                    Text("·  \(matchData.totalShots) total")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.32))
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 10)

            shotTilesGrid
                .padding(.horizontal, 20)

            Spacer(minLength: 22)
        }
        .ignoresSafeArea(edges: .top)
        .contentShape(Rectangle())
        .gesture(swipeUpToClose)
    }

    // MARK: - Hero Metrics Section (hero Shots card + 3 chips)

    private var heroMetricsSection: some View {
        VStack(spacing: 12) {
            heroShotsCard

            HStack(spacing: 10) {
                MetricChip(title: "DURATION", value: matchData.durationText)
                MetricChip(
                    title: "AVG BPM",
                    value: matchData.avgHeartRate > 0
                        ? "\(Int(matchData.avgHeartRate.rounded()))"
                        : "–"
                )
                MetricChip(
                    title: "ZONE 4–5",
                    value: matchData.avgHeartRate > 0 ? "\(Int(matchData.hardShare * 100))%" : "–",
                    valueColor: zoneColor(matchData.hardShare)
                )
            }
        }
    }

    private var heroShotsCard: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SHOTS")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.6)
                    .foregroundColor(Color.white.opacity(0.55))

                Text("\(matchData.totalShots)")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text("wrist-detected shots · beta")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.55))
            }

            Spacer(minLength: 0)

            DotsRing(
                filled: dotsFilled(
                    forPercent: heroPercentFill,
                    total: 14
                ),
                total: 14
            )
            .frame(width: 74, height: 74)
            .opacity(0.9)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Total shots this match: \(matchData.totalShots)")
    }

    private var heroPercentFill: Int {
        guard matchData.peakRally > 0 else { return 0 }
        let p = Double(matchData.peakRally) / 25.0 * 100.0
        return max(0, min(100, Int(p.rounded())))
    }

    private func dotsFilled(forPercent percent: Int, total: Int) -> Int {
        let p = max(0, min(100, percent))
        return Int((Double(p) / 100.0 * Double(total)).rounded())
    }

    private struct MetricChip: View {
        let title: String
        let value: String
        var valueColor: Color = .white

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(Color.white.opacity(0.45))

                Text(value)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(valueColor)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
    }

    private struct DotsRing: View {
        let filled: Int
        let total: Int

        var body: some View {
            GeometryReader { geo in
                let radius = min(geo.size.width, geo.size.height) / 2 - 3
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

                ZStack {
                    ForEach(0..<total, id: \.self) { i in
                        let angle = (Double(i) / Double(total)) * 2 * .pi - .pi / 2
                        let x = center.x + CGFloat(cos(angle)) * radius
                        let y = center.y + CGFloat(sin(angle)) * radius

                        Circle()
                            .fill(
                                i < filled
                                    ? Color.white.opacity(0.9)
                                    : Color.white.opacity(0.22)
                            )
                            .frame(width: 5, height: 5)
                            .position(x: x, y: y)
                    }
                }
            }
        }
    }

    // MARK: - Shot tiles grid

    private var shotTilesGrid: some View {
        let columns: [GridItem] = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
            ShotTile(
                title: "Forehand",
                count: matchData.forehandCount,
                percent: matchData.pct(matchData.forehandCount),
                icon: "tennisball.fill"
            )

            ShotTile(
                title: "Backhand",
                count: matchData.backhandCount,
                percent: matchData.pct(matchData.backhandCount),
                icon: "arrow.uturn.left.circle.fill"
            )

            ShotTile(
                title: "Volley",
                count: matchData.volleyCount,
                percent: matchData.pct(matchData.volleyCount),
                icon: "arrow.up.right.circle.fill"
            )

            ShotTile(
                title: "Serve",
                count: matchData.serveCount,
                percent: matchData.pct(matchData.serveCount),
                icon: "bolt.fill"
            )
        }
    }

    private struct ShotTile: View {
        let title: String
        let count: Int
        let percent: Int
        let icon: String

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 8)

                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                }

                Text("\(count)")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 6) {
                    DotsRow(filled: dotsFilled(for: percent), total: 8)
                        .opacity(0.85)

                    Spacer()

                    Text("\(percent)%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                        .monospacedDigit()
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .accessibilityLabel("\(title): \(count) shots, \(percent)% of total")
        }

        private func dotsFilled(for percent: Int) -> Int {
            let p = max(0, min(100, percent))
            return Int((Double(p) / 100.0 * 8.0).rounded())
        }
    }

    private struct DotsRow: View {
        let filled: Int
        let total: Int

        var body: some View {
            HStack(spacing: 5) {
                ForEach(0..<total, id: \.self) { i in
                    Circle()
                        .fill(i < filled ? Color.white.opacity(0.85) : Color.white.opacity(0.25))
                        .frame(width: 5, height: 5)
                }
            }
        }
    }

    /// Colour for the share of time spent at threshold or above.
    private func zoneColor(_ share: Double) -> Color {
        switch share {
        case ..<0.20: return DS.Palette.win
        case ..<0.40: return DS.Palette.warning
        default:      return DS.Palette.loss
        }
    }
}

// MARK: - Main Menu ───────────────────────────────────────────

struct MainMenu: View {
    @Environment(SportMode.self) private var sportMode
    @State private var showPlayView = false
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showNewTournament = false
    @State private var showScoreboard = false
    @State private var tournamentToContinue: SavedTournament?

    @ObservedObject private var tournamentStore = TournamentStore.shared
    @ObservedObject private var matchStore = MatchStore.shared
    @ObservedObject private var watchManager = WatchConnectivityManager.shared
    private let center = MatchCenter.shared

    @AppStorage("health_access_opt_in")   private var healthAccessOptIn    = false
    @AppStorage("health_access_prompted") private var healthAccessPrompted = false
    @State private var showHealthPrompt = false
    @State private var hasCheckedHealthOnAppear = false

    private var theme: SportTheme { sportMode.theme }

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                ZStack {
                    courtBackground(height: geometry.size.height)

                    // Top: settings + sport badge
                    VStack {
                        HStack {
                            Button(action: { showSettings = true }) {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 26, weight: .regular))
                                    .foregroundStyle(.white)
                                    .padding()
                            }
                            .accessibilityLabel("Open settings")
                            Spacer()
                            SportSwitchBadge(sport: sportMode.sport, showsHint: sportMode.showsHint) {
                                switchSport()
                            }
                            .padding(.trailing, 18)
                        }
                        Spacer()
                    }
                    .padding(.top, 84)

                    // Center actions
                    VStack(spacing: 14) {
                        Spacer()

                        if let live = center.live, !live.isEnded {
                            liveMatchCard(live)
                                .padding(.horizontal, 28)
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }

                        Button(action: { showPlayView = true }) {
                            Text("START MATCH")
                                .font(.system(size: 25, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.black.opacity(0.14))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(theme.accent.opacity(0.6), lineWidth: 1.5)
                                        )
                                )
                        }
                        .buttonStyle(.press)
                        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 8)
                        .accessibilityLabel("Start a new \(sportMode.sport.displayName) match")

                        VStack(spacing: 10) {
                            ForEach(matchStore.parked.prefix(2)) { setup in
                                menuSecondaryButton(
                                    title: "Resume: \(setup.lineup.shortName(of: .a)) vs \(setup.lineup.shortName(of: .b))",
                                    systemImage: "pause.circle.fill"
                                ) {
                                    if center.resume(matchID: setup.matchID) != nil { showScoreboard = true }
                                }
                            }

                            menuSecondaryButton(title: "New Tournament", systemImage: "plus.circle.fill") {
                                showNewTournament = true
                            }

                            ForEach(tournamentStore.incompleteTournaments) { tournament in
                                menuSecondaryButton(
                                    title: "Continue: \(tournament.resolvedTitle)",
                                    systemImage: "play.circle.fill"
                                ) {
                                    tournamentToContinue = tournament
                                }
                            }

                            menuSecondaryButton(title: "Tournament History", systemImage: "clock.arrow.circlepath") {
                                showHistory = true
                            }
                        }
                        .padding(.horizontal, 28)

                        Spacer()
                            .frame(height: geometry.size.height * 0.12)
                    }
                }
            }
            .ignoresSafeArea()

            ShutterPanel()

            if showHealthPrompt {
                healthAccessPrompt
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(DS.Motion.snappy, value: sportMode.sport)
        .animation(DS.Motion.snappy, value: center.live?.id)
        .fullScreenCover(isPresented: $showPlayView) {
            PlayView(onDismiss: { showPlayView = false })
        }
        .fullScreenCover(isPresented: $showScoreboard) {
            LiveMatchScreen()
        }
        .fullScreenCover(isPresented: $showNewTournament) {
            TournamentSetupView()
        }
        .fullScreenCover(item: $tournamentToContinue) { tournament in
            TournamentRunView(tournament: tournament)
        }
        .fullScreenCover(isPresented: $showHistory) {
            NavigationStack {
                TournamentHistoryView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showHistory = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            guard !hasCheckedHealthOnAppear else { return }
            hasCheckedHealthOnAppear = true

            if !healthAccessOptIn, !healthAccessPrompted,
               watchManager.isWatchPaired, watchManager.isWatchAppInstalled {
                showHealthPrompt = true
            }
        }
    }

    // MARK: Court

    private func courtBackground(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Rectangle().fill(theme.courtSurface)
                Rectangle().fill(Color.white).frame(width: 5)
                Rectangle().fill(theme.courtSurfaceAlt)
            }
            .frame(height: height * 0.375)

            Rectangle().fill(Color.white).frame(height: 5)

            Rectangle()
                .fill(DS.Palette.navy)
                .frame(height: height * 0.249)

            Rectangle().fill(Color.white).frame(height: 5)

            HStack(spacing: 0) {
                Rectangle().fill(theme.courtSurface.opacity(0.95))
                Rectangle().fill(Color.white).frame(width: 5)
                Rectangle().fill(theme.courtSurfaceAlt.opacity(0.95))
            }
            .frame(height: height * 0.375)
        }
        .frame(height: height)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func switchSport() {
        if let live = center.live, !live.isEnded {
            // Never switch mid-match: open the match so it can be ended or parked.
            showScoreboard = true
            return
        }
        sportMode.toggle()
        center.publishPreferences(sport: sportMode.sport)
    }

    // MARK: Live match

    private func liveMatchCard(_ match: LiveMatch) -> some View {
        Button {
            Haptics.light()
            showScoreboard = true
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(match.sport.theme.accent)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.isWatchHosted ? "LIVE ON APPLE WATCH" : "LIVE")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(match.sport.theme.accent)
                    Text("\(match.lineup.shortName(of: .a)) vs \(match.lineup.shortName(of: .b))")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(match.display.points.a)–\(match.display.points.b)")
                    .font(DS.Typography.score(26))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(match.sport.theme.accent.opacity(0.5), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.press)
        .accessibilityLabel("Live match, \(match.lineup.name(of: .a)) versus \(match.lineup.name(of: .b)). Open scoreboard.")
    }

    private func menuSecondaryButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.press)
        .accessibilityLabel(title)
    }

    private var healthAccessPrompt: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { showHealthPrompt = false }

            VStack(spacing: 18) {
                Text("Add Apple Watch insights?")
                    .font(.system(size: 18, weight: .semibold))
                    .multilineTextAlignment(.center)

                Text("Your Watch records heart-rate zones, duration and calories for every match, plus beta shot detection. Only while you play with the app open on your wrist.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("Allow Health data access?")
                    .font(.system(size: 15, weight: .semibold))

                HStack(spacing: 12) {
                    Button("Not Now") {
                        healthAccessPrompted = true
                        showHealthPrompt = false
                    }
                    .buttonStyle(.bordered)

                    Button("Allow") {
                        healthAccessPrompted = true
                        showHealthPrompt = false
                        watchManager.requestHealthAuthorization { granted in
                            if granted { healthAccessOptIn = true }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.Palette.ink)
                }
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
        }
    }
}

#Preview {
    MainMenu()
        .environment(SportMode())
}
