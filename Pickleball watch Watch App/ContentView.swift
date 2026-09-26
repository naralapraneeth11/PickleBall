//
//  ContentView.swift
//  Pickleball watch Watch App
//
import SwiftUI
import Combine
import WatchConnectivity

// MARK: - Theme
private enum WatchUI {
    static let navy = Color(red: 0.08, green: 0.12, blue: 0.24)
    static let courtBlue = Color(red: 0.18, green: 0.38, blue: 0.58)
    static let accent = Color(red: 0.55, green: 0.92, blue: 0.25)
    static let label = Color.white.opacity(0.92)
    static let line = Color.white.opacity(0.10)
    static let muted = Color.white.opacity(0.55)
    static let cardFill = Color.white.opacity(0.12)
    static let corner: CGFloat = 14
}

// MARK: - Root
struct ContentView: View {
    @EnvironmentObject private var sync: WatchMatchSync
    @EnvironmentObject private var motionManager: MotionManager

    @State private var showingSetup = false
    @State private var showingResult = false

    var body: some View {
        ZStack {
            WatchCourtBackground().ignoresSafeArea()
            content
        }
        .animation(.smooth(duration: 0.3), value: showingSetup)
        .animation(.smooth(duration: 0.3), value: showingResult)
        
        .onChange(of: sync.state.isMatchActive) { _, isActive in
            if isActive {
                showingResult = false
                sync.resetServeStats() // PRO: Reset serve stats on new match
                if !motionManager.isTracking { motionManager.startTracking() }
            } else {
                if motionManager.isTracking { motionManager.stopTracking() }
                showingSetup = false
            }
        }
        .onChange(of: sync.state.matchCompleted) { _, completed in
            if completed {
                // PRO: Pass hoisted serve stats to the payload before stopping
                if let payload = motionManager.gameCompletePayload(
                    matchID: sync.state.matchID,
                    servePointsPlayed: sync.servePointsPlayed,
                    servePointsWon: sync.servePointsWon
                ) {
                    sync.sendGameComplete(payload: payload)
                }
                if motionManager.isTracking { motionManager.stopTracking() }
                
                WKInterfaceDevice.current().play(sync.state.wonByPlayer1 ? .success : .failure)
                showingResult = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if showingResult {
            WatchMatchResultView(didWin: sync.state.wonByPlayer1, onDismiss: {
                showingResult = false
                sync.resetForNewMatch()
            })
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else if sync.state.isMatchActive {
            WatchGameView(sync: sync, motionManager: motionManager)
                .transition(.opacity)
        } else if showingSetup {
            WatchMatchSetupView(
                onComplete: { games, points, isServingFirst in
                    sync.startWatchInitiatedMatch(totalGames: games, targetScore: points, isPlayer1Serving: isServingFirst)
                    showingSetup = false
                },
                onCancel: { showingSetup = false }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            WatchIdleView(onStartMatch: { showingSetup = true })
                .transition(.opacity)
        }
    }
}

// MARK: - Game View (PRO Serve Logic)
struct WatchGameView: View {
    @ObservedObject var sync: WatchMatchSync
    @ObservedObject var motionManager: MotionManager

    @State private var showEndConfirm = false
    
    // PRO: Snapshot includes serve stats for flawless undo
    private struct PointUndoSnapshot {
        let state: MatchState
        let servePointsPlayed: Int
        let servePointsWon: Int
    }
    @State private var lastPointSnapshot: PointUndoSnapshot?

    private var state: MatchState { sync.state }
    private var gamesToWin: Int { max(1, state.totalGames) }
    private var displayName1: String {
        let p1 = state.player1Name.uppercased()
        return (p1.isEmpty || p1 == "PLAYER1") ? "YOU" : p1
    }
    private var displayName2: String {
        let p2 = state.player2Name.uppercased()
        return (p2.isEmpty || p2 == "PLAYER2") ? "OPPONENT" : p2
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    circleControl(icon: "arrow.uturn.backward", dimmed: lastPointSnapshot == nil, action: undoLastPoint)
                        .disabled(lastPointSnapshot == nil)
                        .accessibilityLabel("Undo last point")
                    circleControl(icon: "arrow.up.arrow.down", dimmed: false, action: swapPlayers)
                        .accessibilityLabel("Swap players")
                }
                Spacer()
                circleControl(icon: "xmark", dimmed: false) { showEndConfirm = true }
                    .accessibilityLabel("End match")
            }
            .padding(.horizontal, 4)

            Spacer(minLength: 2)

            VStack(spacing: 4) {
                if state.totalGames > 1 {
                    Text("GAMES  \(state.player1GamesWon)–\(state.player2GamesWon)")
                        .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(WatchUI.muted)
                }
                scoreboard
            }

            Spacer(minLength: 4)

            // PRO UI: Added "OUT" button for side-outs
            HStack(alignment: .center, spacing: 12) {
                Spacer()
                WatchPickleballToggle(
                    isOn: Binding(
                        get: { state.isPlayer1Serving },
                        set: { newValue in
                            WKInterfaceDevice.current().play(.click)
                            sync.updateState { $0.isPlayer1Serving = newValue }
                        }
                    )
                )
                .frame(width: 44, height: 68)
                .accessibilityLabel("Toggle serving player")

                Spacer()

                Button(action: sideOut) {
                    Text("OUT")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(WatchUI.cardFill))
                        .overlay(Circle().stroke(WatchUI.line, lineWidth: 1))
                }
                .buttonStyle(NativePressStyle())
                .accessibilityLabel("Side out")

                Button(action: awardPoint) {
                    Text("+1")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(WatchUI.navy)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color.white))
                        .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(NativePressStyle())
                .accessibilityLabel("Award point to server")

                Spacer()
            }
            .padding(.bottom, 2)
        }
        .padding(.horizontal, 6)
        .alert("End match?", isPresented: $showEndConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("End", role: .destructive) { sync.endMatch() }
        } message: { Text("This will stop the current match.") }
    }

    // MARK: - Scoring Logic
    private func awardPoint() {
        lastPointSnapshot = PointUndoSnapshot(state: sync.state, servePointsPlayed: sync.servePointsPlayed, servePointsWon: sync.servePointsWon)
        WKInterfaceDevice.current().play(.notification)

        // Watch-initiated: Player 1 is always "YOU"
        var newPlayed = sync.servePointsPlayed
        var newWon = sync.servePointsWon
        
        if state.isPlayer1Serving {
            newPlayed += 1
            newWon += 1 // Server won the rally
        }
        sync.setServeStats(played: newPlayed, won: newWon)

        sync.updateState { state in
            if state.isPlayer1Serving { state.player1Points += 1 }
            else { state.player2Points += 1 }
            checkGameWon(&state)
        }
    }

    private func sideOut() {
        lastPointSnapshot = PointUndoSnapshot(state: sync.state, servePointsPlayed: sync.servePointsPlayed, servePointsWon: sync.servePointsWon)
        WKInterfaceDevice.current().play(.directionDown)

        var newPlayed = sync.servePointsPlayed
        if state.isPlayer1Serving {
            newPlayed += 1 // "YOU" served, but lost the rally (side out)
        }
        sync.setServeStats(played: newPlayed, won: sync.servePointsWon)

        sync.updateState { state in
            state.isPlayer1Serving.toggle()
        }
    }

    private func undoLastPoint() {
        guard let snapshot = lastPointSnapshot else { return }
        WKInterfaceDevice.current().play(.directionDown)
        sync.replaceState(with: snapshot.state)
        sync.setServeStats(played: snapshot.servePointsPlayed, won: snapshot.servePointsWon)
        lastPointSnapshot = nil
    }

    private func checkGameWon(_ state: inout MatchState) {
        let p1 = state.player1Points, p2 = state.player2Points
        let p1Wins = p1 >= state.targetScore && (p1 - p2) >= 2
        let p2Wins = p2 >= state.targetScore && (p2 - p1) >= 2

        if p1Wins {
            state.completedGameScores.append(GameScore(player1: p1, player2: p2))
            state.player1GamesWon += 1
            state.player1Points = 0; state.player2Points = 0
            if state.player1GamesWon >= gamesToWin {
                state.matchCompleted = true; state.wonByPlayer1 = true; state.isMatchActive = false
            }
        } else if p2Wins {
            state.completedGameScores.append(GameScore(player1: p1, player2: p2))
            state.player2GamesWon += 1
            state.player1Points = 0; state.player2Points = 0
            if state.player2GamesWon >= gamesToWin {
                state.matchCompleted = true; state.wonByPlayer1 = false; state.isMatchActive = false
            }
        }
    }

    private func swapPlayers() {
        WKInterfaceDevice.current().play(.click)
        sync.updateState { state in
            swap(&state.player1Name, &state.player2Name)
            swap(&state.player1Points, &state.player2Points)
            swap(&state.player1GamesWon, &state.player2GamesWon)
            state.completedGameScores = state.completedGameScores.map { GameScore(player1: $0.player2, player2: $0.player1) }
            state.isPlayer1Serving.toggle()
        }
    }

    private func circleControl(icon: String, dimmed: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(dimmed ? .white.opacity(0.2) : .white.opacity(0.85))
                .frame(width: 32, height: 32)
                .background(Circle().fill(WatchUI.cardFill))
                .overlay(Circle().stroke(WatchUI.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var scoreboard: some View {
        VStack(spacing: 4) {
            scoreRow(name: displayName1, points: state.player1Points, isServing: state.isPlayer1Serving)
            Rectangle().fill(WatchUI.line).frame(height: 1)
            scoreRow(name: displayName2, points: state.player2Points, isServing: !state.isPlayer1Serving)
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: WatchUI.corner, style: .continuous).fill(WatchUI.navy))
        .overlay(RoundedRectangle(cornerRadius: WatchUI.corner, style: .continuous).stroke(WatchUI.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayName1) \(state.player1Points), \(displayName2) \(state.player2Points)")
    }

    private func scoreRow(name: String, points: Int, isServing: Bool) -> some View {
        HStack(spacing: 8) {
            Group {
                if isServing { WatchPickleballIcon(size: 12) }
                else { Color.clear.frame(width: 12, height: 12) }
            }
            Text(name).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Text("\(points)").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(isServing ? WatchUI.accent : .white).monospacedDigit().contentTransition(.numericText())
        }
    }
}

// MARK: - Match Result (Clean & Premium)
struct WatchMatchResultView: View {
    let didWin: Bool
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: didWin ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 48)).foregroundColor(didWin ? WatchUI.accent : WatchUI.muted).symbolRenderingMode(.hierarchical)
            Text(didWin ? "VICTORY" : "DEFEAT")
                .font(.system(size: 32, weight: .black, design: .rounded)).tracking(1.5).foregroundColor(.white)
            Text("Detailed stats are ready\non your iPhone.")
                .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundColor(WatchUI.muted).multilineTextAlignment(.center)
            Spacer()
            Button(action: onDismiss) {
                Text("NEW MATCH")
                    .font(.system(size: 14, weight: .bold, design: .rounded)).tracking(0.8).foregroundColor(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: WatchUI.corner, style: .continuous).fill(WatchUI.accent))
            }
            .buttonStyle(NativePressStyle()).padding(.horizontal, 12).padding(.bottom, 8)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}

// MARK: - WatchMatchSync (Hoisted Serve Stats)
@MainActor
final class WatchMatchSync: NSObject, ObservableObject {
    @Published var state = MatchState.watchIdle()
    
    // PRO: Hoisted so ContentView can read them for the payload
    @Published var servePointsPlayed: Int = 0
    @Published var servePointsWon: Int = 0

    private var isApplyingRemote = false
    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    override init() { super.init(); activateIfNeeded() }
    func activateIfNeeded() { guard let session else { return }; session.delegate = self; session.activate() }

    func resetServeStats() { servePointsPlayed = 0; servePointsWon = 0 }
    func setServeStats(played: Int, won: Int) { servePointsPlayed = played; servePointsWon = won }

    func updateState(_ update: (inout MatchState) -> Void) {
        var next = state; update(&next); next.timestamp = Date().timeIntervalSince1970
        state = next; send(state: next)
    }
    
    func replaceState(with newState: MatchState) {
        var next = newState; next.timestamp = Date().timeIntervalSince1970
        state = next; send(state: next)
    }
    
    func startWatchInitiatedMatch(totalGames: Int, targetScore: Int, isPlayer1Serving: Bool) {
        var next = MatchState.watchIdle()
        next.matchID = UUID(); next.timestamp = Date().timeIntervalSince1970; next.isMatchActive = true
        next.player1Name = "YOU"; next.player2Name = "OPPONENT"
        next.totalGames = max(1, totalGames); next.targetScore = max(1, targetScore); next.isPlayer1Serving = isPlayer1Serving
        state = next; send(state: next)
    }
    
    func endMatch() {
        updateState { state in
            state.isMatchActive = false; state.matchCompleted = true; state.wonByPlayer1 = false
        }
    }
    
    func resetForNewMatch() { state = MatchState.watchIdle(); resetServeStats() }

    private func send(state: MatchState) {
        guard !isApplyingRemote, let session else { return }
        let payload = state.watchDictionary
        if session.isReachable { session.sendMessage(payload, replyHandler: nil, errorHandler: nil) }
        try? session.updateApplicationContext(payload)
    }
    
    func sendGameComplete(payload: [String: Any]) { session?.transferUserInfo(payload) }

    private func handleIncoming(_ message: [String: Any]) {
        guard let type = message["type"] as? String, type == "phoneMatchState", let newState = MatchState(message: message) else { return }
        if newState.matchCompleted && !state.isMatchActive && newState.matchID != state.matchID { return }
        isApplyingRemote = true; state = newState; isApplyingRemote = false
    }
}

extension WatchMatchSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error { print("WatchMatchSync: activation error: \(error.localizedDescription)") }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { Task { @MainActor in self.handleIncoming(message) } }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { Task { @MainActor in self.handleIncoming(applicationContext) } }
}

extension MatchState {
    static func watchIdle() -> MatchState {
        MatchState(
            matchID: UUID(),
            timestamp: Date().timeIntervalSince1970,
            isMatchActive: false,
            player1Name: "PLAYER1",
            player2Name: "PLAYER2",
            player1Points: 0,
            player2Points: 0,
            player1GamesWon: 0,
            player2GamesWon: 0,
            isPlayer1Serving: true,
            totalGames: 1,
            targetScore: 11,
            matchCompleted: false,
            wonByPlayer1: false,
            completedGameScores: [],
            servePointsPlayed: 0,
            servePointsWon: 0
        )
    }
    
    var watchDictionary: [String: Any] {
        var payload = dictionary
        payload["type"] = "watchMatchState"
        payload["timestamp"] = timestamp
        return payload
    }
}
// MARK: - Supporting Views (Idle, Setup, Background, Icons)
struct WatchIdleView: View {
    let onStartMatch: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "applewatch.side.right").font(.system(size: 32)).foregroundColor(WatchUI.muted).padding(.bottom, 4)
            Button(action: onStartMatch) {
                Text("START MATCH").font(.system(size: 15, weight: .bold, design: .rounded)).tracking(1.0).foregroundColor(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: WatchUI.corner, style: .continuous).fill(WatchUI.accent))
            }.buttonStyle(NativePressStyle())
            Text("or start on your phone").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundColor(WatchUI.muted)
            Spacer()
        }.padding(.horizontal, 14)
    }
}

struct WatchMatchSetupView: View {
    let onComplete: (_ games: Int, _ points: Int, _ isServingFirst: Bool) -> Void
    let onCancel: () -> Void
    @State private var currentPage = 0
    @State private var selectedGames: Int?
    @State private var selectedPoints: Int?

    var body: some View {
        ZStack {
            TabView(selection: $currentPage) {
                setupPage(title: "GAMES TO WIN", options: [("1", 1), ("2", 2), ("3", 3)], selected: selectedGames, onSelect: { selectedGames = $0; advance() }).tag(0)
                setupPage(title: "POINTS / GAME", options: [("11", 11), ("21", 21), ("31", 31)], selected: selectedPoints, onSelect: { selectedPoints = $0; advance() }).tag(1)
                servingPage.tag(2)
            }.tabViewStyle(.verticalPage).animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentPage)
            VStack {
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 22)).symbolRenderingMode(.palette).foregroundStyle(.white.opacity(0.6), WatchUI.navy.opacity(0.4))
                    }.buttonStyle(.plain).padding(.leading, 4).padding(.top, 2).accessibilityLabel("Cancel setup")
                    Spacer()
                }
                Spacer()
            }
        }
    }
    private func advance() { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { if currentPage < 2 { currentPage += 1 } } }
    private func courtPage<Content: View>(title: String, @ViewBuilder controls: () -> Content) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) { WatchUI.courtBlue; Text(title).font(.system(size: 12, weight: .bold, design: .rounded)).tracking(1.5).foregroundColor(.white).padding(.bottom, 8) }.frame(maxHeight: .infinity)
            Rectangle().fill(Color.white).frame(height: 2)
            ZStack { WatchUI.navy; controls().padding(.horizontal, 10) }.frame(height: 78)
            Rectangle().fill(Color.white).frame(height: 2)
            WatchUI.courtBlue.frame(maxHeight: .infinity)
        }.ignoresSafeArea()
    }
    private func setupPage<T: Equatable>(title: String, options: [(label: String, value: T)], selected: T?, onSelect: @escaping (T) -> Void) -> some View {
        courtPage(title: title) {
            HStack(spacing: 6) {
                ForEach(0..<options.count, id: \.self) { i in
                    let option = options[i]; let isSelected = (option.value == selected)
                    Button { WKInterfaceDevice.current().play(.click); onSelect(option.value) } label: {
                        Text(option.label).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(isSelected ? .black : .white)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isSelected ? WatchUI.accent : Color.white.opacity(0.12)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(isSelected ? 0.0 : 0.08), lineWidth: 1))
                    }.buttonStyle(NativePressStyle()).accessibilityLabel("\(title): \(option.label)")
                }
            }
        }
    }
    private var servingPage: some View {
        courtPage(title: "SERVE FIRST?") {
            HStack(spacing: 8) {
                servingButton(label: "NO", highlight: false) { finish(serving: false) }
                servingButton(label: "YES", highlight: true) { finish(serving: true) }
            }
        }
    }
    private func servingButton(label: String, highlight: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(highlight ? .black : .white)
                .frame(maxWidth: .infinity).frame(height: 46)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(highlight ? WatchUI.accent : Color.white.opacity(0.12)))
        }.buttonStyle(NativePressStyle())
    }
    private func finish(serving: Bool) { WKInterfaceDevice.current().play(.start); onComplete(selectedGames ?? 1, selectedPoints ?? 11, serving) }
}

struct WatchCourtBackground: View {
    var body: some View {
        VStack(spacing: 0) {
            WatchUI.courtBlue.frame(maxHeight: .infinity)
            Rectangle().fill(Color.white).frame(height: 2)
            WatchUI.navy.frame(maxHeight: .infinity)
            Rectangle().fill(Color.white).frame(height: 2)
            WatchUI.courtBlue.frame(maxHeight: .infinity)
        }
    }
}

struct WatchPickleballIcon: View {
    let size: CGFloat
    private var holeSize: CGFloat { size * 0.12 }
        
        // ✅ FIXED: Each property is now on its own line
        private var offset1: CGFloat { size * 0.25 }
        private var offset2: CGFloat { size * 0.3 }
        private var offset3: CGFloat { size * 0.4 }
        
    var body: some View {
        Circle().fill(WatchUI.accent).frame(width: size, height: size).overlay(pickleballHoles)
    }
    private var pickleballHoles: some View {
        ZStack {
            ForEach(holePositions, id: \.id) { position in
                Circle().fill(Color.black.opacity(0.28)).frame(width: holeSize, height: holeSize).offset(x: position.x, y: position.y)
            }
        }
    }
    private var holePositions: [(id: Int, x: CGFloat, y: CGFloat)] {
        [(0, -offset1, -offset1), (1, 0, -offset2), (2, offset1, -offset1), (3, -offset3, 0), (4, 0, 0), (5, offset3, 0), (6, -offset1, offset1), (7, 0, offset2), (8, offset1, offset1)]
    }
}

struct WatchPickleballToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { isOn.toggle() } } label: {
            ZStack(alignment: isOn ? .top : .bottom) {
                Capsule().fill(Color(red: 0.22, green: 0.22, blue: 0.26)).overlay(Capsule().stroke(WatchUI.line, lineWidth: 1))
                WatchPickleballIcon(size: 26).padding(.vertical, 4)
            }
        }.buttonStyle(.plain)
    }
}

private struct NativePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.94 : 1.0).opacity(configuration.isPressed ? 0.85 : 1.0).animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    ContentView().environmentObject(WatchMatchSync()).environmentObject(MotionManager())
}
