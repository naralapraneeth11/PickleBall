//
//  Auth.swift
//  CourtNet
//
//  Sign in with Apple, exchanged for a Supabase session. The app runs the
//  Apple sheet (AuthenticationServices) and hands over the identity token
//  and the raw nonce it hashed into the request.
//

import Foundation
import Supabase

public enum AuthState: Sendable, Equatable {
    case signedOut
    case signedIn(userID: UUID)
}

extension SupabaseBackend {
    public var currentUserID: UUID? { client.auth.currentUser?.id }

    @discardableResult
    public func signInWithApple(idToken: String, rawNonce: String) async throws -> UUID {
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: rawNonce)
        )
        return session.user.id
    }

    public func signOut() async {
        try? await client.auth.signOut(scope: .local)
    }

    /// The session as it changes: restored at launch, refreshed, signed out.
    /// An expired saved session still counts as signed in: offline, the app
    /// runs from its cache, and the SDK refreshes the token once it can.
    public func authStates() -> AsyncStream<AuthState> {
        let changes = client.auth.authStateChanges
        return AsyncStream { continuation in
            let task = Task {
                for await (_, session) in changes {
                    if let session {
                        continuation.yield(.signedIn(userID: session.user.id))
                    } else {
                        continuation.yield(.signedOut)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
