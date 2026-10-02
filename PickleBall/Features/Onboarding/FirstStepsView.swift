//
//  FirstStepsView.swift
//  PickleBall
//
//  First run after the profile is set up: how it works in three cards,
//  then bring your crew and choose whether to get nudges. Every step can be
//  skipped; nothing here is required to play.
//

import SwiftUI
import CourtKit
import CourtNet

struct FirstStepsView: View {
    var onDone: () -> Void
    private let social = Social.shared
    @State private var page = 0
    @State private var inviteURL: IdentifiedURL?
    @State private var showFriends = false
    @State private var nudgesAsked = false

    private let lastPage = 3

    @Environment(SportMode.self) private var sportMode
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { finish() }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Court.muted)
                    .padding()
            }
            TabView(selection: $page) {
                card(symbol: "checkmark.seal",
                     title: "Score it. They confirm it.",
                     text: "Score on your Watch or phone, or type it in after. The other side confirms, so every result counts.")
                    .tag(0)
                card(symbol: "crown",
                     title: "Come for the belt.",
                     text: "Beat whoever holds it and it’s yours. Climb your squad’s ladder, run brackets and Mexicano nights, and watch your level move.")
                    .tag(1)
                crewCard.tag(2)
                nudgeCard.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Same dots as Home.
            HStack(spacing: 6) {
                ForEach(0...lastPage, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Court.activeDot(sportMode.sport, scheme: scheme) : Court.dotOff)
                        .frame(width: index == page ? 18 : 6, height: 6)
                }
            }
            .animation(.snappy(duration: 0.25), value: page)
            .padding(.bottom, 18)
            .accessibilityHidden(true)

            Button {
                if page < lastPage {
                    withAnimation { page += 1 }
                } else {
                    finish()
                }
            } label: {
                (page < lastPage ? Text("Next") : Text("Let’s play"))
                    .courtBigButton()
            }
            .buttonStyle(.press)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .courtGround()
        .sheet(item: $inviteURL) { item in
            ShareSheet(items: [String(localized: "Play me on PickleBall: \(item.url.absoluteString)"), item.url])
        }
        .sheet(isPresented: $showFriends) {
            NavigationStack { FriendsView() }
        }
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(Court.text)
            .frame(width: 76, height: 76)
            .courtRaisedCapsule()
            .padding(.bottom, 6)
    }

    private func title(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 34, weight: .semibold))
            .tracking(-1)
            .foregroundStyle(Court.text)
    }

    private func bodyText(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Court.muted)
    }

    private func card(symbol: String, title text: LocalizedStringKey, text body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            icon(symbol)
            title(text)
            bodyText(body)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var crewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            icon("person.3")
            title("Bring your crew.")
            bodyText("PickleBall is friends only. Send your link to the people you play with.")
            VStack(spacing: 12) {
                pill("Share my invite link", symbol: "link") {
                    Task {
                        if let link = await social.inviteLink(.friend) { inviteURL = IdentifiedURL(url: social.shareURL(for: link)) }
                    }
                }
                pill("Find friends by username", symbol: "magnifyingglass") { showFriends = true }
            }
            .padding(.top, 8)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nudgeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            icon("bell.badge")
            title("Low-key nudges.")
            bodyText("One short line at most once a day, like “👀 Sam’s still wearing your belt”. Never at night. Mute any kind in Settings.")
            pill(nudgesAsked ? "Nudges are set" : "Turn on nudges", symbol: nudgesAsked ? "checkmark" : "bell") {
                Task {
                    _ = await Nudger.shared.requestPermission()
                    nudgesAsked = true
                }
            }
            .disabled(nudgesAsked)
            .padding(.top, 8)
            Label("Add the Belt widget to your Home or Lock Screen to see who’s wearing it.", systemImage: "square.grid.2x2")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Court.muted)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pill(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Court.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .courtRaised(cornerRadius: 18)
        }
        .buttonStyle(.press)
    }

    private func finish() {
        Haptics.success()
        onDone()
    }
}
