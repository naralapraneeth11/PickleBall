//
//  DesignSystem.swift
//  CourtKit
//
//  The one design-system file: colours, sport themes, type, motion, the
//  press style and haptics. Shared by the iPhone app, the Watch app and the
//  Live Activity so nothing is copy-pasted per screen again.
//

#if canImport(SwiftUI)
import SwiftUI

public enum DS {

    // MARK: Palette

    public enum Palette {
        // Court and brand blues
        public static let navy = Color(red: 0.08, green: 0.12, blue: 0.24)
        public static let royalBlue = Color(red: 0.055, green: 0.102, blue: 0.275)
        public static let ink = Color(red: 0.04, green: 0.07, blue: 0.30)
        public static let courtBlue = Color(red: 0.18, green: 0.38, blue: 0.58)
        public static let courtBlueLight = Color(red: 0.20, green: 0.42, blue: 0.62)
        public static let courtBlueMid = Color(red: 0.18, green: 0.42, blue: 0.60)
        public static let courtBlueDeep = Color(red: 0.16, green: 0.38, blue: 0.56)

        // Light surfaces
        public static let pageGrey = Color(red: 0.955, green: 0.956, blue: 0.962)
        public static let fieldGrey = Color(red: 0.965, green: 0.967, blue: 0.973)
        public static let stroke = Color.black.opacity(0.08)
        public static let textSecondary = Color(red: 0.38, green: 0.40, blue: 0.48)
        public static let textMuted = Color(red: 0.36, green: 0.39, blue: 0.47)

        // Scoreboard (dark) surfaces
        public static let night = Color(red: 0.035, green: 0.04, blue: 0.055)
        public static let nightRaised = Color(red: 0.09, green: 0.095, blue: 0.12)
        public static let hairline = Color.white.opacity(0.10)
        public static let nightText = Color.white.opacity(0.92)
        public static let nightMuted = Color.white.opacity(0.52)

        // Accents and semantics
        public static let lime = Color(red: 0.55, green: 0.92, blue: 0.25)
        public static let electricBlue = Color(red: 0.24, green: 0.62, blue: 1.0)
        public static let win = Color(red: 0.15, green: 0.62, blue: 0.36)
        public static let loss = Color(red: 0.86, green: 0.24, blue: 0.24)
        public static let gold = Color(red: 1.0, green: 0.84, blue: 0.25)
        public static let warning = Color(red: 0.85, green: 0.55, blue: 0.15)
    }

    // MARK: Metrics

    public enum Radius {
        public static let card: CGFloat = 18
        public static let control: CGFloat = 14
        public static let chip: CGFloat = 10
    }

    // MARK: Type

    public enum Typography {
        /// The one giant number per screen.
        public static func hero(_ size: CGFloat) -> Font {
            .system(size: size, weight: .heavy, design: .rounded).monospacedDigit()
        }
        public static func score(_ size: CGFloat) -> Font {
            .system(size: size, weight: .black, design: .rounded).monospacedDigit()
        }
        public static let eyebrow = Font.system(size: 11, weight: .bold, design: .rounded)
        public static let body = Font.system(size: 15, weight: .medium, design: .rounded)
        public static let bodyStrong = Font.system(size: 15, weight: .semibold, design: .rounded)
        public static let caption = Font.system(size: 12, weight: .medium, design: .rounded)
    }

    // MARK: Motion

    public enum Motion {
        public static let snappy: Animation = .spring(response: 0.28, dampingFraction: 0.84)
        public static let press: Animation = .spring(response: 0.14, dampingFraction: 0.86)
        public static let score: Animation = .spring(response: 0.32, dampingFraction: 0.72)
    }
}

// MARK: - Sport themes

/// Everything that re-tints when the sport switches. One accent per sport
/// so people always know which mode they are in.
public struct SportTheme: Equatable, Sendable {
    public let sport: Sport
    public let accent: Color
    /// Text/icon colour on top of `accent`.
    public let onAccent: Color
    public let courtSurface: Color
    public let courtSurfaceAlt: Color
    public let courtLines: Color

    public var accentSoft: Color { accent.opacity(0.18) }

    public static let pickleball = SportTheme(
        sport: .pickleball,
        accent: DS.Palette.lime,
        onAccent: .black,
        courtSurface: DS.Palette.courtBlue,
        courtSurfaceAlt: DS.Palette.courtBlueLight,
        courtLines: .white
    )

    public static let padel = SportTheme(
        sport: .padel,
        accent: DS.Palette.electricBlue,
        onAccent: .white,
        courtSurface: Color(red: 0.07, green: 0.30, blue: 0.40),
        courtSurfaceAlt: Color(red: 0.08, green: 0.35, blue: 0.46),
        courtLines: .white
    )
}

extension Sport {
    public var theme: SportTheme { self == .pickleball ? .pickleball : .padel }
}

// MARK: - Press style

/// Same-frame touch-down feedback for every custom button.
public struct PressStyle: ButtonStyle {
    public var scale: CGFloat

    public init(scale: CGFloat = 0.96) {
        self.scale = scale
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(DS.Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressStyle {
    public static var press: PressStyle { PressStyle() }
}

// MARK: - Cards

extension View {
    /// White rounded card with the standard hairline and soft shadow.
    public func cardSurface(radius: CGFloat = DS.Radius.card) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(DS.Palette.stroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        )
    }

    /// Small tracked uppercase label used above sections.
    public func eyebrowStyle(_ color: Color = DS.Palette.textSecondary) -> some View {
        font(DS.Typography.eyebrow)
            .tracking(1.4)
            .foregroundStyle(color)
    }
}
#endif

#if canImport(SwiftUI)
/// Marks features whose numbers aren't validated yet (wrist shot detection).
public struct BetaBadge: View {
    public var tint: Color

    public init(tint: Color = .white) {
        self.tint = tint
    }

    public var body: some View {
        Text("BETA")
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .tracking(1)
            .foregroundStyle(tint.opacity(0.9))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 1))
            .accessibilityLabel("Beta")
    }
}
#endif
