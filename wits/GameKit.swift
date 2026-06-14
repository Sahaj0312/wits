//
//  GameKit.swift
//  wits
//
//  Shared interface for the post-onboarding game library: a uniform identity,
//  cognitive-domain mapping, persisted adaptive-difficulty state, a single
//  GameResult every game emits, and the staircase that calibrates difficulty
//  toward the ~71% accuracy sweet spot over repeated sessions.
//

import SwiftUI

// MARK: - Identity

enum GameID: String, CaseIterable, Codable, Identifiable {
    // shipped (built as adaptive, replayable games)
    case arrowStorm, crowdControl, echoGrid
    // roadmap (Phase 2)
    case spotSpeed, colorClash, matchBack, ruleFinder

    var id: String { rawValue }

    /// Games playable today. Roadmap games show as "coming soon" in the library.
    static var live: [GameID] { [.arrowStorm, .crowdControl, .echoGrid] }
    var isLive: Bool { Self.live.contains(self) }
}

enum CognitiveDomain: String, Codable, CaseIterable, Identifiable {
    case focus, multitasking, memory, flexibility, reasoning
    var id: String { rawValue }

    var label: String {
        switch self {
        case .focus: "focus"
        case .multitasking: "multitasking"
        case .memory: "memory"
        case .flexibility: "flexibility"
        case .reasoning: "reasoning"
        }
    }
}

extension GameID {
    var domain: CognitiveDomain {
        switch self {
        case .arrowStorm, .spotSpeed: .focus
        case .crowdControl: .multitasking
        case .echoGrid, .matchBack: .memory
        case .colorClash: .flexibility
        case .ruleFinder: .reasoning
        }
    }

    var displayName: String {
        switch self {
        case .arrowStorm: "arrow storm"
        case .crowdControl: "crowd control"
        case .echoGrid: "echo grid"
        case .spotSpeed: "spot speed"
        case .colorClash: "color clash"
        case .matchBack: "match-back"
        case .ruleFinder: "rule finder"
        }
    }

    /// One-line library tagline.
    var tagline: String {
        switch self {
        case .arrowStorm: "answer only to the middle arrow."
        case .crowdControl: "track the dots through the crowd."
        case .echoGrid: "play the path back — backwards."
        case .spotSpeed: "catch the flash before it fades."
        case .colorClash: "tap the colour, not the word."
        case .matchBack: "spot what repeats."
        case .ruleFinder: "find the rule, finish the grid."
        }
    }

    /// SF Symbol used in the library / workout cards.
    var symbol: String {
        switch self {
        case .arrowStorm: "arrowtriangle.right.fill"
        case .crowdControl: "circle.grid.3x3.fill"
        case .echoGrid: "square.grid.3x3.fill"
        case .spotSpeed: "eye.fill"
        case .colorClash: "paintpalette.fill"
        case .matchBack: "rectangle.stack.fill"
        case .ruleFinder: "puzzlepiece.fill"
        }
    }

    /// Starting difficulty `level` for a brand-new player (0…10 scale).
    var seedLevel: Double {
        switch self {
        case .arrowStorm: 2
        case .crowdControl: 1
        case .echoGrid: 1
        default: 2
        }
    }
}

// MARK: - Adaptive difficulty

/// Persisted per-user, per-game staircase state. `level` is a continuous 0…10
/// parameter each game interprets in its own units (response window, span
/// length, # of targets, …).
struct DifficultyState: Codable, Equatable {
    var level: Double
    var reversals: Int = 0
    var lastDirection: Int = 0
    var sessionsPlayed: Int = 0

    static func seed(for g: GameID) -> DifficultyState {
        DifficultyState(level: g.seedLevel)
    }
}

/// 1-up/2-down-style post-run calibration. We adapt *within* a run for feel
/// (each game tightens/loosens as you go); this nudges the *persisted* starting
/// level between sessions toward the ~71% accuracy target.
enum Staircase {
    static func adjust(_ s: DifficultyState, accuracy: Double, step: Double = 0.6) -> DifficultyState {
        var next = s
        let dir: Int = accuracy >= 0.80 ? 1 : (accuracy <= 0.60 ? -1 : 0)
        if dir != 0 {
            if s.lastDirection != 0 && dir != s.lastDirection { next.reversals += 1 }
            next.level = max(0, min(10, s.level + Double(dir) * step))
            next.lastDirection = dir
        }
        next.sessionsPlayed += 1
        return next
    }
}

// MARK: - Result

/// What every game emits when its scored run ends. Replaces the per-game Stats
/// structs at the boundary; the host fills `newDifficulty` after calling advance.
struct GameResult: Codable, Equatable {
    let game: GameID
    var score: Int
    var accuracy: Double            // 0…1 — the staircase + scoring signal
    var medianRTms: Int? = nil
    var threshold: Double? = nil    // converged difficulty parameter this run
    var trials: Int = 0
    var newDifficulty: DifficultyState? = nil
    var startedAt: Date = Date()
    var durationMs: Int = 0
    var raw: [String: Double] = [:] // game-specific extras → game_sessions.details

    var domain: CognitiveDomain { game.domain }
}

// MARK: - Config

/// Parameters handed to a game at launch.
struct GameConfig {
    var difficulty: DifficultyState
    var targetDurationSec: Double = 45
    var isFreePlay: Bool = false
    var rewardSeed: UInt64 = 0

    static func standard(_ g: GameID, difficulty: DifficultyState, freePlay: Bool = false) -> GameConfig {
        GameConfig(difficulty: difficulty, isFreePlay: freePlay)
    }
}

// MARK: - Game protocol

protocol Game {
    static var id: GameID { get }
    /// Pure staircase update from a finished run's accuracy.
    static func advance(_ s: DifficultyState, accuracy: Double) -> DifficultyState
    /// The playable view; calls onComplete(GameResult) when the scored run ends.
    @MainActor static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView
}

extension Game {
    static func advance(_ s: DifficultyState, accuracy: Double) -> DifficultyState {
        Staircase.adjust(s, accuracy: accuracy)
    }
}
