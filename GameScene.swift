import SwiftUI
import Combine
import WatchConnectivity

// MARK: - Animated Player Character
struct AnimatedPlayerCharacter: View {
    let isTopSide: Bool
    let size: CGFloat
    let isServing: Bool
    @State private var bounceOffset: CGFloat = 0
    @State private var swayAngle: Double = 0
    @State private var paddleTilt: Double = 0
    @State private var ballBounceOffset: CGFloat = 0
    
    private let bounceAmplitude: CGFloat = 4
    private let swayAmplitude: Double = 6
    private let paddleTiltAmplitude: Double = 8
    private let ballBounceHeight: CGFloat = 10
    var body: some View {
        ZStack {
            ZStack {
                paddleOnly
                if isServing {
                    servingBallBounce
                }
            }
            .scaleEffect(isTopSide ? 1 : -1)
        }
        .frame(width: size, height: size * 1.4)
        .onAppear { startAnimations() }
        .onChange(of: isServing) {
            if isServing {
                startBallBounceAnimation()
            } else {
                ballBounceOffset = 0
            }
        }
    }
    private var paddleOnly: some View {
        let rotation = isTopSide
            ? -18 + (isServing ? (swayAngle + paddleTilt) : 0)
            : 18 - (isServing ? (swayAngle + paddleTilt) : 0)
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.38, blue: 0.70),
                            Color(red: 0.08, green: 0.24, blue: 0.50)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.22, height: size * 0.34)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                        .stroke(Color.white.opacity(0.9), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                .offset(y: -size * 0.06)

            RoundedRectangle(cornerRadius: size * 0.03, style: .continuous)
                .fill(Color(red: 0.08, green: 0.18, blue: 0.32))
                .frame(width: size * 0.06, height: size * 0.16)
        }
        .rotationEffect(.degrees(rotation))
        .offset(
            x: size * 0.08,
            y: (isTopSide ? 1 : -1) * (size * 0.10 + (isServing ? bounceOffset * 0.2 : 0))
        )
    }
    private var servingBallBounce: some View {
        let ballSize = size * 0.12
        let paddleCenterX = size * 0.24
        let ballBaseY = (isTopSide ? 1 : -1) * (size * 0.20)

        return PickleballIcon(size: ballSize)
            .offset(x: paddleCenterX, y: ballBaseY + (isTopSide ? 1 : -1) * ballBounceOffset)
    }
    private func startAnimations() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            bounceOffset = bounceAmplitude
        }
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            swayAngle = swayAmplitude
        }
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
            paddleTilt = paddleTiltAmplitude
        }
        if isServing {
            startBallBounceAnimation()
        }
    }
    private func startBallBounceAnimation() {
        withAnimation(.easeInOut(duration: 0.42).repeatForever(autoreverses: true)) {
            ballBounceOffset = ballBounceHeight
        }
    }
}

// MARK: - Immersive Premium Match Won View
struct MatchWonCard: View {
    let winnerName: String
    let score: String
    let didWin: Bool
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var animateContent = false

    private var parsedScore: (left: String, right: String)? {
        let parts = score.split(separator: "-").map { String($0) }
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    private let courtAtmosphereColor = Color(red: 0.36, green: 0.55, blue: 0.72)

    var body: some View {
        ZStack {
            courtAtmosphereColor
                .ignoresSafeArea()
                .overlay(
                    RadialGradient(
                        colors: [.white.opacity(0.18), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 340
                    )
                    .ignoresSafeArea()
                )

            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: geo.size.height * 0.14)

                    Image("Court")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width * 0.62)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .black, location: 0.12),
                                    .init(color: .black, location: 0.88),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .compositingGroup()
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .black, location: 0.10),
                                    .init(color: .black, location: 0.90),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .blur(radius: appeared ? 0 : 4)
                        .scaleEffect(appeared ? 1.0 : 0.97)
                        .animation(.easeOut(duration: 0.6).delay(0.1), value: appeared)

                    Spacer()
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("MATCH SUMMARY")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .tracking(5.0)
                        .foregroundColor(.white.opacity(0.70))

                    Text(didWin ? "VICTORY" : "DEFEAT")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .tracking(-0.5)
                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
                }
                .padding(.top, 40)
                .opacity(animateContent ? 1.0 : 0.0)
                .offset(y: animateContent ? 0 : -10)

                Spacer()

                VStack(spacing: 28) {
                    VStack(spacing: 18) {
                        VStack(spacing: 4) {
                            Text(winnerName.uppercased())
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)

                            Text(didWin ? "CHAMPIONSHIP POINT" : "PLAYED TO THE LIMIT")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(2.0)
                                .foregroundColor(didWin
                                    ? Color.white.opacity(0.9)
                                    : Color.white.opacity(0.7))
                        }

                        HStack(spacing: 0) {
                            if let parsed = parsedScore {
                                scoreSegment(label: "YOU", value: parsed.left, isActive: didWin)

                                RoundedRectangle(cornerRadius: 0.5)
                                    .fill(Color.white.opacity(0.15))
                                    .frame(width: 1, height: 38)

                                scoreSegment(label: "OPPONENT", value: parsed.right, isActive: !didWin)
                            } else {
                                Text(score)
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color.black.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                    .padding(.horizontal, 28)

                    Button(action: onDismiss) {
                        Text("Back to Main Menu")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(courtAtmosphereColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(Color.white)
                            )
                            .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)
                    }
                    .buttonStyle(FluidTouchMechanicStyle())
                    .accessibilityLabel("Back to main menu")
                    .padding(.horizontal, 28)
                }
                .padding(.bottom, 40)
                .opacity(animateContent ? 1.0 : 0.0)
                .offset(y: animateContent ? 0 : 16)
            }
        }
        .onAppear {
            appeared = true
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.15)) {
                animateContent = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(didWin ? "Match won" : "Match lost"). Final score \(score)")
    }
    private func scoreSegment(label: String, value: String, isActive: Bool) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.4))

            Text(value)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundColor(isActive ? .white : .white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Premium Touch Springs
struct FluidTouchMechanicStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.94 : 1.0)
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Game Scene View
struct GameSceneView: View {
    let isPlayer1ServingInitially: Bool
    let totalGames: Int
    let targetScore: Int
    @State private var isPlayer1Serving: Bool
    @State private var player1Name: String
    @State private var player2Name: String
    @State private var player1GamesWon: Int = 0
    @State private var player2GamesWon: Int = 0
    @State private var player1Points: Int = 0
    @State private var player2Points: Int = 0
    @State private var currentGameNumber: Int = 1
    @State private var showGameWonAlert: Bool = false
    @State private var showMatchWonAlert: Bool = false
    @State private var showExitAlert: Bool = false
    @State private var gameWinner: String = ""
    @State private var matchWinner: String = ""
    @State private var didProfilePlayerWinMatch: Bool = false
    @State private var finalGameScore: (player1: Int, player2: Int) = (0, 0)
    @State private var completedGameScores: [GameScore] = []
    @State private var servePointsPlayed: Int = 0
    @State private var servePointsWon: Int = 0
    private let matchID = UUID()
    @State private var undoStack: [MatchSnapshot] = []
    private let maxUndoDepth = 10
    private struct MatchSnapshot {
        let player1Points: Int
        let player2Points: Int
        let player1GamesWon: Int
        let player2GamesWon: Int
        let isPlayer1Serving: Bool
        let currentGameNumber: Int
        let completedGameScores: [GameScore]
    }
    
    @ObservedObject private var sync = WatchConnectivityManager.shared
    @State private var ignoreSyncUpdates: Bool = false
    @State private var didRecordRemoteMatch: Bool = false
    @State private var lastAppliedTimestamp: TimeInterval = 0
    
    @Environment(\.dismiss) var dismiss
    
    var onMatchComplete: ((String, String, Int, Int, [GameScore]) -> Void)? = nil
    
    init(
        player1Name: String,
        player2Name: String,
        isPlayer1ServingInitially: Bool,
        totalGames: Int,
        targetScore: Int,
        onMatchComplete: ((String, String, Int, Int, [GameScore]) -> Void)? = nil
    ) {
        self.isPlayer1ServingInitially = isPlayer1ServingInitially
        self.totalGames = totalGames
        self.targetScore = targetScore
        self.onMatchComplete = onMatchComplete
        
        _isPlayer1Serving = State(initialValue: isPlayer1ServingInitially)
        _player1Name = State(initialValue: player1Name)
        _player2Name = State(initialValue: player2Name)
    }
    
    private var showGamesColumns: Bool { totalGames > 1 }
    private var gamesToWin: Int { (totalGames / 2) + 1 }
    
    private struct SyncTrigger: Equatable {
        let player1Name: String
        let player2Name: String
        let player1Points: Int
        let player2Points: Int
        let player1GamesWon: Int
        let player2GamesWon: Int
        let isPlayer1Serving: Bool
        let completedGameScores: [GameScore]
    }
    private var syncTrigger: SyncTrigger {
        SyncTrigger(
            player1Name: player1Name,
            player2Name: player2Name,
            player1Points: player1Points,
            player2Points: player2Points,
            player1GamesWon: player1GamesWon,
            player2GamesWon: player2GamesWon,
            isPlayer1Serving: isPlayer1Serving,
            completedGameScores: completedGameScores
        )
    }
    
    private var matchWonScore: String {
        "\(player1GamesWon)-\(player2GamesWon)"
    }
    
    private var canUndo: Bool {
        !undoStack.isEmpty
    }
    
    var body: some View {
        ZStack {
            courtBackground
                .blur(radius: showMatchWonAlert ? 4 : 0)
                .animation(.easeOut(duration: 0.25), value: showMatchWonAlert)
            
            courtCharacters
                .opacity(showMatchWonAlert ? 0.4 : 1)
                .animation(.easeOut(duration: 0.25), value: showMatchWonAlert)
            
            servingToggle
                .opacity(showMatchWonAlert ? 0.0 : 1)
                .animation(.easeOut(duration: 0.2), value: showMatchWonAlert)
            
            pointButton
                .opacity(showMatchWonAlert ? 0.0 : 1)
                .animation(.easeOut(duration: 0.2), value: showMatchWonAlert)
            
            topLeftControls
                .opacity(showMatchWonAlert ? 0.0 : 1)
                .animation(.easeOut(duration: 0.2), value: showMatchWonAlert)
            
            if showMatchWonAlert {
                MatchWonCard(
                    winnerName: matchWinner,
                    score: matchWonScore,
                    didWin: didProfilePlayerWinMatch,
                    onDismiss: {
                        onMatchComplete?(
                            player1Name,
                            player2Name,
                            player1GamesWon,
                            player2GamesWon,
                            completedGameScores
                        )
                        dismiss()
                    }
                )
            }
        }
        .alert("Game Won!", isPresented: $showGameWonAlert) {
            Button("Next Game") {
                startNextGame()
            }
        } message: {
            Text("\(gameWinner) won game \(currentGameNumber - 1)!\n\nFinal Score: \(finalGameScore.player1)-\(finalGameScore.player2)")
        }
        .alert("End Match?", isPresented: $showExitAlert) {
            Button("Cancel", role: .cancel) {}
            Button("End Match", role: .destructive) {
                sendSync(isMatchActive: false)
                dismiss()
            }
        } message: {
            Text("Match won't be saved. Are you sure?")
        }
        .onAppear {
            sendSync(isMatchActive: true)
        }
        .onDisappear {
            sendSync(isMatchActive: false)
        }
        .onReceive(sync.$liveMatchState.compactMap { $0 }) { state in
            applyRemoteState(state)
        }
        .onChange(of: syncTrigger) {
            sendSync(isMatchActive: true)
        }
    }
    
    // MARK: - Subviews
    
    private var topLeftControls: some View {
        VStack {
            HStack(spacing: 10) {
                Button(action: { showExitAlert = true }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 45, height: 45)
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .accessibilityLabel("End match")
                
                Button(action: undoLastPoint) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 45, height: 45)
                        Image(systemName: "arrow.uturn.left")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .opacity(canUndo ? 1.0 : 0.35)
                .disabled(!canUndo)
                .accessibilityLabel("Undo last point")
                
                Spacer()
            }
            .padding(.leading, 14)
            
            Spacer()
        }
    }
    private var courtBackground: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Rectangle().fill(Color(red: 0.18, green: 0.38, blue: 0.58))
                    Rectangle().fill(Color.white).frame(width: 5)
                    Rectangle().fill(Color(red: 0.20, green: 0.42, blue: 0.62))
                }
                .frame(height: geometry.size.height * 0.375)
                
                Rectangle().fill(Color.white).frame(height: 5)
                
                ZStack {
                    Rectangle()
                        .fill(Color(red: 0.08, green: 0.12, blue: 0.24))
                        .frame(height: geometry.size.height * 0.249)
                    
                    ScoreboardView(
                        showGamesColumns: showGamesColumns,
                        totalGames: totalGames,
                        currentGameNumber: currentGameNumber,
                        isPlayer1Serving: $isPlayer1Serving,
                        player1Name: $player1Name,
                        player2Name: $player2Name,
                        player1GamesWon: $player1GamesWon,
                        player2GamesWon: $player2GamesWon,
                        player1Points: $player1Points,
                        player2Points: $player2Points,
                        completedGameScores: $completedGameScores,
                        onSwapPlayers: { swapPlayersAction() }
                    )
                    .frame(
                        width: geometry.size.width * 0.75,
                        height: geometry.size.height * 0.18
                    )
                }
                
                Rectangle().fill(Color.white).frame(height: 5)
                
                HStack(spacing: 0) {
                    Rectangle().fill(Color(red: 0.16, green: 0.38, blue: 0.56))
                    Rectangle().fill(Color.white).frame(width: 5)
                    Rectangle().fill(Color(red: 0.18, green: 0.42, blue: 0.60))
                }
                .frame(height: geometry.size.height * 0.375)
            }
        }
        .ignoresSafeArea()
    }
    
    private var courtCharacters: some View {
        GeometryReader { geometry in
            let topCourtHeight = geometry.size.height * 0.375
            let bottomCourtHeight = geometry.size.height * 0.375
            let characterSize: CGFloat = min(geometry.size.width * 0.22, 90)
            
            ZStack {
                AnimatedPlayerCharacter(isTopSide: true, size: characterSize, isServing: isPlayer1Serving)
                    .position(x: geometry.size.width / 2, y: topCourtHeight / 2)
                
                AnimatedPlayerCharacter(isTopSide: false, size: characterSize, isServing: !isPlayer1Serving)
                    .position(x: geometry.size.width / 2, y: geometry.size.height - bottomCourtHeight / 2)
            }
        }
        .allowsHitTesting(false)
    }
    
    private var servingToggle: some View {
        VStack {
            Spacer()
            HStack {
                PickleballToggle(isOn: $isPlayer1Serving)
                    .padding(.leading, 24)
                    .padding(.bottom, 32)
                Spacer()
            }
        }
    }
    // Profile on side 1 or 2 from profilePlayerSide(...)
    // isProfileServing = (side == 1 && isPlayer1Serving) || (side == 2 && !isPlayer1Serving)
    // profileWonPoint  = (side == 1 && awardedToPlayer1) || (side == 2 && !awardedToPlayer1)

    
    private var pointButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                
                Button(action: awardPoint) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: [.white, Color(red: 0.95, green: 0.95, blue: 0.95)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.08, green: 0.12, blue: 0.24).opacity(0.3),
                                                Color(red: 0.08, green: 0.12, blue: 0.24).opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                    
                        Text("+1")
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .foregroundColor(Color(red: 0.08, green: 0.12, blue: 0.24))
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Award point to \(isPlayer1Serving ? player1Name : player2Name)")
                .padding(.trailing, 14)
                .padding(.bottom, 42)
            }
        }
    }
    
    // MARK: - Game Logic
    
    private func swapPlayersAction() {
        swap(&player1Name, &player2Name)
        swap(&player1Points, &player2Points)
        swap(&player1GamesWon, &player2GamesWon)
        completedGameScores = completedGameScores.map { GameScore(player1: $0.player2, player2: $0.player1) }
        isPlayer1Serving.toggle()
    }
    
    private func currentMatchState(
        isMatchActive: Bool,
        matchCompleted: Bool = false,
        wonByPlayer1: Bool = false
    ) -> MatchState {
        MatchState(
            matchID: matchID,
            isMatchActive: isMatchActive,
            player1Name: player1Name,
            player2Name: player2Name,
            player1Points: player1Points,
            player2Points: player2Points,
            player1GamesWon: player1GamesWon,
            player2GamesWon: player2GamesWon,
            isPlayer1Serving: isPlayer1Serving,
            totalGames: totalGames,
            targetScore: targetScore,
            matchCompleted: matchCompleted,
            wonByPlayer1: wonByPlayer1,
            completedGameScores: completedGameScores
        )
    }
    
    private func sendSync(
        isMatchActive: Bool,
        matchCompleted: Bool = false,
        wonByPlayer1: Bool = false
    ) {
        guard !ignoreSyncUpdates else { return }
        sync.sendPhoneMatchState(currentMatchState(
            isMatchActive: isMatchActive,
            matchCompleted: matchCompleted,
            wonByPlayer1: wonByPlayer1
        ))
    }
    
    private func applyRemoteState(_ state: MatchState) {
        guard state.matchID == matchID else { return }
        guard state.timestamp > lastAppliedTimestamp else { return }
        lastAppliedTimestamp = state.timestamp
        
        ignoreSyncUpdates = true
        defer {
            DispatchQueue.main.async { ignoreSyncUpdates = false }
        }
        
        player1Name = state.player1Name
        player2Name = state.player2Name
        player1Points = state.player1Points
        player2Points = state.player2Points
        player1GamesWon = state.player1GamesWon
        player2GamesWon = state.player2GamesWon
        isPlayer1Serving = state.isPlayer1Serving
        completedGameScores = state.completedGameScores
        if let last = state.completedGameScores.last {
            finalGameScore = (last.player1, last.player2)
        }
        currentGameNumber = max(1, state.player1GamesWon + state.player2GamesWon + 1)
        
        if state.matchCompleted, !didRecordRemoteMatch {
            didRecordRemoteMatch = true
            let wonByPlayer1 = state.wonByPlayer1
            matchWinner = wonByPlayer1 ? player1Name : player2Name
            recordMatchIfProfilePlaying(wonByPlayer1: wonByPlayer1)
            showMatchWonAlert = true
        }
    }
    
    private func pushUndoSnapshot() {
        let snapshot = MatchSnapshot(
            player1Points: player1Points,
            player2Points: player2Points,
            player1GamesWon: player1GamesWon,
            player2GamesWon: player2GamesWon,
            isPlayer1Serving: isPlayer1Serving,
            currentGameNumber: currentGameNumber,
            completedGameScores: completedGameScores
        )
        undoStack.append(snapshot)
        if undoStack.count > maxUndoDepth {
            undoStack.removeFirst()
        }
    }
    
    private func awardPoint() {
        pushUndoSnapshot()
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            if isPlayer1Serving {
                player1Points += 1
            } else {
                player2Points += 1
            }
            checkGameWon()
        }
    }
    
    private func undoLastPoint() {
        guard let snapshot = undoStack.popLast() else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            player1Points = snapshot.player1Points
            player2Points = snapshot.player2Points
            player1GamesWon = snapshot.player1GamesWon
            player2GamesWon = snapshot.player2GamesWon
            isPlayer1Serving = snapshot.isPlayer1Serving
            currentGameNumber = snapshot.currentGameNumber
            completedGameScores = snapshot.completedGameScores
        }
    }
    
    private func checkGameWon() {
        let p1Score = player1Points
        let p2Score = player2Points
        
        let player1WinsGame = p1Score >= targetScore && (p1Score - p2Score) >= 2
        let player2WinsGame = p2Score >= targetScore && (p2Score - p1Score) >= 2
        
        if player1WinsGame {
            finalGameScore = (p1Score, p2Score)
            completedGameScores.append(GameScore(player1: p1Score, player2: p2Score))
            player1GamesWon += 1
            gameWinner = player1Name
            
            if player1GamesWon >= gamesToWin {
                matchWinner = player1Name
                recordMatchIfProfilePlaying(wonByPlayer1: true)
                player1Points = 0
                player2Points = 0
                showMatchWonAlert = true
                sendSync(isMatchActive: true, matchCompleted: true, wonByPlayer1: true)
            } else {
                player1Points = 0
                player2Points = 0
                currentGameNumber += 1
                showGameWonAlert = true
            }
        } else if player2WinsGame {
            finalGameScore = (p1Score, p2Score)
            completedGameScores.append(GameScore(player1: p1Score, player2: p2Score))
            player2GamesWon += 1
            gameWinner = player2Name
            
            if player2GamesWon >= gamesToWin {
                matchWinner = player2Name
                recordMatchIfProfilePlaying(wonByPlayer1: false)
                player1Points = 0
                player2Points = 0
                showMatchWonAlert = true
                sendSync(isMatchActive: true, matchCompleted: true, wonByPlayer1: false)
            } else {
                player1Points = 0
                player2Points = 0
                currentGameNumber += 1
                showGameWonAlert = true
            }
        }
    }
    
    private func startNextGame() {
        if let lastGame = completedGameScores.last {
            isPlayer1Serving = lastGame.player1 > lastGame.player2
        } else {
            isPlayer1Serving.toggle()
        }
    }
    
    private func recordMatchIfProfilePlaying(wonByPlayer1: Bool) {
        let didWin = MatchRecorder.recordIfProfilePlaying(
            matchID: matchID,
            player1Name: player1Name,
            player2Name: player2Name,
            player1GamesWon: player1GamesWon,
            player2GamesWon: player2GamesWon,
            completedGameScores: completedGameScores,
            wonByPlayer1: wonByPlayer1
        )
        didProfilePlayerWinMatch = didWin
    }
} // <--- THIS IS WHERE GameSceneView ENDS!

// MARK: - Scoreboard View
struct ScoreboardView: View {
    let showGamesColumns: Bool
    let totalGames: Int
    let currentGameNumber: Int
    @Binding var isPlayer1Serving: Bool
    @Binding var player1Name: String
    @Binding var player2Name: String
    @Binding var player1GamesWon: Int
    @Binding var player2GamesWon: Int
    @Binding var player1Points: Int
    @Binding var player2Points: Int
    @Binding var completedGameScores: [GameScore]
    
    var onSwapPlayers: () -> Void
    
    @State private var isSwapping: Bool = false
    
    private var hasCompletedGames: Bool {
        showGamesColumns && !completedGameScores.isEmpty
    }
    
    private var namesWidthFraction: CGFloat {
        guard showGamesColumns else { return 0.42 }
        return hasCompletedGames ? 0.36 : 0.50
    }
    
    private var pointsWidthFraction: CGFloat {
        guard showGamesColumns else { return 0.58 }
        return hasCompletedGames ? 0.32 : 0.50
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                playerNamesSection(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                
                if hasCompletedGames {
                    completedGamesHistory(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                }
                
                currentPointsColumn(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: completedGameScores.count)
        }
    }
    
    private func playerNamesSection(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            VStack(spacing: 0) {
                playerNameRow(name: player1Name, isServing: isPlayer1Serving, height: height / 2)
                playerNameRow(name: player2Name, isServing: !isPlayer1Serving, height: height / 2)
            }
            
            HStack {
                SwapButton(isSwapping: isSwapping, action: triggerSwap)
                    .offset(x: -20)
                Spacer()
            }
        }
        .frame(width: width * namesWidthFraction)
        .background(Color(red: 0.08, green: 0.12, blue: 0.24))
    }
    
    private func playerNameRow(name: String, isServing: Bool, height: CGFloat) -> some View {
        HStack(spacing: 8) {
            if isServing {
                PickleballIcon(size: 18)
            }
            Text(name)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer()
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .padding(.leading, 12)
    }
    
    private func completedGamesHistory(width: CGFloat, height: CGFloat) -> some View {
        let count = max(completedGameScores.count, 1)
        let sectionWidth = width * 0.30
        let chipWidth = min(48, (sectionWidth - CGFloat(count - 1) * 8) / CGFloat(count))
        
        return HStack(spacing: 8) {
            ForEach(Array(completedGameScores.enumerated()), id: \.offset) { _, game in
                completedGameChip(
                    game: game,
                    width: chipWidth,
                    height: height
                )
            }
        }
        .frame(width: sectionWidth, alignment: .center)
        .padding(.horizontal, 4)
    }
    
    private func completedGameChip(
        game: GameScore,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let p1Won = game.player1 > game.player2
        let p2Won = game.player2 > game.player1
        
        return VStack(spacing: 0) {
            Text("\(game.player1)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white.opacity(p1Won ? 1 : 0.55))
                .frame(height: height / 2)
                .frame(maxWidth: .infinity)
            
            Text("\(game.player2)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white.opacity(p2Won ? 1 : 0.55))
                .frame(height: height / 2)
                .frame(maxWidth: .infinity)
        }
        .frame(width: width)
        .transition(
            .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity
            )
        )
    }
    
    private func currentPointsColumn(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            scoreText(
                "\(player1Points)",
                color: Color(red: 0.15, green: 0.15, blue: 0.15),
                height: height
            )
            scoreText(
                "\(player2Points)",
                color: Color(red: 0.15, green: 0.15, blue: 0.15),
                height: height
            )
        }
        .frame(width: width * pointsWidthFraction)
        .background(Color.white)
    }
    
    private func scoreText(_ text: String, color: Color, height: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundColor(color)
            .frame(height: height / 2)
            .frame(maxWidth: .infinity)
            .contentTransition(.numericText())
    }
    
    private func triggerSwap() {
        guard !isSwapping else { return }
        isSwapping = true
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            onSwapPlayers()
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            await MainActor.run {
                isSwapping = false
            }
        }
    }
}

// MARK: - Swap Button
struct SwapButton: View {
    let isSwapping: Bool
    let action: () -> Void
    
    private let buttonSize: CGFloat = 36
    private let iconSize: CGFloat = 10
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: buttonSize, height: buttonSize)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                
                swapIcon
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Swap players")
    }
    
    private var swapIcon: some View {
        ZStack {
            Image(systemName: "arrow.up")
                .font(.system(size: iconSize, weight: .bold))
                .foregroundColor(.white)
                .offset(y: -4)
            
            Image(systemName: "arrow.down")
                .font(.system(size: iconSize, weight: .bold))
                .foregroundColor(.white)
                .offset(y: 4)
        }
        .rotationEffect(.degrees(isSwapping ? 180 : 0))
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isSwapping)
    }
}

// MARK: - Pickleball Icon
struct PickleballIcon: View {
    let size: CGFloat
    
    private var holeSize: CGFloat { size * 0.125 }
    private var offset1: CGFloat { size * 0.25 }
    private var offset2: CGFloat { size * 0.3 }
    private var offset3: CGFloat { size * 0.4 }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(pickleballGradient)
                .frame(width: size, height: size)
                .overlay(pickleballHoles)
                .overlay(pickleballHighlight)
                .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: 1)
        }
    }
    
    private var pickleballGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.6, green: 1.0, blue: 0.2),
                Color(red: 0.5, green: 0.9, blue: 0.15)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var pickleballHoles: some View {
        ZStack {
            ForEach(holePositions, id: \.id) { position in
                Circle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: holeSize, height: holeSize)
                    .offset(x: position.x, y: position.y)
            }
        }
    }
    
    private var pickleballHighlight: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [.white.opacity(0.4), Color.clear],
                    center: .topLeading,
                    startRadius: size * 0.15,
                    endRadius: size * 0.5
                )
            )
    }
    
    private var holePositions: [(id: Int, x: CGFloat, y: CGFloat)] {
        [
            (0, -offset1, -offset1),
            (1, 0, -offset2),
            (2, offset1, -offset1),
            (3, -offset3, 0),
            (4, 0, 0),
            (5, offset3, 0),
            (6, -offset1, offset1),
            (7, 0, offset2),
            (8, offset1, offset1)
        ]
    }
}

// MARK: - Pickleball Toggle
struct PickleballToggle: View {
    @Binding var isOn: Bool
    
    private let trackWidth: CGFloat = 56
    private let trackHeight: CGFloat = 120
    private let ballSize: CGFloat = 48
    private let animationDuration: Double = 0.3
    
    var body: some View {
        Button(action: toggleServing) {
            ZStack(alignment: isOn ? .top : .bottom) {
                track
                ball
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Toggle serving player")
    }
    
    private var track: some View {
        Capsule()
            .fill(Color(red: 0.25, green: 0.25, blue: 0.28))
            .frame(width: trackWidth, height: trackHeight)
            .overlay(trackBorder)
            .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
    }
    
    private var trackBorder: some View {
        Capsule()
            .stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.1), Color.black.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
    
    private var ball: some View {
        PickleballIcon(size: ballSize)
            .padding(.vertical, 4)
    }
    
    private func toggleServing() {
        withAnimation(.spring(response: animationDuration, dampingFraction: 0.7)) {
            isOn.toggle()
        }
    }
}

// MARK: - Preview
#Preview {
    GameSceneView(
        player1Name: "PLAYER1",
        player2Name: "PLAYER2",
        isPlayer1ServingInitially: true,
        totalGames: 3,
        targetScore: 11
    )
}
