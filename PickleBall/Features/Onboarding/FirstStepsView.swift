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

    var body: some View {
        ZStack {
            LinearGradient(colors: [DS.Palette.night, DS.Palette.royalBlue], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip") { finish() }
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding()
                }
                TabView(selection: $page) {
                    card(symbol: "checkmark.seal.fill",
                         title: "Score it. They confirm it.",
                         text: "Score on your Watch or phone, or type it in after. The other side confirms, so every result counts.")
                        .tag(0)
                    card(symbol: "crown.fill",
                         title: "Come for the belt.",
                         text: "Beat whoever holds it and it’s yours. Climb your squad’s ladder, run brackets and Mexicano nights, and watch your level move.")
                        .tag(1)
                    crewCard.tag(2)
                    nudgeCard.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button {
                    if page < lastPage {
                        withAnimation { page += 1 }
                    } else {
                        finish()
                    }
                } label: {
                    (page < lastPage ? Text("Next") : Text("Let’s play"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Palette.royalBlue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(.white))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .environment(\.colorScheme, .dark)
        .sheet(item: $inviteURL) { item in
            ShareSheet(items: [String(localized: "Play me on PickleBall: \(item.url.absoluteString)"), item.url])
        }
        .sheet(isPresented: $showFriends) {
            NavigationStack { FriendsView() }
        }
    }

    private func card(symbol: String, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(DS.Palette.gold)
            Text(title)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text(text)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var crewCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Image(systemName: "person.3.fill")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(DS.Palette.gold)
            Text("Bring your crew.")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("PickleBall is friends only. Send your link to the people you play with.")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
            VStack(spacing: 10) {
                pill("Share my invite link", symbol: "link") {
                    Task {
                        if let link = await social.inviteLink(.friend) { inviteURL = IdentifiedURL(url: social.shareURL(for: link)) }
                    }
                }
                pill("Find friends by username", symbol: "magnifyingglass") { showFriends = true }
            }
            .padding(.top, 6)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nudgeCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(DS.Palette.gold)
            Text("Low-key nudges.")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("One short line at most once a day, like “👀 Sam’s still wearing your belt”. Never at night. Mute any kind in Settings.")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
            pill(nudgesAsked ? "Nudges are set" : "Turn on nudges", symbol: nudgesAsked ? "checkmark" : "bell") {
                Task {
                    _ = await Nudger.shared.requestPermission()
                    nudgesAsked = true
                }
            }
            .disabled(nudgesAsked)
            Label("Add the Belt widget to your Home or Lock Screen to see who’s wearing it.", systemImage: "square.grid.2x2")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pill(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(.white.opacity(0.12)))
        }
        .buttonStyle(.press)
    }

    private func finish() {
        Haptics.success()
        onDone()
    }
}
