//
//  SportMode.swift
//  CourtKit
//
//  The app-wide sport mode and the long-press switch that flips it.
//  Remembered per device; the Watch follows the phone.
//

#if canImport(SwiftUI)
import SwiftUI
import Observation

@MainActor
@Observable
public final class SportMode {
    public private(set) var sport: Sport
    /// How many times the switch has been used; the visible hint shrinks
    /// away after a few uses.
    public private(set) var switchCount: Int

    @ObservationIgnored private let defaults: UserDefaults
    private static let sportKey = "sportMode.active"
    private static let countKey = "sportMode.switchCount"

    /// After this many switches the badge stops showing its "hold" hint.
    public static let hintUses = 3

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.sport = defaults.string(forKey: Self.sportKey).flatMap(Sport.init(rawValue:)) ?? .pickleball
        self.switchCount = defaults.integer(forKey: Self.countKey)
    }

    public var theme: SportTheme { sport.theme }
    public var showsHint: Bool { switchCount < Self.hintUses }

    public func set(_ sport: Sport) {
        guard sport != self.sport else { return }
        self.sport = sport
        defaults.set(sport.rawValue, forKey: Self.sportKey)
    }

    public func toggle() {
        set(sport.toggled)
        switchCount += 1
        defaults.set(switchCount, forKey: Self.countKey)
    }
}

/// The sport badge. Long-press flips the sport with a haptic and a colour
/// morph. Until the switch has been used a few times it also shows a
/// visible "Hold to switch" hint, because long-press is otherwise hidden.
public struct SportSwitchBadge: View {
    private let sport: Sport
    private let showsHint: Bool
    private let compact: Bool
    private let onSwitch: () -> Void

    @State private var isPressing = false

    public init(sport: Sport, showsHint: Bool, compact: Bool = false, onSwitch: @escaping () -> Void) {
        self.sport = sport
        self.showsHint = showsHint
        self.compact = compact
        self.onSwitch = onSwitch
    }

    public var body: some View {
        let theme = sport.theme
        HStack(spacing: 6) {
            BallIcon(sport: sport, size: compact ? 14 : 16)
            Text(sport.displayName.uppercased())
                .font(.system(size: compact ? 11 : 12, weight: .heavy, design: .rounded))
                .tracking(1.2)
            if showsHint && !compact {
                Text("· HOLD TO SWITCH")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .opacity(0.7)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .foregroundStyle(theme.onAccent)
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 6 : 8)
        .background(Capsule(style: .continuous).fill(theme.accent))
        .scaleEffect(isPressing ? 0.94 : 1)
        .animation(DS.Motion.press, value: isPressing)
        .animation(DS.Motion.snappy, value: sport)
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration: 0.45, pressing: { pressing in
            isPressing = pressing
            if pressing { Haptics.warm() }
        }, perform: {
            Haptics.medium()
            withAnimation(DS.Motion.snappy) { onSwitch() }
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sport: \(sport.displayName)")
        .accessibilityHint("Double-tap and hold to switch to \(sport.toggled.displayName)")
        .accessibilityAction(named: "Switch to \(sport.toggled.displayName)") { onSwitch() }
    }
}
#endif
