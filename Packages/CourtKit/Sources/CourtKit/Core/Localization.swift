//
//  Localization.swift
//  CourtKit
//
//  Display strings that live in CourtKit (format names, belt tiers) are
//  translated from Resources/<lang>.lproj/Localizable.strings. Keys are the
//  English text, so a missing translation shows English.
//

import Foundation

func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, value: key, comment: "")
}

enum CourtKitStrings {
    static var bundle: Bundle { .module }
}
