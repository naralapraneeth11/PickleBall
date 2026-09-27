//
//  Username.swift
//  CourtKit
//
//  Usernames are how friends find each other. The rules here match the
//  database check exactly, so the app can explain a problem before the
//  server rejects it: 3–20 characters, lowercase letters, digits, "_" and
//  ".", not starting or ending with punctuation.
//

import Foundation

public enum Username {
    public static let minLength = 3
    public static let maxLength = 20

    public enum Problem: Error, Hashable, Sendable {
        case tooShort
        case tooLong
        case invalidCharacter(Character)
        case edgePunctuation
        case reserved

        public var message: String {
            switch self {
            case .tooShort: return "At least \(Username.minLength) characters."
            case .tooLong: return "At most \(Username.maxLength) characters."
            case .invalidCharacter(let c): return "“\(c)” can’t be used. Letters, numbers, _ and . only."
            case .edgePunctuation: return "Can’t start or end with _ or ."
            case .reserved: return "That username is taken."
            }
        }
    }

    /// Names that would confuse people if a player held them.
    static let reserved: Set<String> = [
        "admin", "administrator", "support", "help", "official", "moderator", "mod", "staff",
        "system", "root", "null", "undefined", "me", "settings", "pickleball", "padel", "team"
    ]

    private static let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_.")

    /// What the user meant: trimmed, lowercased, without a leading "@".
    public static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while text.hasPrefix("@") { text.removeFirst() }
        return text
    }

    /// The first problem with a (normalized) username, or nil if it's valid.
    public static func problem(with name: String) -> Problem? {
        if let bad = name.first(where: { !allowed.contains($0) }) { return .invalidCharacter(bad) }
        if name.count < minLength { return .tooShort }
        if name.count > maxLength { return .tooLong }
        if let first = name.first, let last = name.last, "_.".contains(first) || "_.".contains(last) {
            return .edgePunctuation
        }
        if reserved.contains(name) { return .reserved }
        return nil
    }

    public static func isValid(_ name: String) -> Bool { problem(with: name) == nil }

    /// A starting suggestion from a display name: "Priya K." → "priya.k".
    public static func suggestion(from displayName: String) -> String {
        let folded = displayName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var result = ""
        var lastWasDot = false
        for character in folded {
            if character.isLetter || character.isNumber, allowed.contains(character) {
                result.append(character)
                lastWasDot = false
            } else if !result.isEmpty, !lastWasDot {
                result.append(".")
                lastWasDot = true
            }
        }
        while let last = result.last, "_.".contains(last) { result.removeLast() }
        result = String(result.prefix(maxLength))
        while let last = result.last, "_.".contains(last) { result.removeLast() }
        if result.count < minLength { result += String(repeating: "0", count: minLength - result.count) }
        return reserved.contains(result) ? result + "1" : result
    }
}
