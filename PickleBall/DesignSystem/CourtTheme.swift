//
//  CourtTheme.swift
//  PickleBall
//
//  The app's look: soft raised and sunken surfaces on a warm off-white
//  ground by day, charcoal by night. Every colour adapts to light and dark
//  on its own, so screens use `Court.text`, `Court.raised` and so on and
//  never branch on the colour scheme.
//
//  The sport's accent (yellow for pickleball, blue for padel) is used
//  sparingly: the selected tab, the page dot. Nowhere else by default.
//
//  An optional Glass appearance (Settings → Appearance) swaps the solid
//  surfaces for frosted material. Standard is the default.
//
//  Shadow radii are SwiftUI radii (about half the mockups' CSS blur).
//

import SwiftUI
import UIKit
import CourtKit

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// One colour for light mode, another for dark.
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

enum Court {
    // MARK: Surfaces

    /// Page background.
    static let ground = Color(light: UIColor(hex: 0xECECE8), dark: UIColor(hex: 0x1C1D1F))
    /// Buttons, pills, cards.
    static let raised = Color(light: UIColor(hex: 0xF6F6F3), dark: UIColor(hex: 0x26282B))
    /// The court frame.
    static let plate = Color(light: UIColor(hex: 0xF3F3EF), dark: UIColor(hex: 0x2A2C2F))
    /// Court boxes and other pressed-in wells.
    static let sunken = Color(light: UIColor(hex: 0xE2E2DD), dark: UIColor(hex: 0x17181A))
    /// A selected tile that's pressed in.
    static let pressed = Color(light: UIColor(hex: 0xE6E6E1), dark: UIColor(hex: 0x1F2023))

    // MARK: Content

    static let text = Color(light: UIColor(hex: 0x161616), dark: UIColor(hex: 0xF2F2F0))
    /// Hints, band labels, secondary text.
    static let muted = Color(light: UIColor(hex: 0x3B3B39), dark: UIColor(hex: 0xC9CACB))
    /// Small eyebrow labels ("HOME").
    static let dim = Color(light: UIColor(hex: 0x4A4A47), dark: UIColor(hex: 0xA9AAAB))
    static let dotOff = Color(light: UIColor(hex: 0xC4C4BF), dark: UIColor(hex: 0x4A4C50))
    static let hairline = Color(light: UIColor(hex: 0x161616, alpha: 0.08), dark: UIColor(white: 1, alpha: 0.08))
    static let avatarBackground = Color(light: UIColor(hex: 0xC4C4BF), dark: UIColor(hex: 0x4A4C50))
    static let avatarForeground = Color(light: .white, dark: UIColor(hex: 0x8A8C90))

    /// Icon on a solid accent tile (yellow or blue alike).
    static let onAccent = Color(hex: 0x111111)

    /// The sport's accent. Kept for the selected tab and the page dot.
    static func accent(_ sport: Sport) -> Color {
        sport == .pickleball ? Color(hex: 0xFFFC00) : Color(hex: 0x0EADFF)
    }

    /// Active page dot: yellow vanishes on the light ground, so pickleball
    /// uses the text colour by day.
    static func activeDot(_ sport: Sport, scheme: ColorScheme) -> Color {
        (scheme == .light && sport == .pickleball) ? text : accent(sport)
    }

    // MARK: Shadows

    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    private static let shade = Color(light: UIColor(hex: 0x46463C, alpha: 0.16), dark: UIColor(white: 0, alpha: 0.55))
    private static let shadeDeep = Color(light: UIColor(hex: 0x46463C, alpha: 0.20), dark: UIColor(white: 0, alpha: 0.60))
    private static let courtShade = Color(light: UIColor(hex: 0x3C3C32, alpha: 0.18), dark: UIColor(white: 0, alpha: 0.60))
    private static let shine = Color(light: UIColor(white: 1, alpha: 0.95), dark: UIColor(white: 1, alpha: 0.05))
    private static let shineInset = Color(light: UIColor(white: 1, alpha: 0.90), dark: UIColor(white: 1, alpha: 0.06))

    static let raisedDark = Shadow(color: shade, radius: 7, x: 5, y: 7)
    static let raisedLight = Shadow(color: shine, radius: 5, x: -4, y: -4)
    static let insetDark = Shadow(color: shadeDeep, radius: 8, x: 7, y: 9)
    static let insetLight = Shadow(color: shineInset, radius: 7, x: -6, y: -6)
    static let pressedDark = Shadow(color: shadeDeep, radius: 5, x: 4, y: 5)
    static let pressedLight = Shadow(color: shineInset, radius: 4, x: -3, y: -3)
    static let courtDrop = Shadow(color: courtShade, radius: 14, x: 12, y: 18)
    static let courtLight = Shadow(color: shine, radius: 7, x: -6, y: -6)

    static var sunkenFill: some ShapeStyle {
        sunken
            .shadow(.inner(color: insetDark.color, radius: insetDark.radius, x: insetDark.x, y: insetDark.y))
            .shadow(.inner(color: insetLight.color, radius: insetLight.radius, x: insetLight.x, y: insetLight.y))
    }

    static var pressedFill: some ShapeStyle {
        pressed
            .shadow(.inner(color: pressedDark.color, radius: pressedDark.radius, x: pressedDark.x, y: pressedDark.y))
            .shadow(.inner(color: pressedLight.color, radius: pressedLight.radius, x: pressedLight.x, y: pressedLight.y))
    }

    // MARK: Metrics

    enum Metrics {
        static let sideInset: CGFloat = 12
        static let courtHeight: CGFloat = 380
        static let courtPadding: CGFloat = 12
        static let courtGap: CGFloat = 12
        static let courtRadius: CGFloat = 34
        static let boxRadius: CGFloat = 22
        static let bandHeight: CGFloat = 100
        static let farHalfGap: CGFloat = 6
        static let farHalfFade: CGFloat = 136
        static let farHalfOpacity: Double = 0.85
        static let pillHeight: CGFloat = 44
        static let tile: CGFloat = 56
        static let tileRadius: CGFloat = 18
        static let tileGap: CGFloat = 8
        static let tileIcon: CGFloat = 22
        static let selectedLine: CGFloat = 3
        static let avatar: CGFloat = 30
        static let tabBarBottom: CGFloat = 34
        /// Room scrolling content leaves for the tab bar.
        static let tabBarClearance: CGFloat = 110
    }
}

// MARK: - Appearance

/// Standard (soft solid surfaces) is the default; Glass is opt-in.
enum AppearanceStyle: String, CaseIterable, Identifiable {
    case standard
    case glass

    static let storageKey = "appearance.style"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .standard: return "Standard"
        case .glass: return "Glass"
        }
    }
}

private struct AppearanceStyleKey: EnvironmentKey {
    static let defaultValue: AppearanceStyle = .standard
}

extension EnvironmentValues {
    var appearanceStyle: AppearanceStyle {
        get { self[AppearanceStyleKey.self] }
        set { self[AppearanceStyleKey.self] = newValue }
    }
}

// MARK: - Surfaces

extension View {
    func shadow(_ s: Court.Shadow) -> some View {
        shadow(color: s.color, radius: s.radius, x: s.x, y: s.y)
    }

    /// A raised card or button.
    func courtRaised(cornerRadius: CGFloat = DS.Radius.card) -> some View {
        modifier(RaisedSurface(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }

    /// A raised capsule (pills).
    func courtRaisedCapsule() -> some View {
        modifier(RaisedSurface(shape: Capsule(style: .continuous)))
    }

    /// A pressed-in well.
    func courtSunken(cornerRadius: CGFloat = Court.Metrics.boxRadius) -> some View {
        modifier(SunkenSurface(cornerRadius: cornerRadius))
    }

    /// The page background, behind safe areas too.
    func courtGround() -> some View {
        modifier(GroundBackground())
    }

    /// Lists and forms on the page background.
    func courtList() -> some View {
        scrollContentBackground(.hidden).courtGround()
    }
}

private struct RaisedSurface<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.appearanceStyle) private var style

    func body(content: Content) -> some View {
        content.background {
            if style == .glass {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)
            } else {
                shape.fill(Court.raised)
                    .shadow(Court.raisedDark)
                    .shadow(Court.raisedLight)
            }
        }
    }
}

private struct SunkenSurface: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.appearanceStyle) private var style

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content.background {
            if style == .glass {
                shape.fill(Court.text.opacity(0.05))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6))
            } else {
                shape.fill(Court.sunkenFill)
            }
        }
    }
}

private struct GroundBackground: ViewModifier {
    @Environment(\.appearanceStyle) private var style
    @Environment(SportMode.self) private var sportMode

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                Court.ground
                if style == .glass {
                    // Glass needs something behind it to frost: a soft wash
                    // of the sport's colour from the top.
                    LinearGradient(colors: [Court.accent(sportMode.sport).opacity(0.18), .clear],
                                   startPoint: .top, endPoint: .center)
                }
            }
            .ignoresSafeArea()
        }
    }
}
