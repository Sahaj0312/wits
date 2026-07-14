//
//  WeeklyChallenge.swift
//  wits
//
//  A deterministic, comparable competition run. Campaign progression stays
//  personal; weekly runs give every player the same rules and random stream.
//

import Foundation

struct WeeklyChallenge: Codable, Equatable, Sendable {
    static let rulesVersion = 1

    let game: GameID
    let weekID: String
    let startsAt: Date
    let endsAt: Date
    let seed: UInt64
    let difficulty: ChallengeDifficulty
    let trackLevel: Int

    static func current(for game: GameID, now: Date = Date()) -> WeeklyChallenge {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        let year = components.yearForWeekOfYear ?? 0
        let week = components.weekOfYear ?? 0
        let weekID = String(format: "%04d-W%02d", year, week)
        let interval = calendar.dateInterval(of: .weekOfYear, for: now)
        let startsAt = interval?.start ?? now
        let endsAt = interval?.end ?? now.addingTimeInterval(7 * 24 * 60 * 60)
        let trackLevel = game.weeklyTrackLevel
        let difficulty = game.weeklyDifficulty
        let seedText = "wits|weekly|v\(rulesVersion)|\(game.rawValue)|\(weekID)"

        return WeeklyChallenge(game: game,
                               weekID: weekID,
                               startsAt: startsAt,
                               endsAt: endsAt,
                               seed: StableSeed.hash(seedText),
                               difficulty: difficulty,
                               trackLevel: trackLevel)
    }

    var leaderboardID: String { "wits.weekly.\(game.rawValue)" }

    var shortWeekLabel: String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: startsAt))–\(formatter.string(from: endsAt.addingTimeInterval(-1)))"
    }
}

extension GameID {
    /// Weekly runs use one approachable fixed tier. Game-specific levels keep
    /// puzzle length and timed-task load comparable without sharing raw scores.
    var weeklyDifficulty: ChallengeDifficulty {
        self == .split ? .hard : .medium
    }

    var weeklyTrackLevel: Int {
        switch self {
        case .slidePuzzle, .blockEscape, .pegSolitaire, .waterSort, .mahjong, .crossword: 5
        case .split, .blockFit, .fuse, .snake, .tower: 1
        default: 8
        }
    }
}

enum StableSeed {
    /// FNV-1a is intentionally simple and stable across processes and devices;
    /// Swift's Hasher is randomized and cannot identify a shared challenge.
    static func hash(_ text: String) -> UInt64 {
        var value: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value &*= 1_099_511_628_211
        }
        return value
    }

    static func mix(_ value: UInt64, stream: UInt64) -> UInt64 {
        var x = value ^ (stream &* 0x9E3779B97F4A7C15)
        x ^= x >> 30
        x &*= 0xBF58476D1CE4E5B9
        x ^= x >> 27
        x &*= 0x94D049BB133111EB
        x ^= x >> 31
        return x
    }
}

nonisolated struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xA0761D6478BD642F : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

struct WeeklyChallengeScore: Equatable {
    let rankValue: Int
    let headline: String
    let detail: String
}

struct WeeklyRunOutcome: Equatable {
    let result: GameResult
    let score: WeeklyChallengeScore
    let improved: Bool
}

enum WeeklyChallengeScorer {
    /// Every leaderboard is game-specific, so each game keeps its native point
    /// model. Fixed boards/rules make those points comparable within that board.
    static func score(_ result: GameResult) -> WeeklyChallengeScore {
        let points = max(0, result.baseScoreValue)
        switch result.game {
        case .crowdControl:
            let correct = Int(result.raw["correctPicks"] ?? 0)
            let total = Int(result.raw["totalTargets"] ?? 0)
            return WeeklyChallengeScore(rankValue: points,
                                        headline: "\(points) points",
                                        detail: "\(correct) of \(total) targets")
        case .echoGrid:
            let span = Int(result.raw["maxSpan"] ?? 0)
            return WeeklyChallengeScore(rankValue: points,
                                        headline: "\(points) points",
                                        detail: "best span \(span)")
        case .lastSeen:
            let remembered = Int(result.raw["remembered"] ?? 0)
            return WeeklyChallengeScore(rankValue: points,
                                        headline: "\(points) points",
                                        detail: "\(remembered) remembered")
        case .slidePuzzle, .blockEscape:
            let moves = Int(result.raw["moves"] ?? Double(result.trials))
            let seconds = Int(result.raw["seconds"] ?? Double(result.durationMs) / 1_000)
            return WeeklyChallengeScore(rankValue: points,
                                        headline: "\(points) points",
                                        detail: "\(moves) moves · \(seconds)s")
        case .waterSort:
            let pours = Int(result.raw["moves"] ?? Double(result.trials))
            let seconds = Int(result.raw["seconds"] ?? Double(result.durationMs) / 1_000)
            return WeeklyChallengeScore(rankValue: points,
                                        headline: "\(points) points",
                                        detail: "\(pours) pours · \(seconds)s")
        case .mahjong:
            let matched = Int(result.raw["pairs"] ?? Double(result.trials))
            let seconds = Int(result.raw["seconds"] ?? Double(result.durationMs) / 1_000)
            return WeeklyChallengeScore(rankValue: points,
                                        headline: "\(points) points",
                                        detail: "\(matched) pairs · \(seconds)s")
        case .pegSolitaire:
            let solved = (result.raw["solved"] ?? 0) >= 1
            let cleared = Int(result.raw["cleared"] ?? 0)
            return WeeklyChallengeScore(rankValue: points,
                                        headline: "\(points) points",
                                        detail: solved ? "board cleared" : "\(cleared) pegs cleared")
        case .split:
            let level = Int(result.raw["maxLevel"] ?? Double(result.score))
            let depth = result.raw["levelDepth"] ?? 0
            return split(level: level, depth: depth)
        case .blockFit:
            let lines = Int(result.raw["lines"] ?? 0)
            return WeeklyChallengeScore(rankValue: points,
                                        headline: "\(points) points",
                                        detail: "\(lines) lines cleared")
        case .fuse:
            let tile = Int(result.raw["bestTile"] ?? 0)
            return WeeklyChallengeScore(rankValue: points,
                                        headline: "\(points) points",
                                        detail: "best tile \(tile)")
        case .snake:
            let length = Int(result.raw["length"] ?? 0)
            return WeeklyChallengeScore(rankValue: points,
                                        headline: "\(points) apples",
                                        detail: "\(length) long")
        case .tower:
            let perfects = Int(result.raw["perfects"] ?? 0)
            return WeeklyChallengeScore(rankValue: points,
                                        headline: "\(points) blocks",
                                        detail: "\(perfects) perfect drops")
        default:
            let correct = Int(result.raw["correct"] ?? 0)
            return WeeklyChallengeScore(rankValue: points,
                                        headline: "\(points) points",
                                        detail: "\(correct) correct")
        }
    }

    /// App Store Connect should format Split scores as a fixed-point value with
    /// three decimals: 8,625 is displayed as level 8.625.
    static func split(level: Int, depth: Double) -> WeeklyChallengeScore {
        let safeLevel = max(1, level)
        let fraction = min(0.999, max(0, depth))
        let value = safeLevel * 1_000 + Int((fraction * 999).rounded())
        return WeeklyChallengeScore(rankValue: value,
                                    headline: "level \(safeLevel)",
                                    detail: "\(Int((fraction * 100).rounded()))% through")
    }

    static func splitLabel(rankValue: Int) -> String {
        String(format: "%.3f", Double(max(0, rankValue)) / 1_000)
    }
}
