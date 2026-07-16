//
//  LevelSystem.swift
//  wits
//
//  Independent, unbounded difficulty tracks. Every game has four tracks and
//  each track owns its own current level, so changing difficulty never moves
//  another track's frontier.
//

import Foundation
import SwiftUI

// MARK: - Difficulty tracks

enum ChallengeDifficulty: String, CaseIterable, Codable, Identifiable, Sendable {
    case easy
    case medium
    case hard
    case extraHard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .easy: "easy"
        case .medium: "medium"
        case .hard: "hard"
        case .extraHard: "extra hard"
        }
    }

    var shortTitle: String {
        switch self {
        case .easy: "easy"
        case .medium: "medium"
        case .hard: "hard"
        case .extraHard: "extra"
        }
    }

    var symbol: String {
        switch self {
        case .easy: "face.smiling"
        case .medium: "bolt.fill"
        case .hard: "flame.fill"
        case .extraHard: "burst.fill"
        }
    }

    var ordinal: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    init?(ordinal: Int) {
        guard Self.allCases.indices.contains(ordinal) else { return nil }
        self = Self.allCases[ordinal]
    }
}

/// Maps an infinite track level into the bounded 1...10 tuning scale the game
/// engines already understand. A track ramps within its own difficulty band
/// and approaches the band's ceiling asymptotically, so very large levels stay
/// valid while procedural games can continue producing fresh boards forever.
enum DifficultyScale {
    private static let bandWidth = 9.0 / Double(ChallengeDifficulty.allCases.count)
    private static let rampLength = 9.0

    static func legacyDifficulty(for difficulty: ChallengeDifficulty, level: Int) -> Double {
        let lower = 1.0 + Double(difficulty.ordinal) * bandWidth
        let progress = 1 - exp(-Double(max(1, level) - 1) / rampLength)
        return DifficultyState.clamp(lower + bandWidth * progress)
    }

    /// Number of safe authored/tuned content steps behind a game's procedural
    /// curve. This is a tuning range, not a player-facing level limit.
    static func contentCeiling(for game: GameID) -> Int {
        switch game {
        case .arrowStorm, .colorClash, .tileShift:
            50
        case .crowdControl, .echoGrid, .lastSeen,
             .slidePuzzle, .blockEscape, .pegSolitaire, .waterSort, .numberNests, .mahjong, .crossword:
            40
        case .split, .blockFit, .fuse, .snake, .tower:
            30
        }
    }

    static func contentLevel(for game: GameID,
                             difficulty: ChallengeDifficulty,
                             trackLevel: Int) -> Int {
        contentLevel(for: game,
                     legacyDifficulty: legacyDifficulty(for: difficulty, level: trackLevel))
    }

    static func contentLevel(for game: GameID, legacyDifficulty: Double) -> Int {
        let count = contentCeiling(for: game)
        let value = DifficultyState.clamp(legacyDifficulty)
        let level = 1 + Int((((value - 1) / 9) * Double(count - 1)).rounded())
        return min(count, max(1, level))
    }

    static func gameDifficulty(for game: GameID,
                               difficulty: ChallengeDifficulty,
                               trackLevel: Int,
                               persisted: DifficultyState) -> DifficultyState {
        var state = persisted
        state.level = legacyDifficulty(for: difficulty, level: trackLevel)
        return state
    }

    static func initialState(for game: GameID,
                             difficulty: ChallengeDifficulty,
                             trackLevel: Int = 1) -> DifficultyState {
        let level = legacyDifficulty(for: difficulty, level: trackLevel)
        return DifficultyState(level: level,
                               mastery: level,
                               variance: 1.2,
                               scoringVersion: game.difficultyScoringVersion)
    }

    /// Best-effort conversion used only by the one-time star-map migration.
    static func trackPosition(forLegacyDifficulty legacyDifficulty: Double) ->
        (difficulty: ChallengeDifficulty, level: Int) {
        let value = DifficultyState.clamp(legacyDifficulty)
        let rawBand = Int((value - 1) / bandWidth)
        let ordinal = min(ChallengeDifficulty.allCases.count - 1, max(0, rawBand))
        let difficulty = ChallengeDifficulty(ordinal: ordinal) ?? .easy
        let lower = 1.0 + Double(ordinal) * bandWidth
        let ratio = min(0.98, max(0, (value - lower) / bandWidth))
        let level = 1 + Int((-rampLength * log(1 - ratio)).rounded())
        return (difficulty, max(1, level))
    }
}

// MARK: - Grading

enum LevelGrader {
    static let passQuality = 0.60

    static func passed(quality: Double) -> Bool {
        quality >= passQuality
    }
}

// MARK: - Progress store

struct LevelRecord: Codable, Equatable {
    var passed: Bool
    var bestQuality: Double

    init(passed: Bool, bestQuality: Double) {
        self.passed = passed
        self.bestQuality = bestQuality
    }

    private enum CodingKeys: String, CodingKey {
        case passed, bestQuality, stars
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bestQuality = try container.decodeIfPresent(Double.self, forKey: .bestQuality) ?? 0
        if let passed = try container.decodeIfPresent(Bool.self, forKey: .passed) {
            self.passed = passed
        } else {
            // Records written before pass/fail stored 1-3 stars; any star was a pass.
            passed = (try container.decodeIfPresent(Int.self, forKey: .stars) ?? 0) >= 1
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(passed, forKey: .passed)
        try container.encode(bestQuality, forKey: .bestQuality)
    }
}

struct DifficultyTrackProgress: Codable, Equatable {
    var unlockedLevel: Int = 1
    var records: [Int: LevelRecord] = [:]
}

struct MarathonBest: Codable, Equatable {
    var depth: Int
    var score: Int
    var depthFraction: Double?
}

enum SplitProgress {
    static func value(level: Int, depth: Double) -> Int {
        let safeLevel = max(1, level)
        let fraction = min(0.999, max(0, depth))
        return safeLevel * 1_000 + Int((fraction * 999).rounded())
    }

    static func label(level: Int, depth: Double) -> String {
        label(value: value(level: level, depth: depth))
    }

    static func label(value: Int) -> String {
        String(format: "%.3f", Double(max(0, value)) / 1_000)
    }
}

/// Rolling day/week bests for an endless run (the post-game card's
/// "Today's best" and "Week's best" rows). Keys are device-local — the
/// calendar the player actually lives in — matching the app's day convention.
struct PeriodBests: Codable, Equatable {
    var day: String
    var dayBest: Int
    var week: String
    var weekBest: Int
}

@MainActor
@Observable
final class LevelProgressStore {
    private(set) var tracks: [GameID: [ChallengeDifficulty: DifficultyTrackProgress]] = [:]
    private(set) var selections: [GameID: ChallengeDifficulty] = [:]
    /// Retained for Split, the app's standalone endless mode.
    private(set) var marathonBests: [GameID: MarathonBest] = [:]
    /// Standalone games with speed modes (Snake) keep one best per mode;
    /// the all-time best across modes lives in `marathonBests`.
    private(set) var modeBests: [GameID: [ChallengeDifficulty: Int]] = [:]
    /// Rolling today/this-week bests per game and mode (games without speed
    /// modes store theirs under `.easy`).
    private(set) var periodBests: [GameID: [ChallengeDifficulty: PeriodBests]] = [:]

    private static let storageKey = "wits.difficultyProgress.v2"
    private static let migrationKey = "wits.difficultyProgress.migrated.v2"
    private static let legacyStorageKey = "wits.levelProgress.v1"

    init() {
        load()
    }

    // MARK: Queries

    func selectedDifficulty(for game: GameID) -> ChallengeDifficulty {
        selections[game] ?? .easy
    }

    func currentLevel(for game: GameID, difficulty: ChallengeDifficulty) -> Int {
        max(1, tracks[game]?[difficulty]?.unlockedLevel ?? 1)
    }

    func record(for game: GameID,
                difficulty: ChallengeDifficulty,
                level: Int) -> LevelRecord? {
        tracks[game]?[difficulty]?.records[level]
    }

    func hasPassed(game: GameID,
                   difficulty: ChallengeDifficulty,
                   level: Int) -> Bool {
        record(for: game, difficulty: difficulty, level: level)?.passed ?? false
    }

    func totalClears(for game: GameID) -> Int {
        tracks[game]?.values.reduce(0) { total, track in
            total + track.records.values.filter(\.passed).count
        } ?? 0
    }

    func marathonBest(for game: GameID) -> MarathonBest? {
        marathonBests[game]
    }

    func modeBest(for game: GameID, difficulty: ChallengeDifficulty) -> Int {
        modeBests[game]?[difficulty] ?? 0
    }

    /// Today's and this week's best for a run, zero once the period rolls over.
    func runBests(for game: GameID,
                  difficulty: ChallengeDifficulty?,
                  now: Date = Date()) -> (today: Int, week: Int) {
        guard let bests = periodBests[game]?[difficulty ?? .easy] else { return (0, 0) }
        return (bests.day == Self.dayKey(now) ? bests.dayBest : 0,
                bests.week == Self.weekKey(now) ? bests.weekBest : 0)
    }

    // MARK: Mutations

    func select(_ difficulty: ChallengeDifficulty, for game: GameID) {
        guard selections[game] != difficulty else { return }
        selections[game] = difficulty
        save()
    }

    /// Saves the best result for this track level. A pass advances only this
    /// difficulty's frontier; attempts on every other track remain untouched.
    @discardableResult
    func recordAttempt(game: GameID,
                       difficulty: ChallengeDifficulty,
                       level: Int,
                       quality: Double) -> Bool {
        let safeLevel = max(1, level)
        var perGame = tracks[game] ?? [:]
        var track = perGame[difficulty] ?? DifficultyTrackProgress()
        let existing = track.records[safeLevel]
        let passed = LevelGrader.passed(quality: quality)
        let improved = (passed && !(existing?.passed ?? false)) ||
            quality > (existing?.bestQuality ?? 0)
        track.records[safeLevel] = LevelRecord(
            passed: passed || (existing?.passed ?? false),
            bestQuality: max(quality, existing?.bestQuality ?? 0)
        )
        if passed, safeLevel >= track.unlockedLevel, safeLevel < Int.max {
            track.unlockedLevel = safeLevel + 1
        }
        perGame[difficulty] = track
        tracks[game] = perGame
        save()
        return improved
    }

    @discardableResult
    func recordMarathon(game: GameID, depth: Int, depthFraction: Double = 0, score: Int) -> Bool {
        let current = marathonBests[game]
        let safeFraction = min(0.999, max(0, depthFraction))
        let newBest = depth > (current?.depth ?? 0) ||
            (depth == (current?.depth ?? 0) && safeFraction > (current?.depthFraction ?? 0)) ||
            (depth == (current?.depth ?? 0) && safeFraction == (current?.depthFraction ?? 0) &&
             score > (current?.score ?? 0))
        if newBest {
            marathonBests[game] = MarathonBest(depth: depth, score: score, depthFraction: safeFraction)
            save()
        }
        return newBest
    }

    func recordRunBests(game: GameID,
                        difficulty: ChallengeDifficulty?,
                        score: Int,
                        now: Date = Date()) {
        let current = runBests(for: game, difficulty: difficulty, now: now)
        var perGame = periodBests[game] ?? [:]
        perGame[difficulty ?? .easy] = PeriodBests(day: Self.dayKey(now),
                                                   dayBest: max(score, current.today),
                                                   week: Self.weekKey(now),
                                                   weekBest: max(score, current.week))
        periodBests[game] = perGame
        save()
    }

    /// Device-local calendar day, e.g. "2026-07-13".
    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Device-local ISO week, e.g. "2026-W29".
    private static func weekKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone.current
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return "\(year)-W\(week)"
    }

    @discardableResult
    func recordModeBest(game: GameID, difficulty: ChallengeDifficulty, score: Int) -> Bool {
        guard score > modeBest(for: game, difficulty: difficulty) else { return false }
        var perGame = modeBests[game] ?? [:]
        perGame[difficulty] = score
        modeBests[game] = perGame
        save()
        return true
    }

    // MARK: Migration

    /// Imports the old finite star map once. Old levels are projected onto the
    /// nearest new difficulty track; untouched tracks still begin at level 1.
    func migrateIfNeeded(from adaptiveDifficulty: [GameID: DifficultyState]) {
        guard !UserDefaults.standard.bool(forKey: Self.migrationKey) else { return }

        if let data = UserDefaults.standard.data(forKey: Self.legacyStorageKey),
           let legacy = try? JSONDecoder().decode(LegacySnapshot.self, from: data) {
            migrate(legacy)
        } else {
            for (game, state) in adaptiveDifficulty where state.sessionsPlayed > 0 {
                let position = DifficultyScale.trackPosition(forLegacyDifficulty: state.level)
                var perGame = tracks[game] ?? [:]
                var track = perGame[position.difficulty] ?? DifficultyTrackProgress()
                track.unlockedLevel = max(track.unlockedLevel, position.level)
                perGame[position.difficulty] = track
                tracks[game] = perGame
                selections[game] = position.difficulty
            }
        }

        UserDefaults.standard.set(true, forKey: Self.migrationKey)
        save()
    }

    private struct LegacySnapshot: Codable {
        var records: [String: [Int: LevelRecord]]
        var marathon: [String: MarathonBest]?
        var seededThrough: [String: Int]?
    }

    private func migrate(_ legacy: LegacySnapshot) {
        for (key, oldRecords) in legacy.records {
            guard let game = GameID(rawValue: key) else { continue }
            var perGame = tracks[game] ?? [:]
            var furthest: (difficulty: ChallengeDifficulty, level: Int)?

            for (oldLevel, record) in oldRecords {
                let ceiling = DifficultyScale.contentCeiling(for: game)
                let bounded = min(ceiling, max(1, oldLevel))
                let legacyDifficulty = 1 + 9 * Double(bounded - 1) / Double(max(1, ceiling - 1))
                let position = DifficultyScale.trackPosition(forLegacyDifficulty: legacyDifficulty)
                var track = perGame[position.difficulty] ?? DifficultyTrackProgress()
                let existing = track.records[position.level]
                track.records[position.level] = LevelRecord(
                    passed: record.passed || (existing?.passed ?? false),
                    bestQuality: max(record.bestQuality, existing?.bestQuality ?? 0)
                )
                if record.passed {
                    track.unlockedLevel = max(track.unlockedLevel, position.level + 1)
                }
                perGame[position.difficulty] = track
                if furthest == nil || oldLevel > (furthest?.level ?? 0) {
                    furthest = (position.difficulty, oldLevel)
                }
            }

            tracks[game] = perGame
            if let furthest { selections[game] = furthest.difficulty }
        }

        for (key, best) in legacy.marathon ?? [:] {
            if let game = GameID(rawValue: key) { marathonBests[game] = best }
        }
    }

    // MARK: Persistence

    private struct StoredTrack: Codable {
        var game: GameID
        var difficulty: ChallengeDifficulty
        var progress: DifficultyTrackProgress
    }

    private struct StoredSelection: Codable {
        var game: GameID
        var difficulty: ChallengeDifficulty
    }

    private struct StoredMarathon: Codable {
        var game: GameID
        var best: MarathonBest
    }

    private struct StoredModeBest: Codable {
        var game: GameID
        var difficulty: ChallengeDifficulty
        var score: Int
    }

    private struct StoredPeriodBest: Codable {
        var game: GameID
        var difficulty: ChallengeDifficulty
        var bests: PeriodBests
    }

    private struct Snapshot: Codable {
        var tracks: [StoredTrack]
        var selections: [StoredSelection]
        var marathon: [StoredMarathon]
        var modes: [StoredModeBest]?
        var periods: [StoredPeriodBest]?
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }

        for entry in snapshot.tracks {
            var perGame = tracks[entry.game] ?? [:]
            perGame[entry.difficulty] = entry.progress
            tracks[entry.game] = perGame
        }
        for entry in snapshot.selections {
            selections[entry.game] = entry.difficulty
        }
        for entry in snapshot.marathon {
            marathonBests[entry.game] = entry.best
        }
        for entry in snapshot.modes ?? [] {
            var perGame = modeBests[entry.game] ?? [:]
            perGame[entry.difficulty] = entry.score
            modeBests[entry.game] = perGame
        }
        for entry in snapshot.periods ?? [] {
            var perGame = periodBests[entry.game] ?? [:]
            perGame[entry.difficulty] = entry.bests
            periodBests[entry.game] = perGame
        }
    }

    private func save() {
        var snapshot = Snapshot(tracks: [], selections: [], marathon: [],
                                modes: [], periods: [])
        for (game, values) in tracks {
            for (difficulty, progress) in values {
                snapshot.tracks.append(StoredTrack(game: game,
                                                   difficulty: difficulty,
                                                   progress: progress))
            }
        }
        for (game, difficulty) in selections {
            snapshot.selections.append(StoredSelection(game: game, difficulty: difficulty))
        }
        for (game, best) in marathonBests {
            snapshot.marathon.append(StoredMarathon(game: game, best: best))
        }
        for (game, values) in modeBests {
            for (difficulty, score) in values {
                snapshot.modes?.append(StoredModeBest(game: game,
                                                      difficulty: difficulty,
                                                      score: score))
            }
        }
        for (game, values) in periodBests {
            for (difficulty, bests) in values {
                snapshot.periods?.append(StoredPeriodBest(game: game,
                                                          difficulty: difficulty,
                                                          bests: bests))
            }
        }
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

enum MarathonMath {
    static func points(level: Int, quality: Double) -> Int {
        Int((100 * Double(level) * max(0, min(1.5, quality))).rounded())
    }
}
