//
//  HeartRateZones.swift
//  CourtKit
//
//  Personal heart-rate zones instead of one fixed "fatigue at 160 bpm"
//  number, which is wrong for most people. Max heart rate comes from Health
//  when available, otherwise it is estimated from age with the Tanaka
//  formula (208 − 0.7 × age). With a resting heart rate the zones use heart
//  rate reserve (Karvonen); without one they use a percentage of max.
//

import Foundation

public struct HeartRateZones: Codable, Hashable, Sendable {
    public enum Zone: Int, Codable, CaseIterable, Hashable, Sendable, Comparable {
        case rest = 0
        case warmUp = 1
        case easy = 2
        case aerobic = 3
        case threshold = 4
        case maximum = 5

        public static func < (lhs: Zone, rhs: Zone) -> Bool { lhs.rawValue < rhs.rawValue }

        public var title: String {
            switch self {
            case .rest: return "Rest"
            case .warmUp: return "Warm-up"
            case .easy: return "Easy"
            case .aerobic: return "Aerobic"
            case .threshold: return "Threshold"
            case .maximum: return "Max"
            }
        }

        /// "Z3". Rest is shown as "Z0".
        public var shortTitle: String { "Z\(rawValue)" }

        /// Lower bound as a fraction of max (or of heart-rate reserve).
        var lowerFraction: Double {
            switch self {
            case .rest: return 0
            case .warmUp: return 0.50
            case .easy: return 0.60
            case .aerobic: return 0.70
            case .threshold: return 0.80
            case .maximum: return 0.90
            }
        }
    }

    public let maxHeartRate: Double
    public let restingHeartRate: Double?

    public init(maxHeartRate: Double, restingHeartRate: Double? = nil) {
        self.maxHeartRate = max(100, maxHeartRate)
        if let restingHeartRate, restingHeartRate > 25, restingHeartRate < self.maxHeartRate - 20 {
            self.restingHeartRate = restingHeartRate
        } else {
            self.restingHeartRate = nil
        }
    }

    public init(age: Int, restingHeartRate: Double? = nil) {
        self.init(maxHeartRate: Self.estimatedMaxHeartRate(age: age), restingHeartRate: restingHeartRate)
    }

    /// Tanaka, Monahan & Seals (2001).
    public static func estimatedMaxHeartRate(age: Int) -> Double {
        let clamped = min(max(age, 10), 100)
        return 208 - 0.7 * Double(clamped)
    }

    /// Lowest heart rate that counts as `zone`.
    public func lowerBound(of zone: Zone) -> Double {
        if let rest = restingHeartRate {
            return rest + (maxHeartRate - rest) * zone.lowerFraction
        }
        return maxHeartRate * zone.lowerFraction
    }

    public func zone(for bpm: Double) -> Zone {
        for zone in Zone.allCases.reversed() where bpm >= lowerBound(of: zone) {
            return zone
        }
        return .rest
    }

    /// Display range, e.g. "133–152".
    public func rangeLabel(for zone: Zone) -> String {
        let low = Int(lowerBound(of: zone).rounded())
        guard let next = Zone(rawValue: zone.rawValue + 1) else { return "\(low)+" }
        return "\(low)–\(Int(lowerBound(of: next).rounded()) - 1)"
    }
}

/// Accumulates time-in-zone from a stream of heart-rate samples.
public struct ZoneAccumulator: Codable, Hashable, Sendable {
    public let zones: HeartRateZones
    /// Seconds per zone, indexed by `Zone.rawValue`.
    public private(set) var seconds: [Double]
    public private(set) var peakBPM: Double
    public private(set) var currentZone: HeartRateZones.Zone?
    private var lastSample: (bpm: Double, at: Date)?
    private var weightedSum: Double
    private var weightedTime: Double

    /// A single sample never counts for more than this, so a dropped sensor
    /// doesn't paint a long gap in one zone.
    public static let maxSampleSpan: TimeInterval = 15

    public init(zones: HeartRateZones) {
        self.zones = zones
        self.seconds = Array(repeating: 0, count: HeartRateZones.Zone.allCases.count)
        self.peakBPM = 0
        self.weightedSum = 0
        self.weightedTime = 0
    }

    public mutating func add(bpm: Double, at date: Date) {
        guard bpm > 0 else { return }
        if let last = lastSample {
            let span = min(max(0, date.timeIntervalSince(last.at)), Self.maxSampleSpan)
            seconds[zones.zone(for: last.bpm).rawValue] += span
            weightedSum += last.bpm * span
            weightedTime += span
        }
        lastSample = (bpm, date)
        peakBPM = max(peakBPM, bpm)
        currentZone = zones.zone(for: bpm)
    }

    public var totalSeconds: Double { seconds.reduce(0, +) }

    /// Time-weighted average, or the single sample when only one arrived.
    public var averageBPM: Double {
        if weightedTime > 0 { return weightedSum / weightedTime }
        return lastSample?.bpm ?? 0
    }

    /// Fraction of time per zone (0…1).
    public var distribution: [Double] {
        let total = totalSeconds
        guard total > 0 else { return seconds.map { _ in 0 } }
        return seconds.map { $0 / total }
    }

    /// Time at threshold or above.
    public var hardSeconds: Double {
        seconds[HeartRateZones.Zone.threshold.rawValue] + seconds[HeartRateZones.Zone.maximum.rawValue]
    }

    private enum CodingKeys: String, CodingKey { case zones, seconds, peakBPM, weightedSum, weightedTime }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        zones = try c.decode(HeartRateZones.self, forKey: .zones)
        seconds = try c.decode([Double].self, forKey: .seconds)
        peakBPM = try c.decode(Double.self, forKey: .peakBPM)
        weightedSum = try c.decode(Double.self, forKey: .weightedSum)
        weightedTime = try c.decode(Double.self, forKey: .weightedTime)
        currentZone = nil
        lastSample = nil
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(zones, forKey: .zones)
        try c.encode(seconds, forKey: .seconds)
        try c.encode(peakBPM, forKey: .peakBPM)
        try c.encode(weightedSum, forKey: .weightedSum)
        try c.encode(weightedTime, forKey: .weightedTime)
    }

    public static func == (lhs: ZoneAccumulator, rhs: ZoneAccumulator) -> Bool {
        lhs.zones == rhs.zones && lhs.seconds == rhs.seconds && lhs.peakBPM == rhs.peakBPM
            && lhs.weightedSum == rhs.weightedSum && lhs.weightedTime == rhs.weightedTime
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(zones)
        hasher.combine(seconds)
        hasher.combine(peakBPM)
    }
}
