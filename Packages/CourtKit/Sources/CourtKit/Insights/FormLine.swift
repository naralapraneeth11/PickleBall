//
//  FormLine.swift
//  CourtKit
//
//  The profile's hero line: form over time. Each match contributes the share
//  of points won, smoothed with an exponential moving average so one blowout
//  doesn't swing the line. Honest and explainable — this is not a rating.
//

import Foundation

public struct FormPoint: Hashable, Sendable, Identifiable {
    public let matchID: UUID
    public let date: Date
    /// Smoothed form, 0…100.
    public let value: Double
    /// This match's raw share of points won, 0…100.
    public let pointShare: Double
    public let didWin: Bool
    public let opponents: [PlayerRef]
    public let scoreLine: String

    public var id: UUID { matchID }
}

public struct FormLine: Hashable, Sendable {
    public let points: [FormPoint]

    /// Weight of the newest match in the moving average.
    public static let smoothing = 0.35

    public var current: Double? { points.last?.value }

    /// Change produced by the latest match.
    public var latestChange: Double? {
        guard points.count >= 2 else { return nil }
        return points[points.count - 1].value - points[points.count - 2].value
    }

    /// Change over the whole visible window.
    public var windowChange: Double? {
        guard let first = points.first, let last = points.last, points.count >= 2 else { return nil }
        return last.value - first.value
    }

    public var wins: Int { points.filter(\.didWin).count }
    public var losses: Int { points.count - wins }

    /// Current streak: positive for wins, negative for losses.
    public var streak: Int {
        guard let last = points.last else { return 0 }
        let count = points.reversed().prefix { $0.didWin == last.didWin }.count
        return last.didWin ? count : -count
    }

    /// - Parameters:
    ///   - sport: restrict to one sport, or nil for all.
    ///   - limit: keep only the most recent matches in the line.
    public static func compute(for me: PlayerID, results: [MatchResult], sport: Sport? = nil, limit: Int = 30) -> FormLine {
        let perspectives = results
            .filter { sport == nil || $0.sport == sport }
            .compactMap { $0.perspective(of: me) }
            .filter { $0.isDecided && $0.pointShare != nil }
            .sorted { $0.result.date < $1.result.date }

        var smoothed: Double?
        var line: [FormPoint] = []
        for p in perspectives {
            let share = (p.pointShare ?? 0.5) * 100
            let value = smoothed.map { $0 + smoothing * (share - $0) } ?? share
            smoothed = value
            line.append(FormPoint(
                matchID: p.result.id,
                date: p.result.date,
                value: value,
                pointShare: share,
                didWin: p.didWin,
                opponents: p.opponents,
                scoreLine: p.scoreLine
            ))
        }
        return FormLine(points: Array(line.suffix(limit)))
    }
}
