import SwiftUI
import SwiftData
import CourtKit
import CourtNet

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss

    @State private var showResetConfirm = false
    @State private var resetCompleted = false
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var showBlocked = false
    @State private var showNudges = false
    @State private var showPrivacy = false
    @State private var showAdmin = false
    @AppStorage(AppearanceStyle.storageKey) private var appearance: AppearanceStyle = .standard
    private let social = Social.shared

    let royalBlue    = Court.muted
    let lightGrey    = Court.ground
    let cardWhite    = Court.raised
    let destructiveRed = DS.Palette.loss
    let versionGrey  = Color(red: 0.627, green: 0.627, blue: 0.627)

    // The web site (web/ on Cloudflare Pages) when configured.
    private var termsURL: URL { SitePages.url("terms/") ?? URL(string: "https://accurate-alder-cf4.notion.site/Terms-of-service-3268c115cbf380c5a352e2382b074ffd")! }
    private var privacyURL: URL { SitePages.url("privacy/") ?? URL(string: "https://accurate-alder-cf4.notion.site/Privacy-Policy-3268c115cbf38009a4ecc5ac57003615")! }
    private var feedbackURL: URL { SitePages.url("support/") ?? URL(string: "https://accurate-alder-cf4.notion.site/3268c115cbf38048be19e2a747011d37")! }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "VERSION \(version) (\(build))"
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACCOUNT")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(royalBlue)
                .tracking(0.5)
                .padding(.horizontal, 20)

            VStack(spacing: 8) {
                if let profile = social.profile {
                    settingsRow(title: "@\(profile.username)", systemImage: "person.crop.circle", tint: royalBlue) {}
                        .disabled(true)
                }
                Button {
                    showBlocked = true
                } label: {
                    rowLabel(title: "Blocked", systemImage: "hand.raised", tint: royalBlue, detail: social.blocked.isEmpty ? nil : "\(social.blocked.count)")
                }
                .buttonStyle(.press)
                Button { showNudges = true } label: {
                    rowLabel(title: String(localized: "Nudges"), systemImage: "bell", tint: royalBlue, detail: Nudger.isEnabled ? nil : String(localized: "Off"))
                }
                .buttonStyle(.press)
                Button { showPrivacy = true } label: {
                    rowLabel(title: String(localized: "Privacy"), systemImage: "lock.shield", tint: royalBlue, detail: nil)
                }
                .buttonStyle(.press)
                if social.isAdmin {
                    Button { showAdmin = true } label: {
                        rowLabel(title: String(localized: "Moderation"), systemImage: "shield.lefthalf.filled", tint: royalBlue, detail: nil)
                    }
                    .buttonStyle(.press)
                }
                if social.outboxCount > 0 {
                    settingsRow(title: "\(social.outboxCount) waiting to send", systemImage: "arrow.up.circle", tint: DS.Palette.warning) {
                        Task { await social.drainOutbox() }
                    }
                }
                settingsRow(title: "Sign out", systemImage: "rectangle.portrait.and.arrow.right", tint: royalBlue) {
                    confirmSignOut = true
                }
                settingsRow(title: isDeleting ? "Deleting…" : "Delete account", systemImage: "trash", tint: destructiveRed) {
                    confirmDelete = true
                }
                .disabled(isDeleting)
            }
            .padding(.horizontal, 20)
        }
        .sheet(isPresented: $showBlocked) {
            NavigationStack { BlockedUsersView() }
        }
        .sheet(isPresented: $showNudges) {
            NavigationStack { NudgeSettingsView() }
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationStack { PrivacySettingsView() }
        }
        .fullScreenCover(isPresented: $showAdmin) {
            AdminView()
        }
        .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task {
                    await social.signOut()
                    dismiss()
                }
            }
        } message: {
            Text(social.outboxCount > 0
                 ? "\(social.outboxCount) change\(social.outboxCount == 1 ? " hasn’t" : "s haven’t") been sent yet and will be lost."
                 : "Matches on this phone stay on this phone.")
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                isDeleting = true
                Task {
                    if await social.deleteAccount() { dismiss() }
                    isDeleting = false
                }
            }
        } message: {
            Text("This permanently deletes your profile, friends, chats, Serves, Replays and trophies. Matches stay in your opponents’ history under “Former player”.")
        }
    }

    private func settingsRow(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowLabel(title: title, systemImage: systemImage, tint: tint, detail: nil)
        }
        .buttonStyle(.press)
    }

    private func rowLabel(title: String, systemImage: String, tint: Color, detail: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).foregroundColor(tint).frame(width: 22)
            Text(LocalizedStringKey(title))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(tint == destructiveRed ? destructiveRed : .primary)
            Spacer()
            if let detail {
                Text(detail).foregroundColor(versionGrey)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardWhite))
    }

    // MARK: - Header

    private var courtStripHeader: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(DS.Palette.courtBlue)
                    .frame(width: geo.size.width * 0.375)

                Rectangle()
                    .fill(.white)
                    .frame(width: 3)

                Rectangle()
                    .fill(DS.Palette.navy)
                    .frame(width: geo.size.width * 0.249)

                Rectangle()
                    .fill(.white)
                    .frame(width: 3)

                Rectangle()
                    .fill(DS.Palette.courtBlueMid)
                    .frame(width: geo.size.width * 0.375)
            }
            .frame(height: 150)
            .ignoresSafeArea(edges: .top)
            .overlay(
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(12)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .padding(.leading, 16)
                    .accessibilityLabel("Go back")

                    Spacer()

                    Text("SETTINGS")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .tracking(2)
                        .foregroundColor(.white)

                    Spacer()

                    // Invisible spacer to keep the title centered
                    Color.clear
                        .frame(width: 44, height: 44)
                        .padding(.trailing, 16)
                }
                .padding(.top, 10),
                alignment: .topLeading
            )
        }
        .frame(height: 150)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            lightGrey.ignoresSafeArea()

            VStack(spacing: 0) {
                courtStripHeader

                ScrollView {
                    VStack(spacing: 24) {

                        if social.phase == .ready {
                            accountSection
                        }

                        // MARK: Appearance

                        VStack(alignment: .leading, spacing: 12) {
                            Text("APPEARANCE")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(royalBlue)
                                .tracking(0.5)
                                .padding(.horizontal, 20)
                            Picker("Appearance", selection: $appearance) {
                                ForEach(AppearanceStyle.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 20)
                            Text("Light and dark follow your iPhone. Glass swaps the soft surfaces for frosted ones.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 20)
                        }

                        // MARK: About Us

                        VStack(alignment: .leading, spacing: 12) {
                            Text("ABOUT US")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(royalBlue)
                                .tracking(0.5)
                                .padding(.horizontal, 20)

                            VStack(spacing: 8) {
                                linkRow(
                                    title: "Terms of Service",
                                    url: termsURL,
                                    accessibilityLabel: "Terms of Service"
                                )

                                linkRow(
                                    title: "Privacy Policy",
                                    url: privacyURL,
                                    accessibilityLabel: "Privacy Policy"
                                )
                            }
                            .padding(.horizontal, 20)
                        }

                        // MARK: Data Management

                        VStack(alignment: .leading, spacing: 12) {
                            Text("DATA")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(royalBlue)
                                .tracking(0.5)
                                .padding(.horizontal, 20)

                            // Reset All Data — honest about what it does.
                            // Previously this was labeled "Clear Cache" with a
                            // dialog claiming it wouldn't affect match history.
                            // It actually deleted the watch session history,
                            // which IS the match history for case-3 matches.
                            Button(action: { showResetConfirm = true }) {
                                HStack {
                                    Image(systemName: resetCompleted ? "checkmark" : "exclamationmark.triangle")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(resetCompleted ? .green : destructiveRed)
                                    Text(resetCompleted ? "Data Reset" : "Reset All Data")
                                        .font(.system(size: 16))
                                        .foregroundColor(resetCompleted ? .green : destructiveRed)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(destructiveRed.opacity(0.6))
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(cardWhite)
                                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                                )
                            }
                            .padding(.horizontal, 20)
                            .accessibilityLabel("Reset all app data")
                            .accessibilityHint("Permanently deletes match history, tournaments, and watch session data")
                        }

                        // MARK: Feedback

                        Button(action: {
                            UIApplication.shared.open(feedbackURL)
                        }) {
                            Text("FEEDBACK")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .tracking(0.5)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(royalBlue)
                                )
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .accessibilityLabel("Send feedback")
                        .accessibilityHint("Opens the feedback form in your browser")

                        // MARK: App Version

                        Text(appVersionText)
                            .font(.system(size: 13))
                            .foregroundColor(versionGrey)
                            .padding(.top, 20)
                            .padding(.bottom, 30)
                            .accessibilityLabel("App \(appVersionText.lowercased())")
                    }
                    .padding(.top, 24)
                }
            }
        }
        // MARK: Reset All Data Alert
        .alert("Reset All Data?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Everything", role: .destructive) {
                resetAllData()
            }
        } message: {
            Text("This will permanently delete all match history, watch sessions, saved tournaments, and your profile. This cannot be undone.")
        }
    }

    // MARK: - Helpers

    private func linkRow(title: String, url: URL, accessibilityLabel: String) -> some View {
        Button(action: {
            UIApplication.shared.open(url)
        }) {
            HStack {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 16))
                    .foregroundColor(royalBlue)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundColor(royalBlue.opacity(0.7))
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(cardWhite)
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            )
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens in browser")
    }

    /// Wipe everything. Honest about what it touches — no surprise data loss.
    private func resetAllData() {
        // SwiftData: matches (with rally logs), Watch sessions, players.
        let context = AppDatabase.context
        do {
            try context.delete(model: RallyRecord.self)
            try context.delete(model: MatchRecord.self)
            try context.delete(model: WorkoutSessionRecord.self)
            try context.delete(model: PlayerRecord.self)
            try context.save()
        } catch {
            print("Settings: reset failed: \(error)")
        }

        let keysToRemove = [
            "profile_firstName",
            "profile_lastName",
            "profile_gender",
            "profile_birthYear",
            "profile_email",
            "profile_country",
            "hasCompletedOnboarding",            // Forces onboarding again next launch
            "health_access_opt_in",
            "health_access_prompted"
        ]
        for key in keysToRemove {
            UserDefaults.standard.removeObject(forKey: key)
        }

        PlayerDirectory.shared.ensureLocalUser()
        PlayerDirectory.shared.reload()
        MatchStore.shared.reload()
        WorkoutStore.shared.reload()

        resetCompleted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            resetCompleted = false
            // After reset, dismiss to root so RootView re-evaluates
            // hasCompletedOnboarding and shows OnboardingView again.
            dismiss()
        }
    }
}

#Preview {
    SettingsView()
}
