//
//  RootView.swift
//  PickleBall
//
//  Sign-up is required: welcome → Sign in with Apple → profile setup →
//  the app. A build without a server (no Secrets.plist) skips straight to
//  on-device scoring after the original onboarding.
//

import SwiftUI
import CourtKit

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let social = Social.shared

    var body: some View {
        ZStack {
            switch social.phase {
            case .launching:
                LaunchView()
                    .transition(.opacity)
            case .signedOut:
                WelcomeView()
                    .transition(.opacity)
            case .needsProfile:
                ProfileSetupView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .ready:
                ContentView()
                    .transition(mainContentTransition)
            case .offlineOnly:
                if hasCompletedOnboarding {
                    ContentView()
                        .transition(mainContentTransition)
                } else {
                    OnboardingView()
                        .transition(.opacity)
                }
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.88), value: social.phase)
        .onChange(of: social.phase) { _, phase in
            guard phase == .ready else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            }
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .debugResetOnboarding)) { _ in
            Haptics.medium()
            hasCompletedOnboarding = false
        }
        #endif
    }

    private var mainContentTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .scale(scale: 0.98).combined(with: .opacity), removal: .opacity)
    }
}

/// Shown for the moment it takes to restore the session.
private struct LaunchView: View {
    var body: some View {
        ZStack {
            Court.ground.ignoresSafeArea()
            BallIcon(sport: .pickleball, size: 56)
                .accessibilityLabel("PickleBall")
        }
    }
}

#if DEBUG
extension Notification.Name {
    static let debugResetOnboarding = Notification.Name("com.pickleball.debug.resetOnboarding")
}
#endif
