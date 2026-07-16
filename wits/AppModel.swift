//
//  AppModel.swift
//  wits
//
//  Root state for the app: the daily streak, per-game difficulty bookkeeping,
//  lifetime game stats, and independent difficulty-track progress. Everything
//  persists locally in UserDefaults.
//

import SwiftUI
import Observation

@Observable
@MainActor
final class AppModel {
    var streak = StreakState.empty
    /// Legacy per-game state retained for cache migration and old untagged runs.
    var difficulty: [GameID: DifficultyState] = [:]
    /// Campaign mastery is isolated by difficulty, matching the four independent
    /// level frontiers. Easy performance can never raise Hard or Extra Hard.
    var trackDifficulty: [GameID: [ChallengeDifficulty: DifficultyState]] = [:]
    var gameStats: [GameID: GameStats] = [:]
    /// Independent Easy/Medium/Hard/Extra Hard progression.
    let levels = LevelProgressStore()

    private let cacheKey = "wits.appstate.v1"

    init() {
        loadCache()
        levels.migrateIfNeeded(from: difficulty)
        migrateTrackDifficultyIfNeeded()
    }

    // MARK: Lifecycle

    /// Foreground / midnight: break the streak if a day was missed.
    func startOfDayRollover() {
        let next = StreakEngine.rollover(streak, today: Date())
        if next != streak {
            streak = next
            saveCache()
        }
    }

    func difficultyState(for game: GameID,
                         difficulty challengeDifficulty: ChallengeDifficulty) -> DifficultyState {
        trackDifficulty[game]?[challengeDifficulty]
            ?? DifficultyScale.initialState(for: game, difficulty: challengeDifficulty)
    }

    func hasPlayed(_ game: GameID) -> Bool {
        (gameStats[game]?.totalPlays ?? 0) > 0 ||
            (difficulty[game]?.sessionsPlayed ?? 0) > 0 ||
            (trackDifficulty[game]?.values.contains { $0.sessionsPlayed > 0 } ?? false)
    }

    // MARK: Game events

    /// Called as each game finishes: score the run and advance the game's
    /// mastery bookkeeping and selected difficulty track.
    @discardableResult
    func recordGameResult(_ result: GameResult) -> GameResult {
        let id = result.game
        if id.isStandalone {
            return recordStandaloneGameResult(result)
        }
        let trackLevel = result.raw["trackLevel"].map { Int($0) }
        let trackDifficulty = result.raw["difficultyTrack"]
            .flatMap { ChallengeDifficulty(ordinal: Int($0)) }
        let current = trackDifficulty.map { difficultyState(for: id, difficulty: $0) }
            ?? id.difficultyState(from: difficulty[id])
        let previous: DifficultyState
        if let trackLevel, let trackDifficulty {
            previous = DifficultyScale.gameDifficulty(for: id,
                                                      difficulty: trackDifficulty,
                                                      trackLevel: trackLevel,
                                                      persisted: current)
        } else {
            previous = current
        }
        let scored = ScoringEngine.score(result, previous: previous)
        if let trackDifficulty {
            var perGame = self.trackDifficulty[id] ?? [:]
            perGame[trackDifficulty] = scored.next
            self.trackDifficulty[id] = perGame
        } else {
            difficulty[id] = scored.next
        }
        let r = scored.result

        recordStats(for: r)

        if let trackLevel, let trackDifficulty {
            let quality = r.performanceQuality ?? r.accuracy
            levels.recordAttempt(game: id,
                                 difficulty: trackDifficulty,
                                 level: trackLevel,
                                 quality: quality)
        }

        streak = StreakEngine.recordActivity(streak, today: Date())
        saveCache()
        return r
    }

    /// Standalone modes (Split) are saved for lifetime stats and the streak,
    /// but skip mastery/star bookkeeping.
    @discardableResult
    func recordStandaloneGameResult(_ result: GameResult) -> GameResult {
        var r = result
        r.baseScore = r.baseScore ?? r.score
        recordStats(for: r)
        streak = StreakEngine.recordActivity(streak, today: Date())
        saveCache()
        return r
    }

    /// Record a finished marathon run. Returns true when the run set a new best.
    @discardableResult
    func recordMarathon(game: GameID, depth: Int, depthFraction: Double = 0, score: Int) -> Bool {
        levels.recordMarathon(game: game,
                              depth: depth,
                              depthFraction: depthFraction,
                              score: score)
    }

    /// Per-mode best for standalone games with speed modes (Snake). The
    /// all-time best across modes goes through `recordMarathon`.
    @discardableResult
    func recordModeBest(game: GameID, difficulty: ChallengeDifficulty, score: Int) -> Bool {
        levels.recordModeBest(game: game, difficulty: difficulty, score: score)
    }

    /// Rolling today/this-week bests shown on the endless post-game card.
    func recordRunBests(game: GameID, difficulty: ChallengeDifficulty? = nil, score: Int) {
        levels.recordRunBests(game: game, difficulty: difficulty, score: score)
    }

    private func recordStats(for result: GameResult) {
        // Every finished run of every mode lands here — the one funnel for
        // "the player just finished a game".
        ReviewPrompter.gameFinished()
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

    // MARK: Local cache

    /// Field names/types match the pre-pivot cache blob so an existing install
    /// decodes its streak, difficulty, and stats with no migration (unknown
    /// keys are ignored; unknown game raw values are dropped by the compactMap).
    private struct CacheState: Codable {
        var streak: StreakState
        var difficulty: [String: DifficultyState]
        var gameStats: [String: GameStats]?
        var trackDifficulty: [String: DifficultyState]?
    }

    private func saveCache() {
        let state = CacheState(
            streak: streak,
            difficulty: Dictionary(uniqueKeysWithValues: difficulty.map { ($0.key.rawValue, $0.value) }),
            gameStats: Dictionary(uniqueKeysWithValues: gameStats.map { ($0.key.rawValue, $0.value) }),
            trackDifficulty: Dictionary(uniqueKeysWithValues: trackDifficulty.flatMap { game, values in
                values.map { difficulty, state in
                    (Self.trackKey(game: game, difficulty: difficulty), state)
                }
            })
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let state = try? JSONDecoder().decode(CacheState.self, from: data) else { return }
        streak = state.streak
        difficulty = Dictionary(uniqueKeysWithValues: state.difficulty.compactMap { k, v in
            GameID(rawValue: k).map { ($0, v) }
        })
        gameStats = Dictionary(uniqueKeysWithValues: (state.gameStats ?? [:]).compactMap { k, v in
            GameID(rawValue: k).map { ($0, v) }
        })
        for (key, value) in state.trackDifficulty ?? [:] {
            guard let parsed = Self.parseTrackKey(key) else { continue }
            var perGame = trackDifficulty[parsed.game] ?? [:]
            perGame[parsed.difficulty] = value
            trackDifficulty[parsed.game] = perGame
        }
    }

    private func migrateTrackDifficultyIfNeeded() {
        guard trackDifficulty.isEmpty else { return }
        for (game, state) in difficulty where state.sessionsPlayed > 0 && game.isLive {
            let selected = levels.selectedDifficulty(for: game)
            var migrated = state
            migrated.level = DifficultyScale.legacyDifficulty(for: selected,
                                                               level: levels.currentLevel(for: game,
                                                                                          difficulty: selected))
            trackDifficulty[game] = [selected: migrated]
        }
        if !trackDifficulty.isEmpty { saveCache() }
    }

    private static func trackKey(game: GameID, difficulty: ChallengeDifficulty) -> String {
        "\(game.rawValue)|\(difficulty.rawValue)"
    }

    private static func parseTrackKey(_ key: String) -> (game: GameID, difficulty: ChallengeDifficulty)? {
        let pieces = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard pieces.count == 2,
              let game = GameID(rawValue: pieces[0]),
              let difficulty = ChallengeDifficulty(rawValue: pieces[1]) else { return nil }
        return (game, difficulty)
    }
}
