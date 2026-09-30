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
        case .play:        return "tennisball.circle.fill"
        case .chats:       return "bubble.left.and.bubble.right.fill"
        case .me:          return "person.crop.circle.fill"
        case .tournaments: return "trophy.fill"
        case .feed:        return "rectangle.stack.fill"
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
                GlassTabBar(selectedTab: $selectedTab, badges: badges)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.keyboard)
        .background(Color(.systemBackground))
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

// MARK: - Glass Tab Bar

private struct GlassTabBar: View {
    @Binding var selectedTab: AppTab
    var badges: Set<AppTab> = []
    @Namespace private var tabNamespace

    private let accent = DS.Palette.ink
    private let inactive = DS.Palette.textMuted

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                TabBarButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    hasBadge: badges.contains(tab),
                    namespace: tabNamespace,
                    accent: accent,
                    inactive: inactive,
                    onPressStart: { Haptics.warm() },
                    action: {
                        guard selectedTab != tab else { return }
                        Haptics.light()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            selectedTab = tab
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 64)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.55),
                                    Color.white.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 6)
        )
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }
}

// MARK: - Tab Bar Button

private struct TabBarButton: View {
    let tab: AppTab
    let isSelected: Bool
    var hasBadge = false
    let namespace: Namespace.ID
    let accent: Color
    let inactive: Color
    let onPressStart: () -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(isSelected ? accent : inactive)
                    .frame(height: 24)
                    .scaleEffect(isSelected ? 1.08 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isSelected)
                    .overlay(alignment: .topTrailing) {
                        if hasBadge {
                            Circle()
                                .fill(DS.Palette.loss)
                                .frame(width: 8, height: 8)
                                .offset(x: 5, y: -2)
                        }
                    }

                Text(tab.label)
                    .font(.system(size: 10,
                                  weight: isSelected ? .semibold : .medium,
                                  design: .rounded))
                    .foregroundColor(isSelected ? accent : inactive)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(
                // Single shared capsule that slides between buttons via
                // matchedGeometryEffect. Only the SELECTED button renders it;
                // SwiftUI animates the geometry transfer for us.
                Group {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(accent.opacity(0.10))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(accent.opacity(0.18), lineWidth: 1)
                            )
                            .matchedGeometryEffect(id: "activeTabIndicator", in: namespace)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 2)
                    }
                }
            )
        }
        // Pre-warm the haptic engine on touch-down rather than on tap.
        // Touches don't fire until the finger lands, but landing → lift
        // is ~50–100ms — enough for .prepare() to ready the actuator.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onPressStart() }
        )
        .buttonStyle(.press)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isSelected ? "\(tab.label) tab, selected" : "\(tab.label) tab")
        .accessibilityValue(hasBadge ? "New activity" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    ContentView()
        .environment(SportMode())
}
