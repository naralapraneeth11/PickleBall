//
//  WatchScoringView.swift
//  Pickleball watch Watch App
//
//  Wrist scoring for both sports. Two big tap targets — "they won the
//  rally" on top, "we won the rally" below — and the engine does the rest.
//  Turn the Digital Crown back to undo. Game, set and match points buzz.
//

import SwiftUI
import WatchKit
import CourtKit

struct WatchScoringView: View {
    @Environment(WatchMatchSession.self) private var session
    @Environment(WorkoutManager.self) private var workout
    let replica: MatchReplica

    @State private var crown: Double = 0
    @State private var crownAnchor: Double = 0
    @State private var showEndConfirm = false
    @FocusState private var focused: Bool

    /// Crown detents backwards needed for one undo.
    private let undoThreshold: Double = 2

    private var display: ScoreDisplay { replica.display }
    private var sport: Sport { replica.setup.rules.sport }
    private var theme: SportTheme { sport.theme }
    private var lineup: Lineup { replica.setup.lineup }

    var body: some View {
        VStack(spacing: 4) {
            header
            teamButton(.b)
            teamButton(.a)
        }
        .padding(.horizontal, 4)
        .overlay(alignment: .top) {
            if let cheer = session.cheer {
                Label(cheer, systemImage: "hands.clap.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(theme.accent))
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.snappy, value: session.cheer)
        .focusable()
        .focused($focused)
        .digitalCrownRotation($crown, from: -1_000, through: 1_000, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { _, newValue in handleCrown(newValue) }
        .onAppear { focused = true }
        .confirmationDialog("End match?", isPresented: $showEndConfirm, titleVisibility: .visible) {
            Button("End without saving", role: .destructive) { session.abandon() }
            Button("Keep playing", role: .cancel) {}
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Button { showEndConfirm = true } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(DS.Palette.nightRaised))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("End match")

            Text(display.call)
                .font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(theme.accent))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityLabel(display.spokenCall)

            Spacer(minLength: 2)

            VStack(alignment: .trailing, spacing: 0) {
                Text(statusText)
                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(pressureText != nil ? theme.accent : DS.Palette.nightMuted)
                    .lineLimit(1)
                if workout.heartRate > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "heart.fill").font(.system(size: 8))
                        Text("\(Int(workout.heartRate))")
                        if let zone = workout.currentZone { Text(zone.shortTitle) }
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(DS.Palette.nightMuted)
                }
            }
        }
    }

    private var pressureText: String? {
        let pressures = Team.allCases.compactMap { team in replica.scorer.pressure(for: team) }
        return pressures.max()?.title.uppercased()
    }

    private var statusText: String {
        if let pressureText { return pressureText }
        if sport == .padel {
            return "S \(display.sets.a)-\(display.sets.b) · G \(display.games.a)-\(display.games.b)"
        }
        if display.completed.isEmpty { return display.phaseTitle.uppercased() }
        return "GAMES \(display.games.a)-\(display.games.b)"
    }

    // MARK: Team buttons

    private func teamButton(_ team: Team) -> some View {
        let serving = display.servingTeam == team
        let name = team == .a && lineup.teams.a.contains(where: { $0.id == session.me.id })
            ? "US"
            : lineup.shortName(of: team).uppercased()

        return Button {
            session.record(team)
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        if serving { BallIcon(sport: sport, size: 10) }
                        Text(name)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    if serving, let number = display.serverNumber {
                        Text("SERVER \(number)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.accent)
                    }
                }
                .foregroundStyle(serving ? Color.white : DS.Palette.nightMuted)

                Spacer(minLength: 2)

                Text(display.points[team])
                    .font(DS.Typography.score(display.points[team].count > 2 ? 30 : 38))
                    .foregroundStyle(serving ? Color.white : Color.white.opacity(0.55))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(serving ? theme.accent.opacity(0.18) : DS.Palette.nightRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(serving ? theme.accent.opacity(0.6) : DS.Palette.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(PressStyle(scale: 0.97))
        .animation(DS.Motion.score, value: display.points[team])
        .accessibilityLabel("Rally won by \(lineup.name(of: team))")
        .accessibilityValue(display.points[team])
    }

    // MARK: Crown undo

    private func handleCrown(_ value: Double) {
        if value > crownAnchor {
            // Turning forward just moves the anchor.
            crownAnchor = value
        } else if crownAnchor - value >= undoThreshold {
            crownAnchor = value
            if session.canUndo {
                session.undo()
            } else {
                Haptics.warning()
            }
        }
    }
}
