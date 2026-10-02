//
//  ShareCardSheet.swift
//  PickleBall
//
//  Cards for sharing outside the app — a belt win, a trophy, a comeback,
//  your player card — rendered to an image with your invite link, so
//  whoever sees it can join and come for the belt.
//

import SwiftUI
import CourtKit
import CourtNet

struct ShareCardSheet: View {
    let content: ShareCardContent
    @Environment(\.dismiss) private var dismiss
    @Environment(SportMode.self) private var sportMode
    private let social = Social.shared
    @State private var link: URL?
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Laid out at the exported size, shown scaled down.
                ShareCardView(content: content, sport: sportMode.sport, link: link)
                    .frame(width: 360, height: 576)
                    .scaleEffect(300.0 / 360.0)
                    .frame(width: 300, height: 480)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(Court.courtDrop)

                if let image {
                    ShareLink(item: Image(uiImage: image), message: Text(message),
                              preview: SharePreview(content.title, image: Image(uiImage: image))) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .courtBigButton()
                    }
                    .padding(.horizontal, 24)
                } else {
                    ProgressView()
                }
            }
            .padding(.top, 20)
            .frame(maxHeight: .infinity, alignment: .top)
            .courtGround()
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } } }
            .task {
                if social.phase == .ready, let invite = await social.inviteLink(.friend) {
                    link = social.shareURL(for: invite)
                }
                render()
            }
        }
        .presentationDetents([.large])
    }

    private var message: String {
        [content.callToAction, link?.absoluteString].compactMap { $0 }.joined(separator: " ")
    }

    private func render() {
        let renderer = ImageRenderer(content: ShareCardView(content: content, sport: sportMode.sport, link: link)
            .frame(width: 360, height: 576))
        renderer.scale = 3
        image = renderer.uiImage
    }
}

/// The card itself, in the app's night look so it reads the same in any
/// feed: charcoal, a raised court plate with sunken boxes, and one thin
/// line of the sport's colour, like the selected tab at night.
struct ShareCardView: View {
    let content: ShareCardContent
    let sport: Sport
    let link: URL?

    /// Fixed colours: the image must look the same whatever mode the phone is in.
    private enum Ink {
        static let ground = Color(hex: 0x1C1D1F)
        static let plate = Color(hex: 0x2A2C2F)
        static let raised = Color(hex: 0x26282B)
        static let sunken = Color(hex: 0x17181A)
        static let text = Color(hex: 0xF2F2F0)
        static let muted = Color(hex: 0xC9CACB)
        static let dim = Color(hex: 0xA9AAAB)
    }

    var body: some View {
        ZStack {
            Ink.ground
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(verbatim: "\(sport.displayName.uppercased()) · \(content.title.uppercased())")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(Ink.dim)
                        .lineLimit(1)
                    Spacer()
                }
                Text(content.subtitle)
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(-0.9)
                    .foregroundStyle(Ink.text)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 8)

                plate
                    .padding(.top, 20)

                if let score = content.scoreLine {
                    Text(score)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Ink.text)
                        .padding(.top, 16)
                }
                Spacer(minLength: 12)
                Text(content.callToAction)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Ink.muted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 8) {
                    BallIcon(sport: sport, size: 16)
                    Text(verbatim: "PickleBall")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Ink.text)
                    Spacer()
                    if let host = link?.host() {
                        Text(verbatim: host)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Ink.dim)
                            .lineLimit(1)
                    }
                }
                .padding(.top, 14)
            }
            .padding(24)
        }
        .environment(\.colorScheme, .dark)
    }

    /// A small court: two sunken halves, the badge raised on the net.
    private var plate: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Ink.sunken)
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Ink.sunken)
        }
        .padding(10)
        .frame(minHeight: 120, maxHeight: 210)
        .background(shape.fill(Ink.plate).shadow(color: .black.opacity(0.6), radius: 14, x: 8, y: 12))
        .overlay(alignment: .bottom) {
            // The one touch of sport colour.
            Rectangle()
                .fill(Court.accent(sport))
                .frame(height: Court.Metrics.selectedLine)
                .padding(.horizontal, 40)
                .clipShape(Capsule())
                .padding(.bottom, 4)
        }
        .overlay {
            ZStack {
                Circle()
                    .fill(Ink.raised)
                    .frame(width: 104, height: 104)
                    .shadow(color: .black.opacity(0.55), radius: 8, x: 5, y: 7)
                    .shadow(color: .white.opacity(0.05), radius: 5, x: -4, y: -4)
                if let tier = content.tier {
                    BeltBadge(tier: tier, size: 58)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(content.kind == .trophy ? DS.Palette.gold : Ink.text)
                }
            }
        }
    }

    private var symbol: String {
        switch content.kind {
        case .trophy: return "trophy.fill"
        case .comeback: return "arrow.up.right"
        case .result: return "rosette"
        default: return "crown.fill"
        }
    }
}
