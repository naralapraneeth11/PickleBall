import SwiftUI
import UIKit

// MARK: - Haptics
private enum Haptics {
    // Retain persistent single instances to eliminate heap allocation latency on taps
    private static let selectionFeedback = UISelectionFeedbackGenerator()
    private static let lightFeedback = UIImpactFeedbackGenerator(style: .light)
    private static let mediumFeedback = UIImpactFeedbackGenerator(style: .medium)
    

    static func selection() {
        selectionFeedback.selectionChanged()
        selectionFeedback.prepare() // Warm up engine for subsequent taps
    }
    
    static func light() {
        lightFeedback.impactOccurred()
        lightFeedback.prepare()
    }
    
    static func medium() {
        mediumFeedback.impactOccurred()
        mediumFeedback.prepare()
    }
}
// MARK: - Press Style
//
// Sub-frame touch-down feedback. Tight spring (response 0.14) so the
// visual reaction is essentially same-frame as the finger landing.
private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.14, dampingFraction: 0.86), value: configuration.isPressed)
    }
}

// Item-based cover wrapper guarantees `resuming` is passed as a parameter
// to the closure rather than captured from state at presentation time.
private struct TournamentPresentation: Identifiable {
    let id: UUID
    let resuming: SavedTournament?
}

struct PlayView: View {
    @AppStorage("profile_firstName") private var profileFirstName: String = ""
    @ObservedObject private var watchManager: WatchConnectivityManager = .shared
    @ObservedObject private var tournamentStore = TournamentStore.shared

    var onDismiss: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var showSpectatorTournament = false
    @State private var isSingles: Bool = true
    @State private var showGameScene: Bool = false
    @State private var tournamentPresentation: TournamentPresentation? = nil

    @State private var showAnalyticsPrompt: Bool = false
    @State private var hasPromptedAnalytics: Bool = false

    @State private var player1Name: String = ""
    @State private var player2Name: String = ""
    @State private var player3Name: String = ""
    @State private var player4Name: String = ""

    @State private var selectedBestOf: Int = 1
    @State private var pointsSelectionIndex: Int = 0
    @State private var customPointsInput: String = "15"
    @State private var firstServerIndex: Int = 0

    private let bestOfOptions = [1, 2, 3]
    private let pointsOptions = [11, 21, 31]

    private enum PlayerField: Hashable { case p1, p2, p3, p4 }
    @FocusState private var focusedField: PlayerField?

    // Design tokens
    private let lightGrey = Color(red: 0.95, green: 0.95, blue: 0.96)
    private let cardWhite = Color.white
    private let royalBlue = Color(red: 0.055, green: 0.102, blue: 0.275)
    private let fieldGrey = Color(red: 0.965, green: 0.967, blue: 0.973)
    private let mutedText = Color(red: 0.36, green: 0.39, blue: 0.47)
    private let stroke    = Color.black.opacity(0.08)

    // ONE spring. Used everywhere selection state animates. Matches Apple's
    // own segmented-control feel (fast, slightly damped, no wobble).
    private static let selectionSpring: Animation = .spring(response: 0.28, dampingFraction: 0.84)

    // MARK: - Derived

    private var effectivePoints: Int {
        if pointsSelectionIndex == 3 {
            let parsed = Int(customPointsInput) ?? 11
            return max(1, min(99, parsed))
        }
        return pointsOptions[pointsSelectionIndex]
    }

    private var customPointsInvalid: Bool {
        guard pointsSelectionIndex == 3 else { return false }
        let trimmed = customPointsInput.trimmingCharacters(in: .whitespaces)
        guard let n = Int(trimmed) else { return true }
        return n < 1
    }

    private var canStartMatch: Bool { !customPointsInvalid }

    private var leftPlayerName: String {
        if isSingles {
            return player1Name.isEmpty ? "PLAYER1" : player1Name.uppercased()
        }
        let p1 = player1Name.isEmpty ? "PLAYER1" : player1Name.uppercased()
        let p2 = player2Name.isEmpty ? "PLAYER2" : player2Name.uppercased()
        return "\(p1)/\(p2)"
    }

    private var rightPlayerName: String {
        if isSingles {
            return player2Name.isEmpty ? "PLAYER2" : player2Name.uppercased()
        }
        let p3 = player3Name.isEmpty ? "PLAYER3" : player3Name.uppercased()
        let p4 = player4Name.isEmpty ? "PLAYER4" : player4Name.uppercased()
        return "\(p3)/\(p4)"
    }

    private var headerFirstName: String {
        profileFirstName.trimmingCharacters(in: .whitespaces)
    }

    private var shouldPromptToWakeWatch: Bool {
        watchManager.isWatchPaired &&
        watchManager.isWatchAppInstalled &&
        !watchManager.isWatchReachable
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            lightGrey.ignoresSafeArea()

            VStack(spacing: 0) {
                courtStripHeader

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        mainCard
                        startMatchButton
                        tournamentButton

                        if !tournamentStore.incompleteTournaments.isEmpty {
                            savedTournamentsSection
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 100)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
            }

            if showAnalyticsPrompt {
                analyticsPrompt
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .fullScreenCover(isPresented: $showGameScene) {
            GameSceneView(
                player1Name: leftPlayerName,
                player2Name: rightPlayerName,
                isPlayer1ServingInitially: firstServerIndex == 0,
                totalGames: selectedBestOf,
                targetScore: effectivePoints
            )
        }
        .fullScreenCover(item: $tournamentPresentation) { presentation in
            if let saved = presentation.resuming {
                // Continue an existing tournament
                TournamentRunView(tournament: saved)
            } else {
                // Brand-new tournament → setup only
                TournamentSetupView()
            }
        }
        .fullScreenCover(isPresented: $showSpectatorTournament) {
            // Spectator path: still needs a real shared tournament to load.
            // Until live-share data exists, open setup (or wire a SavedTournament when you have one).
            // Example when you have a shared tournament:
            // TournamentRunView(tournament: sharedTournament, isReadOnly: true)
            TournamentSetupView()
        }
        .onAppear { applyDefaultPlayerName() }
    }

    // MARK: - Header

    private var headerView: some View {
        Group {
            if headerFirstName.isEmpty {
                Text("PLAY")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(headerFirstName)'s")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.55, green: 0.92, blue: 0.25))
                    Text("GAMEHOUSE")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundColor(.white)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headerFirstName.isEmpty ? "Play" : "\(headerFirstName)'s gamehouse")
    }

    // GeometryReader is used here intentionally and is fine — it only reads
    // its own bounds, not the screen's. (UIScreen.main.bounds is deprecated
    // for multi-scene apps; don't use it.) The header doesn't re-layout the
    // world when the keyboard appears because it sits above the ScrollView,
    // which absorbs the safe-area inset change.
    private var courtStripHeader: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color(red: 0.08, green: 0.12, blue: 0.24))
                    .frame(width: geo.size.width * 0.359)
                Rectangle()
                    .fill(.white)
                    .frame(width: 8)
                Rectangle()
                    .fill(Color(red: 0.18, green: 0.42, blue: 0.60))
                    .frame(width: geo.size.width * 0.62)
            }
            .frame(height: 146)
            .ignoresSafeArea(edges: .top)
            .overlay(
                HStack {
                    backButton.padding(.leading, 14)
                    Spacer()
                    headerView.padding(.trailing, 22)
                }
                .padding(.top, 25),
                alignment: .topLeading
            )
        }
        .frame(height: 146)
    }

    private var backButton: some View {
        Button {
            Haptics.light()
            if let onDismiss { onDismiss() } else { dismiss() }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Go back")
    }

    // MARK: - Main Card

    private var mainCard: some View {
        VStack(spacing: 20) {
            singlesDoublesToggle
            playerCards
            matchFormatPicker
            pointsPicker
            servingFirstPicker
        }
        .padding(.top, 18)
        .padding(.bottom, 22)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(cardWhite)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(stroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 16)
    }

    // MARK: - Singles / Doubles

    private var singlesDoublesToggle: some View {
        OffsetPillSegment(
            options: ["Singles", "Doubles"],
            selectedIndex: isSingles ? 0 : 1,
            height: 40,
            selectedFont: .system(size: 14, weight: .semibold),
            selectedColor: royalBlue,
            unselectedColor: mutedText,
            trackColor: fieldGrey,
            pillColor: .white,
            pillShadow: true
        ) { newIndex in
            Haptics.selection()
            // Animate locally so we don't trigger a root-level invalidation.
            withAnimation(Self.selectionSpring) {
                isSingles = (newIndex == 0)
                firstServerIndex = 0
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Player Cards

    private var playerCards: some View {
        HStack(spacing: 12) {
            editablePlayerCard(
                isLeft: true,
                player1Binding: $player1Name,
                player2Binding: $player2Name,
                primaryField: .p1,
                secondaryField: .p2
            )
            editablePlayerCard(
                isLeft: false,
                player1Binding: isSingles ? $player2Name : $player3Name,
                player2Binding: $player4Name,
                primaryField: isSingles ? .p2 : .p3,
                secondaryField: .p4
            )
        }
        .padding(.horizontal, 16)
        // Local animation — only this subtree re-evaluates when isSingles flips.
        .animation(Self.selectionSpring, value: isSingles)
    }

    // MARK: - Match Format

    private var matchFormatPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("GAMES TO WIN MATCH")
            OffsetPillSegment(
                options: ["1", "2", "3"],
                selectedIndex: bestOfOptions.firstIndex(of: selectedBestOf) ?? 0,
                height: 38,
                selectedFont: .system(size: 13, weight: .bold),
                selectedColor: royalBlue,
                unselectedColor: mutedText,
                trackColor: fieldGrey,
                pillColor: .white,
                pillShadow: false,
                pillStroke: stroke
            ) { newIndex in
                Haptics.selection()
                withAnimation(Self.selectionSpring) {
                    selectedBestOf = bestOfOptions[newIndex]
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Points

    private var pointsPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("GAME POINTS")
            OffsetPillSegment(
                options: pointsOptions.map { "\($0)" } + ["Custom"],
                selectedIndex: pointsSelectionIndex,
                height: 38,
                selectedFont: .system(size: 13, weight: .bold),
                selectedColor: royalBlue,
                unselectedColor: mutedText,
                trackColor: fieldGrey,
                pillColor: .white,
                pillShadow: false,
                pillStroke: stroke
            ) { newIndex in
                Haptics.selection()
                withAnimation(Self.selectionSpring) {
                    pointsSelectionIndex = newIndex
                }
            }

            if pointsSelectionIndex == 3 {
                customPointsRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        // Local animation so only this section re-evaluates on points change.
        .animation(Self.selectionSpring, value: pointsSelectionIndex)
    }

    private var customPointsRow: some View {
        HStack(spacing: 12) {
            Text("Points to play:")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(royalBlue)

            TextField("15", text: $customPointsInput)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(customPointsInvalid ? .red : royalBlue)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(fieldGrey)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            customPointsInvalid ? Color.red.opacity(0.55) : stroke,
                            lineWidth: customPointsInvalid ? 1.2 : 1
                        )
                )
                .frame(width: 82)
                .onChange(of: customPointsInput) { _, newValue in
                    // Strip non-digits, clamp to 2 chars. Empty allowed
                    // during editing; canStartMatch catches it on submit.
                    let filtered = newValue.filter { $0.isNumber }
                    let clamped = filtered.count > 2 ? String(filtered.prefix(2)) : filtered
                    if clamped != newValue { customPointsInput = clamped }
                }
                .accessibilityLabel("Custom points value")

            if customPointsInvalid {
                Text("Required")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.red.opacity(0.85))
                    .transition(.opacity)
            }
            Spacer()
        }
        .padding(.top, 8)
        .animation(Self.selectionSpring, value: customPointsInvalid)
    }

    // MARK: - Serving First

    private var servingFirstPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("SERVING FIRST")
            OffsetPillSegment(
                options: [leftPlayerName, rightPlayerName],
                selectedIndex: firstServerIndex,
                height: 38,
                selectedFont: .system(size: 12.5, weight: .semibold),
                selectedColor: royalBlue,
                unselectedColor: mutedText,
                trackColor: fieldGrey,
                pillColor: .white,
                pillShadow: false,
                pillStroke: stroke,
                minScale: 0.72
            ) { newIndex in
                Haptics.selection()
                withAnimation(Self.selectionSpring) {
                    firstServerIndex = newIndex
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Buttons

    private var startMatchButton: some View {
        Button {
            focusedField = nil
            Haptics.medium()
            if shouldPromptToWakeWatch && !hasPromptedAnalytics {
                hasPromptedAnalytics = true
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                    showAnalyticsPrompt = true
                }
            } else {
                showGameScene = true
            }
        } label: {
            Text("START MATCH")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(canStartMatch ? royalBlue : royalBlue.opacity(0.4))
                        .shadow(color: royalBlue.opacity(canStartMatch ? 0.35 : 0), radius: 12, x: 0, y: 6)
                )
        }
        .buttonStyle(PressStyle())
        .padding(.horizontal, 16)
        .disabled(!canStartMatch || showAnalyticsPrompt)
        .animation(Self.selectionSpring, value: canStartMatch)
        .accessibilityLabel("Start the match")
    }

    private var tournamentButton: some View {
        Button {
            Haptics.light()
            tournamentPresentation = TournamentPresentation(id: UUID(), resuming: nil)
        } label: {
            Text("TOURNAMENT")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundColor(royalBlue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(cardWhite)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(royalBlue.opacity(0.5), lineWidth: 1.5)
                )
        }
        .buttonStyle(PressStyle())
        .padding(.horizontal, 16)
        .accessibilityLabel("Tournament setup")
    }

    // MARK: - Saved Tournaments

    private var savedTournamentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("CONTINUE TOURNAMENT")
                .padding(.horizontal, 16)
            ForEach(tournamentStore.incompleteTournaments) { tournament in
                savedTournamentRow(tournament)
            }
        }
        .animation(Self.selectionSpring, value: tournamentStore.incompleteTournaments.count)
    }

    private func savedTournamentRow(_ tournament: SavedTournament) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tournament.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(royalBlue)
                    .lineLimit(1)
                Text("\(tournament.completedCount) of \(tournament.matches.count) matches complete · \(tournament.createdAt.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.system(size: 12))
                    .foregroundColor(mutedText)
            }

            Spacer()

            Button {
                Haptics.light()
                tournamentStore.delete(id: tournament.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(mutedText)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(fieldGrey).frame(width: 28, height: 28))
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Delete \(tournament.displayTitle)")

            Button {
                Haptics.medium()
                tournamentPresentation = TournamentPresentation(id: tournament.id, resuming: tournament)
            } label: {
                Text("Continue")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(royalBlue))
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Continue \(tournament.displayTitle)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cardWhite))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
    }

    // MARK: - Live / Shared Tournament

    private func sharedTournamentSection(_ t: SavedTournament) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("LIVE TOURNAMENT (SHARED WITH YOU)")
                .padding(.horizontal, 16)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.displayTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(royalBlue)
                        .lineLimit(1)
                    Text("\(t.completedCount) of \(t.matches.count) matches complete · live")
                        .font(.system(size: 12))
                        .foregroundColor(mutedText)
                }
                Spacer()
                Button {
                    Haptics.medium()
                    showSpectatorTournament = true
                } label: {
                    Text("Watch")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(royalBlue))
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Watch \(t.displayTitle) live")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cardWhite))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(stroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Analytics Prompt

    private var analyticsPrompt: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        showAnalyticsPrompt = false
                    }
                }

            VStack(spacing: 18) {
                Text("Enable live shot tracking on Watch?")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(royalBlue)
                    .multilineTextAlignment(.center)

                Text("Open Pickleball Scoreboard on your Apple Watch.\nIt will connect automatically when the match starts.\n\nForehands • Backhands • Rally length • Heart rate")
                    .font(.system(size: 13.5))
                    .foregroundColor(royalBlue.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineSpacing(1.8)

                HStack(spacing: 12) {
                    Button("Not now") {
                        Haptics.light()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            showAnalyticsPrompt = false
                        }
                        showGameScene = true
                    }
                    .buttonStyle(.bordered)

                    Button("Yes, enable") {
                        Haptics.medium()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            showAnalyticsPrompt = false
                        }
                        WatchConnectivityManager.shared.wakeWatchForMatch()
                        showGameScene = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(royalBlue)
                }
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(cardWhite)
                    .shadow(color: .black.opacity(0.22), radius: 20, x: 0, y: 12)
            )
        }
    }

    // MARK: - Editable Player Card
    //
    // Background and interaction layers are separated. The background gets
    // the focus glow + tiny scale; the TextField sits at native scale so
    // its hit target doesn't shift mid-tap. Doubles fields have explicit
    // heights — never .infinity in a stacked VStack, since that forces
    // SwiftUI to re-resolve heights on every layout pass.
    private func editablePlayerCard(
        isLeft: Bool,
        player1Binding: Binding<String>,
        player2Binding: Binding<String>,
        primaryField: PlayerField,
        secondaryField: PlayerField
    ) -> some View {
        let isCardActive: Bool = isSingles
            ? (focusedField == primaryField)
            : (focusedField == primaryField || focusedField == secondaryField)
        let baseTint = isLeft ? Color.blue : Color.red

        return ZStack {
            // Background layer — animates focus glow.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(fieldGrey)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isCardActive ? royalBlue : baseTint.opacity(0.45),
                            lineWidth: isCardActive ? 2.0 : 1.6
                        )
                )
                .scaleEffect(isCardActive ? 1.015 : 1.0)
                .shadow(
                    color: isCardActive ? royalBlue.opacity(0.15) : .clear,
                    radius: isCardActive ? 8 : 0,
                    x: 0, y: 4
                )
                .animation(.spring(response: 0.22, dampingFraction: 0.86), value: isCardActive)

            // Interaction layer — static scale.
            if isSingles {
                TextField("TAP TO ADD NAME", text: player1Binding)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(royalBlue)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .focused($focusedField, equals: primaryField)
                    .submitLabel(.done)
                    .onChange(of: player1Binding.wrappedValue) { _, newValue in
                        if newValue.count > 7 {
                            player1Binding.wrappedValue = String(newValue.prefix(7))
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .accessibilityLabel(isLeft ? "Player 1 name" : "Player 2 name")
            } else {
                VStack(spacing: 2) {
                    TextField("NAME", text: player1Binding)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(royalBlue)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .focused($focusedField, equals: primaryField)
                        .submitLabel(.next)
                        .onSubmit { focusedField = secondaryField }
                        .onChange(of: player1Binding.wrappedValue) { _, newValue in
                            if newValue.count > 7 {
                                player1Binding.wrappedValue = String(newValue.prefix(7))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .contentShape(Rectangle())

                    Text("/")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(royalBlue.opacity(0.35))

                    TextField("NAME", text: player2Binding)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(royalBlue)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .focused($focusedField, equals: secondaryField)
                        .submitLabel(.done)
                        .onChange(of: player2Binding.wrappedValue) { _, newValue in
                            if newValue.count > 7 {
                                player2Binding.wrappedValue = String(newValue.prefix(7))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .contentShape(Rectangle())
                }
                .padding(.horizontal, 8)
            }
        }
        .frame(height: isSingles ? 58 : 84)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(mutedText)
            .tracking(1.4)
    }

    private func applyDefaultPlayerName() {
        guard !headerFirstName.isEmpty, player1Name.isEmpty else { return }
        player1Name = headerFirstName
    }
}

// MARK: - OffsetPillSegment
//
// Sliding-pill segmented control built on a single rendered pill that
// moves via .offset() instead of matchedGeometryEffect.
//
// Why offset instead of matchedGeometry:
//   - One view, no source-view ambiguity on first render.
//   - SwiftUI animates offset on the GPU; no layout re-resolution per option.
//   - No namespace plumbing.
//   - No flicker if the conditional source branch flips faster than the
//     animation completes (e.g. rapid taps).
//
// The pill width is read from a GeometryReader exactly once per layout
// pass (when option count or track width changes), then cached locally.
private struct OffsetPillSegment: View {
    let options: [String]
    let selectedIndex: Int
    let height: CGFloat
    let selectedFont: Font
    let selectedColor: Color
    let unselectedColor: Color
    let trackColor: Color
    let pillColor: Color
    var pillShadow: Bool = false
    var pillStroke: Color? = nil
    var minScale: CGFloat = 1.0
    let onSelect: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let pillWidth = geo.size.width / CGFloat(options.count)
            ZStack(alignment: .leading) {
                // The single sliding pill.
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(pillColor)
                    .overlay(
                        Group {
                            if let pillStroke {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(pillStroke, lineWidth: 1)
                            }
                        }
                    )
                    .shadow(color: pillShadow ? .black.opacity(0.06) : .clear, radius: 5, x: 0, y: 2)
                    .frame(width: pillWidth - 8, height: height - 8)
                    .offset(x: CGFloat(selectedIndex) * pillWidth + 4)

                HStack(spacing: 0) {
                    ForEach(options.indices, id: \.self) { i in
                        Button {
                            // Force the active text field to resign instantly BEFORE state values mutate
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            onSelect(i)
                        } label: {

                            Text(options[i])
                                .font(selectedFont)
                                .foregroundColor(i == selectedIndex ? selectedColor : unselectedColor)
                                .lineLimit(1)
                                .minimumScaleFactor(minScale)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
        }
        .frame(height: height)
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(trackColor))
    }
}

#Preview {
    PlayView()
}
