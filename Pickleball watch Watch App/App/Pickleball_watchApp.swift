//
//  Pickleball_watchApp.swift
//  Pickleball watch Watch App
//
//  Created by sai praneeth reddy narala on 1/19/26.
//

import SwiftUI
import WatchKit
import HealthKit
import CourtKit

@main
struct Pickleball_watch_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate

    /// App-scoped so the WCSession delegate and the workout outlive any view.
    @State private var session = WatchMatchSession.shared
    @State private var workout = WorkoutManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .environment(workout)
        }
        .onChange(of: scenePhase) { _, phase in
            // Back in front: retry anything the phone hasn't confirmed.
            if phase == .active { session.flushJournal() }
        }
        // Data from the phone while in the background: finish saving it
        // before the system suspends us.
        .backgroundTask(.watchConnectivity) {
            await WatchMatchSession.shared.finishBackgroundWork()
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    /// The phone launched us with `startWatchApp(with:)` for a match it is
    /// starting; the match itself arrives over WatchConnectivity.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        _ = WatchMatchSession.shared
    }
}
