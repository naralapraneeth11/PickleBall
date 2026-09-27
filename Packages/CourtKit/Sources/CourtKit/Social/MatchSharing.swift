//
//  MatchSharing.swift
//  CourtKit
//
//  Vocabulary shared by the app and the server for matches that leave the
//  device: where the score came from, whether the other side agreed, and
//  where it was played.
//

import Foundation

/// How a result was recorded. Watch-only extras (heart rate, Replays with
/// rally detail, crowd taps) exist only for `.watch`.
public enum MatchSource: String, Codable, Hashable, Sendable {
    case watch
    case phone
    /// Typed in after the match.
    case entered
}

/// Every result is confirmed by the other side before it counts.
public enum ConfirmationStatus: String, Codable, Hashable, Sendable {
    case pending
    case confirmed
    case disputed

    public var title: String {
        switch self {
        case .pending: return "Waiting for confirmation"
        case .confirmed: return "Confirmed"
        case .disputed: return "Disputed"
        }
    }
}

/// An optional court tag, picked from Apple Maps search.
public struct CourtTag: Codable, Hashable, Sendable {
    public var name: String
    public var latitude: Double?
    public var longitude: Double?
    /// MapKit's `MKMapItem.Identifier` raw value, when there is one.
    public var mapItemID: String?

    public init(name: String, latitude: Double? = nil, longitude: Double? = nil, mapItemID: String? = nil) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.mapItemID = mapItemID
    }

    enum CodingKeys: String, CodingKey {
        case name
        case latitude = "lat"
        case longitude = "lon"
        case mapItemID
    }
}
