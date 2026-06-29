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

/// A game actually played on a given day, with the difficulty level it ran at —
/// the record behind the day-detail recap ("you played these, at these levels").
struct PlayedGame: Codable, Equatable {
    var game: GameID
    var level: Double          // 1...10 mastery level for that run
    var accuracy: Double
    var score: Int
}

struct ProfileSnapshot: Codable, Equatable {
    var displayName: String? = nil
    var birthdate: Date? = nil
    var goals: [String] = []
    var difficultyPreference: String? = nil
    var encouragementStyle: String? = nil
    var exerciseFrequency: String? = nil
    var sleepHours: String? = nil
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
    var gameStats: [GameID: GameStats] = [:]
    var today: DailyWorkout
    var headlineIndex: Double? = nil
    var notificationsNeedSettings = false
    /// Per-day rollups for the progress chart (ascending by day).
    var progressDays: [DailyProgressRow] = []
    /// Actual workout games played per day (key yyyy-MM-dd, local), with the level
    /// played — reconstructed from game_sessions so a past day's recap shows the
    /// real lineup and difficulty, not a rotation guess.
    var playedByDay: [String: [PlayedGame]] = [:]

    let supa: SupabaseManager
    private let cacheKey = "wits.appstate.v1"

    init(supa: SupabaseManager) {
        self.supa = supa
        self.today = WorkoutBuilder.build(for: Date())
        loadCache()
        // Cache is now hydrated → tune today's lineup to the user's weak spots,
        // unless cache restored a workout already underway today.
        if !(Calendar.current.isDate(today.day, inSameDayAs: Date()) && !today.results.isEmpty) {
            today = WorkoutBuilder.build(for: Date(), priorities: todayPriorities)
        }
    }

    // MARK: Lifecycle

    /// Render immediately from cache, then reconcile in the background.
    func bootstrap() {
        guard load == .idle else { return }
        rebuildTodayIfNeeded()
        recomputeEntitlement()
        load = .ready
        Task {
            await syncNotificationAuthorizationAndSchedule()
            await reconcile()
        }
    }

    /// Foreground / midnight: break the streak if a day was missed, refresh the day.
    func startOfDayRollover() {
        let next = StreakEngine.rollover(streak, today: Date())
        if next != streak {
            streak = next
            Task { try? await supa.upsertStreak(streak) }
        }
        rebuildTodayIfNeeded()
        recomputeEntitlement()
        saveCache()
        Task { await syncNotificationAuthorizationAndSchedule() }
    }

    var difficultyFor: (GameID) -> DifficultyState {
        { [difficulty] id in id.difficultyState(from: difficulty[id]) }
    }

    /// Per-domain "needs training" weights driving today's lineup — weakest and
    /// most-neglected domains rank highest. Empty until the user has history, at
    /// which point the workout builder tilts toward what's lagging.
    var todayPriorities: [CognitiveDomain: Double] {
        ProgressMath.domainPriorities(progressDays, asOf: Date())
    }

    enum DayWorkout { case completed, partial, none }

    /// How much of a day's prescribed workout was actually done — measured from
    /// games played vs. the prescribed lineup, NOT the `workout_done` activity
    /// flag. Free play alone is `.none`; finishing every prescribed game is
    /// `.completed`; anything in between is `.partial`.
    func workoutStatus(on day: Date) -> DayWorkout {
        let played = playedGames(on: day).count
        let row = progressDays.first { $0.day == SupabaseManager.dayString(day) }
        let total = row?.workout_games?.count ?? WorkoutBuilder.size
        if total > 0, played >= total { return .completed }
        return played > 0 ? .partial : .none
    }

    /// The games played on `day`, with the level each ran at, for the recap sheet.
    /// Today prefers live results (covers runs not yet synced to the server);
    /// past days come from the reconstructed `playedByDay`.
    func playedGames(on day: Date) -> [PlayedGame] {
        if Calendar.current.isDateInToday(day), !today.results.isEmpty {
            return today.results.map {
                PlayedGame(game: $0.game,
                           level: $0.newDifficulty?.level ?? difficultyFor($0.game).level,
                           accuracy: $0.accuracy, score: $0.score)
            }
        }
        return playedByDay[SupabaseManager.dayString(day)] ?? []
    }

    // MARK: Reminders

    /// Turn the daily reminder on/off and persist the choice. Caller must have
    /// already obtained notification authorization when enabling.
    func setReminder(hour: Int, minute: Int, enabled: Bool) {
        profile.reminderHour = enabled ? hour : nil
        profile.reminderMinute = minute
        profile.notificationsEnabled = enabled
        notificationsNeedSettings = false
        saveCache()
        if enabled {
            refreshReminderSchedule()
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
        guard profile.notificationsEnabled, profile.reminderHour != nil else {
            WitsNotifications.cancelAll()
            return
        }
        WitsNotifications.schedulePlan(profile: profile, context: notificationContext())
    }

    func syncNotificationAuthorizationAndSchedule() async {
        guard profile.notificationsEnabled, profile.reminderHour != nil else {
            notificationsNeedSettings = false
            WitsNotifications.cancelAll()
            return
        }

        switch await WitsNotifications.permissionState() {
        case .ready:
            notificationsNeedSettings = false
            refreshReminderSchedule()
        case .notDetermined:
            notificationsNeedSettings = false
            WitsNotifications.cancelAll()
        case .disabled:
            notificationsNeedSettings = true
            WitsNotifications.cancelAll()
        }
    }

    private func notificationContext(now: Date = Date()) -> WitsNotificationPlanContext {
        WitsNotificationPlanContext(
            now: now,
            todayWorkoutDone: isWorkoutDoneToday,
            streak: streak,
            hasAnyProgress: !progressDays.isEmpty
        )
    }

    var isWorkoutDoneToday: Bool {
        Calendar.current.isDate(today.day, inSameDayAs: Date()) && today.completed
    }

    // MARK: Game / workout events

    /// Called as each game finishes: score the run, persist it, and advance the
    /// game's challenge/mastery state.
    @discardableResult
    func recordGameResult(_ result: GameResult, source: String = "workout", workoutID: String? = nil) -> GameResult {
        let id = result.game
        if id.isStandalone {
            return recordStandaloneGameResult(result, source: source)
        }
        let resetStats = id.shouldResetDifficulty(difficulty[id])
        let current = id.difficultyState(from: difficulty[id])
        let scored = ScoringEngine.score(result, previous: current)
        let next = scored.next
        difficulty[id] = next
        let r = scored.result

        if resetStats { gameStats[id] = nil }
        recordStats(for: r)

        saveCache()
        Task {
            try? await supa.saveSession(r, source: source, workoutID: workoutID)
            try? await supa.upsertDifficulty(game: id, next)
        }

        return r
    }

    /// Standalone modes are saved for history/stats, but intentionally bypass WPI,
    /// mastery, adaptive difficulty, and daily score rollups.
    @discardableResult
    func recordStandaloneGameResult(_ result: GameResult, source: String = "standalone") -> GameResult {
        var r = result
        r.baseScore = r.baseScore ?? r.score
        recordStats(for: r)
        saveCache()
        Task {
            try? await supa.saveSession(r, source: source)
        }
        return r
    }

    private func recordStats(for result: GameResult) {
        let id = result.game
        var st = gameStats[id] ?? GameStats()
        st.totalPlays += 1
        st.bestScore = max(st.bestScore, result.baseScoreValue)
        if let v = result.raw[id.statKey] {
            if let cur = st.bestStat {
                st.bestStat = id.statLowerIsBetter ? min(cur, v) : max(cur, v)
            } else {
                st.bestStat = v
            }
        }
        gameStats[id] = st
    }

    // MARK: Daily challenge (surprise extra game)

    var dailyChallengeGame: GameID? {
        RewardEngine.dailyChallenge(seed: RewardEngine.daySeed(Calendar.current.startOfDay(for: Date())))
    }

    private var challengeKey: String { "wits.challengeDone." + SupabaseManager.dayString(Date()) }

    var dailyChallengeDone: Bool { UserDefaults.standard.bool(forKey: challengeKey) }

    func completeDailyChallenge(_ result: GameResult) {
        let scored = recordGameResult(result, source: "challenge")
        guard !dailyChallengeDone else { return }
        recordDayActivity([scored], countsForStreak: false)
        UserDefaults.standard.set(true, forKey: challengeKey)
        saveCache()
    }

    /// Called as each game of today's workout finishes. Persists per-game so the
    /// workout can be resumed from the next game if the user backs out partway,
    /// and rolls the day up *every* game — so a partly-done workout still records
    /// its prescribed lineup + progress. The streak only ticks on the final game.
    func recordWorkoutGame(_ result: GameResult) {
        // Stamp the run with today's prescribed-workout id so the day's recap can
        // show this exact lineup, distinct from free play / replays.
        let scored = recordGameResult(result, source: "workout", workoutID: today.id.uuidString)
        if today.results.count < today.games.count {
            today.results.append(scored)
        }
        saveCache()
        // Roll up after each game so progress + the prescribed lineup are saved even
        // if the user backs out partway. countsForStreak only on the last game.
        let complete = today.results.count >= today.games.count
        recordDayActivity([scored], countsForStreak: complete, prescribed: today.games)
        refreshReminderSchedule()
    }

    /// Fold a just-played game into today's rollup: accumulate domain scores,
    /// refresh the wits score + improvement chart, and persist the prescribed lineup.
    /// `workout_done` marks a counted progress day (workout or daily challenge).
    /// Free play updates game mastery only. The journey decides "completed" from
    /// games played vs. the prescribed lineup, not from this flag. The streak
    /// advances only when `countsForStreak` is true.
    private func recordDayActivity(_ results: [GameResult], countsForStreak: Bool,
                                   prescribed: [GameID]? = nil) {
        guard !results.isEmpty else { return }
        if countsForStreak {
            streak = StreakEngine.recordActivity(streak, today: Date())
        }

        let dayKey = SupabaseManager.dayString(Date())
        let existing = progressDays.first(where: { $0.day == dayKey })
        let rollup = ScoringAggregator.aggregateGameStates(difficulty)
        let domains = rollup.scores
        let domainConfidence = rollup.confidence
        let domainCounts = rollup.counts
        let rawHeadline = ScoringAggregator.headline(domainScores: domains, confidence: domainConfidence)
            ?? Self.headline(from: domains)
        let anchored = Self.migrationAnchoredHeadline(unanchored: rawHeadline,
                                                      existing: existing,
                                                      progressDays: progressDays,
                                                      dayKey: dayKey)
        let headline = anchored.headline
        headlineIndex = headline
        let headlineConfidence = ScoringAggregator.headlineConfidence(domainConfidence)
        let coverageCount = domainConfidence.filter { $0.value > 0 }.count
        let played = (existing?.games_played ?? 0) + results.count
        // Persist the prescribed lineup (once we know it); keep any earlier value.
        let lineup = prescribed?.map(\.rawValue) ?? existing?.workout_games

        if let i = progressDays.firstIndex(where: { $0.day == dayKey }) {
            progressDays[i].workout_done = true
            progressDays[i].games_played = played
            progressDays[i].headline_index = headline
            progressDays[i].domain_scores = domains
            progressDays[i].domain_confidence = domainConfidence
            progressDays[i].domain_session_counts = domainCounts
            progressDays[i].headline_confidence = headlineConfidence
            progressDays[i].coverage_count = coverageCount
            progressDays[i].migration_offset = anchored.offset
            progressDays[i].scoring_version = ScoringVersion.current
            progressDays[i].workout_games = lineup
        } else {
            progressDays.append(DailyProgressRow(day: dayKey, workout_done: true,
                                                 games_played: played,
                                                 headline_index: headline,
                                                 domain_scores: domains,
                                                 domain_confidence: domainConfidence,
                                                 domain_session_counts: domainCounts,
                                                 headline_confidence: headlineConfidence,
                                                 coverage_count: coverageCount,
                                                 migration_offset: anchored.offset,
                                                 scoring_version: ScoringVersion.current,
                                                 workout_games: lineup))
        }
        saveCache()
        Task {
            if countsForStreak { try? await supa.upsertStreak(streak) }
            try? await supa.upsertDailyProgress(day: dayKey, workoutDone: true,
                                                gamesPlayed: played,
                                                headlineIndex: headline,
                                                domainScores: domains,
                                                domainConfidence: domainConfidence,
                                                domainSessionCounts: domainCounts,
                                                headlineConfidence: headlineConfidence,
                                                coverageCount: coverageCount,
                                                migrationOffset: anchored.offset,
                                                workoutGames: lineup)
        }
    }

    private static func migrationAnchoredHeadline(unanchored: Double,
                                                  existing: DailyProgressRow?,
                                                  progressDays: [DailyProgressRow],
                                                  dayKey: String) -> (headline: Double, offset: Double?) {
        let raw = ScoringMath.clamp(unanchored, 0, ScoringCalibrator.maxWPI)
        let currentDay = parseDate(dayKey)

        if existing?.scoring_version == ScoringVersion.current {
            let offset = existing?.migration_offset ?? 0
            return (ScoringMath.round(ScoringMath.clamp(raw + offset, 0, ScoringCalibrator.maxWPI)), nonZeroOffset(offset))
        }

        let previousRows = progressDays
            .filter { $0.day < dayKey }
            .sorted { ($0.dayDate ?? .distantPast) < ($1.dayDate ?? .distantPast) }

        if let firstAnchor = previousRows.first(where: {
            $0.scoring_version == ScoringVersion.current && $0.migration_offset != nil
        }),
           let initialOffset = firstAnchor.migration_offset,
           let start = firstAnchor.dayDate,
           let currentDay {
            let cal = Calendar.current
            let days = cal.dateComponents([.day],
                                          from: cal.startOfDay(for: start),
                                          to: cal.startOfDay(for: currentDay)).day ?? 0
            let factor = max(0, 1 - Double(max(0, days)) / 14.0)
            let offset = initialOffset * factor
            return (ScoringMath.round(ScoringMath.clamp(raw + offset, 0, ScoringCalibrator.maxWPI)), nonZeroOffset(offset))
        }

        let previousHeadline = existing?.headline_index
            ?? previousRows.reversed().compactMap(\.headline_index).first
        guard let previousHeadline else {
            return (ScoringMath.round(raw), nil)
        }

        let offset = ScoringMath.clamp(previousHeadline - raw, -1000, 1000)
        return (ScoringMath.round(ScoringMath.clamp(raw + offset, 0, ScoringCalibrator.maxWPI)), nonZeroOffset(offset))
    }

    private static func nonZeroOffset(_ offset: Double) -> Double? {
        abs(offset) >= 0.5 ? ScoringMath.round(offset, places: 1) : nil
    }

    // MARK: Reconcile (network → state)

    private func reconcile() async {
        guard supa.isSignedIn else { return }

        if let p = try? await supa.fetchProfile() {
            profile.displayName = p.display_name ?? profile.displayName
            profile.birthdate = Self.parseDate(p.birthdate)
            profile.goals = p.goals ?? profile.goals
            profile.difficultyPreference = p.difficulty ?? profile.difficultyPreference
            profile.encouragementStyle = p.encouragement ?? profile.encouragementStyle
            profile.exerciseFrequency = p.exercise_freq ?? profile.exerciseFrequency
            profile.sleepHours = p.sleep_hours ?? profile.sleepHours
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
                let sessions = row.sessions_played ?? 0
                difficulty[id] = DifficultyState(level: row.level,
                                                 mastery: row.mastery,
                                                 confidence: row.confidence ?? min(1, Double(sessions) / 8.0),
                                                 variance: row.variance ?? 1,
                                                 reversals: row.reversals ?? 0,
                                                 lastDirection: row.last_direction ?? 0,
                                                 sessionsPlayed: sessions,
                                                 lastPlayed: Self.parseServerTimestamp(row.last_played),
                                                 scoringVersion: row.scoring_version ?? "v1_legacy")
            }
            sanitizeMechanicsMigrations()
        }

        if let s = try? await supa.fetchStreak() {
            streak = StreakState(current: s.current_streak ?? 0,
                                 longest: s.longest_streak ?? 0,
                                 lastActiveDay: Self.parseDate(s.last_active_day))
        }

        let since = SupabaseManager.dayString(Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date())
        if let rows = try? await supa.fetchDailyProgress(since: since) {
            progressDays = rows
            headlineIndex = rows.last?.headline_index ?? headlineIndex
        }
        if let rows = try? await supa.fetchSessions(since: since) {
            // Bucket workout runs per local day (oldest → newest), carrying the
            // workout_id that ties each run to a specific prescribed workout.
            typealias Run = (played: PlayedGame, workoutID: String?)
            var byDay: [String: [Run]] = [:]
            for row in rows where row.source == "workout" {
                guard let g = GameID(rawValue: row.game),
                      let d = Self.parseServerTimestamp(row.started_at) else { continue }
                let played = PlayedGame(game: g,
                                        level: row.difficulty ?? g.seedLevel,
                                        accuracy: row.accuracy ?? 0,
                                        score: row.score ?? 0)
                byDay[SupabaseManager.dayString(d), default: []].append((played, row.workout_id))
            }
            playedByDay = byDay.mapValues { runs in
                // Prefer the exact prescribed workout: scope to the most recent
                // workout_id of the day. Fall back to a size-capped dedupe only
                // for legacy runs that predate workout_id stamping.
                let scoped: [Run]
                if let latest = runs.last(where: { $0.workoutID != nil })?.workoutID {
                    scoped = runs.filter { $0.workoutID == latest }
                } else {
                    scoped = runs
                }
                return Self.dailyLineup(scoped.map(\.played))
            }
        }

        recomputeEntitlement()
        rebuildTodayIfNeeded()
        saveCache()
        await syncNotificationAuthorizationAndSchedule()
    }

    private func recomputeEntitlement() {
        entitlement = EntitlementEngine.evaluate(trialStartedAt: profile.trialStartedAt,
                                                 subscriptionUntil: profile.subscriptionUntil)
    }

    /// Refresh today's lineup from the latest weakness signal. Safe to call on
    /// every bootstrap / rollover / reconcile: it rebuilds when the day has
    /// turned over, and otherwise re-tunes today's games to the newest progress
    /// data — but only while the workout hasn't been started, so an in-progress
    /// or completed session is never reshuffled underneath the user.
    private func rebuildTodayIfNeeded() {
        let isToday = Calendar.current.isDate(today.day, inSameDayAs: Date())
        if isToday && !today.results.isEmpty { return }
        today = WorkoutBuilder.build(for: Date(), priorities: todayPriorities)
    }

    // MARK: Derived scores

    static let masteryMin = 1.0
    static let masteryMax = 10.0
    static let wpiMax = 5000.0

    /// Legacy fallback for old rows that only have a level.
    static func wpiScore(level: Double) -> Double {
        (min(masteryMax, max(masteryMin, level)) * (wpiMax / masteryMax)).rounded()
    }

    static func domainScore(level: Double) -> Double {
        wpiScore(level: level)
    }

    /// Fit-test baseline: start from the game's seed level, then nudge up or down
    /// using the same accuracy bands as regular play.
    static func onboardingMasteryLevel(seed: Double, accuracy: Double) -> Double {
        min(masteryMax, max(masteryMin, seed + MasteryLadder.delta(for: accuracy)))
    }

    /// Collapse a day's workout runs (chronological) into the prescribed lineup:
    /// walk newest → oldest, keep the latest run of each distinct game, cap at the
    /// workout size, then restore play order. Drops replays and earlier attempts
    /// so the recap shows the day's workout, not every game touched that day.
    static func dailyLineup(_ runs: [PlayedGame]) -> [PlayedGame] {
        var seen = Set<GameID>()
        var picked: [PlayedGame] = []
        for run in runs.reversed() where !seen.contains(run.game) {
            seen.insert(run.game)
            picked.append(run)
            if picked.count >= WorkoutBuilder.size { break }
        }
        return picked.reversed()
    }

    func domainScores(from results: [GameResult]) -> [String: Double] {
        Self.domainScores(from: results, stateFor: { [difficulty] g in
            difficulty[g] ?? .seed(for: g)
        })
    }

    static func domainScores(from results: [GameResult],
                             levelFor: (GameID) -> Double) -> [String: Double] {
        domainScores(from: results, stateFor: { g in DifficultyState(level: levelFor(g)) })
    }

    static func domainScores(from results: [GameResult],
                             stateFor: (GameID) -> DifficultyState) -> [String: Double] {
        var sums: [String: (Double, Int)] = [:]
        for r in results {
            let key = r.domain.rawValue
            let state = r.newDifficulty ?? stateFor(r.game)
            let sc = r.calibratedAbility ?? ScoringCalibrator.calibratedAbility(game: r.game, mastery: state.mastery)
            let (s, n) = sums[key] ?? (0, 0)
            sums[key] = (s + sc, n + 1)
        }
        return sums.mapValues { $0.1 > 0 ? ($0.0 / Double($0.1)).rounded() : 0 }
    }

    static func headline(from domainScores: [String: Double]) -> Double {
        guard !domainScores.isEmpty else { return 0 }
        return ScoringAggregator.headline(domainScores: domainScores, confidence: [:])
            ?? (domainScores.values.reduce(0, +) / Double(domainScores.count) * 10).rounded() / 10
    }

    // MARK: Local cache

    private struct CacheState: Codable {
        var profile: ProfileSnapshot
        var streak: StreakState
        var difficulty: [String: DifficultyState]
        var gameStats: [String: GameStats]?
        var today: DailyWorkout
        var headlineIndex: Double?
        var progressDays: [DailyProgressRow]
        var playedByDay: [String: [PlayedGame]]?
    }

    private func saveCache() {
        let state = CacheState(
            profile: profile,
            streak: streak,
            difficulty: Dictionary(uniqueKeysWithValues: difficulty.map { ($0.key.rawValue, $0.value) }),
            gameStats: Dictionary(uniqueKeysWithValues: gameStats.map { ($0.key.rawValue, $0.value) }),
            today: today,
            headlineIndex: headlineIndex,
            progressDays: progressDays,
            playedByDay: playedByDay
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
        gameStats = Dictionary(uniqueKeysWithValues: (state.gameStats ?? [:]).compactMap { k, v in
            GameID(rawValue: k).map { ($0, v) }
        })
        headlineIndex = state.headlineIndex
        progressDays = state.progressDays
        playedByDay = state.playedByDay ?? [:]
        // keep cached workout only if it's still today's
        if Calendar.current.isDate(state.today.day, inSameDayAs: Date()) {
            today = state.today
        }
        sanitizeMechanicsMigrations()
    }

    private func sanitizeMechanicsMigrations() {
        if GameID.estimator.shouldResetDifficulty(difficulty[.estimator]) {
            difficulty.removeValue(forKey: .estimator)
            gameStats.removeValue(forKey: .estimator)
        } else if difficulty[.estimator] == nil, gameStats[.estimator] != nil {
            gameStats.removeValue(forKey: .estimator)
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

    /// Parse a PostgREST timestamptz, which comes back space-separated with a
    /// short "+00" offset (e.g. "2026-06-18 02:51:17+00") that the ISO parsers
    /// above reject. Normalises the offset to "+0000" before decoding.
    private static func parseServerTimestamp(_ s: String?) -> Date? {
        guard let s else { return nil }
        var t = s
        if t.range(of: #"[+-]\d{2}$"#, options: .regularExpression) != nil { t += "00" }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd HH:mm:ss.SSSSSSZ", "yyyy-MM-dd HH:mm:ssZ",
                    "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ", "yyyy-MM-dd'T'HH:mm:ssZ"] {
            f.dateFormat = fmt
            if let d = f.date(from: t) { return d }
        }
        return parseDate(s)
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
