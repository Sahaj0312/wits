//
//  LevelSystem.swift
//  wits
//
//  Star-map progression core (docs/level-progression-redesign.md).
//
//  Every game is a paginated ladder of fixed levels. Level n of a game is
//  identical for every player: its spec is derived by mapping the map level
//  onto the game's existing 1...10 difficulty curves, frozen per level.
//  Stars grade each run's policy `performance` quality; passing unlocks the
//  next level; page boundaries gate on star totals. Marathon mode chains
//  levels pass-to-continue until the first sub-pass run (the "death").
//

import Foundation
import SwiftUI

// MARK: - Ladder

enum LevelLadder {
    static let pageSize = 10
    /// Stars required from the previous page to enter a page (60% of 30).
    static let pageGateStars = 18

    /// Map depth per game — set by how many perceptibly distinct difficulty
    /// steps the game's curves support (see design doc §1).
    static func levelCount(for game: GameID) -> Int {
        switch game {
        case .arrowStorm, .colorClash, .tileShift:
            50
        case .crowdControl, .echoGrid, .lastSeen,
             .slidePuzzle, .blockEscape, .pegSolitaire:
            40
        case .split:
            30
        }
    }

    static func pageCount(for game: GameID) -> Int {
        (levelCount(for: game) + pageSize - 1) / pageSize
    }

    /// 0-indexed page containing a 1-indexed level.
    static func page(of level: Int) -> Int {
        max(0, (level - 1) / pageSize)
    }

    static func levels(inPage page: Int, of game: GameID) -> ClosedRange<Int> {
        let lower = page * pageSize + 1
        let upper = min(levelCount(for: game), (page + 1) * pageSize)
        return lower...max(lower, upper)
    }

    /// Freeze map level n onto the game's legacy 1...10 difficulty scale.
    /// Games keep reading `cfg.difficulty.level`; this mapping is what makes
    /// every existing tuning curve serve fixed exam specs without rewrites.
    static func legacyDifficulty(for game: GameID, level: Int) -> Double {
        let count = levelCount(for: game)
        guard count > 1 else { return 1 }
        let clamped = min(count, max(1, level))
        return DifficultyState.clamp(1 + 9 * Double(clamped - 1) / Double(count - 1))
    }

    /// Inverse of `legacyDifficulty`: the map level whose spec is closest to
    /// a legacy 1...10 difficulty. Used to seed existing users' frontiers.
    static func nearestLevel(for game: GameID, legacyDifficulty value: Double) -> Int {
        let count = levelCount(for: game)
        let v = DifficultyState.clamp(value)
        let n = 1 + Int(((v - 1) / 9 * Double(count - 1)).rounded())
        return min(count, max(1, n))
    }

    /// A difficulty state whose `.level` carries the frozen exam spec. Mastery
    /// bookkeeping fields come from the persisted state so WPI evolution
    /// continues; only the served challenge is pinned to the map.
    static func examDifficulty(for game: GameID, level: Int, persisted: DifficultyState) -> DifficultyState {
        var d = persisted
        d.level = legacyDifficulty(for: game, level: level)
        return d
    }
}

// MARK: - Stars

enum StarGrader {
    static let passQuality = 0.60
    static let twoStarQuality = 0.75
    static let threeStarQuality = 0.90

    static func stars(quality: Double) -> Int {
        switch quality {
        case threeStarQuality...: 3
        case twoStarQuality..<threeStarQuality: 2
        case passQuality..<twoStarQuality: 1
        default: 0
        }
    }

    /// Grade a scored run. Prefers the scoring pipeline's difficulty-normalized
    /// quality; falls back to raw accuracy for results that bypassed scoring.
    static func stars(for result: GameResult) -> Int {
        stars(quality: result.performanceQuality ?? result.accuracy)
    }
}

// MARK: - Progress store

struct LevelRecord: Codable, Equatable {
    var stars: Int
    var bestQuality: Double
}

struct MarathonBest: Codable, Equatable {
    var depth: Int
    var score: Int
}

/// Local-first persistence for map progress; UserDefaults is the source of
/// truth on device. Game Center mirrors bests/achievements best-effort.
@MainActor
@Observable
final class LevelProgressStore {
    private(set) var records: [GameID: [Int: LevelRecord]] = [:]
    private(set) var marathonBests: [GameID: MarathonBest] = [:]
    /// Highest level granted by the one-time adaptive-difficulty migration.
    /// Gates never apply at or below `seededThrough + 1` — a converted user
    /// must be able to play their frontier on day one.
    private(set) var seededThrough: [GameID: Int] = [:]

    private static let storageKey = "wits.levelProgress.v1"
    private static let seededKey = "wits.levelProgress.seeded.v1"

    init() {
        load()
    }

    // MARK: Queries

    func record(for game: GameID, level: Int) -> LevelRecord? {
        records[game]?[level]
    }

    func stars(for game: GameID, level: Int) -> Int {
        records[game]?[level]?.stars ?? 0
    }

    func isPassed(_ game: GameID, level: Int) -> Bool {
        stars(for: game, level: level) >= 1
    }

    func starsInPage(_ game: GameID, page: Int) -> Int {
        LevelLadder.levels(inPage: page, of: game).reduce(0) { $0 + stars(for: game, level: $1) }
    }

    func totalStars(for game: GameID) -> Int {
        records[game]?.values.reduce(0) { $0 + $1.stars } ?? 0
    }

    /// A page is open when the previous page has met the star gate — or when
    /// the page already holds progress, or sits inside seeded territory
    /// (past play and migrated frontiers never get retroactively locked out;
    /// gates only bar first entry).
    func isPageUnlocked(_ game: GameID, page: Int) -> Bool {
        guard page > 0 else { return true }
        let range = LevelLadder.levels(inPage: page, of: game)
        if range.lowerBound <= (seededThrough[game] ?? 0) + 1 { return true }
        if range.contains(where: { isPassed(game, level: $0) }) { return true }
        return starsInPage(game, page: page - 1) >= LevelLadder.pageGateStars
    }

    /// Level 1 is always open; otherwise the previous level must be passed and
    /// the level's page gate met.
    func isUnlocked(_ game: GameID, level: Int) -> Bool {
        guard level > 1 else { return true }
        guard level <= LevelLadder.levelCount(for: game) else { return false }
        return isPassed(game, level: level - 1) && isPageUnlocked(game, page: LevelLadder.page(of: level))
    }

    /// Lowest unpassed level (the "next up" tile), ignoring gates.
    func frontier(for game: GameID) -> Int {
        let count = LevelLadder.levelCount(for: game)
        for level in 1...count where !isPassed(game, level: level) {
            return level
        }
        return count
    }

    /// The level a workout serves: the frontier when it is actually playable;
    /// when a page gate blocks it, the weakest-star passed level in the
    /// previous page (consolidation replay that also earns the gate stars).
    func workoutLevel(for game: GameID) -> Int {
        let frontier = frontier(for: game)
        if isUnlocked(game, level: frontier) { return frontier }
        let page = LevelLadder.page(of: frontier)
        guard page > 0 else { return 1 }
        let previous = LevelLadder.levels(inPage: page - 1, of: game)
        return previous.min { stars(for: game, level: $0) < stars(for: game, level: $1) } ?? frontier
    }

    func marathonBest(for game: GameID) -> MarathonBest? {
        marathonBests[game]
    }

    // MARK: Mutations

    /// Record a level attempt. Stars only ever go up. Returns true when the
    /// attempt improved the stored stars.
    @discardableResult
    func recordAttempt(game: GameID, level: Int, stars: Int, quality: Double) -> Bool {
        var perGame = records[game] ?? [:]
        let existing = perGame[level]
        let improved = stars > (existing?.stars ?? 0)
        perGame[level] = LevelRecord(
            stars: max(stars, existing?.stars ?? 0),
            bestQuality: max(quality, existing?.bestQuality ?? 0)
        )
        records[game] = perGame
        save()
        return improved
    }

    /// Record a marathon run. Returns true on a new best depth.
    @discardableResult
    func recordMarathon(game: GameID, depth: Int, score: Int) -> Bool {
        let current = marathonBests[game]
        let newBest = depth > (current?.depth ?? 0) ||
            (depth == (current?.depth ?? 0) && score > (current?.score ?? 0))
        if newBest {
            marathonBests[game] = MarathonBest(depth: depth, score: score)
            save()
        }
        return newBest
    }

    // MARK: Migration seeding

    /// One-time conversion for existing users: unlock the map up to the level
    /// equivalent to their old adaptive difficulty, granting 1★ per level so
    /// nobody replays trivial content (no stars gifted above 1★ — see doc §8).
    func seedIfNeeded(from difficulty: [GameID: DifficultyState]) {
        guard !UserDefaults.standard.bool(forKey: Self.seededKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.seededKey)
        for (game, state) in difficulty where state.sessionsPlayed > 0 {
            let frontier = LevelLadder.nearestLevel(for: game, legacyDifficulty: state.level)
            guard frontier > 1 else { continue }
            var perGame = records[game] ?? [:]
            for level in 1..<frontier where perGame[level] == nil {
                perGame[level] = LevelRecord(stars: 1, bestQuality: StarGrader.passQuality)
            }
            records[game] = perGame
            seededThrough[game] = frontier - 1
        }
        save()
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var records: [String: [Int: LevelRecord]]
        var marathon: [String: MarathonBest]?
        var seededThrough: [String: Int]?
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        for (key, value) in snap.records {
            if let game = GameID(rawValue: key) { records[game] = value }
        }
        for (key, value) in snap.marathon ?? [:] {
            if let game = GameID(rawValue: key) { marathonBests[game] = value }
        }
        for (key, value) in snap.seededThrough ?? [:] {
            if let game = GameID(rawValue: key) { seededThrough[game] = value }
        }
    }

    private func save() {
        var snap = Snapshot(records: [:], marathon: [:], seededThrough: [:])
        for (game, value) in records { snap.records[game.rawValue] = value }
        for (game, value) in marathonBests { snap.marathon?[game.rawValue] = value }
        for (game, value) in seededThrough { snap.seededThrough?[game.rawValue] = value }
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

// MARK: - Marathon scoring

enum MarathonMath {
    /// Clearing level n pays 100·n·quality — cumulative total grows
    /// quadratically with depth so late levels dominate (no farming).
    static func points(level: Int, quality: Double) -> Int {
        Int((100 * Double(level) * max(0, min(1.5, quality))).rounded())
    }
}
