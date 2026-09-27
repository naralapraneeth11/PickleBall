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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .environment(workout)
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
