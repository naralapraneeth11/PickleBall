//
//  ScoreLiveActivity.swift
//  ScoreActivityWidget
//
//  Live score on the Lock Screen and in the Dynamic Island while a match
//  is being scored. Renders the `LiveScoreSnapshot` the app computed with
//  CourtKit, so it can never disagree with the scoreboard.
//

import SwiftUI
import WidgetKit
import ActivityKit
import CourtKit

@main
struct ScoreActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        ScoreLiveActivity()
        BeltWidget()
    }
}

struct ScoreLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveScoreAttributes.self) { context in
            LockScreenScoreView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(DS.Palette.night)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TeamColumn(
                        name: context.attributes.teamA,
                        points: context.state.points.a,
                        isServing: context.state.servingTeam == .a,
                        sport: context.attributes.sport,
                        alignment: .leading
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TeamColumn(
                        name: context.attributes.teamB,
                        points: context.state.points.b,
                        isServing: context.state.servingTeam == .b,
                        sport: context.attributes.sport,
                        alignment: .trailing
                    )
                }
                DynamicIslandExpandedRegion(.center) {
                    CallBadge(state: context.state, sport: context.attributes.sport)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    FooterLine(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    if context.state.servingTeam == .a {
                        BallIcon(sport: context.attributes.sport, size: 10)
                    }
                    Text(context.state.points.a)
                        .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                }
            } compactTrailing: {
                HStack(spacing: 4) {
                    Text(context.state.points.b)
                        .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                    if context.state.servingTeam == .b {
                        BallIcon(sport: context.attributes.sport, size: 10)
                    }
                }
            } minimal: {
                BallIcon(sport: context.attributes.sport, size: 14)
            }
            .keylineTint(context.attributes.sport.theme.accent)
        }
    }
}

// MARK: - Lock Screen

private struct LockScreenScoreView: View {
    let attributes: LiveScoreAttributes
    let state: LiveScoreSnapshot

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                TeamColumn(name: attributes.teamA, points: state.points.a, isServing: state.servingTeam == .a,
                           sport: attributes.sport, alignment: .leading)
                Spacer(minLength: 8)
                CallBadge(state: state, sport: attributes.sport)
                Spacer(minLength: 8)
                TeamColumn(name: attributes.teamB, points: state.points.b, isServing: state.servingTeam == .b,
                           sport: attributes.sport, alignment: .trailing)
            }
            FooterLine(attributes: attributes, state: state)
        }
        .padding(16)
    }
}

// MARK: - Pieces

private struct TeamColumn: View {
    let name: String
    let points: String
    let isServing: Bool
    let sport: Sport
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            HStack(spacing: 4) {
                if isServing && alignment == .leading { BallIcon(sport: sport, size: 10) }
                Text(name.uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(isServing ? Color.white : Color.white.opacity(0.6))
                    .lineLimit(1)
                if isServing && alignment == .trailing { BallIcon(sport: sport, size: 10) }
            }
            Text(points.isEmpty ? "–" : points)
                .font(.system(size: 38, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(isServing ? Color.white : Color.white.opacity(0.55))
                .contentTransition(.numericText())
        }
    }
}

private struct CallBadge: View {
    let state: LiveScoreSnapshot
    let sport: Sport

    var body: some View {
        let theme = sport.theme
        VStack(spacing: 4) {
            Text(state.winner != nil ? "FINAL" : state.call)
                .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(theme.accent))
            Text(state.pressure?.uppercased() ?? state.phaseTitle.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(state.pressure != nil ? theme.accent : Color.white.opacity(0.6))
                .lineLimit(1)
        }
    }
}

private struct FooterLine: View {
    let attributes: LiveScoreAttributes
    let state: LiveScoreSnapshot

    var body: some View {
        HStack {
            Text(attributes.sport == .padel
                 ? "Sets \(state.sets.a)–\(state.sets.b) · Games \(state.games.a)–\(state.games.b)"
                 : "Games \(state.games.a)–\(state.games.b)")
            Spacer()
            Text(state.history.isEmpty ? attributes.rulesSummary : state.history)
                .lineLimit(1)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundStyle(Color.white.opacity(0.65))
    }
}
