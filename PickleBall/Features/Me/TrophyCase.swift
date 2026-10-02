//
//  TrophyCase.swift
//  PickleBall
//
//  Tournament wins and saved Replays.
//

import SwiftUI
import CourtKit
import CourtNet

struct TrophyCase: View {
    let trophies: [TrophyRow]
    private let social = Social.shared
    @State private var openReplay: ReplayRow?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(trophies) { trophy in
                    Button {
                        if trophy.kind == .replay, let id = trophy.replayID {
                            openReplay = social.replays.first { $0.id == id }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: trophy.kind == .tournament ? "trophy.fill" : "play.rectangle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(trophy.kind == .tournament ? DS.Palette.gold : DS.Palette.electricBlue)
                            Text(trophy.title)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(Court.text)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(trophy.awardedAt.formatted(.dateTime.month(.abbreviated).year()))
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(Court.muted)
                        }
                        .frame(width: 130, alignment: .leading)
                        .padding(14)
                        .courtRaised(cornerRadius: 16)
                    }
                    .buttonStyle(.press)
                }
            }
        }
        .fullScreenCover(item: $openReplay) { replay in
            ReplayViewer(replays: [replay])
        }
    }
}
