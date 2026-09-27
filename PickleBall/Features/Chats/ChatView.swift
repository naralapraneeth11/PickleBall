//
//  ChatView.swift
//  PickleBall
//
//  A friend or squad chat. The belt they're fighting over is pinned on
//  top; results, belt changes, call outs and Replays arrive as event
//  cards between messages. Long-press to report or delete.
//

import SwiftUI
import PhotosUI
import CourtKit
import CourtNet

struct ChatView: View {
    let conversationID: UUID
    private let social = Social.shared
    @State private var text = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showInfo = false
    @State private var showCallOut = false
    @State private var reporting: MessageRow?
    @State private var openedReplay: ReplayRow?
    @State private var openedMatch: MatchRecord?
    @State private var confirmBlock = false
    @FocusState private var composerFocused: Bool

    private var conversation: ConversationRow? { social.conversations.first { $0.id == conversationID } }
    private var messages: [MessageRow] { social.messages[conversationID] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            if let conversation {
                BeltBanner(conversation: conversation)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            let previous = index > 0 ? messages[index - 1] : nil
                            if previous.map({ !Calendar.current.isDate($0.createdAt, inSameDayAs: message.createdAt) }) ?? true {
                                Text(message.createdAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 8)
                            }
                            messageView(message, showsSender: previous?.senderID != message.senderID)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                .onChange(of: messages.last?.id) { _, id in
                    guard let id else { return }
                    withAnimation(DS.Motion.snappy) { proxy.scrollTo(id, anchor: .bottom) }
                    social.markRead(conversationID)
                }
            }
            composer
        }
        .navigationTitle(conversation.map(social.title(of:)) ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showInfo = true } label: {
                        Label(conversation?.kind == .squad ? "Squad info" : "Player card", systemImage: "info.circle")
                    }
                    Button { showCallOut = true } label: { Label("Call out", systemImage: "flag.2.crossed") }
                    if conversation?.kind == .direct, let friend = friendID {
                        Divider()
                        Button(role: .destructive) {
                            Task { _ = await social.report(.user, id: friend, reason: "Reported from chat") }
                        } label: { Label("Report", systemImage: "exclamationmark.bubble") }
                        Button(role: .destructive) { confirmBlock = true } label: { Label("Block", systemImage: "hand.raised") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showInfo) {
            NavigationStack {
                if let conversation, conversation.kind == .squad, let squadID = conversation.squadID {
                    SquadInfoView(squadID: squadID)
                } else if let friendID {
                    ProfileView(playerID: PlayerID(rawValue: friendID))
                }
            }
        }
        .sheet(isPresented: $showCallOut) {
            CallOutComposerView(opponents: friendID.map { [$0] } ?? [], squadID: conversation?.squadID)
        }
        .sheet(item: $reporting) { message in
            ReportSheet(target: .message, id: message.id)
        }
        .fullScreenCover(item: $openedReplay) { replay in
            ReplayViewer(replays: [replay])
        }
        .sheet(item: $openedMatch) { record in
            NavigationStack { MatchDetailView(record: record) }
        }
        .confirmationDialog("Block \(friendID.map(social.firstName(of:)) ?? "them")?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                if let friendID { Task { await social.block(friendID) } }
            }
        } message: {
            Text("They won’t be able to message you, see your Serves or call you out. They aren’t told.")
        }
        .onChange(of: photoItem) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self), let jpeg = ImageResizer.jpeg(data) else { return }
                photoItem = nil
                guard await ContentSafety.isSafe(imageData: jpeg) else {
                    social.notice = "That photo can’t be sent."
                    return
                }
                await social.send("", in: conversationID, photo: jpeg)
            }
        }
        .task {
            await social.loadMessages(in: conversationID)
            social.markRead(conversationID)
        }
    }

    private var friendID: UUID? {
        guard let conversation, conversation.kind == .direct else { return nil }
        return social.people(in: conversation).first
    }

    // MARK: Messages

    @ViewBuilder
    private func messageView(_ message: MessageRow, showsSender: Bool) -> some View {
        if message.kind == .event, let event = message.payload {
            EventCard(event: event) { open(event) }
                .padding(.vertical, 4)
        } else {
            let mine = message.senderID == social.userID
            HStack(alignment: .bottom, spacing: 8) {
                if mine { Spacer(minLength: 50) }
                if !mine, conversation?.kind == .squad {
                    if showsSender, let sender = message.senderID {
                        ProfileAvatar(userID: sender, size: 28)
                    } else {
                        Color.clear.frame(width: 28, height: 28)
                    }
                }
                VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                    if !mine, showsSender, conversation?.kind == .squad, let sender = message.senderID {
                        Text(social.firstName(of: sender)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    bubble(message, mine: mine)
                }
                if !mine { Spacer(minLength: 50) }
            }
            .opacity(social.isPending(message) ? 0.6 : 1)
            .contextMenu {
                if let body = message.body {
                    Button { UIPasteboard.general.string = body } label: { Label("Copy", systemImage: "doc.on.doc") }
                }
                if mine {
                    Button(role: .destructive) { Task { await social.deleteMessage(message) } } label: { Label("Delete", systemImage: "trash") }
                } else {
                    Button(role: .destructive) { reporting = message } label: { Label("Report", systemImage: "exclamationmark.bubble") }
                }
            }
        }
    }

    @ViewBuilder
    private func bubble(_ message: MessageRow, mine: Bool) -> some View {
        if message.kind == .photo, let path = message.mediaPath {
            RemotePhoto(path: path)
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            Text(message.body ?? "")
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(mine ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(mine ? DS.Palette.electricBlue : Color(.secondarySystemBackground)))
        }
    }

    private func open(_ event: ChatEvent) {
        switch event {
        case .result(let matchID):
            openedMatch = MatchStore.shared.record(id: matchID)
        case .belt(let belt):
            openedMatch = MatchStore.shared.record(id: belt.matchID)
        case .replay(let replayID, _):
            openedReplay = social.replays.first { $0.id == replayID }
            if openedReplay == nil { social.notice = "That Replay has expired." }
        case .callOut, .joined, .tournamentCreated, .champion, .unknown:
            break
        }
    }

    // MARK: Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 20))
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Send a photo")
            TextField("Message", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemBackground)))
                .focused($composerFocused)
            Button {
                let message = text
                text = ""
                Haptics.light()
                Task { await social.send(message, in: conversationID) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : DS.Palette.electricBlue)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .padding(.bottom, 64)
        .background(.bar)
    }
}

// MARK: - Belt banner

enum ChatBelt {
    /// The belts a chat is about: the friends' rivalry belts, or the squad's.
    @MainActor
    static func belts(for conversation: ConversationRow, social: Social) -> [Belt] {
        let ledger = MatchStore.shared.belts
        switch conversation.kind {
        case .squad:
            return conversation.squadID.map(ledger.squadBelts) ?? []
        case .direct:
            guard let me = social.userID, let friend = social.people(in: conversation).first else { return [] }
            return ledger.rivalryBelts(between: PlayerID(rawValue: me), and: PlayerID(rawValue: friend))
        }
    }
}

/// Pinned at the top of every chat: who holds the belt, and their record.
struct BeltBanner: View {
    let conversation: ConversationRow
    private let social = Social.shared

    var body: some View {
        let belts = ChatBelt.belts(for: conversation, social: social)
        if belts.isEmpty {
            HStack(spacing: 10) {
                BeltBadge(tier: .plain, size: 22).opacity(0.5)
                Text(conversation.kind == .squad ? "The first squad match creates the squad belt." : "Your first match creates your belt.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(belts) { belt in
                        NavigationLink {
                            BeltDetailView(belt: belt)
                        } label: {
                            BeltChip(belt: belt)
                        }
                        .buttonStyle(.press)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.bar)
        }
    }
}

struct BeltChip: View {
    let belt: Belt
    private let social = Social.shared

    var body: some View {
        let holder = belt.holder ?? []
        let record = holder.first.map(belt.record(of:)) ?? (0, 0)
        HStack(spacing: 10) {
            BeltBadge(tier: belt.tier, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(holder.map { social.firstName(of: $0.rawValue) }.joined(separator: " & ")) holds the \(belt.key.kind.isSquad ? "squad " : "")\(belt.key.sport.displayName.lowercased()) belt")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(record.0)–\(record.1) in title matches · \(belt.defenses) defense\(belt.defenses == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(belt.tier == .plain ? Color(.secondarySystemBackground) : DS.Palette.gold.opacity(0.18)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Event cards

enum EventText {
    @MainActor
    static func summary(_ event: ChatEvent, social: Social) -> String {
        switch event {
        case .result(let matchID):
            guard let record = MatchStore.shared.record(id: matchID), let lineup = record.lineup, let winner = record.winner else {
                return "New result"
            }
            return "\(lineup.name(of: winner, separator: " & ")) beat \(lineup.name(of: winner.opponent, separator: " & ")) \(record.result?.perspective(of: lineup.teams[winner].first?.id ?? PlayerID())?.scoreLine ?? "")"
        case .belt(let belt):
            return social.beltLine(belt)
        case .callOut(let id, let by):
            if let row = social.callOuts.first(where: { $0.id == id }) {
                let them = row.challenged.map(social.firstName(of:)).joined(separator: " & ")
                return "\(social.firstName(of: by)) called out \(them)"
            }
            return "\(social.firstName(of: by)) sent a call out"
        case .replay(_, let by):
            return "\(social.firstName(of: by)) shared a Replay"
        case .joined(let user):
            return "\(social.firstName(of: user)) joined the squad"
        case .tournamentCreated(let id):
            return "New tournament: \(social.tournaments.first { $0.id == id }?.name ?? "check Tournaments")"
        case .champion(let id, let champions):
            let names = champions.map(social.firstName(of:)).joined(separator: " & ")
            return "\(names) won \(social.tournaments.first { $0.id == id }?.name ?? "the tournament")!"
        case .unknown:
            return "Update"
        }
    }

    static func symbol(_ event: ChatEvent) -> String {
        switch event {
        case .result: return "sportscourt.fill"
        case .belt: return "crown.fill"
        case .callOut: return "flag.2.crossed.fill"
        case .replay: return "play.rectangle.fill"
        case .joined: return "person.crop.circle.badge.plus"
        case .tournamentCreated: return "calendar"
        case .champion: return "trophy.fill"
        case .unknown: return "sparkles"
        }
    }
}

struct EventCard: View {
    let event: ChatEvent
    let onTap: () -> Void
    private let social = Social.shared

    var body: some View {
        if case .callOut(let id, _) = event, let row = social.callOuts.first(where: { $0.id == id }), row.status.isActive {
            CallOutCard(callOut: row)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
        } else {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    Image(systemName: EventText.symbol(event))
                        .foregroundStyle(isBelt ? DS.Palette.gold : DS.Palette.electricBlue)
                    Text(EventText.summary(event, social: social))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isBelt ? DS.Palette.gold.opacity(0.14) : Color(.secondarySystemBackground)))
            }
            .buttonStyle(.press)
        }
    }

    private var isBelt: Bool {
        if case .belt = event { return true }
        if case .champion = event { return true }
        return false
    }
}

/// Why are you reporting this? Sent to the moderation queue.
struct ReportSheet: View {
    let target: ReportDraft.Target
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    private let social = Social.shared
    private let reasons = ["Harassment or bullying", "Hate or abuse", "Nudity or sexual content", "Spam", "Fake result", "Something else"]

    var body: some View {
        NavigationStack {
            List(reasons, id: \.self) { reason in
                Button(reason) {
                    Task {
                        if await social.report(target, id: id, reason: reason) { dismiss() }
                    }
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
