//
//  ContentView.swift
//  Pickleball watch Watch App
//
//  Idle → setup → scoring → result, for pickleball and padel. The sport
//  follows the phone; turn the Digital Crown on the idle screen to switch.
//

import SwiftUI
import WatchKit
import CourtKit

struct ContentView: View {
    @Environment(WatchMatchSession.self) private var session
    @State private var showingSetup = false

    var body: some View {
        ZStack {
            DS.Palette.night.ignoresSafeArea()
            content
        }
        .animation(.smooth(duration: 0.3), value: showingSetup)
        .animation(.smooth(duration: 0.3), value: session.revision == 0)
        .animation(.smooth(duration: 0.3), value: session.replica?.matchID)
    }

    @ViewBuilder
    private var content: some View {
        if let replica = session.replica {
            if replica.isFinished {
                WatchResultView(replica: replica)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                WatchScoringView(replica: replica)
                    .transition(.opacity)
            }
        } else if showingSetup {
            WatchSetupView(sport: session.sport) { rules, lineup in
                session.startMatch(rules: rules, lineup: lineup)
                showingSetup = false
            } onCancel: {
                showingSetup = false
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            WatchIdleView(onStart: { showingSetup = true })
                .transition(.opacity)
        }
    }
}

// MARK: - Idle

struct WatchIdleView: View {
    @Environment(WatchMatchSession.self) private var session
    let onStart: () -> Void

    @State private var crown: Double = 0
    @FocusState private var focused: Bool

    var body: some View {
        let theme = session.sport.theme
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            CourtArtView(sport: session.sport, lineWidth: 1, lineOpacity: 0.5, showsSurface: true)
                .frame(height: 64)
                .animation(.smooth, value: session.sport)

            HStack(spacing: 6) {
                BallIcon(sport: session.sport, size: 12)
                Text(session.sport.displayName.uppercased())
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(theme.accent)
            }

            Button(action: onStart) {
                Text("START MATCH")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.accent))
            }
            .buttonStyle(.press)

            Text("Turn the crown to switch sport")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(DS.Palette.nightMuted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .focusable()
        .focused($focused)
        .digitalCrownRotation($crown, from: -3, through: 3, by: 1, sensitivity: .low, isContinuous: true, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { oldValue, newValue in
            // Any detent flips between the two sports.
            guard Int(newValue.rounded()) != Int(oldValue.rounded()) else { return }
            session.sport = session.sport.toggled
            Haptics.selection()
        }
        .onAppear { focused = true }
    }
}

// MARK: - Result

struct WatchResultView: View {
    @Environment(WatchMatchSession.self) private var session
    let replica: MatchReplica

    var body: some View {
        let display = replica.display
        let winner = display.winner ?? .a
        let won = winner == .a
        let theme = replica.setup.rules.sport.theme

        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: won ? "trophy.fill" : "flag.checkered")
                    .font(.system(size: 30))
                    .foregroundStyle(won ? theme.accent : DS.Palette.nightMuted)
                Text(won ? "VICTORY" : "DEFEAT")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(display.matchScore.a)–\(display.matchScore.b)")
                    .font(DS.Typography.hero(34))
                    .foregroundStyle(.white)
                Text(display.completed.map(\.label).joined(separator: "  "))
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(DS.Palette.nightMuted)
                    .multilineTextAlignment(.center)

                if replica.isEnded {
                    Button("Done") { session.dismissEnded() }
                        .tint(theme.accent)
                } else {
                    Button {
                        session.finish()
                    } label: {
                        Text("SAVE MATCH")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.accent))
                    }
                    .buttonStyle(.press)

                    Button {
                        session.undo()
                    } label: {
                        Label("Undo last rally", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.Palette.nightText)
                }
            }
            .padding(.horizontal, 8)
        }
        .onChange(of: replica.isEnded) { _, ended in
            if ended { session.dismissEnded() }
        }
    }
}
