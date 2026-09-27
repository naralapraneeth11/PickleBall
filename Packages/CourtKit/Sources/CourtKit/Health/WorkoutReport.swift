//
//  WorkoutReport.swift
//  CourtKit
//
//  What the Watch measured during a match, sent to the phone when the
//  workout ends. Shot counts come from wrist-motion thresholds and are
//  labelled beta everywhere they appear.
//

import Foundation

public struct WorkoutReport: Codable, Hashable, Sendable {
    public var duration: TimeInterval
    public var averageHeartRate: Double
    public var peakHeartRate: Double
    public var calories: Double
    /// Seconds per heart-rate zone, indexed by `HeartRateZones.Zone.rawValue`.
    public var secondsInZone: [Double]
    /// Max heart rate the zones were computed from.
    public var maxHeartRate: Double?
    public var shots: ShotCounts?

    public struct ShotCounts: Codable, Hashable, Sendable {
        public var forehand: Int
        public var backhand: Int
        public var volley: Int
        public var serve: Int
        public var longestRally: Int

        public init(forehand: Int, backhand: Int, volley: Int, serve: Int, longestRally: Int) {
            self.forehand = forehand
            self.backhand = backhand
            self.volley = volley
            self.serve = serve
            self.longestRally = longestRally
        }

        public var total: Int { forehand + backhand + volley + serve }
    }

    public init(
        duration: TimeInterval,
        averageHeartRate: Double,
        peakHeartRate: Double,
        calories: Double,
        secondsInZone: [Double],
        maxHeartRate: Double?,
        shots: ShotCounts?
    ) {
        self.duration = duration
        self.averageHeartRate = averageHeartRate
        self.peakHeartRate = peakHeartRate
        self.calories = calories
        self.secondsInZone = secondsInZone
        self.maxHeartRate = maxHeartRate
        self.shots = shots
    }

    public var totalZoneSeconds: Double { secondsInZone.reduce(0, +) }

    /// Share of time at threshold or above (0…1).
    public var hardShare: Double {
        let total = totalZoneSeconds
        guard total > 0, secondsInZone.count > HeartRateZones.Zone.maximum.rawValue else { return 0 }
        return (secondsInZone[HeartRateZones.Zone.threshold.rawValue] + secondsInZone[HeartRateZones.Zone.maximum.rawValue]) / total
    }

    /// The highest zone holding at least 10% of the time.
    public var dominantZone: HeartRateZones.Zone? {
        let total = totalZoneSeconds
        guard total > 0 else { return nil }
        for zone in HeartRateZones.Zone.allCases.reversed()
        where zone.rawValue < secondsInZone.count && secondsInZone[zone.rawValue] / total >= 0.10 {
            return zone
        }
        return nil
    }
}

/// Settings the phone pushes to the Watch so it follows the phone's mode.
public struct WatchPreferences: Codable, Hashable, Sendable {
    public var sport: Sport
    /// The device owner, so Watch-started matches are recorded by ID.
    public var me: PlayerRef?
    /// Recent opponents and partners for the Watch's quick pickers.
    public var recentPlayers: [PlayerRef]
    /// For heart-rate zones when Health has no date of birth.
    public var age: Int?

    public init(sport: Sport, me: PlayerRef?, recentPlayers: [PlayerRef] = [], age: Int? = nil) {
        self.sport = sport
        self.me = me
        self.recentPlayers = recentPlayers
        self.age = age
    }
}
