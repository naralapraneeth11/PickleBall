//
//  Sport.swift
//  CourtKit
//

import Foundation

/// The sport mode. Switching sport swaps the rules engine and the game-layer
/// theme; identity, history and everything social stays shared.
public enum Sport: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case pickleball
    case padel

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pickleball: return L("Pickleball")
        case .padel: return L("Padel")
        }
    }

    /// The sport a long-press switches to.
    public var toggled: Sport { self == .pickleball ? .padel : .pickleball }

    /// SF Symbol used for badges and the Live Activity.
    public var symbolName: String {
        switch self {
        case .pickleball: return "figure.pickleball"
        case .padel: return "figure.racquetball"
        }
    }
}
