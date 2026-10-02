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

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 700
            content(courtHeight: compact ? 150 : min(240, geo.size.height * 0.28),
                    topRoom: compact ? 88 : min(150, geo.size.height * 0.16),
                    titleSize: compact ? 32 : 38)
        }
        .courtGround()
        .noticeToast()
    }

    private func content(courtHeight: CGFloat, topRoom: CGFloat, titleSize: CGFloat) -> some View {
        VStack(spacing: 0) {
            // The court is the picture: the same one Home opens on. Room
            // above it for the far half fading out.
            CourtHome(sport: sportMode.sport, height: courtHeight)
                .padding(.horizontal, Court.Metrics.sideInset + 20)
                .padding(.top, topRoom)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(spacing: 14) {
                Text("Your court.\nYour crew.\nYour belt.")
                    .font(.system(size: titleSize, weight: .semibold))
                    .tracking(-1.1)
                    .foregroundStyle(Court.text)
                    .multilineTextAlignment(.center)
                Text("Score on your Watch or type it in later. Friends confirm every result, and the Belt goes to whoever beats the holder.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Court.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 28)

            Spacer(minLength: 16)

            SignInWithAppleButton(.continue) { request in
                rawNonce = Self.randomNonce()
                request.requestedScopes = [.fullName]
                request.nonce = Self.sha256(rawNonce)
            } onCompletion: { result in
                handle(result)
            }
            // Black on light, white on dark (Apple's guidelines).
            .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
            .id(scheme)
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 24)
            .disabled(isSigningIn)
            .overlay {
                if isSigningIn { ProgressView() }
            }

            Text("Friends only. Nothing you post is ever public.")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Court.dim)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
