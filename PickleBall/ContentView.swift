import SwiftUI
import UIKit

// MARK: - Tab Definition

enum AppTab: Int, CaseIterable, Identifiable {
    case home, stats, play, profile, watch

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .home:    return "Home"
        case .stats:   return "Stats"
        case .play:    return "Play"
        case .profile: return "Profile"
        case .watch:   return "Watch"
        }
    }

    var icon: String {
        switch self {
        case .home:    return "house.fill"
        case .stats:   return "circle.hexagongrid.fill"
        case .play:    return "tennisball.circle.fill"
        case .profile: return "person.fill"
        case .watch:   return "applewatch"
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    // @State (not @SceneStorage) so cold launches always start on Home.
    // Selection still survives backgrounding within the same session because
    // SwiftUI keeps @State alive as long as the scene is alive.
    @State private var selectedTab: AppTab = .home

    @State private var isKeyboardVisible: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Switch instead of opacity stack. Apple's own tabs (Settings,
            // Photos, Messages) swap, not crossfade. The opacity-stack
            // approach keeps all 5 views alive at all times — meaning
            // WatchStatsDetailView's fetchRecentFromHealthKit, MainMenu's
            // loaders, etc. all fire on launch. Not worth it.
            Group {
                switch selectedTab {
                case .home:
                    MainMenu()
                case .stats:
                    NavigationStack { StatsView() }
                case .play:
                    PlayView()
                case .profile:
                    ProfileView()
                case .watch:
                    NavigationStack { WatchStatsDetailView() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !isKeyboardVisible {
                GlassTabBar(selectedTab: $selectedTab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.keyboard)
        .background(Color(.systemBackground))
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
}

// MARK: - Glass Tab Bar

private struct GlassTabBar: View {
    @Binding var selectedTab: AppTab
    @Namespace private var tabNamespace

    /// Pre-warmed haptic generator. Initializing + firing in one breath
    /// cold-starts the Taptic engine and adds ~30–50ms of physical lag
    /// between tap and click. Holding an instance and calling .prepare()
    /// on touch-down keeps the actuator armed.
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private let accent = Color(red: 0.04, green: 0.07, blue: 0.30)
    private let inactive = Color(red: 0.36, green: 0.39, blue: 0.47)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                TabBarButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    namespace: tabNamespace,
                    accent: accent,
                    inactive: inactive,
                    onPressStart: { haptic.prepare() },
                    action: {
                        guard selectedTab != tab else { return }
                        haptic.impactOccurred(intensity: 0.85)
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
        .buttonStyle(TabBarButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isSelected ? "\(tab.label) tab, selected" : "\(tab.label) tab")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Slight scale-down on press for tactile feedback. Despite what you might
/// read in self-help dev blogs, there is no "150ms gesture engine highlight
/// delay" to strip out — .buttonStyle(.plain) is already instant. This just
/// adds a subtle press-state visual.
private struct TabBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    ContentView()
}
