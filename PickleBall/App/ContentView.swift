import SwiftUI
import UIKit
import CourtKit

// MARK: - Tab Definition

/// Five tabs, opening on Play. Me sits in the middle.
enum AppTab: Int, CaseIterable, Identifiable {
    case play, chats, me, tournaments, feed

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .play:        return String(localized: "Play")
        case .chats:       return String(localized: "Chats")
        case .me:          return String(localized: "Me")
        case .tournaments: return String(localized: "Tournaments")
        case .feed:        return String(localized: "Feed")
        }
    }

    var icon: String {
        switch self {
        case .play:        return "tennisball"
        case .chats:       return "bubble.left.and.bubble.right"
        case .me:          return "person.crop.circle"
        case .tournaments: return "trophy"
        case .feed:        return "square.stack"
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    // @State (not @SceneStorage) so cold launches always start on Play.
    @State private var selectedTab: AppTab = .play
    @State private var isKeyboardVisible: Bool = false
    @AppStorage("onboarding.firstStepsDone") private var firstStepsDone = false
    private let social = Social.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            // Switch instead of an opacity stack: only the visible tab is
            // alive, so its loaders don't all fire at launch.
            Group {
                switch selectedTab {
                case .play:
                    MainMenu()
                case .chats:
                    NavigationStack { ChatsView() }
                case .me:
                    NavigationStack { ProfileView() }
                case .tournaments:
                    NavigationStack { TournamentsView() }
                case .feed:
                    NavigationStack { FeedView() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !isKeyboardVisible {
                TileTabBar(selectedTab: $selectedTab, badges: badges)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .ignoresSafeArea(.keyboard)
        .courtGround()
        .noticeToast()
        .sharePromptHost()
        .fullScreenCover(isPresented: Binding(get: { social.phase == .ready && !firstStepsDone },
                                              set: { if !$0 { firstStepsDone = true } })) {
            FirstStepsView { firstStepsDone = true }
        }
        .onOpenURL { url in
            // The belt widget opens the player card.
            if url.scheme == "pickleball", url.host == "belts" { selectedTab = .me }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
        ) { _ in
            withAnimation(.easeOut(duration: 0.18)) { isKeyboardVisible = true }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        ) { _ in
            withAnimation(.easeOut(duration: 0.18)) { isKeyboardVisible = false }
        }
    }

    /// Tabs with something waiting.
    private var badges: Set<AppTab> {
        var set: Set<AppTab> = []
        if !social.awaitingMyConfirmation.isEmpty || !social.callOutsAwaitingMe.isEmpty { set.insert(.play) }
        if social.conversations.contains(where: social.hasUnread) || !social.incomingRequests.isEmpty { set.insert(.chats) }
        return set
    }
}

// MARK: - Tab bar

/// Five same-size tiles, centred with fixed gaps. The selected tile is a
/// solid sport-colour tile by day, pressed in with a thin sport-colour line
/// along its bottom at night, and a frosted tile with the line in Glass.
private struct TileTabBar: View {
    @Binding var selectedTab: AppTab
    var badges: Set<AppTab> = []
    @Environment(SportMode.self) private var sportMode

    var body: some View {
        HStack(spacing: Court.Metrics.tileGap) {
            ForEach(AppTab.allCases) { tab in
                TabTile(tab: tab, sport: sportMode.sport, isSelected: selectedTab == tab,
                        hasBadge: badges.contains(tab)) {
                    guard selectedTab != tab else { return }
                    Haptics.light()
                    withAnimation(.snappy(duration: 0.28)) { selectedTab = tab }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        // Fixed distance from the bottom edge on every iPhone, above the
        // home indicator.
        .padding(.bottom, Court.Metrics.tabBarBottom)
        .background(alignment: .bottom) {
            // Content scrolling underneath fades out instead of showing
            // through the gaps between tiles.
            LinearGradient(stops: [.init(color: Court.ground.opacity(0), location: 0),
                                   .init(color: Court.ground.opacity(0.92), location: 0.45),
                                   .init(color: Court.ground, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        }
    }
}

private struct TabTile: View {
    let tab: AppTab
    let sport: Sport
    let isSelected: Bool
    var hasBadge = false
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.appearanceStyle) private var style
    private let social = Social.shared

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Court.Metrics.tileRadius, style: .continuous)
    }

    /// Standard, day: solid accent fill. Night or Glass: the thin line.
    private var solid: Bool { isSelected && scheme == .light && style == .standard }
    private var line: Bool { isSelected && !solid }

    var body: some View {
        Button(action: action) {
            icon
                .frame(width: Court.Metrics.tile, height: Court.Metrics.tile)
                .background { background }
                .overlay {
                    if line {
                        Rectangle()
                            .fill(Court.accent(sport))
                            .frame(height: Court.Metrics.selectedLine)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .clipShape(shape)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if hasBadge {
                        Circle()
                            .fill(DS.Palette.loss)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Court.ground, lineWidth: 2))
                            .offset(x: -7, y: 7)
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(.press)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in Haptics.warm() })
        .accessibilityLabel(tab.label)
        .accessibilityValue(hasBadge ? String(localized: "New activity") : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var background: some View {
        if style == .glass {
            shape.fill(.ultraThinMaterial)
                .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8))
                .shadow(color: .black.opacity(isSelected ? 0.04 : 0.08), radius: 8, x: 0, y: 4)
        } else if line {
            shape.fill(Court.pressedFill)
        } else {
            shape.fill(solid ? Court.accent(sport) : Court.raised)
                .shadow(Court.raisedDark)
                .shadow(Court.raisedLight)
        }
    }

    @ViewBuilder
    private var icon: some View {
        if tab == .me {
            // Your photo, or a neutral silhouette. No ring.
            Group {
                if let path = social.profile?.avatarPath,
                   let url = social.backend?.publicURL(for: path, in: .avatars) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            silhouette
                        }
                    }
                } else {
                    silhouette
                }
            }
            .frame(width: Court.Metrics.avatar, height: Court.Metrics.avatar)
            .clipShape(Circle())
        } else {
            Image(systemName: tab.icon)
                .font(.system(size: Court.Metrics.tileIcon, weight: .semibold))
                .foregroundStyle(solid ? Court.onAccent : Court.text)
        }
    }

    private var silhouette: some View {
        Circle()
            .fill(Court.avatarBackground)
            .overlay(alignment: .bottom) {
                Image(systemName: "person.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Court.avatarForeground)
                    .offset(y: 4)
            }
    }
}

#Preview {
    ContentView()
        .environment(SportMode())
}
