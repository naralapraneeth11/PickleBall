//
//  SocialComponents.swift
//  PickleBall
//
//  Small pieces shared by the social screens: avatars, the notice toast,
//  section headers, empty states and relative times.
//

import SwiftUI
import UIKit
import CourtKit
import CourtNet

/// A friend's photo, or their initials.
struct ProfileAvatar: View {
    let userID: UUID
    var size: CGFloat = 40
    private let social = Social.shared

    var body: some View {
        let profile = userID == social.userID ? social.profile : social.profiles[userID]
        let name = social.name(of: userID)
        Group {
            if let path = profile?.avatarPath, let url = social.backend?.publicURL(for: path, in: .avatars) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Avatar(name: name, color: Self.color(for: userID), size: size)
                    }
                }
            } else {
                Avatar(name: name, color: Self.color(for: userID), size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    /// A stable colour per person.
    static func color(for id: UUID) -> Color {
        let palette: [Color] = [DS.Palette.courtBlue, DS.Palette.win, Color(red: 0.55, green: 0.35, blue: 0.85),
                                Color(red: 0.9, green: 0.45, blue: 0.2), Color(red: 0.15, green: 0.55, blue: 0.6), DS.Palette.royalBlue]
        let value = id.uuid.0 ^ id.uuid.5 ^ id.uuid.10 ^ id.uuid.15
        return palette[Int(value) % palette.count]
    }
}

/// Stacked avatars for a squad or a pair.
struct AvatarStack: View {
    let userIDs: [UUID]
    var size: CGFloat = 28
    var limit = 4

    var body: some View {
        HStack(spacing: -size * 0.32) {
            ForEach(Array(userIDs.prefix(limit)), id: \.self) { id in
                ProfileAvatar(userID: id, size: size)
                    .overlay(Circle().stroke(Court.raised, lineWidth: 2))
            }
        }
    }
}

/// Transient messages from `Social.notice`.
struct NoticeToast: ViewModifier {
    private let social = Social.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let notice = social.notice {
                Text(notice)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.black.opacity(0.82)))
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { social.notice = nil }
                    .task(id: notice) {
                        try? await Task.sleep(for: .seconds(3.5))
                        if social.notice == notice {
                            withAnimation(DS.Motion.snappy) { social.notice = nil }
                        }
                    }
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(DS.Motion.snappy, value: social.notice)
    }
}

extension View {
    func noticeToast() -> some View { modifier(NoticeToast()) }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title.uppercased()).eyebrowStyle()
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
        }
    }
}

/// A row that reads "Alice · 2h".
enum RelativeTime {
    static func short(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        case ..<(7 * 86_400): return "\(Int(seconds / 86_400))d"
        default: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    static func upcoming(_ date: Date?) -> String {
        guard let date else { return "Time to be decided" }
        if Calendar.current.isDateInToday(date) { return "Today \(date.formatted(date: .omitted, time: .shortened))" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow \(date.formatted(date: .omitted, time: .shortened))" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }
}

/// A pill-shaped secondary button used across the social screens.
struct PillButton: View {
    let title: String
    var systemImage: String?
    var prominent = false
    var tint: Color?
    let action: () -> Void

    /// Navy by day, a lighter blue at night so it stays readable.
    private static let defaultTint = Color(light: UIColor(DS.Palette.royalBlue), dark: UIColor(red: 0.62, green: 0.72, blue: 1, alpha: 1))
    private static let onDefaultTint = Color(light: .white, dark: UIColor(white: 0.07, alpha: 1))

    var body: some View {
        let color = tint ?? Self.defaultTint
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(LocalizedStringKey(title))
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(prominent ? (tint == nil ? Self.onDefaultTint : .white) : color)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(prominent ? color : color.opacity(0.12)))
        }
        .buttonStyle(.press)
    }
}

/// Chats, Tournaments and the Feed in a build with no server: says so
/// instead of showing buttons that can't do anything.
struct ServerNeededView: View {
    let eyebrow: LocalizedStringKey
    let title: LocalizedStringKey
    let symbol: String
    let message: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow).courtEyebrow()
            Text(title)
                .font(.system(size: 38, weight: .semibold))
                .tracking(-1.1)
                .foregroundStyle(Court.text)
                .padding(.top, 4)
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Court.text)
                    .frame(width: 76, height: 76)
                    .courtRaised(cornerRadius: 24)
                Text("Needs the PickleBall server")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Court.text)
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(Court.muted)
                    .multilineTextAlignment(.center)
                Text("Scoring, stats and your player card work without it.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(Court.dim)
                    .multilineTextAlignment(.center)
                #if DEBUG
                Text(verbatim: "Developer: add PickleBall/Secrets.plist (docs/LAUNCH_CHECKLIST.md, steps 1–2).")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Court.dim)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                #endif
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, Court.Metrics.tabBarClearance)
        .courtGround()
    }
}
