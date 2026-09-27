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
                ShareCardView(content: content, sport: sportMode.sport, link: link)
                    .frame(width: 300, height: 480)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 10)

                if let image {
                    ShareLink(item: Image(uiImage: image), message: Text(message),
                              preview: SharePreview(content.title, image: Image(uiImage: image))) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(DS.Palette.royalBlue))
                    }
                    .padding(.horizontal, 24)
                } else {
                    ProgressView()
                }
            }
            .padding(.top, 20)
            .frame(maxHeight: .infinity, alignment: .top)
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

struct ShareCardView: View {
    let content: ShareCardContent
    let sport: Sport
    let link: URL?

    var body: some View {
        ZStack {
            LinearGradient(colors: [DS.Palette.navy, sport.theme.courtSurfaceAlt], startPoint: .top, endPoint: .bottom)
            CourtArtView(sport: sport, lineWidth: 1.2, lineOpacity: 0.15, showsSurface: false)
                .padding(24)

            VStack(spacing: 16) {
                Spacer()
                if let tier = content.tier {
                    BeltBadge(tier: tier, size: 64)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 54, weight: .bold))
                        .foregroundStyle(DS.Palette.gold)
                }
                Text(content.title.uppercased())
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(sport.theme.accent)
                Text(content.subtitle)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 20)
                if let score = content.scoreLine {
                    Text(score)
                        .font(DS.Typography.score(26))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Text(content.callToAction)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                HStack(spacing: 8) {
                    BallIcon(sport: sport, size: 18)
                    Text("PickleBall")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.bottom, 22)
            }
        }
    }

    private var symbol: String {
        switch content.kind {
        case .trophy: return "trophy.fill"
        case .comeback: return "arrow.up.right.circle.fill"
        default: return "crown.fill"
        }
    }
}
