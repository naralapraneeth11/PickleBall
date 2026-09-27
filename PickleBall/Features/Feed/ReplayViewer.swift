//
//  ReplayViewer.swift
//  PickleBall
//
//  Replays play like stories: one beat per page, tap to advance, hold to
//  pause. From here you can send it to a friend or squad chat, or (if
//  it's yours) save it to your trophy case so it outlives 24 hours.
//

import SwiftUI
import CourtKit
import CourtNet

struct ReplayViewer: View {
    let replays: [ReplayRow]
    @Environment(\.dismiss) private var dismiss
    private let social = Social.shared
    @State private var replayIndex = 0
    @State private var beatIndex = 0
    @State private var progress: Double = 0
    @State private var paused = false
    @State private var showSend = false

    private static let beatDuration: Double = 3.2

    private var replay: ReplayRow? { replays.indices.contains(replayIndex) ? replays[replayIndex] : nil }

    var body: some View {
        ZStack {
            DS.Palette.night.ignoresSafeArea()
            if let replay {
                let beats = replay.story.beats
                VStack(spacing: 14) {
                    HStack(spacing: 4) {
                        ForEach(beats.indices, id: \.self) { index in
                            GeometryReader { geo in
                                Capsule().fill(DS.Palette.hairline)
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(Color.white)
                                            .frame(width: geo.size.width * fill(for: index))
                                    }
                            }
                            .frame(height: 3)
                        }
                    }
                    header(replay)
                    Spacer()
                    if beats.indices.contains(beatIndex) {
                        BeatView(beat: beats[beatIndex], replay: replay)
                            .id("\(replay.id)-\(beatIndex)")
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                    Spacer()
                    actions(replay)
                }
                .padding(20)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in paused = true }
                        .onEnded { value in
                            paused = false
                            if abs(value.translation.width) < 10 && abs(value.translation.height) < 10 {
                                value.location.x < 120 ? back() : advance()
                            } else if value.translation.height > 100 {
                                dismiss()
                            }
                        }
                )
            }
        }
        .preferredColorScheme(.dark)
        .animation(DS.Motion.snappy, value: beatIndex)
        .task(id: "\(replayIndex)-\(beatIndex)") {
            progress = 0
            let steps = 40
            for _ in 0..<steps {
                try? await Task.sleep(for: .seconds(Self.beatDuration / Double(steps)))
                if Task.isCancelled { return }
                if !paused { progress += 1 / Double(steps) }
            }
            advance()
        }
        .sheet(isPresented: $showSend) {
            if let replay { SendToChatView(replay: replay) }
        }
    }

    private func fill(for index: Int) -> Double {
        if index < beatIndex { return 1 }
        if index == beatIndex { return min(1, progress) }
        return 0
    }

    private func header(_ replay: ReplayRow) -> some View {
        HStack(spacing: 10) {
            ProfileAvatar(userID: replay.authorID, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(replay.authorID == social.userID ? "You" : social.name(of: replay.authorID))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(RelativeTime.short(replay.createdAt)).font(.caption).foregroundStyle(DS.Palette.nightMuted)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).frame(width: 40, height: 40)
            }
            .accessibilityLabel("Close")
        }
        .foregroundStyle(.white)
    }

    private func actions(_ replay: ReplayRow) -> some View {
        HStack(spacing: 12) {
            Button { showSend = true } label: {
                Label("Send", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.nightRaised))
            }
            if replay.authorID == social.userID {
                Button {
                    Task { await social.saveReplayToTrophyCase(replay) }
                } label: {
                    Label(replay.saved || isSaved(replay) ? "Saved" : "Save to trophy case", systemImage: "trophy.fill")
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.nightRaised))
                }
                .disabled(replay.saved || isSaved(replay))
            } else {
                Menu {
                    Button("Report", role: .destructive) {
                        Task { _ = await social.report(.replay, id: replay.id, reason: "Reported Replay") }
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 46, height: 46)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.nightRaised))
                }
            }
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
    }

    private func isSaved(_ replay: ReplayRow) -> Bool {
        social.replays.first { $0.id == replay.id }?.saved == true
    }

    private func advance() {
        guard let replay else { return }
        if beatIndex + 1 < replay.story.beats.count {
            beatIndex += 1
        } else if replayIndex + 1 < replays.count {
            replayIndex += 1
            beatIndex = 0
        } else {
            dismiss()
        }
    }

    private func back() {
        if beatIndex > 0 {
            beatIndex -= 1
        } else if replayIndex > 0 {
            replayIndex -= 1
            beatIndex = 0
        }
    }
}

private struct BeatView: View {
    let beat: ReplayStory.Beat
    let replay: ReplayRow

    var body: some View {
        VStack(spacing: 14) {
            switch beat {
            case .opening(let sport, let date, let court, let isTitleMatch):
                BallIcon(sport: sport, size: 52)
                if isTitleMatch {
                    Label("TITLE MATCH", systemImage: "crown.fill")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(DS.Palette.gold)
                }
                Text(replay.story.headline)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                Text([date.formatted(date: .abbreviated, time: .shortened), court].compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(DS.Palette.nightMuted)
            case .lineup(let teamA, let teamB):
                Text(teamA.joined(separator: " & ")).font(.system(size: 28, weight: .heavy, design: .rounded))
                Text("VS").font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(DS.Palette.nightMuted)
                Text(teamB.joined(separator: " & ")).font(.system(size: 28, weight: .heavy, design: .rounded))
            case .unit(let index, let score, let tiebreak, let isSuperTiebreak):
                Text(isSuperTiebreak ? "MATCH TIEBREAK" : "\(index + 1)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(DS.Palette.nightMuted)
                let shown = isSuperTiebreak ? (tiebreak ?? score) : score
                Text("\(shown.a)–\(shown.b)").font(DS.Typography.hero(88))
                if let tiebreak, !isSuperTiebreak {
                    Text("Tiebreak \(tiebreak.a)–\(tiebreak.b)").foregroundStyle(DS.Palette.nightMuted)
                }
            case .moment(let text):
                Image(systemName: "bolt.fill").font(.system(size: 40)).foregroundStyle(DS.Palette.gold)
                Text(text).font(.system(size: 28, weight: .heavy, design: .rounded)).multilineTextAlignment(.center)
            case .photo(let index):
                if replay.photoPaths.indices.contains(index) {
                    RemotePhoto(path: replay.photoPaths[index], contentMode: .fit)
                        .frame(maxHeight: 460)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            case .belt(let text):
                BeltBadge(tier: .gold, size: 70)
                Text(text).font(.system(size: 28, weight: .heavy, design: .rounded)).multilineTextAlignment(.center)
            case .workout(let minutes, let heartRate, let calories):
                Image(systemName: "applewatch").font(.system(size: 40))
                Text("\(minutes) min").font(DS.Typography.hero(56))
                Text([heartRate.map { "\($0) bpm avg" }, calories.map { "\($0) kcal" }].compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(DS.Palette.nightMuted)
            case .final(let winners, let scoreLine):
                Text("FINAL").font(.system(size: 15, weight: .heavy, design: .rounded)).tracking(3).foregroundStyle(DS.Palette.nightMuted)
                Text(winners).font(.system(size: 32, weight: .heavy, design: .rounded)).multilineTextAlignment(.center)
                Text(scoreLine).font(DS.Typography.score(28))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }
}

/// Pick a friend or squad chat to send a Replay to.
struct SendToChatView: View {
    let replay: ReplayRow
    @Environment(\.dismiss) private var dismiss
    private let social = Social.shared

    var body: some View {
        NavigationStack {
            List(social.conversations) { conversation in
                Button {
                    Task {
                        await social.sendReplay(replay, to: conversation.id)
                        dismiss()
                    }
                } label: {
                    ConversationRowView(conversation: conversation)
                }
            }
            .navigationTitle("Send Replay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
