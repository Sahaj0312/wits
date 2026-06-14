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
        load = .ready
        Task { await reconcile() }
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

    /// Called once the full workout completes: tick the streak + roll up the day.
    func finishWorkout(_ results: [GameResult]) {
        today.results = results
        streak = StreakEngine.recordActivity(streak, today: Date())

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
    }

    private func saveCache() {
        let state = CacheState(
            profile: profile,
            streak: streak,
            difficulty: Dictionary(uniqueKeysWithValues: difficulty.map { ($0.key.rawValue, $0.value) }),
            today: today,
            headlineIndex: headlineIndex,
            progressDays: progressDays
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

extension DailyProgressRow {
    var dayDate: Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: day)
    }
}
