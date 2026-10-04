//
//  AppleReauth.swift
//  PickleBall
//
//  Asks Sign in with Apple once more before deleting an account. The
//  fresh authorization code lets the server revoke the app's access to
//  the Apple ID, as Apple requires when an account is deleted.
//

import AuthenticationServices
import UIKit

@MainActor
final class AppleReauth: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<String?, Never>?
    /// Kept alive until Apple answers.
    private var controller: ASAuthorizationController?

    /// The authorization code, or nil if the person cancelled or it failed.
    func authorizationCode() async -> String? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = []
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        let code = (authorization.credential as? ASAuthorizationAppleIDCredential)?
            .authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        Task { @MainActor in self.finish(code) }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }

    private func finish(_ code: String?) {
        continuation?.resume(returning: code)
        continuation = nil
        controller = nil
    }
}
