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

/// Section boundaries in the onboarding flow. We record the furthest one each
/// user reaches so drop-off can be measured without writing on every screen.
enum OnboardingCheckpoint: Int, CaseIterable {
    case accountCreated = 1
    case birthdate
    case goals
    case selfAssessment
    case demographics
    case fitTest
    case planBuilt
    case reachedPaywall
    case completed

    var key: String {
        switch self {
        case .accountCreated: "account_created"
        case .birthdate:      "birthdate"
        case .goals:          "goals"
        case .selfAssessment: "self_assessment"
        case .demographics:   "demographics"
        case .fitTest:        "fit_test"
        case .planBuilt:      "plan_built"
        case .reachedPaywall: "reached_paywall"
        case .completed:      "completed"
        }
    }
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

// MARK: - Read row models (PostgREST → Decodable)

struct ProfileRow: Decodable {
    var display_name: String?
    var birthdate: String?
    var goals: [String]?
    var training_days: Int?
    var reminder_hour: Int?
    var reminder_minute: Int?
    var notifications_enabled: Bool?
    var trial_started_at: String?
    var subscription_until: String?
    var onboarding_completed: Bool?
}

struct DifficultyRow: Decodable {
    var game: String
    var level: Double
    var reversals: Int?
    var last_direction: Int?
    var sessions_played: Int?
}

struct DailyProgressRow: Codable {
    var day: String
    var workout_done: Bool?
    var games_played: Int?
    var headline_index: Double?
    var domain_scores: [String: Double]?
    /// The prescribed workout lineup for the day (GameID raw values), so a past
    /// day's recap can show every prescribed game — including ones not completed.
    var workout_games: [String]?
}

struct StreakRow: Decodable {
    var current_streak: Int?
    var longest_streak: Int?
    var last_active_day: String?
}

/// One recorded run, for reconstructing a past day's exact lineup + the level
/// each game was played at. `difficulty` is the 1...10 mastery level for the run.
struct SessionRow: Decodable {
    var game: String
    var source: String
    var difficulty: Double?
    var accuracy: Double?
    var score: Int?
    var started_at: String?
    var workout_id: String?
}

struct CheckInRow: Decodable {
    var day: String
    var mood: Int?
    var sleep: Int?
}

// MARK: - Manager

@Observable
@MainActor
final class SupabaseManager {
    static let shared = SupabaseManager()

    private(set) var session: AuthSession?

    var isSignedIn: Bool { session != nil }
    var userID: String? { session?.userID }

    /// Name Apple hands back on first sign-in — used only to prefill the
    /// onboarding username step. Apple returns this exactly once.
    var suggestedName: String?

    private let keychainKey = "wits.supabase.session"
    private var appleCoordinator: AppleSignInCoordinator?
    private var webAuthCoordinator: WebAuthCoordinator?

    private init() {
        session = Keychain.loadJSON(keychainKey)
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

        // Apple only returns the user's name on the FIRST authorization. Stash it
        // to prefill the onboarding username step; the user confirms/edits there.
        if let nameComponents = credential.fullName {
            let formatter = PersonNameComponentsFormatter()
            let name = formatter.string(from: nameComponents).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { suggestedName = String(name.prefix(24)) }
        }
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

    /// Records the furthest onboarding section reached (fire-and-forget),
    /// optionally folding in that section's collected data as one write.
    func recordCheckpoint(_ cp: OnboardingCheckpoint, merging extra: [String: Any] = [:]) {
        guard isSignedIn else { return }
        var fields = extra
        fields["onboarding_checkpoint"] = cp.key
        fields["onboarding_checkpoint_index"] = cp.rawValue
        if cp == .completed {
            fields["onboarding_completed"] = true
            fields["completed_at"] = ISO8601DateFormatter().string(from: Date())
            // Start the 3-day trial clock the moment onboarding finishes.
            fields["trial_started_at"] = ISO8601DateFormatter().string(from: Date())
        }
        Task { try? await upsertProfile(fields) }
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

    // MARK: - Main-app persistence (sessions / difficulty / progress / streak)

    private static let iso = ISO8601DateFormatter()

    /// One row per scored run in the main app (supersedes game_scores).
    /// `workoutID` ties a run to the specific prescribed daily workout it belongs
    /// to, so a day's recap can show that exact lineup (vs. free play / replays).
    func saveSession(_ r: GameResult, source: String, workoutID: String? = nil) async throws {
        guard let id = userID else { throw SupabaseError.notSignedIn }
        var row: [String: Any] = [
            "user_id": id,
            "game": r.game.rawValue,
            "domain": r.domain.rawValue,
            "source": source,
            "score": r.score,
            "accuracy": r.accuracy,
            "trials": r.trials,
            "started_at": Self.iso.string(from: r.startedAt),
        ]
        if let workoutID { row["workout_id"] = workoutID }
        if let t = r.threshold { row["threshold"] = t }
        if let rt = r.medianRTms { row["median_rt_ms"] = rt }
        if let d = r.newDifficulty?.level { row["difficulty"] = d }
        if !r.raw.isEmpty { row["details"] = r.raw }
        try await restWrite(table: "game_sessions", body: [row], prefer: "return=minimal")
    }

    func upsertDifficulty(game: GameID, _ s: DifficultyState) async throws {
        guard let id = userID else { throw SupabaseError.notSignedIn }
        let row: [String: Any] = [
            "user_id": id, "game": game.rawValue,
            "level": s.level, "reversals": s.reversals,
            "last_direction": s.lastDirection, "sessions_played": s.sessionsPlayed,
            "updated_at": Self.iso.string(from: Date()),
        ]
        try await restWrite(
            table: "game_difficulty", body: [row],
            prefer: "resolution=merge-duplicates,return=minimal",
            query: [URLQueryItem(name: "on_conflict", value: "user_id,game")]
        )
    }

    func upsertDailyProgress(day: String, workoutDone: Bool, gamesPlayed: Int,
                             headlineIndex: Double?, domainScores: [String: Double],
                             workoutGames: [String]? = nil) async throws {
        guard let id = userID else { throw SupabaseError.notSignedIn }
        var row: [String: Any] = [
            "user_id": id, "day": day,
            "workout_done": workoutDone, "games_played": gamesPlayed,
            "domain_scores": domainScores,
            "updated_at": Self.iso.string(from: Date()),
        ]
        if let h = headlineIndex { row["headline_index"] = h }
        if let workoutGames { row["workout_games"] = workoutGames }
        try await restWrite(
            table: "daily_progress", body: [row],
            prefer: "resolution=merge-duplicates,return=minimal",
            query: [URLQueryItem(name: "on_conflict", value: "user_id,day")]
        )
    }

    func upsertCheckIn(day: String, mood: Int, sleep: Int) async throws {
        guard let id = userID else { throw SupabaseError.notSignedIn }
        let row: [String: Any] = ["user_id": id, "day": day, "mood": mood, "sleep": sleep]
        try await restWrite(
            table: "daily_checkin", body: [row],
            prefer: "resolution=merge-duplicates,return=minimal",
            query: [URLQueryItem(name: "on_conflict", value: "user_id,day")]
        )
    }

    func fetchCheckins(since day: String) async throws -> [CheckInRow] {
        let data = try await restRead(table: "daily_checkin", query: [
            URLQueryItem(name: "select", value: "day,mood,sleep"),
            URLQueryItem(name: "day", value: "gte.\(day)"),
            URLQueryItem(name: "order", value: "day.asc"),
        ])
        return try JSONDecoder().decode([CheckInRow].self, from: data)
    }

    func upsertStreak(_ s: StreakState) async throws {
        guard let id = userID else { throw SupabaseError.notSignedIn }
        var row: [String: Any] = [
            "user_id": id,
            "current_streak": s.current, "longest_streak": s.longest,
            "updated_at": Self.iso.string(from: Date()),
        ]
        if let last = s.lastActiveDay { row["last_active_day"] = Self.dayString(last) }
        try await restWrite(
            table: "streaks", body: [row],
            prefer: "resolution=merge-duplicates,return=minimal",
            query: [URLQueryItem(name: "on_conflict", value: "user_id")]
        )
    }

    // MARK: Reads

    func fetchProfile() async throws -> ProfileRow? {
        guard let id = userID else { throw SupabaseError.notSignedIn }
        let data = try await restRead(table: "profiles", query: [
            URLQueryItem(name: "id", value: "eq.\(id)"),
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "limit", value: "1"),
        ])
        return try JSONDecoder().decode([ProfileRow].self, from: data).first
    }

    /// Whether the signed-in account already finished onboarding (server-side), so
    /// a returning user who signed out doesn't get sent through it again.
    func isOnboardingComplete() async -> Bool {
        (try? await fetchProfile())?.onboarding_completed == true
    }

    func fetchDifficulty() async throws -> [DifficultyRow] {
        let data = try await restRead(table: "game_difficulty", query: [
            URLQueryItem(name: "select", value: "*"),
        ])
        return try JSONDecoder().decode([DifficultyRow].self, from: data)
    }

    func fetchDailyProgress(since day: String) async throws -> [DailyProgressRow] {
        let data = try await restRead(table: "daily_progress", query: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "day", value: "gte.\(day)"),
            URLQueryItem(name: "order", value: "day.asc"),
        ])
        return try JSONDecoder().decode([DailyProgressRow].self, from: data)
    }

    /// All recorded runs since `day` (yyyy-MM-dd), oldest first. Used to rebuild
    /// each past day's actual games + the level played.
    func fetchSessions(since day: String) async throws -> [SessionRow] {
        let data = try await restRead(table: "game_sessions", query: [
            URLQueryItem(name: "select", value: "game,source,difficulty,accuracy,score,started_at,workout_id"),
            URLQueryItem(name: "started_at", value: "gte.\(day)T00:00:00"),
            URLQueryItem(name: "order", value: "started_at.asc"),
        ])
        return try JSONDecoder().decode([SessionRow].self, from: data)
    }

    func fetchStreak() async throws -> StreakRow? {
        let data = try await restRead(table: "streaks", query: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "limit", value: "1"),
        ])
        return try JSONDecoder().decode([StreakRow].self, from: data).first
    }

    static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
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

    /// GET twin of restWrite. RLS scopes every read to the signed-in user.
    private func restRead(table: String, query: [URLQueryItem]) async throws -> Data {
        guard let token = await validAccessToken() else { throw SupabaseError.notSignedIn }
        var comps = URLComponents(
            url: SupabaseConfig.url.appendingPathComponent("rest/v1/\(table)"),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty { comps.queryItems = query }

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw SupabaseError.message(Self.errorMessage(from: data, status: status))
        }
        return data
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
