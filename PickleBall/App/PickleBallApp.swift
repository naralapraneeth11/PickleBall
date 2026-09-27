//
//  PickleBallApp.swift
//  PickleBall
//
//  Created by sai praneeth reddy narala on 1/12/26.
//

import SwiftUI
import UIKit
import SwiftData
import CourtKit

@main
struct PickleBallApp: App {
    @State private var sportMode = SportMode()

    init() {
        // Order matters: the local player must exist before any match is
        // recorded, and the match centre must be listening before
        // WatchConnectivity delivers anything queued while the phone slept.
        _ = PlayerDirectory.shared
        MatchStore.shared.reload()
        TournamentStore.shared.reload()
        WorkoutStore.shared.reload()
        MatchCenter.shared.boot()

        // Kill the ~100ms tap-vs-drag delay on every ScrollView in the app.
        UIScrollView.appearance().delaysContentTouches = false
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(sportMode)
                .onAppear {
                    MatchCenter.shared.publishPreferences(sport: sportMode.sport)
                }
        }
        .modelContainer(AppDatabase.container)
    }
}
