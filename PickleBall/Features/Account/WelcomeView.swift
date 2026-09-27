//
//  WelcomeView.swift
//  PickleBall
//
//  The front door. One button: Sign in with Apple. The account is what
//  lets friends find you, confirm your results and fight you for the belt.
//

import SwiftUI
import AuthenticationServices
import CryptoKit
import CourtKit

struct WelcomeView: View {
    @Environment(SportMode.self) private var sportMode
    @State private var rawNonce = ""
    @State private var isSigningIn = false
    private let social = Social.shared

    var body: some View {
        ZStack {
            LinearGradient(colors: [sportMode.theme.courtSurfaceAlt, DS.Palette.navy], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            CourtArtView(sport: sportMode.sport, lineWidth: 1.5, lineOpacity: 0.22, showsSurface: false)
                .padding(40)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer()
                BallIcon(sport: sportMode.sport, size: 64)
                    .padding(.bottom, 22)
                Text("Your court.\nYour crew.\nYour belt.")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                Text("Score on your Watch or type it in later. Friends confirm every result, and the Belt goes to whoever beats the holder.")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 16)
                Spacer()

                SignInWithAppleButton(.continue) { request in
                    rawNonce = Self.randomNonce()
                    request.requestedScopes = [.fullName]
                    request.nonce = Self.sha256(rawNonce)
                } onCompletion: { result in
                    handle(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                .padding(.horizontal, 24)
                .disabled(isSigningIn)
                .overlay {
                    if isSigningIn { ProgressView().tint(.black) }
                }

                Text("Friends only. Nothing you post is ever public.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 14)
                    .padding(.bottom, 24)
            }
        }
        .noticeToast()
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                social.notice = "Apple didn’t send a sign-in token. Try again."
                return
            }
            // Apple shares the name only the first time; keep it for setup.
            if let name = credential.fullName {
                let formatted = PersonNameComponentsFormatter.localizedString(from: name, style: .default)
                if !formatted.isEmpty { UserDefaults.standard.set(formatted, forKey: "apple_full_name") }
            }
            isSigningIn = true
            Haptics.medium()
            Task {
                await social.signInWithApple(idToken: token, rawNonce: rawNonce)
                isSigningIn = false
            }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                social.notice = "Sign in didn’t work. \(error.localizedDescription)"
            }
        }
    }

    static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
