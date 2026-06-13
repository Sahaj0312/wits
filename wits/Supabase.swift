//
//  Supabase.swift
//  wits
//
//  Lightweight GoTrue + PostgREST client. No SPM dependency — just URLSession,
//  AuthenticationServices and CryptoKit — so the project stays buildable and the
//  auth flow is fully native (email OTP, Sign in with Apple, Google web OAuth).
//

import SwiftUI
import UIKit
import Observation
import AuthenticationServices
import CryptoKit

// MARK: - Config

enum SupabaseConfig {
    static let url = URL(string: "https://blrvygwdiosdiweeydmh.supabase.co")!
    /// Publishable "anon" key — safe to ship in the client; RLS guards the data.
    static let anonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJscnZ5Z3dkaW9zZGl3ZWV5ZG1oIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODEzNTgyOTMsImV4cCI6MjA5NjkzNDI5M30.5GgNpEPF5sqNSSjbusM4u8XZbPT8s5Jh53_xZsywGKg"
    /// Custom scheme used as the OAuth redirect target (no Info.plist entry needed
    /// — ASWebAuthenticationSession intercepts it). Add `wits://auth-callback`
    /// to Auth → URL Configuration → Redirect URLs in the Supabase dashboard.
    static let redirectScheme = "wits"
    static let redirectURL = "wits://auth-callback"
}

// MARK: - Session

struct AuthSession: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String?

    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
}

enum SupabaseError: LocalizedError {
    case message(String)
    case notSignedIn
    case cancelled

    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        case .notSignedIn: return "you're not signed in."
        case .cancelled: return "cancelled."
        }
    }
}

// MARK: - Manager

@Observable
@MainActor
final class SupabaseManager {
    static let shared = SupabaseManager()

    private(set) var session: AuthSession?

    var isSignedIn: Bool { session != nil }
    var userID: String? { session?.userID }

    private let keychainKey = "wits.supabase.session"
    private var appleCoordinator: AppleSignInCoordinator?
    private var webAuthCoordinator: WebAuthCoordinator?

    private init() {
        session = Keychain.loadJSON(keychainKey)
    }

    // MARK: Email OTP (passwordless / "magic link")

    /// Sends a one-time code (and magic link) to the address.
    func sendEmailOTP(_ email: String) async throws {
        try await call(
            "auth/v1/otp",
            method: "POST",
            body: ["email": email, "create_user": true],
            authed: false
        )
    }

    /// Verifies the 6-digit code and starts a session.
    func verifyEmailOTP(email: String, token: String) async throws {
        let data = try await call(
            "auth/v1/verify",
            method: "POST",
            body: ["type": "email", "email": email, "token": token],
            authed: false
        )
        try persist(decodeTokenResponse(data))
    }

    // MARK: Sign in with Apple (native, id_token grant)

    func signInWithApple() async throws {
        let rawNonce = Self.randomNonce()
        let coordinator = AppleSignInCoordinator()
        appleCoordinator = coordinator
        defer { appleCoordinator = nil }

        let credential = try await coordinator.run(hashedNonce: Self.sha256(rawNonce))
        guard
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8)
        else {
            throw SupabaseError.message("apple didn't return an identity token.")
        }
        let data = try await call(
            "auth/v1/token",
            method: "POST",
            query: [URLQueryItem(name: "grant_type", value: "id_token")],
            body: ["provider": "apple", "id_token": idToken, "nonce": rawNonce],
            authed: false
        )
        try persist(decodeTokenResponse(data))
    }

    // MARK: Google (web OAuth via ASWebAuthenticationSession)

    func signInWithGoogle() async throws {
        var comps = URLComponents(
            url: SupabaseConfig.url.appendingPathComponent("auth/v1/authorize"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: SupabaseConfig.redirectURL),
        ]
        let coordinator = WebAuthCoordinator()
        webAuthCoordinator = coordinator
        defer { webAuthCoordinator = nil }

        let callback = try await coordinator.run(
            url: comps.url!,
            scheme: SupabaseConfig.redirectScheme
        )
        // Implicit flow returns tokens in the URL fragment.
        let frag = fragmentParams(callback)
        guard let access = frag["access_token"], let refresh = frag["refresh_token"] else {
            if let err = frag["error_description"] ?? frag["error"] {
                throw SupabaseError.message(err.replacingOccurrences(of: "+", with: " "))
            }
            throw SupabaseError.message("google sign-in didn't return a session.")
        }
        let claims = Self.decodeJWT(access)
        let session = AuthSession(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: claims.exp ?? Date().addingTimeInterval(3600),
            userID: claims.sub ?? "",
            email: claims.email
        )
        try persist(session)
    }

    // MARK: Session lifecycle

    func signOut() {
        session = nil
        Keychain.delete(keychainKey)
    }

    /// Returns a valid access token, refreshing if necessary.
    func validAccessToken() async -> String? {
        guard let s = session else { return nil }
        guard s.isExpired else { return s.accessToken }
        do {
            let data = try await call(
                "auth/v1/token",
                method: "POST",
                query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                body: ["refresh_token": s.refreshToken],
                authed: false
            )
            try persist(decodeTokenResponse(data))
            return session?.accessToken
        } catch {
            return nil
        }
    }

    // MARK: PostgREST writes (best-effort persistence of onboarding data)

    func upsertProfile(_ fields: [String: Any]) async throws {
        guard let id = userID else { throw SupabaseError.notSignedIn }
        var row = fields
        row["id"] = id
        try await restWrite(
            table: "profiles",
            body: [row],
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    func saveAssessment(_ rows: [(idx: Int, statement: String, score: Int)]) async throws {
        guard let id = userID else { throw SupabaseError.notSignedIn }
        let body = rows.map {
            ["user_id": id, "statement_idx": $0.idx, "statement": $0.statement, "score": $0.score] as [String: Any]
        }
        try await restWrite(
            table: "self_assessment",
            body: body,
            prefer: "resolution=merge-duplicates,return=minimal",
            query: [URLQueryItem(name: "on_conflict", value: "user_id,statement_idx")]
        )
    }

    func saveGameScores(_ rows: [[String: Any]]) async throws {
        guard let id = userID else { throw SupabaseError.notSignedIn }
        let body = rows.map { row -> [String: Any] in
            var r = row
            r["user_id"] = id
            return r
        }
        try await restWrite(table: "game_scores", body: body, prefer: "return=minimal")
    }

    // MARK: - Networking

    @discardableResult
    private func call(
        _ path: String,
        method: String,
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        authed: Bool
    ) async throws -> Data {
        var comps = URLComponents(
            url: SupabaseConfig.url.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty { comps.queryItems = query }

        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authed, let token = await validAccessToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            req.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseError.message("no response from the server.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseError.message(Self.errorMessage(from: data, status: http.statusCode))
        }
        return data
    }

    private func restWrite(
        table: String,
        body: [[String: Any]],
        prefer: String,
        query: [URLQueryItem] = []
    ) async throws {
        guard let token = await validAccessToken() else { throw SupabaseError.notSignedIn }
        var comps = URLComponents(
            url: SupabaseConfig.url.appendingPathComponent("rest/v1/\(table)"),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty { comps.queryItems = query }

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(prefer, forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw SupabaseError.message(Self.errorMessage(from: data, status: status))
        }
    }

    // MARK: - Helpers

    private func persist(_ session: AuthSession) throws {
        self.session = session
        Keychain.saveJSON(session, key: keychainKey)
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_at: Double?
        let expires_in: Double?
        struct User: Decodable { let id: String; let email: String? }
        let user: User
    }

    private func decodeTokenResponse(_ data: Data) throws -> AuthSession {
        let r = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expiry: Date = {
            if let at = r.expires_at { return Date(timeIntervalSince1970: at) }
            return Date().addingTimeInterval(r.expires_in ?? 3600)
        }()
        return AuthSession(
            accessToken: r.access_token,
            refreshToken: r.refresh_token,
            expiresAt: expiry,
            userID: r.user.id,
            email: r.user.email
        )
    }

    private func fragmentParams(_ url: URL) -> [String: String] {
        let frag = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment ?? ""
        var out: [String: String] = [:]
        for pair in frag.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                out[String(kv[0])] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
            }
        }
        return out
    }

    private static func errorMessage(from data: Data, status: Int) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["error_description", "msg", "message", "error"] {
                if let v = obj[key] as? String { return v }
            }
        }
        return "something went wrong (\(status))."
    }

    // MARK: Crypto

    private static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if Int(random) < chars.count {
                result.append(chars[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private struct JWTClaims { var sub: String?; var email: String?; var exp: Date? }

    private static func decodeJWT(_ token: String) -> JWTClaims {
        let segments = token.split(separator: ".")
        guard segments.count > 1 else { return JWTClaims() }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard
            let data = Data(base64Encoded: base64),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return JWTClaims() }
        let exp = (obj["exp"] as? Double).map { Date(timeIntervalSince1970: $0) }
        return JWTClaims(sub: obj["sub"] as? String, email: obj["email"] as? String, exp: exp)
    }
}

// MARK: - Apple sign-in coordinator

private final class AppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    @MainActor
    func run(hashedNonce: String) async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashedNonce
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            continuation?.resume(returning: credential)
        } else {
            continuation?.resume(throwing: SupabaseError.message("unexpected apple credential."))
        }
        continuation = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if (error as? ASAuthorizationError)?.code == .canceled {
            continuation?.resume(throwing: SupabaseError.cancelled)
        } else {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        keyWindow()
    }
}

// MARK: - Web OAuth coordinator

private final class WebAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var authSession: ASWebAuthenticationSession?

    @MainActor
    func run(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let callback {
                    cont.resume(returning: callback)
                } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    cont.resume(throwing: SupabaseError.cancelled)
                } else {
                    cont.resume(throwing: error ?? SupabaseError.message("sign-in failed."))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        keyWindow()
    }
}

@MainActor
private func keyWindow() -> ASPresentationAnchor {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap(\.windows)
    if let key = windows.first(where: { $0.isKeyWindow }) { return key }
    if let any = windows.first { return any }
    if let scene = scenes.first { return UIWindow(windowScene: scene) }
    // Unreachable while any UI is on screen (a foreground app always has a window scene).
    preconditionFailure("no UIWindowScene available to present authentication")
}

// MARK: - Keychain

private enum Keychain {
    static func saveJSON<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func loadJSON<T: Decodable>(_ key: String) -> T? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
