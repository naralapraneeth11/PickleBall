//
//  WatchStatsDetailView.swift
//  PickleBall
//
//  Watch performance — pure models, actor repository, thin ViewModel,
//  single hero (serve hold), compact shot mix, matchID-first join.
//

import SwiftUI
import UIKit
import CourtKit

// MARK: - Load pipeline result

struct WatchStatsFetchResult: Sendable {
    let hasPermission: Bool
    let snapshot: WatchStatsSnapshot?
    let joinMissCount: Int
}

struct WatchStatsSnapshot: Equatable, Sendable {
    let allTime: AllTimeWatchStats
    let serveHold: ServeHoldStats
    let insight: String
    let recent: [RecentMatchCardModel]
}

// MARK: - Serve hold (scoring truth → StoredMatch)

struct ServeHoldStats: Equatable, Sendable {
    let pointsPlayed: Int
    let pointsWon: Int

    var percent: Int {
        guard pointsPlayed > 0 else { return 0 }
        return Int((Double(pointsWon) / Double(pointsPlayed) * 100).rounded())
    }

    var subtitle: String {
        guard pointsPlayed > 0 else { return "No serve points logged yet" }
        return "\(pointsWon) of \(pointsPlayed) points on your serve"
    }

    static let zero = ServeHoldStats(pointsPlayed: 0, pointsWon: 0)

    static func compute(from matches: [StoredMatch]) -> ServeHoldStats {
        let played = matches.reduce(0) { $0 + ($1.servePointsPlayed ?? 0) }
        let won = matches.reduce(0) { $0 + ($1.servePointsWon ?? 0) }
        return ServeHoldStats(pointsPlayed: played, pointsWon: won)
    }
}

// MARK: - All-time Watch aggregates (IMU / session truth)

struct AllTimeWatchStats: Equatable, Sendable {
    let totalSessions: Int
    let totalDuration: TimeInterval
    let totalShots: Int
    let forehandCount: Int
    let backhandCount: Int
    let volleyCount: Int
    let serveSwingCount: Int
    let maxRallyLength: Int
    let avgHeartRate: Double
    let totalCalories: Double
    /// Average share of match time at heart-rate zone 4–5 (0…1).
    let avgHardShare: Double

    var sessionCount: Int { totalSessions }

    var avgSessionDuration: TimeInterval {
        totalSessions > 0 ? totalDuration / Double(totalSessions) : 0
    }

    func percent(of count: Int) -> Int {
        guard totalShots > 0 else { return 0 }
        return Int((Double(count) / Double(totalShots) * 100).rounded())
    }

    static func compute(sessions: [GameSession]) -> AllTimeWatchStats {
        let real = sessions.filter { $0.totalShots > 0 || $0.duration > 0 }
        let hrSamples = real.filter { $0.avgHeartRate > 0 }
        let avgHR = hrSamples.isEmpty
            ? 0
            : hrSamples.map(\.avgHeartRate).reduce(0, +) / Double(hrSamples.count)

        return AllTimeWatchStats(
            totalSessions: real.count,
            totalDuration: real.reduce(0) { $0 + $1.duration },
            totalShots: real.reduce(0) { $0 + $1.totalShots },
            forehandCount: real.reduce(0) { $0 + $1.forehandCount },
            backhandCount: real.reduce(0) { $0 + $1.backhandCount },
            volleyCount: real.reduce(0) { $0 + $1.volleyCount },
            serveSwingCount: real.reduce(0) { $0 + $1.serveCount },
            maxRallyLength: real.map(\.maxRallyLength).max() ?? 0,
            avgHeartRate: avgHR,
            totalCalories: real.reduce(0) { $0 + $1.caloriesBurned },
            avgHardShare: {
                let zoned = real.filter { !$0.secondsInZone.isEmpty }
                return zoned.isEmpty ? 0 : zoned.map(\.hardShare).reduce(0, +) / Double(zoned.count)
            }()
        )
    }
}

// MARK: - Insight

enum WatchStatsInsight {
    static func make(allTime: AllTimeWatchStats, serveHold: ServeHoldStats) -> String {
        guard allTime.totalSessions > 0 else {
            return "Play with your Watch to unlock performance insights."
        }

        let swings: [(String, Int)] = [
            ("Forehand", allTime.forehandCount),
            ("Backhand", allTime.backhandCount),
            ("Volley", allTime.volleyCount)
        ]
        let dominant = swings.max(by: { $0.1 < $1.1 })?.0 ?? "Forehand"
        let hard = Int((allTime.avgHardShare * 100).rounded())
        let avgMin = max(1, Int(allTime.avgSessionDuration / 60))

        if serveHold.pointsPlayed >= 8 {
            return "\(dominant)-heavy (beta) · Serve hold \(serveHold.percent)% · Zone 4–5 \(hard)%"
        }
        return "\(dominant)-heavy · Avg \(avgMin)m · Peak rally \(allTime.maxRallyLength)"
    }
}

// MARK: - Recent card

struct RecentMatchCardModel: Identifiable, Equatable, Sendable {
    let id: UUID
    let dateText: String
    let durationText: String
    let opponentLabel: String
    let yourScoreText: String
    let opponentScoreText: String
    let didWin: Bool?
    let totalShots: Int
    let maxRallyLength: Int
    let forehandPercent: Double
    let backhandPercent: Double
    let volleyPercent: Double
    let hardZonePercent: Double
    let serveHoldPercent: Int?
    let joinedByMatchID: Bool
    let scoreLinked: Bool
    var isPersonalBestRally: Bool = false
    var isPersonalBestHold: Bool = false
}

// MARK: - Card builder

enum RecentMatchCardBuilder {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
    
    static func build(
        sessions: [GameSession],
        storedMatches: [StoredMatch]
    ) -> (cards: [RecentMatchCardModel], joinMissCount: Int) {
        
        let byID = Dictionary(
            storedMatches.compactMap { match in match.matchID.map { ($0, match) } },
            uniquingKeysWith: { _, last in last }
        )
        let sortedStored = storedMatches.sorted { $0.date < $1.date }
        let storedDates = sortedStored.map { $0.date.timeIntervalSince1970 }

        var miss = 0
        let cards: [RecentMatchCardModel] = sessions.reversed().map { session in
            let total = max(0, session.totalShots)
            let fh = total > 0 ? Double(session.forehandCount) / Double(total) : 0
            let bh = total > 0 ? Double(session.backhandCount) / Double(total) : 0
            let vo = total > 0 ? Double(session.volleyCount) / Double(total) : 0

            let joined = resolve(session: session, byID: byID, sorted: sortedStored, dates: storedDates)
            if joined.stored == nil { miss += 1 }

            let servePct: Int? = {
                let played = joined.stored?.servePointsPlayed
                let won = joined.stored?.servePointsWon
                guard let played, played > 0, let won else { return nil }
                return Int((Double(won) / Double(played) * 100).rounded())
            }()

            let stableID = session.id

            return RecentMatchCardModel(
                id: stableID,
                dateText: dateFormatter.string(from: session.date),
                durationText: formatDuration(session.duration),
                opponentLabel: joined.stored?.opponent ?? "Opponent",
                yourScoreText: joined.stored.map { "\($0.myScore)" } ?? "—",
                opponentScoreText: joined.stored.map { "\($0.opponentScore)" } ?? "—",
                didWin: joined.stored?.didWin,
                totalShots: total,
                maxRallyLength: session.maxRallyLength,
                forehandPercent: fh,
                backhandPercent: bh,
                volleyPercent: vo,
                hardZonePercent: max(0, min(1, session.hardShare)),
                serveHoldPercent: servePct,
                joinedByMatchID: joined.byMatchID,
                scoreLinked: joined.stored != nil
            )
        }
        
        // Compute Personal Bests across this set
        let bestRally = cards.map(\.maxRallyLength).max() ?? 0
        let bestHold = cards.compactMap(\.serveHoldPercent).max()

        let cardsWithPB: [RecentMatchCardModel] = cards.map { c in
            var copy = c
            copy.isPersonalBestRally = bestRally > 0 && c.maxRallyLength == bestRally
            if let bestHold, let h = c.serveHoldPercent {
                copy.isPersonalBestHold = h == bestHold
            }
            return copy
        }
        
        return (cardsWithPB, miss)
    }

    private static func resolve(
        session: GameSession,
        byID: [UUID: StoredMatch],
        sorted: [StoredMatch],
        dates: [Double]
    ) -> (stored: StoredMatch?, byMatchID: Bool) {
        if let mid = session.matchID, let hit = byID[mid] {
            return (hit, true)
        }
        let legacy = closest(for: session.date, in: sorted, dates: dates, window: 300)
        return (legacy, false)
    }

    private static func closest(
        for target: Date,
        in sorted: [StoredMatch],
        dates: [Double],
        window: TimeInterval
    ) -> StoredMatch? {
        guard !sorted.isEmpty else { return nil }
        let key = target.timeIntervalSince1970
        var lo = 0, hi = dates.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if dates[mid] < key { lo = mid + 1 } else { hi = mid }
        }
        let candidates = [lo - 1, lo].filter { $0 >= 0 && $0 < dates.count }
        guard let best = candidates.min(by: { abs(dates[$0] - key) < abs(dates[$1] - key) }),
              abs(dates[best] - key) < window else { return nil }
        return sorted[best]
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(max(0, m))m"
    }
}

// MARK: - Repository

protocol WatchStatsRepositoryProtocol: Sendable {
    func fetch() async -> WatchStatsFetchResult
}

actor WatchStatsRepository: WatchStatsRepositoryProtocol {
    func fetch() async -> WatchStatsFetchResult {
        let permitted = await requestHealthPermission()
        guard permitted else {
            return WatchStatsFetchResult(hasPermission: false, snapshot: nil, joinMissCount: 0)
        }

        let sessions = await MainActor.run { WorkoutStore.shared.sessions }
        let stored = await MainActor.run { MatchStore.shared.matches }

        guard !sessions.isEmpty else {
            return WatchStatsFetchResult(hasPermission: true, snapshot: nil, joinMissCount: 0)
        }

        // The builders are cheap, pure and main-actor isolated by the app's
        // default isolation; run them there rather than hopping per call.
        let (allTime, serveHold, insight, built) = await MainActor.run {
            let allTime = AllTimeWatchStats.compute(sessions: sessions)
            let serveHold = ServeHoldStats.compute(from: stored)
            let insight = WatchStatsInsight.make(allTime: allTime, serveHold: serveHold)
            let built = RecentMatchCardBuilder.build(sessions: sessions, storedMatches: stored)
            return (allTime, serveHold, insight, built)
        }

        #if DEBUG
        if built.joinMissCount > 0 {
            print("WatchStats: joinMissCount=\(built.joinMissCount) — prefer matchID on GameSession")
        }
        #endif

        let snap = WatchStatsSnapshot(
            allTime: allTime,
            serveHold: serveHold,
            insight: insight,
            recent: built.cards
        )
        return WatchStatsFetchResult(
            hasPermission: true,
            snapshot: snap,
            joinMissCount: built.joinMissCount
        )
    }

    private func requestHealthPermission() async -> Bool {
        await withCheckedContinuation { cont in
            Task { @MainActor in
                WatchConnectivityManager.shared.requestHealthAuthorization { success in
                    cont.resume(returning: success)
                }
            }
        }
    }
}

// MARK: - Preview Repository (Must be defined before ViewModel)

#if DEBUG
private struct PreviewWatchStatsRepository: WatchStatsRepositoryProtocol {
    func fetch() async -> WatchStatsFetchResult {
        try? await Task.sleep(nanoseconds: 400_000_000)

        let allTime = AllTimeWatchStats(
            totalSessions: 12, totalDuration: 18_400, totalShots: 1_482,
            forehandCount: 712, backhandCount: 418, volleyCount: 196,
            serveSwingCount: 156, maxRallyLength: 18, avgHeartRate: 138,
            totalCalories: 2_140, avgHardShare: 0.32
        )
        let serveHold = ServeHoldStats(pointsPlayed: 94, pointsWon: 61)
        let insight = WatchStatsInsight.make(allTime: allTime, serveHold: serveHold)

        let recent: [RecentMatchCardModel] = [
            RecentMatchCardModel(
                id: UUID(), dateText: "Aug 28, 6:42 PM", durationText: "41m", opponentLabel: "Arjun",
                yourScoreText: "11", opponentScoreText: "7", didWin: true, totalShots: 118,
                maxRallyLength: 18, forehandPercent: 0.54, backhandPercent: 0.29, volleyPercent: 0.12,
                hardZonePercent: 0.58, serveHoldPercent: 72, joinedByMatchID: true, scoreLinked: true,
                isPersonalBestRally: false, isPersonalBestHold: true
            ),
            RecentMatchCardModel(
                id: UUID(), dateText: "Aug 27, 7:15 PM", durationText: "36m", opponentLabel: "Vikram",
                yourScoreText: "9", opponentScoreText: "11", didWin: false, totalShots: 102,
                maxRallyLength: 12, forehandPercent: 0.48, backhandPercent: 0.34, volleyPercent: 0.11,
                hardZonePercent: 0.71, serveHoldPercent: 55, joinedByMatchID: true, scoreLinked: true,
                isPersonalBestRally: false, isPersonalBestHold: false
            ),
            RecentMatchCardModel(
                id: UUID(), dateText: "Aug 26, 5:50 PM", durationText: "48m", opponentLabel: "Rahul",
                yourScoreText: "11", opponentScoreText: "5", didWin: true, totalShots: 134,
                maxRallyLength: 24, forehandPercent: 0.61, backhandPercent: 0.26, volleyPercent: 0.09,
                hardZonePercent: 0.49, serveHoldPercent: 80, joinedByMatchID: true, scoreLinked: true,
                isPersonalBestRally: true, isPersonalBestHold: false
            )
        ]

        return WatchStatsFetchResult(
            hasPermission: true,
            snapshot: WatchStatsSnapshot(allTime: allTime, serveHold: serveHold, insight: insight, recent: recent),
            joinMissCount: 1
        )
    }
}
#endif

// MARK: - ViewModel

@MainActor
@Observable
final class WatchStatsViewModel {
    private(set) var isLoading = true
    private(set) var hasPermission = false
    private(set) var snapshot: WatchStatsSnapshot?
    private(set) var loadFailedMessage: String?

    private let repository: WatchStatsRepositoryProtocol

    init(repository: WatchStatsRepositoryProtocol) {
        self.repository = repository
    }
    
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            self.repository = PreviewWatchStatsRepository()
            return
        }
        #endif
        self.repository = WatchStatsRepository()
    }

    func load() async {
        isLoading = true
        loadFailedMessage = nil
        let result = await repository.fetch()
        hasPermission = result.hasPermission
        snapshot = result.snapshot
        isLoading = false
    }

    func refresh() async {
        await load()
    }
}

// MARK: - Theme

private enum WatchStatsTheme {
    static let darkBg = Color(red: 0.07, green: 0.08, blue: 0.12)
    static let card = Color(red: 0.12, green: 0.13, blue: 0.18)
    static let navyText = Color(red: 0.92, green: 0.93, blue: 0.96)
    static let muted = Color.white.opacity(0.45)
    static let lime = DS.Palette.lime
    static let stroke = Color.white.opacity(0.08)
    static let loss = Color(red: 1.0, green: 0.38, blue: 0.38)
}

// MARK: - View

struct WatchStatsDetailView: View {
    @State private var viewModel = WatchStatsViewModel()
    @State private var expandedMatchID: UUID? = nil
    @State private var recentFilter: RecentFilter = .all
    
    private enum RecentFilter: String, CaseIterable {
        case all = "All"
        case wins = "Wins"
        case losses = "Losses"
    }
    
    var body: some View {
        ZStack {
            WatchStatsTheme.darkBg.ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    
                    if viewModel.isLoading {
                        skeleton
                    } else if !viewModel.hasPermission {
                        permissionCard
                    } else if let snap = viewModel.snapshot {
                        readyContent(snap)
                    } else {
                        emptyCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .refreshable { await viewModel.refresh() }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task {
            Haptics.warm()
            await viewModel.load()
        }
    }
    
    // MARK: Header
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("WATCH")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(WatchStatsTheme.muted)
                Spacer()
                Image(systemName: "applewatch.side.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.1)))
                    .accessibilityHidden(true)
            }
            .padding(.top, 12)
            
            Text("Performance")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Watch performance")
    }
    
    // MARK: Ready
    
    private func readyContent(_ snap: WatchStatsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            heroCard(snap)
            metaStrip(snap.allTime)
            shotMixCard(snap.allTime)
            biometricsRow(snap.allTime)
            trendStrip(snap.recent)
            recentSection(snap.recent)
        }
    }
    
    private func heroCard(_ snap: WatchStatsSnapshot) -> some View {
        let hold = snap.serveHold
        let hasHold = hold.pointsPlayed > 0
        
        return VStack(alignment: .leading, spacing: 10) {
            Text(hasHold ? "SERVE HOLD" : "PEAK RALLY")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(WatchStatsTheme.muted)
            
            if hasHold {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(hold.percent)")
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.white)
                    Text("%")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Text(hold.subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(WatchStatsTheme.muted)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(snap.allTime.maxRallyLength)")
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text("shots")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(WatchStatsTheme.muted)
                }
                Text("Longest rally · log serve points in a match to unlock hold %")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(WatchStatsTheme.muted)
            }
            
            Text(snap.insight)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(WatchStatsTheme.lime)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(cardBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            hasHold
            ? "Serve hold \(hold.percent) percent. \(hold.subtitle). \(snap.insight)"
            : "Peak rally \(snap.allTime.maxRallyLength) shots. \(snap.insight)"
        )
    }
    
    private func filteredRecent(_ matches: [RecentMatchCardModel]) -> [RecentMatchCardModel] {
        switch recentFilter {
        case .all: return matches
        case .wins: return matches.filter { $0.didWin == true }
        case .losses: return matches.filter { $0.didWin == false }
        }
    }
    
    @ViewBuilder
    private func trendStrip(_ matches: [RecentMatchCardModel]) -> some View {
        let last5 = Array(matches.prefix(5))
        
        // Using 'if' instead of 'guard' is the safest way to return optional views in @ViewBuilder
        if last5.count >= 2 {
            VStack(alignment: .leading, spacing: 8) {
                Text("TREND · LAST \(last5.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(WatchStatsTheme.muted)
                
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(last5) { m in
                        let h = max(4.0, CGFloat(m.totalShots) / 150.0 * 36.0)
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(m.didWin == true ? WatchStatsTheme.lime.opacity(0.85)
                                      : m.didWin == false ? WatchStatsTheme.loss.opacity(0.7)
                                      : Color.white.opacity(0.2))
                                .frame(width: 14, height: h)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 40)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(cardBackground)
            }
        }
    }
    
    private func metaStrip(_ s: AllTimeWatchStats) -> some View {
        HStack(spacing: 0) {
            metaItem("\(s.sessionCount)", "Sessions")
            metaDivider
            metaItem(RecentMatchCardBuilder.formatDuration(s.totalDuration), "Time")
            metaDivider
            metaItem("\(s.totalShots)", "Shots")
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(s.sessionCount) sessions, \(RecentMatchCardBuilder.formatDuration(s.totalDuration)), \(s.totalShots) shots"
        )
    }
    
    private func metaItem(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(WatchStatsTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var metaDivider: some View {
        Rectangle()
            .fill(WatchStatsTheme.stroke)
            .frame(width: 1, height: 28)
    }
    
    private func shotMixCard(_ s: AllTimeWatchStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SHOT MIX · BETA")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(WatchStatsTheme.muted)
            
            shotRow("Forehand", s.forehandCount, s.percent(of: s.forehandCount))
            shotRow("Backhand", s.backhandCount, s.percent(of: s.backhandCount))
            shotRow("Volley", s.volleyCount, s.percent(of: s.volleyCount))
            shotRow("Serve swings", s.serveSwingCount, s.percent(of: s.serveSwingCount))
            
            Text("Serve swings are Watch motion counts — not the same as serve hold %.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(WatchStatsTheme.muted.opacity(0.85))
                .padding(.top, 2)
        }
        .padding(18)
        .background(cardBackground)
    }
    
    private func shotRow(_ name: String, _ count: Int, _ percent: Int) -> some View {
        HStack(spacing: 12) {
            Text(name)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 108, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(WatchStatsTheme.lime.opacity(0.9))
                        .frame(width: max(4, geo.size.width * CGFloat(percent) / 100.0))
                }
            }
            .frame(height: 8)
            Text("\(percent)%")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(WatchStatsTheme.muted)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(count) shots, \(percent) percent")
    }
    
    private func biometricsRow(_ s: AllTimeWatchStats) -> some View {
        HStack(spacing: 10) {
            bioChip(
                title: "Heart",
                value: s.avgHeartRate > 0 ? "\(Int(s.avgHeartRate.rounded()))" : "—",
                unit: "bpm"
            )
            bioChip(
                title: "Calories",
                value: s.totalCalories > 999
                ? String(format: "%.1fk", s.totalCalories / 1000)
                : "\(Int(s.totalCalories.rounded()))",
                unit: "kcal"
            )
            bioChip(
                title: "Zone 4–5",
                value: "\(Int((s.avgHardShare * 100).rounded()))",
                unit: "%"
            )
        }
    }
    
    private func bioChip(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(WatchStatsTheme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(WatchStatsTheme.muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value) \(unit)")
    }
    
    private func recentSection(_ matches: [RecentMatchCardModel]) -> some View {
        let visible = Array(filteredRecent(matches).prefix(6))
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RECENT")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(WatchStatsTheme.muted)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(RecentFilter.allCases, id: \.self) { f in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { recentFilter = f }
                        } label: {
                            Text(f.rawValue)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(recentFilter == f ? .black : WatchStatsTheme.muted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule().fill(recentFilter == f ? WatchStatsTheme.lime : Color.white.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            if visible.isEmpty {
                Text("No sessions yet.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(WatchStatsTheme.muted)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 10) {
                    ForEach(visible) { model in
                        recentRow(
                            model,
                            isExpanded: expandedMatchID == model.id
                        ) {
                            Haptics.light()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
                                expandedMatchID = (expandedMatchID == model.id) ? nil : model.id
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(cardBackground)
    }
    
    private func recentRow(
        _ m: RecentMatchCardModel,
        isExpanded: Bool,
        onToggle: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(m.dateText)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(WatchStatsTheme.muted)
                        Spacer()
                        Text(m.durationText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(WatchStatsTheme.muted)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WatchStatsTheme.muted)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    
                    HStack(spacing: 8) {
                        if let w = m.didWin {
                            Text(w ? "W" : "L")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(w ? WatchStatsTheme.lime : WatchStatsTheme.loss)
                                .frame(width: 26, height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill((w ? WatchStatsTheme.lime : WatchStatsTheme.loss).opacity(0.15))
                                )
                        }
                        Text("\(m.yourScoreText)–\(m.opponentScoreText)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                        Text("vs \(m.opponentLabel)")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(WatchStatsTheme.muted)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(m.totalShots) shots")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(WatchStatsTheme.muted)
                    }
                    
                    HStack(spacing: 10) {
                        if let serve = m.serveHoldPercent {
                            HStack(spacing: 3) {
                                Text("Hold \(serve)%")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(WatchStatsTheme.lime.opacity(0.9))
                                if m.isPersonalBestHold { pbCrown }
                            }
                        }
                        HStack(spacing: 3) {
                            Text("Rally \(m.maxRallyLength)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(WatchStatsTheme.muted)
                            if m.isPersonalBestRally { pbCrown }
                        }
                        Text("Zone 4–5 \(Int(m.hardZonePercent * 100))%")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(WatchStatsTheme.muted)
                        if !m.scoreLinked {
                            Text("Score not linked")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(WatchStatsTheme.muted.opacity(0.8))
                        }
                    }
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                MatchDetailExpanded(model: m)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isExpanded ? WatchStatsTheme.card : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(WatchStatsTheme.stroke, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(recentA11y(m))
        .accessibilityHint(isExpanded ? "Collapse details" : "Expand shot details")
    }
    
    private var pbCrown: some View {
        Image(systemName: "crown.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(DS.Palette.gold)
            .accessibilityLabel("Personal best")
    }
    
    private func recentA11y(_ m: RecentMatchCardModel) -> String {
        let result = m.didWin.map { $0 ? "Win" : "Loss" } ?? "Match"
        let score = m.scoreLinked ? "\(m.yourScoreText) to \(m.opponentScoreText). " : "Score not linked. "
        let hold = m.serveHoldPercent.map { "Serve hold \($0) percent. " } ?? ""
        return "\(m.dateText). \(result) versus \(m.opponentLabel). \(score)\(m.totalShots) shots. \(hold)Zone 4 to 5, \(Int(m.hardZonePercent * 100)) percent."
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(WatchStatsTheme.card)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(WatchStatsTheme.stroke, lineWidth: 1)
            )
    }
    
    // MARK: Empty / permission / loading
    
    private var skeleton: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 88)
            }
        }
        .accessibilityLabel("Loading watch stats")
    }
    
    private var permissionCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 40))
                .foregroundStyle(WatchStatsTheme.muted)
            Text("Enable Watch tracking")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Workout data is read only when you play — heart-rate zones, calories and beta shot counts. Nothing is shared.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(WatchStatsTheme.muted)
                .multilineTextAlignment(.center)
            
            Button {
                Haptics.medium()
                Task {
                    await viewModel.load()
                    if !viewModel.hasPermission,
                       let url = URL(string: UIApplication.openSettingsURLString) {
                        await UIApplication.shared.open(url)
                    }
                }
            } label: {
                Text("Enable Access")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(WatchStatsTheme.darkBg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(WatchStatsTheme.lime))
            }
            .accessibilityLabel("Enable Health access")
        }
        .padding(24)
        .background(cardBackground)
    }
    
    private var emptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "applewatch.slash")
                .font(.system(size: 36))
                .foregroundStyle(WatchStatsTheme.muted)
            Text("No Watch data yet")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Play a session with your Apple Watch to see performance here.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(WatchStatsTheme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Expanded Detail Views (Must be outside WatchStatsDetailView)

struct MatchDetailExpanded: View {
    let model: RecentMatchCardModel
    
    var body: some View {
        VStack(spacing: 14) {
            Divider().overlay(WatchStatsTheme.stroke)
                .padding(.horizontal, 16)
            
            HStack(spacing: 12) {
                ShotStatRing(label: "FH", percent: model.forehandPercent, color: Color.purple.opacity(0.9))
                ShotStatRing(label: "BH", percent: model.backhandPercent, color: Color.cyan.opacity(0.85))
                ShotStatRing(label: "VO", percent: model.volleyPercent, color: WatchStatsTheme.lime)
                if let serve = model.serveHoldPercent {
                    ShotStatRing(
                        label: "HOLD",
                        percent: Double(serve) / 100.0,
                        color: WatchStatsTheme.lime,
                        isPB: model.isPersonalBestHold
                    )
                }
            }
            .padding(.horizontal, 12)
            
            HStack {
                Text("Peak rally")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(WatchStatsTheme.muted)
                if model.isPersonalBestRally {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Palette.gold)
                }
                Spacer()
                Text("\(model.maxRallyLength) shots")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Zone 4–5")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(WatchStatsTheme.muted)
                    Spacer()
                    Text("\(Int(model.hardZonePercent * 100))%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.08))
                        Capsule()
                            .fill(WatchStatsTheme.lime.opacity(0.85))
                            .frame(width: geo.size.width * CGFloat(model.hardZonePercent))
                    }
                }
                .frame(height: 6)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }
}

struct ShotStatRing: View {
    let label: String
    let percent: Double
    let color: Color
    var isPB: Bool = false
    
    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().stroke(.white.opacity(0.1), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, percent)))
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(percent * 100))")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .frame(width: 48, height: 48)
            HStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WatchStatsTheme.muted)
                if isPB {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(DS.Palette.gold)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    WatchStatsDetailView()
}
