//
//  PickleBallApp.swift
//  PickleBall
//
//  Created by sai praneeth reddy narala on 1/12/26.
//

import SwiftUI
import UIKit
import CloudKit

@main
struct PickleBallApp: App {

    // CloudKit share-accept and silent-push hooks only exist at the
    // app-delegate level, so we bridge one in. Everything else stays
    // pure SwiftUI.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Activate WCSession as early as possible so we don't miss any
        // pending transferUserInfo deliveries from the watch (e.g. a
        // gameComplete payload sent while the phone was backgrounded).
        _ = WatchConnectivityManager.shared

        // Kill the ~100ms tap-vs-drag delay on every ScrollView in the app.
        UIScrollView.appearance().delaysContentTouches = false
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

// MARK: - App Delegate (CloudKit hooks only)

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Needed so silent CloudKit pushes can wake the app to fetch updates.
        application.registerForRemoteNotifications()
        return true
    }

    /// Spectator tapped a shared tournament link. iOS hands us the metadata;
    /// we pass it to the sync manager, which accepts + loads + subscribes.
   // func application(_ application: UIApplication,
     //                userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
       // Task { @MainActor in
         //   await CloudTournamentSync.shared.acceptShare(metadata)
        }
    //}

    /// A CloudKit change push arrived (organizer edited a score, etc).
    /// Re-fetch the latest record so the UI updates.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {

        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completionHandler(.noData)
            return
        }

     //   Task { @MainActor in
           // await CloudTournamentSync.shared.handleRemoteNotification()
          //  completionHandler(.newData)
     //   }
    }
//}
