//
//  MainMenu.swift
//  PickleBall
//
//  Home (the Play tab): the sport and its switch pill, the court (tap to
//  start, hold to switch sport), then whatever is waiting: a live match,
//  parked matches, results to confirm, call outs.
//

import SwiftUI
import UIKit
import CourtKit
import CourtNet

struct MainMenu: View {
    @Environment(SportMode.self) private var sportMode
    @State private var showPlayView = false
    @State private var showSettings = false
    @State private var showScoreboard = false
    @State private var showEnterScore = false
    @State private var showInbox = false
    @State private var following: LiveMatchRow?

    @ObservedObject private var matchStore = MatchStore.shared
    private let social = Social.shared
    @ObservedObject private var watchManager = WatchConnectivityManager.shared
    private let center = MatchCenter.shared

    @AppStorage("health_access_opt_in")   private var healthAccessOptIn    = false
    @AppStorage("health_access_prompted") private var healthAccessPrompted = false
    @State private var showHealthPrompt = false
    @State private var hasCheckedHealthOnAppear = false

    private var theme: SportTheme { sportMode.theme }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var courtPressed = false

    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 14)
                        .padding(.bottom, 20)
                        .zIndex(1)

                    CourtHome(sport: sportMode.sport)
                        .scaleEffect(courtPressed && !reduceMotion ? 0.985 : 1)
                        .animation(.snappy(duration: 0.18), value: courtPressed)
                        .padding(.horizontal, Court.Metrics.sideInset)
                        .onTapGesture { startFromCourt() }
                        .onLongPressGesture(minimumDuration: 0.45) {
                            courtPressed = false
                            switchSport()
                        } onPressingChanged: { pressing in
                            courtPressed = pressing
                        }
                        .accessibilityAction { startFromCourt() }
                        .accessibilityAction(named: Text("Switch to \(sportMode.sport.toggled.displayName)")) { switchSport() }

                    hint.padding(.top, 22)

                    VStack(spacing: 12) {
                        if let live = center.live, !live.isEnded {
                            liveMatchCard(live)
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                        ForEach(matchStore.parked.prefix(2)) { setup in
                            menuSecondaryButton(
                                title: String(localized: "Resume: \(setup.lineup.shortName(of: .a)) vs \(setup.lineup.shortName(of: .b))"),
                                systemImage: "pause.circle"
                            ) {
                                if center.resume(matchID: setup.matchID) != nil { showScoreboard = true }
                            }
                        }
                        menuSecondaryButton(title: String(localized: "Enter a score"), systemImage: "square.and.pencil") {
                            showEnterScore = true
                        }
                        ForEach(inboxItems.prefix(3)) { item in
                            menuSecondaryButton(title: item.title, systemImage: item.symbol) {
                                open(item)
                            }
                        }
                        if inboxItems.count > 3 {
                            menuSecondaryButton(title: String(localized: "See all (\(inboxItems.count))"), systemImage: "tray.full") {
                                showInbox = true
                            }
                        }
                    }
                    .padding(.horizontal, Court.Metrics.sideInset + 4)
                    .padding(.top, 28)
                }
                .padding(.top, 8)
                .padding(.bottom, Court.Metrics.tabBarClearance)
            }
            // The far half of the court rises behind the header and fades
            // out; don't cut it off at the top of the scroll area. Content
            // scrolled up fades under the status bar instead (below).
            .scrollClipDisabled()
            .overlay(alignment: .top) { statusBarFade }
            .courtGround()

            if showHealthPrompt {
                healthAccessPrompt
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .sensoryFeedback(.selection, trigger: sportMode.sport)
        .animation(DS.Motion.snappy, value: sportMode.sport)
        .animation(DS.Motion.snappy, value: center.live?.id)
        .fullScreenCover(isPresented: $showPlayView) {
            PlayView(onDismiss: { showPlayView = false })
        }
        .fullScreenCover(isPresented: $showScoreboard) {
            LiveMatchScreen()
        }
        .sheet(isPresented: $showEnterScore) {
            EnterScoreView()
        }
        .sheet(isPresented: $showInbox) {
            NavigationStack { PlayInboxView() }
        }
        .fullScreenCover(item: $following) { live in
            LiveFollowView(live: live)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            guard !hasCheckedHealthOnAppear else { return }
            hasCheckedHealthOnAppear = true

            if !healthAccessOptIn, !healthAccessPrompted,
               watchManager.isWatchPaired, watchManager.isWatchAppInstalled {
                showHealthPrompt = true
            }
        }
    }

    // MARK: Inbox

    /// What's waiting on the Play tab: results to confirm, call outs to
    /// answer, the next match, friends playing right now.
    private var inboxItems: [PlayInboxItem] { PlayInboxItem.all(social: social) }

    private func open(_ item: PlayInboxItem) {
        switch item.kind {
        case .live(let live): following = live
        default: showInbox = true
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("HOME")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(Court.dim)
                Text(sportMode.sport.displayName)
                    .font(.system(size: 38, weight: .semibold))
                    .tracking(-1.1)
                    .foregroundStyle(Court.text)
                    .contentTransition(.opacity)
            }
            Spacer()
            Button(action: switchSport) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                    Text(sportMode.sport.toggled.displayName)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Court.text)
                .padding(.horizontal, 16)
                .frame(height: Court.Metrics.pillHeight)
                .courtRaisedCapsule()
            }
            .buttonStyle(.press)
            .accessibilityLabel("Switch to \(sportMode.sport.toggled.displayName)")
        }
    }

    // MARK: Hint and page dots

    private var hint: some View {
        VStack(spacing: 12) {
            Text("TAP COURT TO START · HOLD TO SWITCH")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(Court.muted)
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                ForEach(Sport.allCases) { s in
                    Capsule()
                        .fill(s == sportMode.sport ? Court.activeDot(s, scheme: scheme) : Court.dotOff)
                        .frame(width: s == sportMode.sport ? 18 : 6, height: 6)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
    }

    /// Tapping the court: open the live match if there is one, else start.
    private func startFromCourt() {
        Haptics.medium()
        if let live = center.live, !live.isEnded { showScoreboard = true } else { showPlayView = true }
    }

    /// Ground colour under the status bar, so content scrolled up fades out
    /// rather than running into the clock.
    private var statusBarFade: some View {
        GeometryReader { geo in
            // Ends exactly where content starts, so the header is never washed.
            LinearGradient(stops: [.init(color: Court.ground, location: 0),
                                   .init(color: Court.ground, location: 0.7),
                                   .init(color: Court.ground.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: geo.safeAreaInsets.top)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        // Reaches up under the status bar; safeAreaInsets still reports it.
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func switchSport() {
        if let live = center.live, !live.isEnded {
            // Never switch mid-match: open the match so it can be ended or parked.
            showScoreboard = true
            return
        }
        sportMode.toggle()
        center.publishPreferences(sport: sportMode.sport)
    }

    // MARK: Live match

    private func liveMatchCard(_ match: LiveMatch) -> some View {
        Button {
            Haptics.light()
            showScoreboard = true
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(DS.Palette.loss)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.isWatchHosted ? "LIVE ON APPLE WATCH" : "LIVE")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(DS.Palette.loss)
                    Text("\(match.lineup.shortName(of: .a)) vs \(match.lineup.shortName(of: .b))")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Court.text)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(match.display.points.a)–\(match.display.points.b)")
                    .font(DS.Typography.score(26))
                    .foregroundStyle(Court.text)
                    .contentTransition(.numericText())
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Court.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .courtRaised(cornerRadius: 20)
        }
        .buttonStyle(.press)
        .accessibilityLabel("Live match, \(match.lineup.name(of: .a)) versus \(match.lineup.name(of: .b)). Open scoreboard.")
    }

    private func menuSecondaryButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22)
                Text(verbatim: title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Court.muted)
            }
            .foregroundStyle(Court.text)
            .padding(.horizontal, 16)
            .frame(height: 54)
            .courtRaised(cornerRadius: 18)
        }
        .buttonStyle(.press)
        .accessibilityLabel(title)
    }

    private var healthAccessPrompt: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { showHealthPrompt = false }

            VStack(spacing: 18) {
                Text("Add Apple Watch insights?")
                    .font(.system(size: 18, weight: .semibold))
                    .multilineTextAlignment(.center)

                Text("Your Watch records heart-rate zones, duration and calories for every match, plus beta shot detection. Only while you play with the app open on your wrist.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("Allow Health data access?")
                    .font(.system(size: 15, weight: .semibold))

                HStack(spacing: 12) {
                    Button("Not Now") {
                        healthAccessPrompted = true
                        showHealthPrompt = false
                    }
                    .buttonStyle(.bordered)

                    Button("Allow") {
                        healthAccessPrompted = true
                        showHealthPrompt = false
                        watchManager.requestHealthAuthorization { granted in
                            if granted { healthAccessOptIn = true }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.Palette.ink)
                }
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
        }
    }
}

#Preview {
    MainMenu()
        .environment(SportMode())
}

// MARK: - Court

/// The near half court on a raised plate, with the far half mirrored above
/// the net and fading out. Pickleball: kitchen by the net. Padel: back court.
struct CourtHome: View {
    let sport: Sport
    var height: CGFloat = Court.Metrics.courtHeight

    var body: some View {
        CourtPlate(sport: sport)
            .frame(height: height)
            .background(alignment: .top) {
                CourtPlate(sport: sport, mirrored: true, elevated: false, showLabel: false)
                    .frame(height: height)
                    .mask(fade)
                    .offset(y: -(height + Court.Metrics.farHalfGap))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .contentShape(RoundedRectangle(cornerRadius: Court.Metrics.courtRadius, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Start a new \(sport.displayName) match"))
            .accessibilityHint(Text("Touch and hold to switch to \(sport.toggled.displayName)"))
            .accessibilityAddTraits(.isButton)
    }

    private var fade: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(Court.Metrics.farHalfOpacity), location: 0),
                .init(color: .clear, location: min(1, Court.Metrics.farHalfFade / height))
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}

private struct CourtPlate: View {
    let sport: Sport
    var mirrored = false
    var elevated = true
    var showLabel = true
    @Environment(\.appearanceStyle) private var style

    /// The net is at the top of the near half (the bottom of the mirror).
    private var bandOnTop: Bool { (sport == .pickleball) != mirrored }

    var body: some View {
        VStack(spacing: Court.Metrics.courtGap) {
            if bandOnTop {
                band
                boxes
            } else {
                boxes
                band
            }
        }
        .padding(Court.Metrics.courtPadding)
        .background { plate }
    }

    @ViewBuilder
    private var plate: some View {
        let shape = RoundedRectangle(cornerRadius: Court.Metrics.courtRadius, style: .continuous)
        if style == .glass {
            shape.fill(.ultraThinMaterial)
                .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8))
                .shadow(color: .black.opacity(elevated ? 0.10 : 0), radius: 16, x: 0, y: 10)
        } else {
            shape.fill(Court.plate)
                .shadow(color: elevated ? Court.courtDrop.color : .clear, radius: Court.courtDrop.radius,
                        x: Court.courtDrop.x, y: Court.courtDrop.y)
                .shadow(color: elevated ? Court.courtLight.color : .clear, radius: Court.courtLight.radius,
                        x: Court.courtLight.x, y: Court.courtLight.y)
        }
    }

    private var band: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: Court.Metrics.bandHeight)
            .courtSunken()
            .overlay {
                if showLabel {
                    Text(sport == .pickleball ? "KITCHEN" : "BACK COURT")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(2.2)
                        .foregroundStyle(Court.muted)
                }
            }
    }

    private var boxes: some View {
        HStack(spacing: Court.Metrics.courtGap) {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).courtSunken()
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).courtSunken()
        }
        .frame(maxHeight: .infinity)
    }
}
