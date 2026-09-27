//
//  InviteLink.swift
//  CourtNetCore
//
//  Friend links, QR codes, squad links and guest-claim links all carry one
//  token; the server knows what it's for. Inside the app the custom scheme
//  opens directly. Links shared outside the app point at a small static
//  page (docs/invite, served by GitHub Pages) with "Open in PickleBall" and
//  "Get the app" buttons, and the code for typing in by hand.
//

import Foundation

public struct InviteLink: Hashable, Sendable {
    public static let scheme = "pickleball"

    public let token: String

    public init?(token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidToken(trimmed) else { return nil }
        self.token = trimmed
    }

    /// Accepts pickleball://invite/<token>, https://…/invite/<token> and
    /// any https link with ?t=<token>.
    public init?(url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let query = components?.queryItems?.first(where: { $0.name == "t" })?.value {
            self.init(token: query)
            return
        }
        let parts = ([url.host].compactMap { $0 } + url.pathComponents).filter { $0 != "/" }
        guard let index = parts.lastIndex(of: "invite"), index + 1 < parts.count else { return nil }
        self.init(token: parts[index + 1])
    }

    /// Opens the app directly.
    public var appURL: URL {
        URL(string: "\(Self.scheme)://invite/\(token)")!
    }

    /// For sharing outside the app and for QR codes: the landing page with
    /// the token as `?t=`. Without a landing page, the app link.
    public func shareURL(page: URL?) -> URL {
        guard let page, var components = URLComponents(url: page, resolvingAgainstBaseURL: false) else { return appURL }
        components.queryItems = (components.queryItems ?? []).filter { $0.name != "t" } + [URLQueryItem(name: "t", value: token)]
        return components.url ?? appURL
    }

    /// Pasted text: a link, or just the code.
    public init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil, let link = InviteLink(url: url) {
            self = link
        } else {
            self.init(token: trimmed.lowercased())
        }
    }

    /// Tokens are 24 lowercase hex characters (12 random bytes).
    static func isValidToken(_ token: String) -> Bool {
        token.count == 24 && token.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}
