//
//  SharePromptHost.swift
//  PickleBall
//
//  Share cards are offered after a belt win, a trophy or a big comeback —
//  often while the scoreboard or another sheet is on screen. Every
//  presentation root hosts the prompt; only the topmost one shows it, so
//  it appears wherever the player is and never collides with a sheet.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class PresentationStack {
    static let shared = PresentationStack()
    private(set) var tokens: [UUID] = []

    func push(_ token: UUID) {
        tokens.removeAll { $0 == token }
        tokens.append(token)
    }

    func pop(_ token: UUID) {
        tokens.removeAll { $0 == token }
    }

    var top: UUID? { tokens.last }
}

struct SharePromptHost: ViewModifier {
    @State private var token = UUID()
    private let stack = PresentationStack.shared
    private let social = Social.shared

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(
                get: { stack.top == token ? social.sharePrompt : nil },
                set: { social.sharePrompt = $0 }
            )) { prompt in
                ShareCardSheet(content: prompt.content)
            }
            .onAppear { stack.push(token) }
            .onDisappear { stack.pop(token) }
    }
}

extension View {
    func sharePromptHost() -> some View { modifier(SharePromptHost()) }
}
