//
//  BlockedUsersView.swift
//  PickleBall
//
//  People you've blocked. They can't message you, see your Serves or call
//  you out, and they aren't told.
//

import SwiftUI
import CourtKit

struct BlockedUsersView: View {
    private let social = Social.shared

    var body: some View {
        List {
            Group {
                ForEach(Array(social.blocked), id: \.self) { id in
                    HStack {
                        ProfileAvatar(userID: id, size: 34)
                        Text(social.name(of: id))
                        Spacer()
                        Button("Unblock") { Task { await social.unblock(id) } }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .courtRows()
        }
        .courtList()
        .navigationTitle("Blocked")
        .overlay {
            if social.blocked.isEmpty {
                ContentUnavailableView("Nobody blocked", systemImage: "hand.raised")
            }
        }
    }
}
