//
//  AppDatabase.swift
//  PickleBall
//
//  Owns the SwiftData container. Everything is local and offline-first:
//  scoring must work at a park court with no signal.
//

import Foundation
import SwiftData

@MainActor
enum AppDatabase {
    static let schema = Schema([
        PlayerRecord.self,
        MatchRecord.self,
        RallyRecord.self,
        WorkoutSessionRecord.self
    ])

    /// True when the on-disk store couldn't be opened and matches are only
    /// kept in memory. The app tells the player instead of pretending.
    nonisolated(unsafe) private(set) static var isTemporary = false

    /// The app's container. Falls back to an in-memory store (and says so)
    /// rather than crashing if the on-disk store cannot be opened.
    static let container: ModelContainer = {
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isPreview)
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            print("AppDatabase: persistent store failed (\(error)); using in-memory store")
            isTemporary = !isPreview
            do {
                return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
            } catch {
                fatalError("AppDatabase: cannot create any model container: \(error)")
            }
        }
    }()

    static var context: ModelContext { container.mainContext }

    static func save() {
        do {
            try context.save()
        } catch {
            print("AppDatabase: save failed: \(error)")
            Social.shared.notice = String(localized: "Couldn’t save on this iPhone. Free up some storage so your matches aren’t lost.")
        }
    }

    /// Said once at launch when matches can't be kept.
    static var storageWarning: String? {
        isTemporary ? String(localized: "Matches can’t be saved on this iPhone right now and will be lost when the app closes. Free up some storage, then restart PickleBall.") : nil
    }
}
