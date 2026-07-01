//
//  GameKit.swift
//  wits
//
//  Shared interface for the post-onboarding game library: a uniform identity,
//  cognitive-domain mapping, persisted adaptive-difficulty state, a single
//  GameResult every game emits, and the mastery ladder that calibrates
//  difficulty over repeated sessions.
//

import SwiftUI
import Observation

// MARK: - Identity

enum GameID: String, CaseIterable, Codable, Identifiable {
    // shipped (built as adaptive, replayable games)
    case arrowStorm, crowdControl, echoGrid
    case spotSpeed, colorClash, matchBack, ruleFinder
    // expanded library
    case numberRush, estimator, oddOneOut, tileShift, lastSeen, pathKeeper
    case wordConnect, memoryLock, dotsConnect, oneLine, towerOfHanoi, slidePuzzle
    // Standalone survival mode. Playable in the library, not prescribed in daily
    // workouts, and not connected to WPI/mastery scoring.
    case split

    var id: String { rawValue }

    /// Games in the daily-workout pool (mastery-adjusted train mode).
    static var live: [GameID] {
        [.arrowStorm, .crowdControl, .echoGrid, .colorClash, .spotSpeed, .matchBack, .ruleFinder,
         .numberRush, .estimator, .oddOneOut, .tileShift, .lastSeen, .pathKeeper, .wordConnect, .dotsConnect,
         .oneLine, .memoryLock, .towerOfHanoi, .slidePuzzle]
    }
    var isLive: Bool { Self.live.contains(self) }

    static var standalone: [GameID] { [.split] }
    var isStandalone: Bool { Self.standalone.contains(self) }

    /// Tappable in the library (has some playable mode).
    var isPlayable: Bool { isLive || isStandalone }

    /// Uses the standard pre-game card but hides adaptive level UI.
    var usesAdaptiveLevelDisplay: Bool { isLive }

    /// Screens that draw their own full-bleed safe-area background and manage
    /// their own top/bottom spacing.
    var ownsSafeAreaSurface: Bool {
        switch self {
        case .echoGrid, .pathKeeper, .wordConnect, .memoryLock, .dotsConnect, .oneLine, .towerOfHanoi, .slidePuzzle: true
        default: false
        }
    }

    /// Some games place their own primary top-left control inside the playfield.
    var usesEmbeddedQuitControl: Bool {
        switch self {
        case .dotsConnect, .oneLine: true
        default: false
        }
    }
}

enum CognitiveDomain: String, Codable, CaseIterable, Identifiable {
    case focus, multitasking, memory, flexibility, reasoning, math, language
    var id: String { rawValue }

    var label: String {
        switch self {
        case .focus: "focus"
        case .multitasking: "multitasking"
        case .memory: "memory"
        case .flexibility: "flexibility"
        case .reasoning: "reason"
        case .math: "math"
        case .language: "language"
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
        case .ruleFinder, .dotsConnect, .oneLine, .towerOfHanoi, .slidePuzzle: .reasoning
        case .numberRush, .estimator: .math
        case .wordConnect, .memoryLock: .language
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
        case .matchBack: "memory lane"
        case .ruleFinder: "rule finder"
        case .numberRush: "number rush"
        case .estimator: "target forge"
        case .oddOneOut: "odd one out"
        case .tileShift: "tile shift"
        case .lastSeen: "last seen"
        case .pathKeeper: "path keeper"
        case .wordConnect: "word connect"
        case .memoryLock: "memory lock"
        case .dotsConnect: "dots connect"
        case .oneLine: "one line"
        case .towerOfHanoi: "tower of hanoi"
        case .slidePuzzle: "slide puzzle"
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
        case .matchBack: "compare each card to the lane behind it."
        case .ruleFinder: "find the rule, finish the grid."
        case .numberRush: "keep the running total, then type it."
        case .estimator: "build the number."
        case .oddOneOut: "find the one that doesn't fit."
        case .tileShift: "the rule keeps changing."
        case .lastSeen: "never tap the same one twice."
        case .pathKeeper: "repeat the hops, in order."
        case .wordConnect: "connect letters into hidden words."
        case .memoryLock: "solve the word before the clues fade."
        case .dotsConnect: "connect matching dots without crossing paths."
        case .oneLine: "draw every segment in a single stroke."
        case .towerOfHanoi: "clear the tower campaign one level at a time."
        case .slidePuzzle: "slide the tiles back into order."
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
        case .ruleFinder, .dotsConnect, .oneLine, .towerOfHanoi, .slidePuzzle: "problem solving"
        case .numberRush, .estimator: "math"
        case .wordConnect, .memoryLock: "language"
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
        case .estimator: "mental arithmetic"
        case .wordConnect: "vocabulary"
        case .memoryLock: "lexical memory"
        case .dotsConnect: "planning"
        case .oneLine: "logical reasoning"
        case .towerOfHanoi: "sequential planning"
        case .slidePuzzle: "spatial planning"
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
        case .matchBack: "cards move through a short lane. decide if the current card matches the one a few steps back by symbol, colour, or both."
        case .ruleFinder: "work out the rule running across the grid and pick the figure that completes it."
        case .numberRush: "watch a start value and operations appear one at a time. keep the running total in mind, then type the final answer before the timer bar drains."
        case .estimator: "use number tiles and operators to hit the target exactly, or get as close as you can before the clock bites."
        case .oddOneOut: "scan the grid and tap the single shape that doesn't match the rest."
        case .tileShift: "follow the rule on screen — sometimes match by colour, sometimes by shape. it keeps flipping."
        case .lastSeen: "tap each object once — never tap one you've already chosen as new ones appear."
        case .pathKeeper: "watch a token hop across the board, then repeat its path in the same order."
        case .wordConnect: "connect letters in the wheel to uncover every hidden word in the grid. clear two boards to unlock the next level."
        case .memoryLock: "guess the hidden word in 6 tries. after each guess, green means right letter and right spot, yellow means right letter but wrong spot, and gray means that letter is not in the word. clues fade after a moment — faster, with longer words, as your level climbs."
        case .dotsConnect: "draw paths between matching dots, cover every square, and avoid crossing another path."
        case .oneLine: "trace the graph in one continuous route. each segment can be used once, so every choice changes what remains open."
        case .towerOfHanoi: "clear a 36-level tower campaign. each level gives you a source tower and a target tower; move the stack across in as few moves as possible."
        case .slidePuzzle: "the numbered tiles are scrambled around one empty square. slide them through the gap until they read in order — in as few moves as you can."
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
        case .dotsConnect: "planning is building a sequence of moves that satisfies several constraints at the same time."
        case .oneLine: "logical reasoning is recognising structure, spotting constraints, and planning a path that leaves no segment stranded."
        case .towerOfHanoi: "sequential planning is thinking several moves ahead while respecting a changing set of constraints."
        case .slidePuzzle: "spatial planning is seeing moves ahead — how each slide reshapes the board and which tile it frees up next."
        case .numberRush: "arithmetic is performing quick mental calculations accurately under time pressure."
        case .estimator: "mental arithmetic is composing numbers quickly: scanning options, choosing operations, and keeping the result in mind."
        case .wordConnect: "vocabulary is fluent word retrieval: spotting letter patterns, spelling accurately, and finding possibilities quickly."
        case .memoryLock: "lexical memory is keeping spelling clues in mind while searching for the word that fits them."
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
        case .estimator: "equal.circle.fill"
        case .oddOneOut: "magnifyingglass"
        case .tileShift: "arrow.triangle.2.circlepath"
        case .lastSeen: "sparkles"
        case .pathKeeper: "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .wordConnect: "textformat.abc"
        case .memoryLock: "lock.fill"
        case .dotsConnect: "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .oneLine: "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .towerOfHanoi: "square.stack.3d.up.fill"
        case .slidePuzzle: "square.grid.3x3.topleft.filled"
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
        case .estimator: (0x214E63, 0x132F42)
        case .oddOneOut: (0x2E2A5E, 0x1A1840)
        case .tileShift: (0x4A1E50, 0x2D1433)
        case .lastSeen: (0x123A4D, 0x0F2A3A)
        case .pathKeeper: (0x1E3A5E, 0x14243F)
        case .wordConnect: (0x315EC8, 0x24306D)
        case .memoryLock: (0x3A2350, 0x151C38)
        case .dotsConnect: (0x6C0588, 0x135DB7)
        case .oneLine: (0x8D55F6, 0x22B8EA)
        case .towerOfHanoi: (0x224D63, 0x123447)
        case .slidePuzzle: (0x4A3A22, 0x2B2112)
        case .split: (0x123A33, 0x0F2A2A)
        }
    }

    /// Starting mastery/difficulty level for a brand-new player (1…10).
    var seedLevel: Double {
        switch self {
        case .crowdControl, .echoGrid, .lastSeen, .pathKeeper, .matchBack: 1
        case .wordConnect, .memoryLock, .dotsConnect, .oneLine, .towerOfHanoi, .slidePuzzle: 1
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
        case .pathKeeper: "maxSpan"    // TracePathArcade emits maxSpan for both path games
        case .wordConnect: "wordsFound"
        case .memoryLock: "wordsSolved"
        case .dotsConnect: "boardsSolved"
        case .oneLine: "perfectBoards"
        case .towerOfHanoi: "efficiency"
        case .slidePuzzle: "efficiency"
        case .split: "maxLevel"
        case .estimator: "exact"
        default: "bestStreak"
        }
    }

    var statLowerIsBetter: Bool { self == .spotSpeed }

    func statLabel(_ v: Double) -> String {
        switch self {
        case .echoGrid: "\(Int(v)) tiles"
        case .spotSpeed: "\(Int(v)) ms"
        case .matchBack: "\(Int(v))-back"
        case .ruleFinder: "tier \(Int(v))"
        case .crowdControl: "\(Int(v)) perfect"
        case .lastSeen: "\(Int(v)) recalled"
        case .pathKeeper: "\(Int(v)) steps"
        case .wordConnect: "\(Int(v)) words"
        case .memoryLock: "\(Int(v)) solved"
        case .dotsConnect: "\(Int(v)) boards"
        case .oneLine: "\(Int(v)) perfect"
        case .towerOfHanoi: "\(Int(v))% optimal"
        case .slidePuzzle: "\(Int(v))% of par"
        case .split: "level \(Int(v))"
        case .estimator: "\(Int(v)) exact"
        default: "streak \(Int(v))"
        }
    }
}

extension GameID {
    var difficultyScoringVersion: String {
        switch self {
        case .estimator:
            "target_forge_v1"
        default:
            ScoringVersion.current
        }
    }

    func difficultyState(from stored: DifficultyState?) -> DifficultyState {
        guard let stored else { return .seed(for: self) }
        guard shouldResetDifficulty(stored) else { return stored }
        return .seed(for: self)
    }

    func shouldResetDifficulty(_ stored: DifficultyState?) -> Bool {
        guard let stored else { return false }
        switch self {
        case .estimator:
            return stored.scoringVersion != difficultyScoringVersion
        default:
            return false
        }
    }
}

/// Per-game lifetime stats shown on the pre-game card.
struct GameStats: Codable {
    var bestScore: Int = 0
    var totalPlays: Int = 0
    var bestStat: Double? = nil
}

// MARK: - Adaptive difficulty

/// Persisted per-user, per-game state. `level` controls the next run's challenge;
/// `mastery` is the score estimate used by WPI.
struct DifficultyState: Codable, Equatable {
    var level: Double
    var mastery: Double
    var confidence: Double
    var variance: Double
    var reversals: Int = 0
    var lastDirection: Int = 0
    var sessionsPlayed: Int = 0
    var lastPlayed: Date? = nil
    var scoringVersion: String = "v1_legacy"

    init(level: Double,
         mastery: Double? = nil,
         confidence: Double = 0,
         variance: Double = 1,
         reversals: Int = 0,
         lastDirection: Int = 0,
         sessionsPlayed: Int = 0,
         lastPlayed: Date? = nil,
         scoringVersion: String = "v1_legacy") {
        let clamped = Self.clamp(level)
        self.level = clamped
        self.mastery = Self.clamp(mastery ?? clamped)
        self.confidence = min(1, max(0, confidence))
        self.variance = max(0.05, variance)
        self.reversals = reversals
        self.lastDirection = lastDirection
        self.sessionsPlayed = sessionsPlayed
        self.lastPlayed = lastPlayed
        self.scoringVersion = scoringVersion
    }

    static func seed(for g: GameID) -> DifficultyState {
        DifficultyState(level: g.seedLevel, mastery: g.seedLevel, variance: 1.2, scoringVersion: g.difficultyScoringVersion)
    }

    var masteryOrLevel: Double { mastery.isFinite ? mastery : level }

    static func clamp(_ value: Double) -> Double {
        min(10, max(1, value.isFinite ? value : 1))
    }

    private enum CodingKeys: String, CodingKey {
        case level, mastery, confidence, variance, reversals, lastDirection, sessionsPlayed, lastPlayed, scoringVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedLevel = try c.decode(Double.self, forKey: .level)
        let sessions = try c.decodeIfPresent(Int.self, forKey: .sessionsPlayed) ?? 0
        let decodedMastery = try c.decodeIfPresent(Double.self, forKey: .mastery)
        let decodedConfidence = try c.decodeIfPresent(Double.self, forKey: .confidence)
            ?? min(1, Double(sessions) / 8.0)
        self.init(level: decodedLevel,
                  mastery: decodedMastery,
                  confidence: decodedConfidence,
                  variance: try c.decodeIfPresent(Double.self, forKey: .variance) ?? max(0.2, 1.0 - decodedConfidence),
                  reversals: try c.decodeIfPresent(Int.self, forKey: .reversals) ?? 0,
                  lastDirection: try c.decodeIfPresent(Int.self, forKey: .lastDirection) ?? 0,
                  sessionsPlayed: sessions,
                  lastPlayed: try c.decodeIfPresent(Date.self, forKey: .lastPlayed),
                  scoringVersion: try c.decodeIfPresent(String.self, forKey: .scoringVersion) ?? "v1_legacy")
    }
}

/// Simple post-run mastery ladder. Raw points stay game-local; this is the
/// official skill signal used for WPI. Strong runs raise the next starting level,
/// weak runs lower it gently, and middling runs keep the user near their current
/// ability band.
enum MasteryLadder {
    static func delta(for accuracy: Double) -> Double {
        switch accuracy {
        case 0.85...: 0.5
        case 0.70..<0.85: 0.2
        case 0.55..<0.70: -0.1
        default: -0.3
        }
    }

    static func adjust(_ s: DifficultyState, accuracy: Double) -> DifficultyState {
        var next = s
        let change = delta(for: accuracy)
        let dir: Int = change > 0 ? 1 : (change < 0 ? -1 : 0)
        if dir != 0 {
            if s.lastDirection != 0 && dir != s.lastDirection { next.reversals += 1 }
            next.level = max(1, min(10, s.level + change))
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
    var baseScore: Int? = nil
    var accuracy: Double            // 0...1 — the mastery adjustment signal
    var medianRTms: Int? = nil
    var threshold: Double? = nil    // converged difficulty parameter this run
    var trials: Int = 0
    var newDifficulty: DifficultyState? = nil
    var previousDifficulty: DifficultyState? = nil
    var performanceQuality: Double? = nil
    var performanceConfidence: Double? = nil
    var abilitySignal: Double? = nil
    var challengeLevel: Double? = nil
    var calibratedAbility: Double? = nil
    var wpiDelta: Double? = nil
    var varianceAfter: Double? = nil
    var scoringVersion: String? = nil
    var startedAt: Date = Date()
    var durationMs: Int = 0
    var raw: [String: Double] = [:] // game-specific extras → game_sessions.details
    var text: [String: [String]] = [:]

    var domain: CognitiveDomain { game.domain }
    var baseScoreValue: Int { baseScore ?? score }

    init(game: GameID,
         score: Int,
         baseScore: Int? = nil,
         accuracy: Double,
         medianRTms: Int? = nil,
         threshold: Double? = nil,
         trials: Int = 0,
         newDifficulty: DifficultyState? = nil,
         previousDifficulty: DifficultyState? = nil,
         performanceQuality: Double? = nil,
         performanceConfidence: Double? = nil,
         abilitySignal: Double? = nil,
         challengeLevel: Double? = nil,
         calibratedAbility: Double? = nil,
         wpiDelta: Double? = nil,
         varianceAfter: Double? = nil,
         scoringVersion: String? = nil,
         startedAt: Date = Date(),
         durationMs: Int = 0,
         raw: [String: Double] = [:],
         text: [String: [String]] = [:]) {
        self.game = game
        self.score = score
        self.baseScore = baseScore
        self.accuracy = accuracy
        self.medianRTms = medianRTms
        self.threshold = threshold
        self.trials = trials
        self.newDifficulty = newDifficulty
        self.previousDifficulty = previousDifficulty
        self.performanceQuality = performanceQuality
        self.performanceConfidence = performanceConfidence
        self.abilitySignal = abilitySignal
        self.challengeLevel = challengeLevel
        self.calibratedAbility = calibratedAbility
        self.wpiDelta = wpiDelta
        self.varianceAfter = varianceAfter
        self.scoringVersion = scoringVersion
        self.startedAt = startedAt
        self.durationMs = durationMs
        self.raw = raw
        self.text = text
    }

    private enum CodingKeys: String, CodingKey {
        case game, score, baseScore, accuracy, medianRTms, threshold, trials
        case newDifficulty, previousDifficulty, performanceQuality, performanceConfidence
        case abilitySignal, challengeLevel, calibratedAbility, wpiDelta, varianceAfter
        case scoringVersion, startedAt, durationMs, raw, text
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        game = try c.decode(GameID.self, forKey: .game)
        score = try c.decode(Int.self, forKey: .score)
        baseScore = try c.decodeIfPresent(Int.self, forKey: .baseScore)
        accuracy = try c.decode(Double.self, forKey: .accuracy)
        medianRTms = try c.decodeIfPresent(Int.self, forKey: .medianRTms)
        threshold = try c.decodeIfPresent(Double.self, forKey: .threshold)
        trials = try c.decodeIfPresent(Int.self, forKey: .trials) ?? 0
        newDifficulty = try c.decodeIfPresent(DifficultyState.self, forKey: .newDifficulty)
        previousDifficulty = try c.decodeIfPresent(DifficultyState.self, forKey: .previousDifficulty)
        performanceQuality = try c.decodeIfPresent(Double.self, forKey: .performanceQuality)
        performanceConfidence = try c.decodeIfPresent(Double.self, forKey: .performanceConfidence)
        abilitySignal = try c.decodeIfPresent(Double.self, forKey: .abilitySignal)
        challengeLevel = try c.decodeIfPresent(Double.self, forKey: .challengeLevel)
        calibratedAbility = try c.decodeIfPresent(Double.self, forKey: .calibratedAbility)
        wpiDelta = try c.decodeIfPresent(Double.self, forKey: .wpiDelta)
        varianceAfter = try c.decodeIfPresent(Double.self, forKey: .varianceAfter)
        scoringVersion = try c.decodeIfPresent(String.self, forKey: .scoringVersion)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs) ?? 0
        raw = try c.decodeIfPresent([String: Double].self, forKey: .raw) ?? [:]
        text = try c.decodeIfPresent([String: [String]].self, forKey: .text) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(game, forKey: .game)
        try c.encode(score, forKey: .score)
        try c.encodeIfPresent(baseScore, forKey: .baseScore)
        try c.encode(accuracy, forKey: .accuracy)
        try c.encodeIfPresent(medianRTms, forKey: .medianRTms)
        try c.encodeIfPresent(threshold, forKey: .threshold)
        try c.encode(trials, forKey: .trials)
        try c.encodeIfPresent(newDifficulty, forKey: .newDifficulty)
        try c.encodeIfPresent(previousDifficulty, forKey: .previousDifficulty)
        try c.encodeIfPresent(performanceQuality, forKey: .performanceQuality)
        try c.encodeIfPresent(performanceConfidence, forKey: .performanceConfidence)
        try c.encodeIfPresent(abilitySignal, forKey: .abilitySignal)
        try c.encodeIfPresent(challengeLevel, forKey: .challengeLevel)
        try c.encodeIfPresent(calibratedAbility, forKey: .calibratedAbility)
        try c.encodeIfPresent(wpiDelta, forKey: .wpiDelta)
        try c.encodeIfPresent(varianceAfter, forKey: .varianceAfter)
        try c.encodeIfPresent(scoringVersion, forKey: .scoringVersion)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(durationMs, forKey: .durationMs)
        try c.encode(raw, forKey: .raw)
        try c.encode(text, forKey: .text)
    }
}

// MARK: - Config

enum GameMode: String, Codable { case workout, freePlay }

private struct GamePauseSpan {
    let start: Date
    let end: Date
}

@Observable
final class GamePauseController {
    var isPaused = false
    @ObservationIgnored private var pauseStartedAt: Date?
    @ObservationIgnored private var spans: [GamePauseSpan] = []

    func pause(now: Date = Date()) {
        guard !isPaused else { return }
        isPaused = true
        pauseStartedAt = now
    }

    func resume(now: Date = Date()) {
        guard isPaused else { return }
        if let pauseStartedAt {
            spans.append(GamePauseSpan(start: pauseStartedAt, end: now))
        }
        pauseStartedAt = nil
        isPaused = false
    }

    func reset() {
        isPaused = false
        pauseStartedAt = nil
        spans.removeAll()
    }

    func elapsed(since start: Date, until now: Date = Date()) -> TimeInterval {
        max(0, now.timeIntervalSince(start) - pausedDuration(since: start, until: now))
    }

    private func pausedDuration(since start: Date, until now: Date) -> TimeInterval {
        var total: TimeInterval = 0
        for span in spans {
            total += overlap(from: span.start, to: span.end, withStart: start, withEnd: now)
        }
        if let pauseStartedAt {
            total += overlap(from: pauseStartedAt, to: now, withStart: start, withEnd: now)
        }
        return total
    }

    private func overlap(from spanStart: Date, to spanEnd: Date, withStart start: Date, withEnd end: Date) -> TimeInterval {
        let lower = max(spanStart.timeIntervalSinceReferenceDate, start.timeIntervalSinceReferenceDate)
        let upper = min(spanEnd.timeIntervalSinceReferenceDate, end.timeIntervalSinceReferenceDate)
        return max(0, upper - lower)
    }
}

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
    var pauseController: GamePauseController?
    /// Back-compat: existing call sites read `isFreePlay`.
    var isFreePlay: Bool { mode == .freePlay }
    var isSurvival: Bool { false }
    var isPaused: Bool { pauseController?.isPaused == true }

    static func standard(_ g: GameID,
                         difficulty: DifficultyState,
                         freePlay: Bool = false,
                         pauseController: GamePauseController? = nil) -> GameConfig {
        GameConfig(difficulty: difficulty, mode: freePlay ? .freePlay : .workout, pauseController: pauseController)
    }

    func pause() {
        pauseController?.pause()
    }

    func resume() {
        pauseController?.resume()
    }

    func activeElapsed(since start: Date, now: Date = Date()) -> TimeInterval {
        pauseController?.elapsed(since: start, until: now) ?? now.timeIntervalSince(start)
    }

    func sleepActive(milliseconds: Int) async {
        guard let pauseController else {
            try? await Task.sleep(for: .milliseconds(milliseconds))
            return
        }

        var remaining = TimeInterval(milliseconds) / 1_000
        var last = Date()
        while remaining > 0, !Task.isCancelled {
            let step = min(remaining, 0.04)
            try? await Task.sleep(for: .milliseconds(max(8, Int(step * 1_000))))
            let now = Date()
            if !pauseController.isPaused {
                remaining -= now.timeIntervalSince(last)
            }
            last = now
        }
    }
}

// MARK: - Game protocol

protocol Game {
    static var id: GameID { get }
    /// Legacy challenge-level update from a finished run's accuracy.
    static func advance(_ s: DifficultyState, accuracy: Double) -> DifficultyState
    /// The playable view; calls onComplete(GameResult) when the scored run ends.
    @MainActor static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView
}

extension Game {
    static func advance(_ s: DifficultyState, accuracy: Double) -> DifficultyState {
        MasteryLadder.adjust(s, accuracy: accuracy)
    }
}
