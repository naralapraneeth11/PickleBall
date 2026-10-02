//
//  FriendsView.swift
//  PickleBall
//
//  Friends, requests, and three ways to add someone: search their
//  username, send your invite link, or scan (or show) a QR code.
//

import SwiftUI
import CourtKit
import CourtNet

struct FriendsView: View {
    @Environment(\.dismiss) private var dismiss
    private let social = Social.shared
    @State private var query = ""
    @State private var results: [ProfileCard] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var inviteURL: URL?
    @State private var showQR = false
    @State private var showScanner = false
    @State private var showCode = false
    @State private var code = ""

    var body: some View {
        List {
            if !query.isEmpty {
                Section("Results") {
                    Group {
                        if results.isEmpty {
                            Text("No one with that username yet.").foregroundStyle(.secondary)
                        }
                        ForEach(results) { card in
                            PersonRow(userID: card.id, name: card.displayName, username: card.username) {
                                relationshipButton(card.id)
                            }
                        }
                    }
                    .courtRows()
                }
            } else {
                Section {
                    Group {
                        Button { Task { await makeInvite() } } label: {
                            Label("Share my invite link", systemImage: "link")
                        }
                        Button { showQR = true } label: { Label("Show my QR code", systemImage: "qrcode") }
                        Button { showScanner = true } label: { Label("Scan a QR code", systemImage: "qrcode.viewfinder") }
                        Button { showCode = true } label: { Label("Enter an invite code", systemImage: "keyboard") }
                    }
                    .courtRows()
                } footer: {
                    Text("Friends see your matches, Serves and belts. Nothing is ever public.")
                }

                if !social.incomingRequests.isEmpty {
                    Section("Requests") {
                        Group {
                            ForEach(social.incomingRequests) { profile in
                                PersonRow(userID: profile.id, name: profile.displayName, username: profile.username) {
                                    HStack(spacing: 6) {
                                        PillButton(title: "Accept", prominent: true, tint: DS.Palette.win) {
                                            Task { await social.respondToRequest(from: profile.id, accept: true) }
                                        }
                                        PillButton(title: "Ignore", tint: DS.Palette.textMuted) {
                                            Task { await social.respondToRequest(from: profile.id, accept: false) }
                                        }
                                    }
                                }
                            }
                        }
                        .courtRows()
                    }
                }

                if !social.outgoingRequests.isEmpty {
                    Section("Sent") {
                        Group {
                            ForEach(social.outgoingRequests) { profile in
                                PersonRow(userID: profile.id, name: profile.displayName, username: profile.username) {
                                    Text("Pending").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .courtRows()
                    }
                }

                Section("Friends") {
                    Group {
                        if social.friends.isEmpty {
                            Text("Search a username above, or share your link with the people you play.").foregroundStyle(.secondary)
                        }
                        ForEach(social.friends) { profile in
                            NavigationLink {
                                ProfileView(playerID: PlayerID(rawValue: profile.id))
                            } label: {
                                PersonRow(userID: profile.id, name: profile.displayName, username: profile.username) { EmptyView() }
                            }
                        }
                    }
                    .courtRows()
                }

                let guests = PlayerDirectory.shared.guests
                if !guests.isEmpty {
                    Section {
                        Group {
                            NavigationLink {
                                GuestsView()
                            } label: {
                                Label("Guests you’ve played (\(guests.count))", systemImage: "person.fill.questionmark")
                            }
                        }
                        .courtRows()
                    }
                }
            }
        }
        .courtList()
        .navigationTitle("Friends")
        .searchable(text: $query, prompt: "Search usernames")
        .textInputAutocapitalization(.never)
        .onChange(of: query) { _, _ in search() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .sheet(item: Binding(get: { inviteURL.map(IdentifiedURL.init) }, set: { inviteURL = $0?.url })) { item in
            ShareSheet(items: ["Play me on PickleBall. Tap to add me as a friend: \(item.url.absoluteString)", item.url])
        }
        .sheet(isPresented: $showQR) { MyQRCodeView() }
        .sheet(isPresented: $showScanner) {
            QRScannerView { link in
                showScanner = false
                Task { await social.redeem(link) }
            }
        }
        .alert("Invite code", isPresented: $showCode) {
            TextField("Code or link", text: $code)
                .textInputAutocapitalization(.never)
            Button("Add") {
                if let link = InviteLink(text: code) {
                    Task { await social.redeem(link) }
                } else {
                    social.notice = "That code doesn’t look right."
                }
                code = ""
            }
            Button("Cancel", role: .cancel) { code = "" }
        }
        .refreshable { await social.refreshFriends() }
        .noticeToast()
    }

    @ViewBuilder
    private func relationshipButton(_ id: UUID) -> some View {
        switch social.relationship(with: id) {
        case .friend: Text("Friends").font(.caption.weight(.semibold)).foregroundStyle(DS.Palette.win)
        case .outgoing: Text("Requested").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        case .incoming:
            PillButton(title: "Accept", prominent: true, tint: DS.Palette.win) { Task { await social.respondToRequest(from: id, accept: true) } }
        case .me, .blocked: EmptyView()
        case .none:
            PillButton(title: "Add", systemImage: "person.badge.plus", prominent: true) { Task { await social.requestFriend(id) } }
        }
    }

    private func search() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            results = await social.search(query)
        }
    }

    private func makeInvite() async {
        guard let link = await social.inviteLink(.friend) else { return }
        inviteURL = social.shareURL(for: link)
    }
}

struct PersonRow<Accessory: View>: View {
    let userID: UUID
    let name: String
    let username: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatar(userID: userID, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(.primary)
                Text("@\(username)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            accessory()
        }
    }
}

struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// UIActivityViewController, for sharing text and a link together.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Guests created on this phone, each with a link to claim their stats.
struct GuestsView: View {
    @ObservedObject private var directory = PlayerDirectory.shared
    private let social = Social.shared
    @State private var shareURL: URL?

    var body: some View {
        List {
            Section {
                Group {
                    ForEach(directory.guests) { guest in
                        HStack {
                            Avatar(name: guest.displayName, color: DS.Palette.textMuted, size: 36)
                            Text(guest.displayName)
                            Spacer()
                            PillButton(title: "Claim link", systemImage: "link") {
                                Task {
                                    if let link = await social.inviteLink(.guestClaim, target: guest.id.rawValue) {
                                        shareURL = social.shareURL(for: link)
                                    }
                                }
                            }
                        }
                    }
                }
                .courtRows()
            } footer: {
                Text("A guest who signs up with their link gets every match you played together, and becomes your friend.")
            }
        }
        .courtList()
        .navigationTitle("Guests")
        .sheet(item: Binding(get: { shareURL.map(IdentifiedURL.init) }, set: { shareURL = $0?.url })) { item in
            ShareSheet(items: ["Claim our matches on PickleBall: \(item.url.absoluteString)", item.url])
        }
        .noticeToast()
    }
}
