//
//  LaunchSettings.swift
//  PickleBall
//
//  Nudges and privacy settings.
//

import SwiftUI
import UserNotifications
import CourtKit
import CourtNet

/// Pages on the public web site (privacy policy, terms, support).
enum SitePages {
    static func url(_ path: String) -> URL? {
        Social.shared.backend?.config.site?.appendingPathComponent(path)
    }
}

struct NudgeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var enabled = Nudger.isEnabled
    @State private var muted = Nudger.muted
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section {
                Toggle("Nudges", isOn: $enabled)
                    .onChange(of: enabled) { _, on in
                        Nudger.isEnabled = on
                        if on, status == .notDetermined {
                            Task {
                                _ = await Nudger.shared.requestPermission()
                                await refreshStatus()
                            }
                        }
                    }
            } footer: {
                Text("One short line at most once a day, never at night. The details are only in the app.")
            }

            if enabled {
                Section("Nudge me when") {
                    ForEach(Nudge.Kind.allCases, id: \.self) { kind in
                        Toggle(Nudger.title(for: kind), isOn: Binding(
                            get: { !muted.contains(kind) },
                            set: { on in
                                if on { muted.remove(kind) } else { muted.insert(kind) }
                                Nudger.muted = muted
                            }
                        ))
                    }
                }
            }

            if status == .denied {
                Section {
                    Button("Allow notifications in Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } footer: {
                    Text("Notifications are off for PickleBall in iOS Settings.")
                }
            }
        }
        .navigationTitle("Nudges")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { await refreshStatus() }
    }

    private func refreshStatus() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

struct PrivacySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var telemetry = Telemetry.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Share anonymous usage and crash reports", isOn: $telemetry)
                    .onChange(of: telemetry) { _, on in Telemetry.isEnabled = on }
            } footer: {
                Text("A random install ID, your region setting, language and app version once a day, and crash reports from iOS. Never linked to your account, never used for ads, never sold.")
            }

            Section("What friends see") {
                Label("Your matches, belts and level: friends and squadmates only.", systemImage: "person.2")
                Label("Serves: friends only. Nothing is ever public.", systemImage: "eye.slash")
                Label("Live pages you share show first names and the score only.", systemImage: "link")
            }
            .font(.subheadline)

            if let url = SitePages.url("privacy/") {
                Section {
                    Link("Privacy policy", destination: url)
                }
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
