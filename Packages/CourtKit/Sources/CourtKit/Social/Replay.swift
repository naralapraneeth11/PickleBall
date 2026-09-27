//
//  Replay.swift
//  CourtKit
//
//  A Replay is the auto-made story of a match: who played, how each game
//  went, the moments that mattered, what happened to the belt, and any
//  photos from the changeovers. It lives for 24 hours unless its author
//  saves it to their trophy case.
//
//  The story is data, not video: every phone renders it natively, and it
//  is small enough to send through chat.
//

import Foundation

public struct ReplayStory: Hashable, Codable, Sendable {
    public enum Beat: Hashable, Codable, Sendable {
        case opening(sport: Sport, date: Date, court: String?, isTitleMatch: Bool)
        case lineup(teamA: [String], teamB: [String])
        case unit(index: Int, score: TeamPair<Int>, tiebreak: TeamPair<Int>?, isSuperTiebreak: Bool)
        case moment(String)
        case photo(index: Int)
        case belt(String)
        case workout(minutes: Int, averageHeartRate: Int?, calories: Int?)
        case final(winners: String, scoreLine: String)
    }

    public var matchID: UUID
    public var headline: String
    public var beats: [Beat]
    /// 0…1, from the drama detector. Replays above ~0.5 are highlighted.
    public var intensity: Double

    public init(matchID: UUID, headline: String, beats: [Beat], intensity: Double) {
        self.matchID = matchID
        self.headline = headline
        self.beats = beats
        self.intensity = intensity
    }

    /// Builds the story. Workout details only exist for Watch-scored
    /// matches; photos are counted, not embedded.
    public static func make(
        result: MatchResult,
        drama: DramaReport,
        beltLines: [String] = [],
        court: CourtTag? = nil,
        workout: WorkoutReport? = nil,
        photoCount: Int = 0
    ) -> ReplayStory {
        var beats: [Beat] = [
            .opening(sport: result.sport, date: result.date, court: court?.name, isTitleMatch: !beltLines.isEmpty),
            .lineup(teamA: result.lineup.teams.a.map(\.displayName), teamB: result.lineup.teams.b.map(\.displayName))
        ]

        // Photos go between games, in order, so the story reads like the match.
        var photosLeft = photoCount
        for (index, unit) in result.units.enumerated() {
            beats.append(.unit(index: index, score: unit.score, tiebreak: unit.tiebreak, isSuperTiebreak: unit.isSuperTiebreak))
            if photosLeft > 0 {
                beats.append(.photo(index: photoCount - photosLeft))
                photosLeft -= 1
            }
        }
        while photosLeft > 0 {
            beats.append(.photo(index: photoCount - photosLeft))
            photosLeft -= 1
        }

        beats += drama.lines(result.lineup).prefix(3).map(Beat.moment)
        beats += beltLines.map(Beat.belt)

        if let workout {
            beats.append(.workout(
                minutes: Int((workout.duration / 60).rounded()),
                averageHeartRate: workout.averageHeartRate > 0 ? Int(workout.averageHeartRate.rounded()) : nil,
                calories: workout.calories > 0 ? Int(workout.calories.rounded()) : nil
            ))
        }

        let winners = result.winner.map { result.lineup.name(of: $0, separator: " & ") } ?? "Nobody"
        beats.append(.final(winners: winners, scoreLine: result.scoreLine))

        return ReplayStory(matchID: result.id, headline: drama.headline(result.lineup), beats: beats, intensity: drama.intensity)
    }
}

public enum ReplayLifetime {
    public static let duration: TimeInterval = 24 * 60 * 60

    public static func expiresAt(createdAt: Date) -> Date { createdAt.addingTimeInterval(duration) }

    public static func isVisible(createdAt: Date, saved: Bool, now: Date = Date()) -> Bool {
        saved || now < expiresAt(createdAt: createdAt)
    }

    /// Fraction of the 24 hours left, for the ring around a Replay bubble.
    public static func remaining(createdAt: Date, now: Date = Date()) -> Double {
        let left = expiresAt(createdAt: createdAt).timeIntervalSince(now)
        return max(0, min(1, left / duration))
    }
}

/// When to ask for a changeover photo during a Watch-scored match: at a
/// change of ends or between games, never twice within a few minutes and
/// never more than a handful of times, so nobody is nagged mid-match.
public struct PhotoPrompter: Hashable, Sendable {
    public static let maxPrompts = 3
    public static let minimumGap: TimeInterval = 8 * 60

    public private(set) var prompts: [Date] = []

    public init() {}

    public func shouldPrompt(after events: [ScoreEvent], at now: Date) -> Bool {
        guard prompts.count < Self.maxPrompts else { return false }
        if events.contains(where: { if case .matchWon = $0 { return true } else { return false } }) { return false }
        let isChangeover = events.contains { event in
            switch event {
            case .changeEnds, .gameWon, .setWon: return true
            default: return false
            }
        }
        guard isChangeover else { return false }
        if let last = prompts.last, now.timeIntervalSince(last) < Self.minimumGap { return false }
        return true
    }

    public mutating func didPrompt(at date: Date) {
        prompts.append(date)
    }
}
