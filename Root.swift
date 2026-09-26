//
//  RootView.swift
//  PickleBall
//
//  Root view that gates the app behind onboarding.
//  Uses @AppStorage for synchronous, crash-resistant state persistence.
//

import SwiftUI

struct RootView: View {
    // @AppStorage is the Apple-standard for simple, durable flags.
    // It reads synchronously on init, preventing any "first-frame flicker".
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    
    // Apple HIG Requirement: Respect system motion preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if hasCompletedOnboarding {
                ContentView()
                    .transition(mainContentTransition)
            } else {
                // No arguments needed: OnboardingView will set the @AppStorage flag directly
                OnboardingView()
                    .transition(.opacity)
            }
        }
        // Scoped animation prevents unnecessary re-evaluation of unrelated child views
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.88), value: hasCompletedOnboarding)
        
        // Accessibility: Announce screen change for VoiceOver users when onboarding completes
        .onChange(of: hasCompletedOnboarding) { newValue in
            if newValue {
                // Slight delay ensures the transition has visually begun before VoiceOver speaks
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    UIAccessibility.post(notification: .screenChanged, argument: nil)
                }
            }
        }
        
        // Future-proofing: Deep link handling at the root level
        .onOpenURL { url in
            // TODO: Handle deep links (e.g., if url is a match invite, route accordingly)
        }
        
        // MARK: - Bulletproof Debug Reset
        #if DEBUG
        // Listens for a specific notification to reset onboarding.
        // 100% collision-free (no accidental taps) and can be triggered from
        // a hidden Dev Settings screen, Mac keyboard shortcut, or Xcode console:
        // NotificationCenter.default.post(name: .debugResetOnboarding, object: nil)
        .onReceive(NotificationCenter.default.publisher(for: .debugResetOnboarding)) { _ in
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            hasCompletedOnboarding = false
        }
        #endif
    }
    
    // MARK: - Transitions
    
    private var mainContentTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        // Matches native iOS system sheet dismissal feel
        return .asymmetric(
            insertion: .scale(scale: 0.98).combined(with: .opacity),
            removal: .opacity
        )
    }
}

// MARK: - Debug Extensions

#if DEBUG
extension Notification.Name {
    static let debugResetOnboarding = Notification.Name("com.pickleball.debug.resetOnboarding")
}
#endif

// MARK: - Previews

#Preview("Onboarding") {
    RootView()
        .onAppear {
            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        }
}

#Preview("Main App") {
    RootView()
        .onAppear {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        }
}
