//
//  Lossy.swift
//  CourtNetCore
//
//  Decodes one row of a list, or nothing if the row is malformed, so one
//  bad record from the server can't stop every other row from loading.
//

import Foundation
#if canImport(os)
import os
#endif

public struct Lossy<Value: Decodable>: Decodable {
    public let value: Value?

    public init(from decoder: Decoder) throws {
        do {
            value = try decoder.singleValueContainer().decode(Value.self)
        } catch {
            value = nil
            #if canImport(os)
            Logger(subsystem: "CourtNet", category: "decode")
                .error("Skipped an unreadable \(String(describing: Value.self), privacy: .public): \(String(describing: error), privacy: .public)")
            #endif
        }
    }
}

extension Lossy: Sendable where Value: Sendable {}
