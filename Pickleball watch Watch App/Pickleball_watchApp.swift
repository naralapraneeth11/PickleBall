//
//  Pickleball_watchApp.swift
//  Pickleball watch Watch App
//
//  Created by sai praneeth reddy narala on 1/19/26.
//

import SwiftUI

@main
struct Pickleball_watch_Watch_AppApp: App {
    /// Hoisted from ContentView to App scope so the workout session and
    /// the WCSession delegate live for the entire app lifetime, not just
    /// while ContentView is on screen. Previously these were @StateObjects
    /// inside ContentView, which meant a SwiftUI tear-down could destroy
    /// an active workout session mid-match.
    @StateObject private var sync = WatchMatchSync()
    @StateObject private var motionManager = MotionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sync)
                .environmentObject(motionManager)
        }
    }
}
