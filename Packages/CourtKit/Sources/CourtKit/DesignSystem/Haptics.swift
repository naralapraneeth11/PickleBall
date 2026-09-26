//
//  Haptics.swift
//  CourtKit
//
//  One haptic vocabulary for iPhone and Apple Watch. Generators are kept
//  warm so the tap and the click land in the same frame.
//

#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

@MainActor
public enum Haptics {
    #if os(iOS)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    #endif

    /// Prepares every generator; call when a screen with haptics appears.
    public static func warm() {
        #if os(iOS)
        selectionGenerator.prepare()
        lightGenerator.prepare()
        mediumGenerator.prepare()
        rigidGenerator.prepare()
        notificationGenerator.prepare()
        #endif
    }

    public static func selection() {
        #if os(iOS)
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }

    public static func light() {
        #if os(iOS)
        lightGenerator.impactOccurred()
        lightGenerator.prepare()
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }

    public static func medium() {
        #if os(iOS)
        mediumGenerator.impactOccurred()
        mediumGenerator.prepare()
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.directionUp)
        #endif
    }

    public static func soft() {
        #if os(iOS)
        softGenerator.impactOccurred()
        softGenerator.prepare()
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.directionDown)
        #endif
    }

    public static func success() {
        #if os(iOS)
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #endif
    }

    public static func warning() {
        #if os(iOS)
        notificationGenerator.notificationOccurred(.warning)
        notificationGenerator.prepare()
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.retry)
        #endif
    }

    /// Distinct double-tap for game / set / match point.
    public static func pressure() {
        #if os(iOS)
        rigidGenerator.impactOccurred(intensity: 1.0)
        rigidGenerator.prepare()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 110_000_000)
            rigidGenerator.impactOccurred(intensity: 0.7)
        }
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.notification)
        #endif
    }

    /// The single most important haptic for a rally's events.
    public static func play(_ events: [ScoreEvent]) {
        if events.contains(where: { if case .matchWon = $0 { return true } else { return false } }) {
            success()
        } else if events.contains(where: {
            switch $0 {
            case .gameWon, .setWon: return true
            default: return false
            }
        }) {
            medium()
        } else if events.contains(where: { if case .pressure = $0 { return true } else { return false } }) {
            pressure()
        } else if events.contains(where: {
            switch $0 {
            case .sideOut, .secondServer: return true
            default: return false
            }
        }) {
            soft()
        } else if !events.isEmpty {
            light()
        }
    }
}
