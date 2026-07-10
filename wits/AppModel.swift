//
//  AppModel.swift
//  wits
//
//  Root state for the app: the daily streak, per-game difficulty bookkeeping,
//  lifetime game stats, and independent difficulty-track progress. Everything persists
//  locally (UserDefaults); Game Center carries leaderboards and achievements.
//

import SwiftUI
import Observation

@Observable
@MainActor
final class AppModel {
    var streak = StreakState.empty
    var difficulty: [GameID: DifficultyState] = [:]
    var gameStats: [GameID: GameStats] = [:]
    /// Independent Easy/Medium/Hard/Extra Hard progression.
    let levels = LevelProgressStore()

    private let cacheKey = "wits.appstate.v1"

    init() {
        loadCache()
        levels.migrateIfNeeded(from: difficulty)
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

    var difficultyFor: (GameID) -> DifficultyState {
        { [difficulty] id in id.difficultyState(from: difficulty[id]) }
    }

    func hasPlayed(_ game: GameID) -> Bool {
        (gameStats[game]?.totalPlays ?? 0) > 0 || (difficulty[game]?.sessionsPlayed ?? 0) > 0
    }

    // MARK: Game events

    /// Called as each game finishes: score the run, advance the game's mastery
    /// bookkeeping and selected difficulty track, then refresh achievements.
    @discardableResult
    func recordGameResult(_ result: GameResult) -> GameResult {
        let id = result.game
        if id.isStandalone {
            return recordStandaloneGameResult(result)
        }
        let current = id.difficultyState(from: difficulty[id])
        let trackLevel = result.raw["trackLevel"].map { Int($0) }
        let trackDifficulty = result.raw["difficultyTrack"]
            .flatMap { ChallengeDifficulty(ordinal: Int($0)) }
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
        difficulty[id] = scored.next
        let r = scored.result

        recordStats(for: r)

        if let trackLevel, let trackDifficulty {
            let quality = r.performanceQuality ?? r.accuracy
            levels.recordAttempt(game: id,
                                 difficulty: trackDifficulty,
                                 level: trackLevel,
                                 stars: StarGrader.stars(quality: quality), quality: quality)
        }

        streak = StreakEngine.recordActivity(streak, today: Date())
        saveCache()
        GameCenterManager.shared.recordProgress(levels: levels, streak: streak)
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
        GameCenterManager.shared.recordProgress(levels: levels, streak: streak)
        return r
    }

    /// Record a finished marathon run; on a new best, submit it to Game Center.
    /// Returns true when the run set a new best.
    @discardableResult
    func recordMarathon(game: GameID, depth: Int, score: Int) -> Bool {
        let improved = levels.recordMarathon(game: game, depth: depth, score: score)
        if improved {
            GameCenterManager.shared.submitMarathonBest(game: game, levels: levels)
        }
        return improved
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

    // MARK: Local cache

    /// Field names/types match the pre-pivot cache blob so an existing install
    /// decodes its streak, difficulty, and stats with no migration (unknown
    /// keys are ignored; unknown game raw values are dropped by the compactMap).
    private struct CacheState: Codable {
        var streak: StreakState
        var difficulty: [String: DifficultyState]
        var gameStats: [String: GameStats]?
    }

    private func saveCache() {
        let state = CacheState(
            streak: streak,
            difficulty: Dictionary(uniqueKeysWithValues: difficulty.map { ($0.key.rawValue, $0.value) }),
            gameStats: Dictionary(uniqueKeysWithValues: gameStats.map { ($0.key.rawValue, $0.value) })
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
    }
}
