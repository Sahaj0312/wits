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
    case spotSpeed, colorClash, matchBack, ruleFinder
    // expanded library
    case numberRush, estimator, oddOneOut, tileShift, lastSeen, pathKeeper
    // survival-only (no staircased workout mode; not in the daily pool)
    case split

    var id: String { rawValue }

    /// Games in the daily-workout pool (staircased, train + survival modes).
    static var live: [GameID] {
        [.arrowStorm, .crowdControl, .echoGrid, .colorClash, .spotSpeed, .matchBack, .ruleFinder,
         .numberRush, .estimator, .oddOneOut, .tileShift, .lastSeen, .pathKeeper]
    }
    var isLive: Bool { Self.live.contains(self) }

    /// Games that exist only as a survival/arcade run — no train mode, never
    /// prescribed in the daily workout, but they still feed the weakness engine.
    static var survivalOnly: [GameID] { [.split] }
    var isSurvivalOnly: Bool { Self.survivalOnly.contains(self) }

    /// Tappable in the library (has some playable mode).
    var isPlayable: Bool { isLive || isSurvivalOnly }
}

enum CognitiveDomain: String, Codable, CaseIterable, Identifiable {
    case focus, multitasking, memory, flexibility, reasoning, math
    var id: String { rawValue }

    var label: String {
        switch self {
        case .focus: "focus"
        case .multitasking: "multitasking"
        case .memory: "memory"
        case .flexibility: "flexibility"
        case .reasoning: "reasoning"
        case .math: "math"
        }
    }
}

extension GameID {
    /// Scoring bucket for the progress breakdown.
    var domain: CognitiveDomain {
        switch self {
        case .arrowStorm, .spotSpeed, .oddOneOut: .focus
        case .crowdControl: .multitasking
        case .echoGrid, .matchBack, .lastSeen, .pathKeeper: .memory
        case .colorClash, .tileShift: .flexibility
        case .ruleFinder: .reasoning
        case .numberRush, .estimator: .math
        case .split: .multitasking
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
        case .numberRush: "number rush"
        case .estimator: "snap count"
        case .oddOneOut: "odd one out"
        case .tileShift: "tile shift"
        case .lastSeen: "last seen"
        case .pathKeeper: "path keeper"
        case .split: "split"
        }
    }

    /// One-line tagline (library cell + card hero subtitle).
    var tagline: String {
        switch self {
        case .arrowStorm: "answer only to the middle arrow."
        case .crowdControl: "track the dots through the crowd."
        case .echoGrid: "play the path back — backwards."
        case .spotSpeed: "catch the flash before it fades."
        case .colorClash: "tap the colour, not the word."
        case .matchBack: "spot what repeats."
        case .ruleFinder: "find the rule, finish the grid."
        case .numberRush: "solve it before it drops."
        case .estimator: "more, at a glance."
        case .oddOneOut: "find the one that doesn't fit."
        case .tileShift: "the rule keeps changing."
        case .lastSeen: "never tap the same one twice."
        case .pathKeeper: "repeat the hops, in order."
        case .split: "fly and pick at once. one slip ends it."
        }
    }

    /// Breadcrumb: top-level discipline shown on the card.
    var domainTitle: String {
        switch self {
        case .arrowStorm, .crowdControl, .oddOneOut: "attention"
        case .spotSpeed: "speed"
        case .echoGrid, .matchBack, .lastSeen, .pathKeeper: "memory"
        case .colorClash, .tileShift: "flexibility"
        case .ruleFinder: "problem solving"
        case .numberRush, .estimator: "math"
        case .split: "attention"
        }
    }

    /// Breadcrumb: the specific sub-skill the game trains.
    var subskill: String {
        switch self {
        case .arrowStorm: "selective attention"
        case .crowdControl: "divided attention"
        case .oddOneOut: "visual search"
        case .spotSpeed: "field of view"
        case .echoGrid: "spatial recall"
        case .matchBack: "working memory"
        case .lastSeen: "short-term memory"
        case .pathKeeper: "working memory"
        case .colorClash: "response inhibition"
        case .tileShift: "task switching"
        case .ruleFinder: "logical reasoning"
        case .numberRush: "arithmetic"
        case .estimator: "numerical estimation"
        case .split: "dual-tasking"
        }
    }

    /// First card paragraph — what you do.
    var cardHow: String {
        switch self {
        case .arrowStorm: "spot which way the middle arrow points while the crowd around it tries to pull your answer the other way."
        case .crowdControl: "keep your eyes on a few glowing dots as they scatter into an identical crowd, then pick them back out."
        case .echoGrid: "watch a path of tiles light up, then tap them back in reverse order."
        case .spotSpeed: "identify the shape in the centre and catch where a target flashes at the edge — before it's masked."
        case .colorClash: "tap the colour a word is printed in, not the word it spells."
        case .matchBack: "tap match whenever the current square is the same as the one a few steps back."
        case .ruleFinder: "work out the rule running across the grid and pick the figure that completes it."
        case .numberRush: "solve each falling equation and pick the answer before it hits the bottom."
        case .estimator: "two groups flash for an instant — pick the one with more before you can count."
        case .oddOneOut: "scan the grid and tap the single shape that doesn't match the rest."
        case .tileShift: "follow the rule on screen — sometimes match by colour, sometimes by shape. it keeps flipping."
        case .lastSeen: "tap each object once — never tap one you've already chosen as new ones appear."
        case .pathKeeper: "watch a token hop across the board, then repeat its path in the same order."
        case .split: "keep the flyer alive at the bottom while you tap the right targets up top and never tap the look-alike. one mistake ends the run — see how many levels you clear."
        }
    }

    /// Second card paragraph — what the skill is.
    var cardAbout: String {
        switch self {
        case .arrowStorm, .oddOneOut: "selective attention is focusing on what matters while ignoring everything competing for your eyes."
        case .crowdControl: "divided attention is following several moving things at once without losing track of any."
        case .spotSpeed: "field of view is how much you can take in at a single glance, without moving your eyes."
        case .echoGrid: "spatial recall is holding where things were in mind and replaying that layout accurately."
        case .matchBack, .pathKeeper: "working memory is holding recent information in mind and acting on it."
        case .lastSeen: "short-term memory is keeping recent items in mind so you don't repeat yourself."
        case .colorClash: "response inhibition is overriding the automatic answer to give the correct one."
        case .tileShift: "task switching is adapting quickly when the goal keeps changing underneath you."
        case .ruleFinder: "logical reasoning is recognising patterns, drawing conclusions, and making decisions."
        case .numberRush: "arithmetic is performing quick mental calculations accurately under time pressure."
        case .estimator: "numerical estimation is judging quantities at a glance, without stopping to count."
        case .split: "divided attention is doing two demanding things at once — steering one hand while deciding with the other — without dropping either."
        }
    }

    /// SF Symbol for the library cell / workout cards.
    var symbol: String {
        switch self {
        case .arrowStorm: "arrowtriangle.right.fill"
        case .crowdControl: "circle.grid.3x3.fill"
        case .echoGrid: "square.grid.3x3.fill"
        case .spotSpeed: "eye.fill"
        case .colorClash: "paintpalette.fill"
        case .matchBack: "rectangle.stack.fill"
        case .ruleFinder: "puzzlepiece.fill"
        case .numberRush: "plus.forwardslash.minus"
        case .estimator: "circle.hexagongrid.fill"
        case .oddOneOut: "magnifyingglass"
        case .tileShift: "arrow.triangle.2.circlepath"
        case .lastSeen: "sparkles"
        case .pathKeeper: "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .split: "rectangle.split.1x2.fill"
        }
    }

    /// Card hero gradient (top, bottom) as hex.
    var heroColors: (UInt32, UInt32) {
        switch self {
        case .arrowStorm: (0x243155, 0x141B33)
        case .crowdControl: (0x123A33, 0x0F2A2A)
        case .echoGrid: (0x1F2A4D, 0x141B33)
        case .spotSpeed: (0x2A3A5E, 0x16243F)
        case .colorClash: (0x3A2350, 0x201433)
        case .matchBack: (0x14304D, 0x10233A)
        case .ruleFinder: (0x243155, 0x141B33)
        case .numberRush: (0x5E3A1E, 0x331F14)
        case .estimator: (0x3F4A1E, 0x2A3314)
        case .oddOneOut: (0x2E2A5E, 0x1A1840)
        case .tileShift: (0x4A1E50, 0x2D1433)
        case .lastSeen: (0x123A4D, 0x0F2A3A)
        case .pathKeeper: (0x1E3A5E, 0x14243F)
        case .split: (0x123A33, 0x0F2A2A)
        }
    }

    /// Starting difficulty `level` for a brand-new player (0…10).
    var seedLevel: Double {
        switch self {
        case .crowdControl, .echoGrid, .lastSeen, .pathKeeper, .matchBack: 1
        default: 2
        }
    }

    // MARK: Card "best stat"

    /// Key in GameResult.raw that holds this game's headline stat.
    var statKey: String {
        switch self {
        case .crowdControl: "perfectRounds"
        case .echoGrid: "maxSpan"
        case .spotSpeed: "thresholdMs"
        case .matchBack: "n"
        case .ruleFinder: "complexity"
        case .lastSeen: "remembered"
        case .pathKeeper: "maxLen"
        case .split: "maxLevel"
        default: "bestStreak"
        }
    }

    var statLowerIsBetter: Bool { self == .spotSpeed }

    func statLabel(_ v: Double) -> String {
        switch self {
        case .echoGrid: "\(Int(v)) tiles"
        case .spotSpeed: "\(Int(v)) ms"
        case .matchBack: "\(Int(v))-back"
        case .ruleFinder: "level \(Int(v))"
        case .crowdControl: "\(Int(v)) perfect"
        case .lastSeen: "\(Int(v)) recalled"
        case .pathKeeper: "\(Int(v)) steps"
        case .split: "level \(Int(v))"
        default: "streak \(Int(v))"
        }
    }
}

/// Per-game lifetime stats shown on the pre-game card.
struct GameStats: Codable {
    var bestScore: Int = 0
    var totalPlays: Int = 0
    var bestStat: Double? = nil
    var survivalBest: Int = 0      // best survival run score (defaulted → old cache decodes)
    var survivalRuns: Int = 0
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

enum GameMode: String, Codable { case workout, freePlay, survival }

/// A single decision's outcome, emitted by a game in survival so the host can
/// own lives/combo/score. `points` is the game's base points for that decision.
struct TrialOutcome: Equatable {
    enum Kind { case hit, miss, nearMiss, timeout }
    var kind: Kind
    var points: Int = 0
}

/// Parameters handed to a game at launch.
struct GameConfig {
    var difficulty: DifficultyState
    var targetDurationSec: Double = 45
    var mode: GameMode = .workout
    var rewardSeed: UInt64 = 0
    /// Survival only: the game pushes each decision up; the host owns lives/score.
    /// In survival, a game runs forever (no self-end) and self-escalates as it goes.
    var onOutcome: ((TrialOutcome) -> Void)? = nil

    /// Back-compat: existing call sites read `isFreePlay`.
    var isFreePlay: Bool { mode == .freePlay }
    var isSurvival: Bool { mode == .survival }

    static func standard(_ g: GameID, difficulty: DifficultyState, freePlay: Bool = false) -> GameConfig {
        GameConfig(difficulty: difficulty, mode: freePlay ? .freePlay : .workout)
    }

    static func survival(_ g: GameID, difficulty: DifficultyState,
                         onOutcome: @escaping (TrialOutcome) -> Void) -> GameConfig {
        GameConfig(difficulty: difficulty, mode: .survival, onOutcome: onOutcome)
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
