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
    @Environment(WorkoutManager.self) private var workout
    let onStart: () -> Void

    @State private var crown: Double = 0
    @State private var showWorkoutSettings = false
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

            Button { showWorkoutSettings = true } label: {
                Label(LocalizedStringKey(workout.recordsWorkouts ? (workout.isIndoor ? "Workout · Indoor" : "Workout · Outdoor") : "Score only"),
                      systemImage: workout.recordsWorkouts ? "heart.fill" : "heart.slash")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Palette.nightText)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Workout settings")

            if let draft = session.pendingDraft {
                VStack(spacing: 4) {
                    Text("Ready from iPhone")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Palette.nightMuted)
                    Text(draft.setup.lineup.shortName(of: .a) + " v " + draft.setup.lineup.shortName(of: .b))
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Button("Start on Watch") { session.startPendingDraft() }
                        .tint(theme.accent)
                }
            }
            if session.needsUpdate {
                Text("Update PickleBall on your iPhone and Watch")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Palette.loss)
                    .multilineTextAlignment(.center)
            }
            if session.unsentCount > 0 {
                Label(session.unsentCount == 1 ? LocalizedStringKey("1 match waiting for iPhone")
                                               : LocalizedStringKey("\(session.unsentCount) matches waiting for iPhone"),
                      systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Palette.nightText)
            } else {
                Text("Turn the crown to switch sport")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Palette.nightMuted)
            }
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
        .sheet(isPresented: $showWorkoutSettings) { WatchWorkoutSettings() }
    }
}

/// Workout recording is optional: scoring works the same without it.
struct WatchWorkoutSettings: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        @Bindable var workout = workout
        List {
            Toggle("Record workout", isOn: $workout.recordsWorkouts)
            if workout.recordsWorkouts {
                Toggle("Indoor court", isOn: $workout.isIndoor)
                Toggle("Shot estimates (beta)", isOn: $workout.estimatesShots)
            }
            if workout.authorizationDenied {
                Text("Health access is off. Turn it on in Settings › Health to record workouts. Scoring works without it.")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.nightMuted)
            } else {
                Text("Changes apply to the next match.")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.nightMuted)
            }
        }
        .navigationTitle("Workout")
    }
}

// MARK: - Result

struct WatchResultView: View {
    @Environment(WatchMatchSession.self) private var session
    @Environment(WorkoutManager.self) private var workout
    let replica: MatchReplica

    var body: some View {
        let display = replica.display
        let winner = display.winner ?? .a
        // Victory is the wearer's side winning, whichever side that is.
        let wearer = session.ownedJournal?.manifest.wearerTeam ?? session.wearerTeam(in: replica.setup.lineup) ?? .a
        let won = winner == wearer
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

                if let note = session.ownedSyncNote, replica.isEnded {
                    Text(session.ownedJournal?.status == .finished && session.ownedJournal?.unacknowledged.isEmpty == false
                         ? String(localized: "Match saved on Watch · sync pending") : note)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Palette.nightMuted)
                        .multilineTextAlignment(.center)
                }
                if replica.isEnded, workout.state(for: replica.matchID) == .finishing {
                    // The score is complete; HealthKit is still saving.
                    Text("Match saved · workout details finishing.")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Palette.nightMuted)
                        .multilineTextAlignment(.center)
                }
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
            // A phone-owned match ended elsewhere closes; a Watch-owned one
            // stays up with its sync status until "Done".
            if ended, session.ownedJournal == nil { session.dismissEnded() }
        }
    }
}
