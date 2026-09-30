//
//  BeltWidget.swift
//  ScoreActivityWidget
//
//  The belt widget, low-key on purpose: a friend's face, the belt, a day
//  count. No headline. Small on the Home Screen, a tiny round badge on the
//  Lock Screen. Reads the snapshot the app keeps in the App Group; days
//  are counted from the reign's start, so it stays right at midnight
//  without the app running.
//

import SwiftUI
import WidgetKit
import CourtKit

struct BeltEntry: TimelineEntry {
    let date: Date
    let belt: BeltWidgetSnapshot.Entry?
    let avatar: UIImage?
}

struct BeltProvider: TimelineProvider {
    static let appGroup = "group.ME.PickleBall"

    func placeholder(in context: Context) -> BeltEntry {
        BeltEntry(date: Date(), belt: .init(beltID: "preview", sport: .pickleball, tier: .gold, holderName: "Sam", initials: "S",
                                            avatarFile: nil, since: Date().addingTimeInterval(-12 * 86_400), isMine: false),
                  avatar: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (BeltEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BeltEntry>) -> Void) {
        let now = Date()
        // One entry now and one each midnight for the next few days, so the
        // count ticks over on time.
        let calendar = Calendar.current
        var entries = [entry(at: now)]
        var day = calendar.startOfDay(for: now)
        for _ in 0..<3 {
            day = calendar.date(byAdding: .day, value: 1, to: day)!
            entries.append(entry(at: day))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date) -> BeltEntry {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup),
              let data = try? Data(contentsOf: container.appendingPathComponent("belt-widget.json")),
              let snapshot = try? JSONDecoder().decode(BeltWidgetSnapshot.self, from: data),
              let belt = snapshot.entries.first else {
            return BeltEntry(date: date, belt: nil, avatar: nil)
        }
        let avatar = belt.avatarFile.flatMap { UIImage(contentsOfFile: container.appendingPathComponent("avatars/\($0)").path) }
        return BeltEntry(date: date, belt: belt, avatar: avatar)
    }
}

struct BeltWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BeltWidget", provider: BeltProvider()) { entry in
            BeltWidgetView(entry: entry)
                .containerBackground(for: .widget) { DS.Palette.night }
                .widgetURL(URL(string: "pickleball://belts"))
        }
        .configurationDisplayName("Belt")
        .description("Who’s wearing the belt, and for how long.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct BeltWidgetView: View {
    let entry: BeltEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let belt = entry.belt {
            switch family {
            case .accessoryCircular: circular(belt)
            default: small(belt)
            }
        } else {
            empty
        }
    }

    private func small(_ belt: BeltWidgetSnapshot.Entry) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                face(belt, size: 64)
                Image(systemName: "crown.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint(belt.tier))
                    .padding(5)
                    .background(Circle().fill(DS.Palette.night))
                    .offset(x: 4, y: 4)
            }
            Text(belt.dayCount(asOf: entry.date))
                .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(belt.holderName), \(belt.days(asOf: entry.date)) days with the belt")
    }

    private func circular(_ belt: BeltWidgetSnapshot.Entry) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "crown.fill").font(.system(size: 11, weight: .bold))
                Text(belt.dayCount(asOf: entry.date))
                    .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6)
                Text(belt.initials)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .opacity(0.8)
            }
        }
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(belt.holderName), \(belt.days(asOf: entry.date)) days with the belt")
    }

    @ViewBuilder
    private func face(_ belt: BeltWidgetSnapshot.Entry, size: CGFloat) -> some View {
        if let avatar = entry.avatar {
            Image(uiImage: avatar)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().stroke(tint(belt.tier), lineWidth: 2.5))
        } else {
            Circle()
                .fill(tint(belt.tier).opacity(0.25))
                .frame(width: size, height: size)
                .overlay(Text(belt.initials).font(.system(size: size * 0.38, weight: .bold, design: .rounded)).foregroundStyle(.white))
                .overlay(Circle().stroke(tint(belt.tier), lineWidth: 2.5))
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "crown")
                .font(.system(size: family == .accessoryCircular ? 16 : 28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            if family != .accessoryCircular {
                Text("—").font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func tint(_ tier: BeltTier) -> Color {
        switch tier {
        case .gold, .undisputed: return DS.Palette.gold
        default: return .white
        }
    }
}
