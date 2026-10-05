//
//  WatchHandoffSheet.swift
//  PickleBall
//
//  Handing a match to the Apple Watch, with honest states: "Ready on Watch"
//  only after the Watch has saved the match, and once Start is sent the
//  phone doesn't take scoring back unless the Watch agrees.
//

import SwiftUI
import CourtKit

struct WatchHandoffSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var link = WatchConnectivityManager.shared
    private let center = MatchCenter.shared

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Court.text)
                .frame(width: 72, height: 72)
                .courtRaised(cornerRadius: 22)
                .padding(.top, 24)
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Court.text)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.system(size: 15))
                .foregroundStyle(Court.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer(minLength: 0)
            actions
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .courtGround()
        .onChange(of: center.handoff?.state) { _, state in
            if state == .scoringOnWatch { Haptics.success() }
        }
    }

    // MARK: State

    private var state: WatchHandoff.State? { center.handoff?.state }

    private var symbol: String {
        switch state {
        case .scoringOnWatch: return "checkmark.circle"
        case .ready: return "applewatch.radiowaves.left.and.right"
        default: return "applewatch"
        }
    }

    private var title: String {
        if center.watchNeedsUpdate { return String(localized: "Update PickleBall") }
        switch link.availability {
        case .checking: return String(localized: "Checking Apple Watch…")
        case .unsupported, .notPaired: return String(localized: "No Apple Watch paired")
        case .appNotInstalled: return String(localized: "Install PickleBall on your Apple Watch")
        default: break
        }
        switch state {
        case .preparing, nil:
            return link.availability == .reachable ? String(localized: "Getting your Watch ready…")
                                                   : String(localized: "Open PickleBall on your Watch")
        case .ready: return String(localized: "Ready on Watch")
        case .starting: return String(localized: "Starting on Watch…")
        case .scoringOnWatch: return String(localized: "Scoring on Watch")
        case .cancelling: return String(localized: "Taking it back…")
        }
    }

    private var detail: String {
        if center.watchNeedsUpdate {
            return String(localized: "Your Watch has a newer version. Update the app on both devices.")
        }
        if link.availability == .appNotInstalled {
            return String(localized: "Open the Watch app on your iPhone to install it, then try again. You can also score on this iPhone.")
        }
        switch state {
        case .preparing, nil:
            return String(localized: "The match is sent to your Watch. It starts only when you tap Start.")
        case .ready:
            return String(localized: "Start here or on your Watch. Every rally is saved on the Watch first, so it works with no signal.")
        case .starting:
            return String(localized: "Your Watch takes over as soon as it gets this. The match stays on the Watch even if it arrives later.")
        case .scoringOnWatch:
            return String(localized: "Score on your wrist. This iPhone follows along and saves the result when it’s done.")
        case .cancelling:
            return String(localized: "Your Watch gives the match back if no rally has been scored yet.")
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch state {
        case .ready, .preparing:
            VStack(spacing: 10) {
                Button { center.startOnWatch() } label: { Text("Start on Watch").courtBigButton() }
                    .buttonStyle(.press)
                    .disabled(state != .ready)
                    .opacity(state == .ready ? 1 : 0.5)
                Button("Score on this iPhone instead") {
                    center.cancelWatchHandoff()
                    dismiss()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Court.muted)
            }
        case .starting, .cancelling:
            Button("Take the match back") { center.cancelWatchHandoff() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Court.muted)
                .disabled(state == .cancelling)
        case .scoringOnWatch:
            Button { dismiss() } label: { Text("Done").courtBigButton() }
                .buttonStyle(.press)
        case nil:
            Button { dismiss() } label: { Text("Close").courtBigButton() }
                .buttonStyle(.press)
        }
    }
}
