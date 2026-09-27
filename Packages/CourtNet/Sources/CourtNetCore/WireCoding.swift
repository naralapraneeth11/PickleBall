//
//  WireCoding.swift
//  CourtNetCore
//
//  One JSON dialect for everything that crosses the network or sits in the
//  outbox. Keys are spelled out per type (snake_case, matching the
//  database). Dates go out as ISO 8601 with milliseconds and come back in
//  any of the shapes Postgres produces.
//

import Foundation

public enum WireCoding {
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(format(date))
        }
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = parse(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date \(text)")
            }
            return date
        }
        return decoder
    }

    public static func format(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().dateSeparator(.dash)
            .time(includingFractionalSeconds: true).timeSeparator(.colon).timeZone(separator: .omitted))
    }

    /// Parses "2026-09-27T06:15:20Z", "…20.015Z", "…20.015123+00:00" and
    /// Postgres' space-separated "2026-09-27 06:15:20.015+00".
    public static func parse(_ raw: String) -> Date? {
        var text = raw.replacingOccurrences(of: " ", with: "T")
        // Normalise the zone: "+00" → "+00:00", "Z" stays.
        if let range = text.range(of: #"[+-]\d{2}$"#, options: .regularExpression) {
            text.replaceSubrange(range, with: text[range] + ":00")
        }
        // Trim sub-millisecond digits: ".015123" → ".015".
        if let range = text.range(of: #"\.\d{4,}"#, options: .regularExpression) {
            text.replaceSubrange(range, with: text[range].prefix(4))
        }
        if let date = try? Date(text, strategy: .iso8601.year().month().day().dateSeparator(.dash)
            .time(includingFractionalSeconds: true).timeSeparator(.colon).timeZone(separator: .colon)) {
            return date
        }
        if let date = try? Date(text, strategy: .iso8601.year().month().day().dateSeparator(.dash)
            .time(includingFractionalSeconds: false).timeSeparator(.colon).timeZone(separator: .colon)) {
            return date
        }
        return try? Date(text, strategy: .iso8601)
    }
}
