//
//  CourtArt.swift
//  CourtKit
//
//  Court geometry as the design language: kitchen lines for pickleball,
//  service boxes and glass walls for padel. Drawn to scale, top-down, with
//  the net across the middle.
//

#if canImport(SwiftUI)
import SwiftUI

/// The painted lines of a court, fitted into the rect with correct proportions.
public struct CourtLines: Shape {
    public var sport: Sport

    public init(sport: Sport) {
        self.sport = sport
    }

    /// Court length / width. Pickleball 44×20 ft, padel 20×10 m.
    public static func aspectRatio(for sport: Sport) -> CGFloat {
        sport == .pickleball ? 20.0 / 44.0 : 10.0 / 20.0
    }

    public func path(in rect: CGRect) -> Path {
        let court = Self.fittedRect(in: rect, sport: sport)
        var path = Path()
        path.addRect(court)

        let midY = court.midY
        // Net
        path.move(to: CGPoint(x: court.minX, y: midY))
        path.addLine(to: CGPoint(x: court.maxX, y: midY))

        switch sport {
        case .pickleball:
            // Non-volley zone: 7 ft either side of the net on a 44 ft court.
            let kitchen = court.height * 7.0 / 44.0
            for y in [midY - kitchen, midY + kitchen] {
                path.move(to: CGPoint(x: court.minX, y: y))
                path.addLine(to: CGPoint(x: court.maxX, y: y))
            }
            // Centre lines from kitchen to baseline.
            path.move(to: CGPoint(x: court.midX, y: court.minY))
            path.addLine(to: CGPoint(x: court.midX, y: midY - kitchen))
            path.move(to: CGPoint(x: court.midX, y: midY + kitchen))
            path.addLine(to: CGPoint(x: court.midX, y: court.maxY))

        case .padel:
            // Service lines 6.95 m from the net on a 20 m court.
            let service = court.height * 6.95 / 20.0
            for y in [midY - service, midY + service] {
                path.move(to: CGPoint(x: court.minX, y: y))
                path.addLine(to: CGPoint(x: court.maxX, y: y))
            }
            // Centre service line, extended slightly past the service lines.
            let overrun = court.height * 0.2 / 20.0
            path.move(to: CGPoint(x: court.midX, y: midY - service - overrun))
            path.addLine(to: CGPoint(x: court.midX, y: midY + service + overrun))
        }
        return path
    }

    static func fittedRect(in rect: CGRect, sport: Sport) -> CGRect {
        let ratio = aspectRatio(for: sport)
        var width = rect.width
        var height = width / ratio
        if height > rect.height {
            height = rect.height
            width = height * ratio
        }
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }
}

/// Padel's glass back walls and the side-wall glass panels.
public struct PadelGlass: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let court = CourtLines.fittedRect(in: rect, sport: .padel)
        var path = Path()
        // Back walls are glass; the first 4 m of each side wall is glass too.
        let sideGlass = court.height * 4.0 / 20.0
        for (y, direction) in [(court.minY, 1.0), (court.maxY, -1.0)] {
            path.move(to: CGPoint(x: court.minX, y: y + direction * sideGlass))
            path.addLine(to: CGPoint(x: court.minX, y: y))
            path.addLine(to: CGPoint(x: court.maxX, y: y))
            path.addLine(to: CGPoint(x: court.maxX, y: y + direction * sideGlass))
        }
        return path
    }
}

/// A full court illustration: surface, lines and (for padel) glass.
public struct CourtArtView: View {
    public var sport: Sport
    public var lineWidth: CGFloat
    public var lineOpacity: Double
    /// Draws a subtle surface fill behind the lines.
    public var showsSurface: Bool

    public init(sport: Sport, lineWidth: CGFloat = 2, lineOpacity: Double = 0.9, showsSurface: Bool = true) {
        self.sport = sport
        self.lineWidth = lineWidth
        self.lineOpacity = lineOpacity
        self.showsSurface = showsSurface
    }

    public var body: some View {
        let theme = sport.theme
        ZStack {
            if showsSurface {
                GeometryReader { geo in
                    let court = CourtLines.fittedRect(in: CGRect(origin: .zero, size: geo.size), sport: sport)
                    Rectangle()
                        .fill(LinearGradient(colors: [theme.courtSurfaceAlt, theme.courtSurface], startPoint: .top, endPoint: .bottom))
                        .frame(width: court.width, height: court.height)
                        .position(x: court.midX, y: court.midY)
                }
            }
            CourtLines(sport: sport)
                .stroke(theme.courtLines.opacity(lineOpacity), lineWidth: lineWidth)
            if sport == .padel {
                PadelGlass()
                    .stroke(theme.accent.opacity(0.55 * lineOpacity), style: StrokeStyle(lineWidth: lineWidth * 2.5, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Ball

/// Pickleball (holes) or padel ball (seam), in the sport's accent.
public struct BallIcon: View {
    public var sport: Sport
    public var size: CGFloat

    public init(sport: Sport, size: CGFloat) {
        self.sport = sport
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.35), .clear],
                        center: .topLeading,
                        startRadius: size * 0.05,
                        endRadius: size * 0.7
                    )
                )
                .background(Circle().fill(sport == .pickleball ? DS.Palette.lime : Color(red: 0.86, green: 0.95, blue: 0.20)))
            if sport == .pickleball {
                ForEach(Self.holes.indices, id: \.self) { i in
                    Circle()
                        .fill(Color.black.opacity(0.28))
                        .frame(width: size * 0.13, height: size * 0.13)
                        .offset(x: Self.holes[i].x * size, y: Self.holes[i].y * size)
                }
            } else {
                PadelSeam()
                    .stroke(Color.white.opacity(0.95), lineWidth: max(1, size * 0.07))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static let holes: [CGPoint] = [
        CGPoint(x: -0.25, y: -0.25), CGPoint(x: 0, y: -0.3), CGPoint(x: 0.25, y: -0.25),
        CGPoint(x: -0.38, y: 0), CGPoint(x: 0, y: 0), CGPoint(x: 0.38, y: 0),
        CGPoint(x: -0.25, y: 0.25), CGPoint(x: 0, y: 0.3), CGPoint(x: 0.25, y: 0.25)
    ]
}

private struct PadelSeam: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: w * 0.12, y: h * 0.22))
        path.addQuadCurve(to: CGPoint(x: w * 0.12, y: h * 0.78), control: CGPoint(x: w * 0.52, y: h * 0.5))
        path.move(to: CGPoint(x: w * 0.88, y: h * 0.22))
        path.addQuadCurve(to: CGPoint(x: w * 0.88, y: h * 0.78), control: CGPoint(x: w * 0.48, y: h * 0.5))
        return path
    }
}
#endif
