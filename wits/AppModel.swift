//
//  AppModel.swift
//  wits
//
//  Root state for the post-onboarding app — the analog of SupabaseManager for
//  the main experience. Cache-first: it hydrates instantly from a local snapshot
//  so the home screen renders in <2s, then reconciles with Supabase in the
//  background. Owns the day's workout, streak, per-game difficulty, and the
//  derived progress used by the home/progress screens.
//

import SwiftUI
import Observation

struct ProfileSnapshot: Codable, Equatable {
    var birthdate: Date? = nil
    var goals: [String] = []
    var trainingDays: Int = 5
    var reminderHour: Int? = nil
    var reminderMinute: Int = 0
    var notificationsEnabled = false
    var trialStartedAt: Date? = nil
    var subscriptionUntil: Date? = nil
}

@Observable
@MainActor
final class AppModel {
    enum Load: Equatable { case idle, ready }

    var load: Load = .idle
    var profile = ProfileSnapshot()
    var entitlement: Entitlement = .unknown
    var streak = StreakState.empty
    var difficulty: [GameID: DifficultyState] = [:]
    var today: DailyWorkout
    var headlineIndex: Double? = nil
    /// Per-day rollups for the progress chart (ascending by day).
    var progressDays: [DailyProgressRow] = []
    var league: LeagueResult? = nil
    private var leagueWeekStart: String?
    private var leagueWeekXP = 0
    var percentile: Int? = nil
    var percentileMessage: String? = nil
    var friendCode: String? = nil
    var friends: [FriendInfo] = []

    let supa: SupabaseManager
    private let cacheKey = "wits.appstate.v1"

    init(supa: SupabaseManager) {
        self.supa = supa
        self.today = WorkoutBuilder.build(for: Date())
        loadCache()
    }

    // MARK: Lifecycle

    /// Render immediately from cache, then reconcile in the background.
    func bootstrap() {
        guard load == .idle else { return }
        rebuildTodayIfNeeded()
        recomputeEntitlement()
        refreshReminderSchedule()
        seedFreezesIfNew()
        load = .ready
        Task { await reconcile() }
        Task { await refreshLeague() }
        Task { await refreshSocial() }
    }

    // MARK: Leagues

    func refreshLeague() async {
        guard supa.isSignedIn else { return }
        guard let data = try? await supa.callFunction("league-join"),
              let res = try? JSONDecoder().decode(LeagueResult.self, from: data) else { return }
        league = res
        leagueWeekStart = res.week_start
        leagueWeekXP = res.standings.first(where: { $0.isMe })?.xp ?? leagueWeekXP
        saveCache()
    }

    // MARK: Social (percentile + friends)

    func refreshSocial() async {
        guard supa.isSignedIn else { return }
        if let d = try? await supa.callFunction("social", body: ["action": "percentile"]),
           let r = try? JSONDecoder().decode(PercentileResp.self, from: d), r.hasData {
            percentile = r.percentile
            percentileMessage = r.message
        }
        await refreshFriends()
    }

    func loadFriendCode() async {
        guard supa.isSignedIn else { return }
        if let d = try? await supa.callFunction("social", body: ["action": "friendCode"]),
           let r = try? JSONDecoder().decode(CodeResp.self, from: d) {
            friendCode = r.code
        }
    }

    @discardableResult
    func addFriend(_ code: String) async -> Bool {
        guard let d = try? await supa.callFunction("social", body: ["action": "friendAdd", "code": code]),
              let r = try? JSONDecoder().decode([String: Bool].self, from: d), r["ok"] == true
        else { return false }
        await refreshFriends()
        return true
    }

    func refreshFriends() async {
        guard supa.isSignedIn else { return }
        if let d = try? await supa.callFunction("social", body: ["action": "friendList"]),
           let r = try? JSONDecoder().decode(FriendListResp.self, from: d) {
            friends = r.friends
        }
    }

    /// Add weekly league XP (from a finished workout) and re-rank.
    func addLeagueXP(_ points: Int) {
        guard points > 0, let lid = league?.league_id else { return }
        leagueWeekXP += points
        saveCache()
        let xp = leagueWeekXP
        Task {
            try? await supa.upsertLeagueXP(leagueID: lid, xp: xp)
            await refreshLeague()
        }
    }

    /// New users start with two streak freezes to clear the fragile 7-day hump.
    private func seedFreezesIfNew() {
        guard !UserDefaults.standard.bool(forKey: "wits.freezesSeeded") else { return }
        if streak.lastActiveDay == nil { streak.freezes = max(streak.freezes, 2) }
        UserDefaults.standard.set(true, forKey: "wits.freezesSeeded")
        saveCache()
    }

    /// Foreground / midnight: resolve streak grace and refresh the day's workout.
    func startOfDayRollover() {
        let r = StreakEngine.rollover(streak, today: Date())
        if r.state != streak {
            streak = r.state
            Task { try? await supa.upsertStreak(streak) }
        }
        rebuildTodayIfNeeded()
        recomputeEntitlement()
        saveCache()
    }

    var difficultyFor: (GameID) -> DifficultyState {
        { [difficulty] id in difficulty[id] ?? .seed(for: id) }
    }

    // MARK: Reminders

    /// Turn the daily reminder on/off and persist the choice. Caller must have
    /// already obtained notification authorization when enabling.
    func setReminder(hour: Int, minute: Int, enabled: Bool) {
        profile.reminderHour = enabled ? hour : nil
        profile.reminderMinute = minute
        profile.notificationsEnabled = enabled
        saveCache()
        if enabled {
            WitsNotifications.scheduleDaily(hour: hour, minute: minute)
        } else {
            WitsNotifications.cancelAll()
        }
        Task {
            try? await supa.upsertProfile([
                "reminder_hour": enabled ? hour : NSNull(),
                "reminder_minute": minute,
                "notifications_enabled": enabled,
            ])
        }
    }

    /// Re-arm the OS schedule from persisted prefs on launch (system clears
    /// pending requests in some cases; cheap to re-add).
    func refreshReminderSchedule() {
        guard profile.notificationsEnabled, let h = profile.reminderHour else { return }
        WitsNotifications.scheduleDaily(hour: h, minute: profile.reminderMinute)
    }

    var isWorkoutDoneToday: Bool {
        Calendar.current.isDate(today.day, inSameDayAs: Date()) && today.completed
    }

    // MARK: Game / workout events

    /// Called as each game in a workout finishes: persist the run + advance the
    /// game's persisted difficulty.
    func recordGameResult(_ result: GameResult, source: String = "workout") {
        let id = result.game
        let current = difficulty[id] ?? .seed(for: id)
        let next = advanceDifficulty(for: id, current, accuracy: result.accuracy)
        difficulty[id] = next
        var r = result
        r.newDifficulty = next
        saveCache()
        Task {
            try? await supa.saveSession(r, source: source)
            try? await supa.upsertDifficulty(game: id, next)
        }
    }

    // MARK: Daily challenge (surprise extra game → earns a streak freeze)

    var dailyChallengeGame: GameID? {
        RewardEngine.dailyChallenge(seed: RewardEngine.daySeed(Calendar.current.startOfDay(for: Date())))
    }

    private var challengeKey: String { "wits.challengeDone." + SupabaseManager.dayString(Date()) }

    var dailyChallengeDone: Bool { UserDefaults.standard.bool(forKey: challengeKey) }

    func completeDailyChallenge(_ result: GameResult) {
        recordGameResult(result, source: "challenge")
        guard !dailyChallengeDone else { return }
        UserDefaults.standard.set(true, forKey: challengeKey)
        streak.freezes = min(3, streak.freezes + 1)
        saveCache()
        Task { try? await supa.upsertStreak(streak) }
    }

    /// Called once the full workout completes: tick the streak + roll up the day.
    func finishWorkout(_ results: [GameResult]) {
        today.results = results
        streak = StreakEngine.recordActivity(streak, today: Date())
        addLeagueXP(max(1, results.reduce(0) { $0 + $1.score } / 100))

        let domainScores = Self.domainScores(from: results)
        let headline = Self.headline(from: domainScores)
        headlineIndex = headline

        // reflect the day locally for the chart without waiting on the network
        let dayKey = SupabaseManager.dayString(Date())
        if let i = progressDays.firstIndex(where: { $0.day == dayKey }) {
            progressDays[i].workout_done = true
            progressDays[i].games_played = results.count
            progressDays[i].headline_index = headline
            progressDays[i].domain_scores = domainScores
        } else {
            progressDays.append(DailyProgressRow(day: dayKey, workout_done: true,
                                                 games_played: results.count,
                                                 headline_index: headline,
                                                 domain_scores: domainScores))
        }
        saveCache()
        Task {
            try? await supa.upsertStreak(streak)
            try? await supa.upsertDailyProgress(day: dayKey, workoutDone: true,
                                                gamesPlayed: results.count,
                                                headlineIndex: headline,
                                                domainScores: domainScores)
        }
    }

    // MARK: Reconcile (network → state)

    private func reconcile() async {
        guard supa.isSignedIn else { return }

        if let p = try? await supa.fetchProfile() {
            profile.birthdate = Self.parseDate(p.birthdate)
            profile.goals = p.goals ?? profile.goals
            profile.trainingDays = p.training_days ?? profile.trainingDays
            profile.reminderHour = p.reminder_hour ?? profile.reminderHour
            profile.reminderMinute = p.reminder_minute ?? profile.reminderMinute
            profile.notificationsEnabled = p.notifications_enabled ?? profile.notificationsEnabled
            profile.trialStartedAt = Self.parseDate(p.trial_started_at) ?? profile.trialStartedAt
            profile.subscriptionUntil = Self.parseDate(p.subscription_until) ?? profile.subscriptionUntil
        }

        if let rows = try? await supa.fetchDifficulty() {
            for row in rows {
                guard let id = GameID(rawValue: row.game) else { continue }
                difficulty[id] = DifficultyState(level: row.level,
                                                 reversals: row.reversals ?? 0,
                                                 lastDirection: row.last_direction ?? 0,
                                                 sessionsPlayed: row.sessions_played ?? 0)
            }
        }

        if let s = try? await supa.fetchStreak() {
            streak = StreakState(current: s.current_streak ?? 0,
                                 longest: s.longest_streak ?? 0,
                                 lastActiveDay: Self.parseDate(s.last_active_day),
                                 freezes: s.freezes ?? 0)
        }

        let since = SupabaseManager.dayString(Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date())
        if let rows = try? await supa.fetchDailyProgress(since: since) {
            progressDays = rows
            headlineIndex = rows.last?.headline_index ?? headlineIndex
        }

        recomputeEntitlement()
        rebuildTodayIfNeeded()
        saveCache()
    }

    private func recomputeEntitlement() {
        entitlement = EntitlementEngine.evaluate(trialStartedAt: profile.trialStartedAt,
                                                 subscriptionUntil: profile.subscriptionUntil)
    }

    private func rebuildTodayIfNeeded() {
        if !Calendar.current.isDate(today.day, inSameDayAs: Date()) {
            today = WorkoutBuilder.build(for: Date())
        }
    }

    // MARK: Derived scores (Phase-1 simple; EWMA/headline pipeline is Phase 2)

    static func domainScores(from results: [GameResult]) -> [String: Double] {
        var sums: [String: (Double, Int)] = [:]
        for r in results {
            let key = r.domain.rawValue
            let (s, n) = sums[key] ?? (0, 0)
            sums[key] = (s + r.accuracy * 100, n + 1)
        }
        return sums.mapValues { $0.1 > 0 ? ($0.0 / Double($0.1)).rounded() : 0 }
    }

    static func headline(from domainScores: [String: Double]) -> Double {
        guard !domainScores.isEmpty else { return 0 }
        return (domainScores.values.reduce(0, +) / Double(domainScores.count) * 10).rounded() / 10
    }

    // MARK: Local cache

    private struct CacheState: Codable {
        var profile: ProfileSnapshot
        var streak: StreakState
        var difficulty: [String: DifficultyState]
        var today: DailyWorkout
        var headlineIndex: Double?
        var progressDays: [DailyProgressRow]
        var leagueWeekStart: String?
        var leagueWeekXP: Int?
    }

    private func saveCache() {
        let state = CacheState(
            profile: profile,
            streak: streak,
            difficulty: Dictionary(uniqueKeysWithValues: difficulty.map { ($0.key.rawValue, $0.value) }),
            today: today,
            headlineIndex: headlineIndex,
            progressDays: progressDays,
            leagueWeekStart: leagueWeekStart,
            leagueWeekXP: leagueWeekXP
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let state = try? JSONDecoder().decode(CacheState.self, from: data) else { return }
        profile = state.profile
        streak = state.streak
        difficulty = Dictionary(uniqueKeysWithValues: state.difficulty.compactMap { k, v in
            GameID(rawValue: k).map { ($0, v) }
        })
        headlineIndex = state.headlineIndex
        progressDays = state.progressDays
        leagueWeekStart = state.leagueWeekStart
        leagueWeekXP = state.leagueWeekXP ?? 0
        // keep cached workout only if it's still today's
        if Calendar.current.isDate(state.today.day, inSameDayAs: Date()) {
            today = state.today
        }
    }

    // MARK: Date helpers

    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        // PostgREST timestamptz with fractional seconds / space separator
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}

// MARK: - Social decode models

struct FriendInfo: Decodable {
    var streak: Int
    var trainedToday: Bool
    var friendStreak: Int
}

struct PercentileResp: Decodable {
    var hasData: Bool
    var percentile: Int?
    var message: String?
}

struct CodeResp: Decodable { var code: String? }
struct FriendListResp: Decodable { var friends: [FriendInfo] }

extension DailyProgressRow {
    var dayDate: Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: day)
    }
}
