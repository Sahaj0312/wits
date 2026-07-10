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
    // Difficulty-track games.
    case arrowStorm, crowdControl, echoGrid
    case colorClash, tileShift, lastSeen
    case slidePuzzle, blockEscape, pegSolitaire
    // Standalone survival mode.
    case split

    var id: String { rawValue }

    /// Difficulty-track games (everything but the standalone survival modes).
    static var live: [GameID] {
        [.arrowStorm, .crowdControl, .echoGrid, .colorClash, .tileShift, .lastSeen,
         .slidePuzzle, .blockEscape, .pegSolitaire]
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
        case .echoGrid, .slidePuzzle, .blockEscape, .pegSolitaire: true
        default: false
        }
    }

    /// Some games place their own primary top-left control inside the playfield.
    var usesEmbeddedQuitControl: Bool { false }
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
    /// Scoring bucket (cosmetic grouping in the library).
    var domain: CognitiveDomain {
        switch self {
        case .arrowStorm: .focus
        case .crowdControl: .multitasking
        case .echoGrid, .lastSeen: .memory
        case .colorClash, .tileShift: .flexibility
        case .slidePuzzle, .blockEscape, .pegSolitaire: .reasoning
        case .split: .multitasking
        }
    }

    var displayName: String {
        switch self {
        case .arrowStorm: "arrow storm"
        case .crowdControl: "crowd control"
        case .echoGrid: "echo grid"
        case .colorClash: "color clash"
        case .tileShift: "tile shift"
        case .lastSeen: "last seen"
        case .slidePuzzle: "slide puzzle"
        case .blockEscape: "block escape"
        case .pegSolitaire: "peg solitaire"
        case .split: "split"
        }
    }

    /// One-line tagline (library cell + card hero subtitle).
    var tagline: String {
        switch self {
        case .arrowStorm: "answer only to the middle arrow."
        case .crowdControl: "track the dots through the crowd."
        case .echoGrid: "play the path back — backwards."
        case .colorClash: "tap the colour, not the word."
        case .tileShift: "the rule keeps changing."
        case .lastSeen: "never tap the same one twice."
        case .slidePuzzle: "slide the tiles back into order."
        case .blockEscape: "free the big block."
        case .pegSolitaire: "jump pegs. leave just one."
        case .split: "fly and pick at once. one slip ends it."
        }
    }

    /// Breadcrumb: top-level discipline shown on the card.
    var domainTitle: String {
        switch self {
        case .arrowStorm, .crowdControl: "attention"
        case .echoGrid, .lastSeen: "memory"
        case .colorClash, .tileShift: "flexibility"
        case .slidePuzzle, .blockEscape, .pegSolitaire: "problem solving"
        case .split: "attention"
        }
    }

    /// Breadcrumb: the specific sub-skill the game leans on.
    var subskill: String {
        switch self {
        case .arrowStorm: "selective attention"
        case .crowdControl: "divided attention"
        case .echoGrid: "spatial recall"
        case .lastSeen: "short-term memory"
        case .colorClash: "response inhibition"
        case .tileShift: "task switching"
        case .slidePuzzle: "spatial planning"
        case .blockEscape: "forward planning"
        case .pegSolitaire: "strategic planning"
        case .split: "dual-tasking"
        }
    }

    /// First card paragraph — what you do.
    var cardHow: String {
        switch self {
        case .arrowStorm: "spot which way the middle arrow points while the crowd around it tries to pull your answer the other way."
        case .crowdControl: "keep your eyes on a few glowing dots as they scatter into an identical crowd, then pick them back out."
        case .echoGrid: "watch a path of tiles light up, then tap them back in reverse order."
        case .colorClash: "tap the colour a word is printed in, not the word it spells."
        case .tileShift: "follow the rule on screen — sometimes match by colour, sometimes by shape. it keeps flipping."
        case .lastSeen: "tap each object once — never tap one you've already chosen as new ones appear."
        case .slidePuzzle: "the numbered tiles are scrambled around one empty square. slide them through the gap until they read in order — in as few moves as you can."
        case .blockEscape: "mixed-size blocks jam a small tray. slide them along rows and columns to clear a path, then walk the big block out the bottom exit — in as few moves as you can."
        case .pegSolitaire: "every jump leaps one peg over a neighbour into an empty hole, and the jumped peg is removed. keep jumping until a single peg remains — on the marked hole at higher levels."
        case .split: "keep the flyer alive at the bottom while you tap the right targets up top and never tap the look-alike. one mistake ends the run — see how many levels you clear."
        }
    }

    /// Second card paragraph — what the skill is.
    var cardAbout: String {
        switch self {
        case .arrowStorm: "selective attention is focusing on what matters while ignoring everything competing for your eyes."
        case .crowdControl: "divided attention is following several moving things at once without losing track of any."
        case .echoGrid: "spatial recall is holding where things were in mind and replaying that layout accurately."
        case .lastSeen: "short-term memory is keeping recent items in mind so you don't repeat yourself."
        case .colorClash: "response inhibition is overriding the automatic answer to give the correct one."
        case .tileShift: "task switching is adapting quickly when the goal keeps changing underneath you."
        case .slidePuzzle: "spatial planning is seeing moves ahead — how each slide reshapes the board and which tile it frees up next."
        case .blockEscape: "forward planning is simulating moves in your head — seeing how each slide opens or closes the big block's path several steps ahead."
        case .pegSolitaire: "strategic planning is ordering moves so nothing gets stranded — every jump has to leave the rest of the board still clearable."
        case .split: "divided attention is doing two demanding things at once — steering one hand while deciding with the other — without dropping either."
        }
    }

    /// SF Symbol for the library cell / workout cards.
    var symbol: String {
        switch self {
        case .arrowStorm: "arrowtriangle.right.fill"
        case .crowdControl: "circle.grid.3x3.fill"
        case .echoGrid: "square.grid.3x3.fill"
        case .colorClash: "paintpalette.fill"
        case .tileShift: "arrow.triangle.2.circlepath"
        case .lastSeen: "sparkles"
        case .slidePuzzle: "square.grid.3x3.topleft.filled"
        case .blockEscape: "square.split.2x2.fill"
        case .pegSolitaire: "circle.grid.cross.fill"
        case .split: "rectangle.split.1x2.fill"
        }
    }

    /// Starting difficulty level for a brand-new player (1…10).
    var seedLevel: Double {
        switch self {
        case .crowdControl, .echoGrid, .lastSeen, .slidePuzzle, .blockEscape, .pegSolitaire: 1
        default: 2
        }
    }

    // MARK: Card "best stat"

    /// Key in GameResult.raw that holds this game's headline stat.
    var statKey: String {
        switch self {
        case .crowdControl: "perfectRounds"
        case .echoGrid: "maxSpan"
        case .lastSeen: "remembered"
        case .slidePuzzle: "efficiency"
        case .blockEscape: "efficiency"
        case .pegSolitaire: "clearPct"
        case .split: "maxLevel"
        default: "bestStreak"
        }
    }

    var statLowerIsBetter: Bool { false }

    func statLabel(_ v: Double) -> String {
        switch self {
        case .echoGrid: "\(Int(v)) tiles"
        case .crowdControl: "\(Int(v)) perfect"
        case .lastSeen: "\(Int(v)) recalled"
        case .slidePuzzle: "\(Int(v))% of par"
        case .blockEscape: "\(Int(v))% of par"
        case .pegSolitaire: "\(Int(v))% cleared"
        case .split: "level \(Int(v))"
        default: "streak \(Int(v))"
        }
    }
}

extension GameID {
    var difficultyScoringVersion: String { ScoringVersion.current }

    func difficultyState(from stored: DifficultyState?) -> DifficultyState {
        stored ?? .seed(for: self)
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

    nonisolated static func clamp(_ value: Double) -> Double {
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
    /// 3…2…1 shown over the still-frozen game before a resume lands (nil when
    /// not counting). The game stays paused — clocks and input included —
    /// until the count finishes.
    var resumeCountdown: Int?
    @ObservationIgnored private var pauseStartedAt: Date?
    @ObservationIgnored private var spans: [GamePauseSpan] = []
    @ObservationIgnored private var resumeTask: Task<Void, Never>?

    func pause(now: Date = Date()) {
        guard !isPaused else { return }
        isPaused = true
        pauseStartedAt = now
    }

    /// Count the player back in, then resume for real.
    func beginResumeCountdown() {
        guard isPaused, resumeTask == nil else { return }
        resumeTask = Task { @MainActor in
            for n in [3, 2, 1] {
                resumeCountdown = n
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
            }
            resumeCountdown = nil
            resumeTask = nil
            resume()
        }
    }

    func resume(now: Date = Date()) {
        guard isPaused else { return }
        resumeTask?.cancel()
        resumeTask = nil
        resumeCountdown = nil
        if let pauseStartedAt {
            spans.append(GamePauseSpan(start: pauseStartedAt, end: now))
        }
        pauseStartedAt = nil
        isPaused = false
    }

    func reset() {
        resumeTask?.cancel()
        resumeTask = nil
        resumeCountdown = nil
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
    /// Safe content-curve step derived from the selected difficulty and track
    /// level. Procedural games that use discrete recipes read this value.
    var mapLevel: Int? = nil
    var difficultyTrack: ChallengeDifficulty? = nil
    var trackLevel: Int? = nil
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

    static func challenge(_ g: GameID,
                          difficulty: ChallengeDifficulty,
                          trackLevel: Int,
                          persisted: DifficultyState,
                          freePlay: Bool = true,
                          pauseController: GamePauseController? = nil) -> GameConfig {
        GameConfig(difficulty: DifficultyScale.gameDifficulty(for: g,
                                                              difficulty: difficulty,
                                                              trackLevel: trackLevel,
                                                              persisted: persisted),
                   mode: freePlay ? .freePlay : .workout,
                   pauseController: pauseController,
                   mapLevel: DifficultyScale.contentLevel(for: g,
                                                          difficulty: difficulty,
                                                          trackLevel: trackLevel),
                   difficultyTrack: difficulty,
                   trackLevel: trackLevel)
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
