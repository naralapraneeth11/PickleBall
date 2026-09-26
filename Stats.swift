//
//  StatsView.swift
//  PickleBall
//
//  Player stats — shown when profile firstName is set.
//  Stats are recorded when the player's first name appears in a match.
//

import SwiftUI

// MARK: - Preference Key (sticky trigger)

private struct StatsHeroFrameKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - StatsView

struct StatsView: View {
    @AppStorage("profile_firstName") private var firstName: String = ""
    @ObservedObject private var matchStore = MatchStore.shared
    @State private var showSettings = false
    @State private var heroMinY: CGFloat = 0

    // Design tokens
    private let pageBg     = Color(red: 0.955, green: 0.955, blue: 0.962)
    private let cardBg     = Color.white
    private let navy       = Color(red: 0.04, green: 0.07, blue: 0.28)
    private let stroke     = Color.black.opacity(0.06)
    private let limeAccent = Color(red: 0.55, green: 0.92, blue: 0.25)

    private var trimmedFirstName: String {
        firstName.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Metrics

    private var matches: [StoredMatch] {
        matchStore.matchesForPlayer(firstName: trimmedFirstName)
    }

    private var totalWins: Int {
        matchStore.totalWins(firstName: trimmedFirstName)
    }

    private var totalLosses: Int {
        max(0, matches.count - totalWins)
    }

    private var winRatePercent: Int {
        guard !matches.isEmpty else { return 0 }
        return Int((Double(totalWins) / Double(matches.count) * 100).rounded())
    }

    private var averagePoints: Double {
        matchStore.averagePointsScored(firstName: trimmedFirstName)
    }

    private var bestWinScore: String {
        matchStore.bestWinScore(firstName: trimmedFirstName)
    }

    private var recentMatches: [StoredMatch] {
        matchStore.recentMatches(firstName: trimmedFirstName, limit: 15)
    }

    private var pointWinPercent: String {
        guard !matches.isEmpty else { return "—" }
        var myTotal = 0
        var oppTotal = 0
        for match in matches {
            if let games = match.gameScores, !games.isEmpty {
                myTotal  += games.reduce(0) { $0 + $1.myPoints }
                oppTotal += games.reduce(0) { $0 + $1.opponentPoints }
            } else {
                myTotal  += match.myScore
                oppTotal += match.opponentScore
            }
        }
        let total = myTotal + oppTotal
        guard total > 0 else { return "—" }
        return "\(Int((Double(myTotal) / Double(total) * 100).rounded()))%"
    }

    private var showStickyBar: Bool {
        heroMinY < -48 && !trimmedFirstName.isEmpty
    }

    private var shutterDarkBackground: AnyShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.11, blue: 0.26),
                    Color(red: 0.04, green: 0.07, blue: 0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: Body

    var body: some View {
        ZStack {
            pageBg.ignoresSafeArea()

            VStack(spacing: 0) {
                courtStripHeader

                ZStack(alignment: .top) {
                    ScrollView {
                        VStack(spacing: 16) {
                            if trimmedFirstName.isEmpty {
                                addNamePrompt
                            } else {
                                scrollContent
                            }
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 82)
                    }
                    .coordinateSpace(name: "statsScroll")

                    if showStickyBar {
                        compactStickyBar
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .animation(.spring(response: 0.30, dampingFraction: 0.88), value: showStickyBar)
                    }
                }
                .onPreferenceChange(StatsHeroFrameKey.self) { heroMinY = $0 }
            }

            ShutterPanel(backgroundOverride: shutterDarkBackground)
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Scroll Content

    private var scrollContent: some View {
        VStack(spacing: 16) {
            heroMetric
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: StatsHeroFrameKey.self,
                            value: geo.frame(in: .named("statsScroll")).minY
                        )
                    }
                )

            statsGrid

            matchHistorySection
        }
    }

    // MARK: - Hero

    private var heroMetric: some View {
        VStack(spacing: 6) {
            Text("WIN RATE")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.6)
                .foregroundColor(navy.opacity(0.45))

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(winRatePercent)")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("%")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
            }
            .foregroundColor(navy)

            Text("\(totalWins) wins  ·  \(totalLosses) losses")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(navy.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(stroke, lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Win rate \(winRatePercent) percent. \(totalWins) wins, \(totalLosses) losses.")
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            StatsMetricCard(title: "Wins", value: "\(totalWins)", icon: "rosette", navy: navy)
            StatsMetricCard(title: "Avg Points", value: "\(Int(averagePoints.rounded()))", icon: "chart.bar.fill", navy: navy)
            StatsMetricCard(title: "Best Win", value: bestWinScore, icon: "flag.fill", navy: navy)
            StatsMetricCard(title: "Points Won", value: pointWinPercent, icon: "percent", navy: navy)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Match History

    private var matchHistorySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Match History")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(navy)
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 10)

            if recentMatches.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "figure.pickleball")
                        .font(.system(size: 28))
                        .foregroundColor(navy.opacity(0.28))
                        .accessibilityHidden(true)
                    Text("No matches yet")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(navy.opacity(0.75))
                    Text("Play a match with your name to log history.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(navy.opacity(0.45))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentMatches.enumerated()), id: \.element.id) { index, match in
                        StatsMatchRow(match: match, navy: navy)
                        if index < recentMatches.count - 1 {
                            Divider()
                                .padding(.leading, 56)
                                .opacity(0.55)
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(stroke, lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Compact Sticky Bar

    private var compactStickyBar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(spacing: 14) {
                stickyChip(value: "\(totalWins)", label: "W")
                stickyDot
                stickyChip(value: "\(winRatePercent)%", label: "Win")
                stickyDot
                stickyChip(value: "\(Int(averagePoints.rounded()))", label: "Avg")
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(navy)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(stroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
        )
        .padding(.horizontal, 48)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(totalWins) wins, \(winRatePercent) percent win rate, average \(Int(averagePoints.rounded())) points")
    }

    private var stickyDot: some View {
        Text("·")
            .foregroundColor(navy.opacity(0.28))
    }

    private func stickyChip(value: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .fontWeight(.bold)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(navy.opacity(0.5))
        }
    }

    // MARK: - Court Header

    private var courtStripHeader: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color(red: 0.18, green: 0.38, blue: 0.58))
                    .frame(width: geo.size.width * 0.625)
                Rectangle()
                    .fill(.white)
                    .frame(width: 8)
                Rectangle()
                    .fill(Color(red: 0.08, green: 0.12, blue: 0.24))
                    .frame(width: geo.size.width * 0.359)
            }
            .frame(height: 132)
            .ignoresSafeArea(edges: .top)
            .overlay(
                HStack(alignment: .center) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.white.opacity(0.16)))
                    }
                    .accessibilityLabel("Open settings")

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        if trimmedFirstName.isEmpty {
                            Text("Stats")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        } else {
                            Text(trimmedFirstName)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(limeAccent)
                            Text("Stats")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        trimmedFirstName.isEmpty ? "Stats" : "\(trimmedFirstName)'s stats"
                    )
                }
                .padding(.horizontal, 18)
                .padding(.top, 44),
                alignment: .top
            )
        }
        .frame(height: 132)
    }

    // MARK: - Empty: No Profile Name

    private var addNamePrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 44))
                .foregroundColor(navy.opacity(0.35))
                .accessibilityHidden(true)

            Text("Set your name to track stats")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(navy)
                .multilineTextAlignment(.center)

            Text("Stats are recorded when your first name appears in a match as Player 1 or Player 2.")
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(navy.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            Button { showSettings = true } label: {
                Text("Open Profile")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(Capsule(style: .continuous).fill(navy))
            }
            .padding(.top, 4)
            .accessibilityLabel("Open profile settings")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(stroke, lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - Metric Card

private struct StatsMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let navy: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(navy.opacity(0.32))
                    .accessibilityHidden(true)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundColor(navy.opacity(0.48))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(navy)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

// MARK: - Match Row

private struct StatsMatchRow: View {
    let match: StoredMatch
    let navy: Color

    private let winColor = Color(red: 0.14, green: 0.62, blue: 0.36)
    private let lossColor = Color(red: 0.86, green: 0.24, blue: 0.24)

    var body: some View {
        HStack(spacing: 12) {
            Text(match.didWin ? "W" : "L")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(match.didWin ? winColor : lossColor)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill((match.didWin ? winColor : lossColor).opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("vs \(match.opponent)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(navy)
                    .lineLimit(1)
                Text("Games \(match.myScore)–\(match.opponentScore)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(navy.opacity(0.45))
            }

            Spacer(minLength: 8)

            Text(totalPointsText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(navy.opacity(0.55))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(match.didWin ? "Win" : "Loss") against \(match.opponent). Games \(match.myScore) to \(match.opponentScore). Points \(totalPointsText)."
        )
    }

    private var totalPointsText: String {
        guard let games = match.gameScores, !games.isEmpty else {
            return "\(match.myScore)–\(match.opponentScore)"
        }
        let myTotal = games.reduce(0) { $0 + $1.myPoints }
        let oppTotal = games.reduce(0) { $0 + $1.opponentPoints }
        return "\(myTotal)–\(oppTotal)"
    }
}

// MARK: - Preview

#Preview {
    StatsView()
}
