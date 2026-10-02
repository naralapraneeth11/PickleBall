//
//  ChatsView.swift
//  PickleBall
//
//  Friend chats and squad chats, newest first, with friend requests on top
//  and a way to add friends or start a squad.
//

import SwiftUI
import CourtKit
import CourtNet

struct ChatsView: View {
    private let social = Social.shared
    @State private var showFriends = false
    @State private var showNewSquad = false

    var body: some View {
        List {
            if !social.incomingRequests.isEmpty {
                Section {
                    NavigationLink {
                        FriendsView()
                    } label: {
                        HStack {
                            AvatarStack(userIDs: social.incomingRequests.map(\.id), size: 30)
                            Text("\(social.incomingRequests.count) friend request\(social.incomingRequests.count == 1 ? "" : "s")")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                        }
                    }
                }
            }

            let squadChats = social.conversations.filter { $0.kind == .squad }
            if !squadChats.isEmpty {
                Section("Squads") {
                    ForEach(squadChats) { conversation in
                        NavigationLink(value: conversation) { ConversationRowView(conversation: conversation) }
                    }
                }
            }

            let friendChats = social.conversations.filter { $0.kind == .direct && social.people(in: $0).allSatisfy { !social.blocked.contains($0) } }
            Section("Friends") {
                ForEach(friendChats) { conversation in
                    NavigationLink(value: conversation) { ConversationRowView(conversation: conversation) }
                }
                Button {
                    showFriends = true
                } label: {
                    Label(social.friends.isEmpty ? "Add your first friend" : "Friends", systemImage: "person.2.fill")
                }
            }
        }
        .courtList()
        .navigationTitle("Chats")
        .navigationDestination(for: ConversationRow.self) { conversation in
            ChatView(conversationID: conversation.id)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showFriends = true } label: { Image(systemName: "person.badge.plus") }
                    .accessibilityLabel("Add friends")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNewSquad = true } label: { Image(systemName: "person.3.fill") }
                    .accessibilityLabel("New squad")
            }
        }
        .sheet(isPresented: $showFriends) {
            NavigationStack { FriendsView() }
        }
        .sheet(isPresented: $showNewSquad) {
            CreateSquadView()
        }
        .refreshable { await social.refreshAll() }
        .overlay {
            if social.conversations.isEmpty && social.incomingRequests.isEmpty {
                ContentUnavailableView {
                    Label("No chats yet", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Add friends by username, link or QR code. Every friend gets a chat, and every squad gets one too.")
                } actions: {
                    Button("Add friends") { showFriends = true }.buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

struct ConversationRowView: View {
    let conversation: ConversationRow
    private let social = Social.shared

    var body: some View {
        HStack(spacing: 12) {
            switch conversation.kind {
            case .direct:
                if let friend = social.people(in: conversation).first { ProfileAvatar(userID: friend, size: 46) }
            case .squad:
                ZStack {
                    Circle().fill(DS.Palette.royalBlue).frame(width: 46, height: 46)
                    Image(systemName: "person.3.fill").foregroundStyle(.white).font(.system(size: 16))
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(social.title(of: conversation))
                        .font(.system(size: 16, weight: social.hasUnread(conversation) ? .bold : .semibold, design: .rounded))
                        .lineLimit(1)
                    if let belt = headlineBelt {
                        BeltBadge(tier: belt.tier, size: 16)
                    }
                }
                Text(preview)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if let date = conversation.lastMessageAt {
                    Text(RelativeTime.short(date)).font(.caption).foregroundStyle(.secondary)
                }
                if social.hasUnread(conversation) {
                    Circle().fill(DS.Palette.electricBlue).frame(width: 9, height: 9)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var headlineBelt: Belt? {
        ChatBelt.belts(for: conversation, social: social).first
    }

    private var preview: String {
        guard let last = social.messages[conversation.id]?.last else {
            return conversation.kind == .squad ? "Say hi to the squad" : "Say hi"
        }
        let who = last.senderID == social.userID ? "You: " : (conversation.kind == .squad ? last.senderID.map { "\(social.firstName(of: $0)): " } ?? "" : "")
        switch last.kind {
        case .text: return who + (last.body ?? "")
        case .photo: return who + "Photo"
        case .event: return last.payload.map { EventText.summary($0, social: social) } ?? "Update"
        }
    }
}
