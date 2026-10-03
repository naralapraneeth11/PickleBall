//
//  AccountScope.swift
//  PickleBall
//
//  Which account's history this phone is showing. Matches and workouts
//  are stamped with the account that was signed in when they were made
//  (or synced), so on a shared phone A's history never shows up as B's,
//  and B never uploads it. Signed out, the phone shows its own anonymous
//  history.
//

import Foundation

nonisolated enum AccountScope {
    /// The signed-in account, or nil when signed out or built without a
    /// server. Written on the main actor only (sign-in and sign-out); read
    /// from model initialisers, which SwiftData may run anywhere.
    nonisolated(unsafe) static var current: UUID?

    static func owns(_ owner: UUID?) -> Bool { owner == current }
}
