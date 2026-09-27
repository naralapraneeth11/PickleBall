//
//  ContentFilter.swift
//  CourtKit
//
//  The "filter" part of report / block / filter (App Store Guideline 1.2).
//  Runs on every chat message, Serve, Return, squad name and display name
//  before it is sent. Profanity is masked; slurs are refused outright.
//  Obfuscations like "sh1t" or "f u c k" are caught by normalizing first.
//

import Foundation

public struct ContentFilter: Sendable {
    public enum Verdict: Hashable, Sendable {
        case clean
        /// Allowed with the listed words masked: "what the f***".
        case masked(String)
        /// Not allowed at all.
        case blocked
    }

    public let masked: Set<String>
    public let blocked: Set<String>

    public init(masked: Set<String>, blocked: Set<String>) {
        self.masked = masked
        self.blocked = blocked
    }

    public static let standard = ContentFilter(
        masked: [
            "fuck", "fucking", "fucker", "fucked", "motherfucker", "shit", "shitty", "bullshit",
            "bitch", "bitches", "asshole", "bastard", "dick", "dickhead", "cock", "pussy",
            "cunt", "twat", "wanker", "whore", "slut", "douche", "piss", "prick"
        ],
        blocked: [
            "nigger", "nigga", "faggot", "fag", "retard", "retarded", "tranny", "spic", "chink",
            "kike", "wetback", "gook", "dyke", "coon"
        ]
    )

    public func check(_ text: String) -> Verdict {
        let tokens = Self.tokens(in: text)
        // Spaced-out spellings ("f u c k") count when the letters join into
        // a listed word.
        let runs = Self.singleLetterRuns(tokens)
        if tokens.contains(where: { !$0.forms.isDisjoint(with: blocked) })
            || runs.contains(where: { blocked.contains($0.word) }) {
            return .blocked
        }

        var ranges = tokens.filter { !$0.forms.isDisjoint(with: masked) }.map(\.range)
        for run in runs where masked.contains(run.word) {
            ranges += run.tokens.map(\.range)
        }
        guard !ranges.isEmpty else { return .clean }

        var output = text
        for range in ranges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            let word = output[range]
            let keep = word.count > 1 ? String(word.prefix(1)) : ""
            output.replaceSubrange(range, with: keep + String(repeating: "*", count: max(word.count - keep.count, 1)))
        }
        return .masked(output)
    }

    public func allows(_ text: String) -> Bool { check(text) != .blocked }

    /// The text to send: masked if needed, nil if it must not be sent.
    public func cleaned(_ text: String) -> String? {
        switch check(text) {
        case .clean: return text
        case .masked(let masked): return masked
        case .blocked: return nil
        }
    }

    // MARK: - Normalizing

    struct Token {
        let range: Range<String.Index>
        /// Lowercased, look-alikes undone, letters only.
        let normalized: String
        /// `normalized` plus its de-stretched spellings: runs of three or
        /// more of a letter squashed to one and to two ("fuuuck" → "fuck",
        /// "cooool" → "col"/"cool"). Doubles are left alone so "coon" and
        /// "con" stay different words.
        let forms: Set<String>
    }

    private static let substitutions: [Character: Character] = [
        "0": "o", "1": "i", "!": "i", "3": "e", "4": "a", "@": "a", "5": "s", "$": "s", "7": "t", "+": "t"
    ]

    static func tokens(in text: String) -> [Token] {
        var result: [Token] = []
        var start: String.Index?
        func close(at end: String.Index) {
            guard let s = start else { return }
            let normalized = normalize(text[s..<end])
            if !normalized.isEmpty {
                let forms: Set<String> = [normalized, squash(normalized, keeping: 1), squash(normalized, keeping: 2)]
                result.append(Token(range: s..<end, normalized: normalized, forms: forms))
            }
            start = nil
        }
        var index = text.startIndex
        while index < text.endIndex {
            let c = text[index]
            let isWordish = c.isLetter || c.isNumber || substitutions[c] != nil || c == "*"
            if isWordish {
                if start == nil { start = index }
            } else {
                close(at: index)
            }
            index = text.index(after: index)
        }
        close(at: text.endIndex)
        return result
    }

    /// Lowercase, fold diacritics, undo look-alike substitutions, drop
    /// anything that isn't a letter.
    static func normalize(_ word: Substring) -> String {
        let folded = String(word).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        return String(folded.compactMap { raw -> Character? in
            let c = substitutions[raw] ?? raw
            return c.isLetter ? c : nil
        })
    }

    /// Shortens runs of three or more of the same letter to `keeping`.
    static func squash(_ word: String, keeping: Int) -> String {
        var output = ""
        var run: [Character] = []
        func flush() {
            output += run.count >= 3 ? String(run.prefix(keeping)) : String(run)
            run = []
        }
        for c in word {
            if let last = run.last, last != c { flush() }
            run.append(c)
        }
        flush()
        return output
    }

    /// Runs of three or more single-letter tokens, joined: "f u c k" → "fuck".
    static func singleLetterRuns(_ tokens: [Token]) -> [(word: String, tokens: [Token])] {
        var runs: [(word: String, tokens: [Token])] = []
        var current: [Token] = []
        func flush() {
            if current.count > 2 { runs.append((current.map(\.normalized).joined(), current)) }
            current = []
        }
        for token in tokens {
            if token.normalized.count == 1 { current.append(token) } else { flush() }
        }
        flush()
        return runs
    }
}
