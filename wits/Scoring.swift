//
//  Scoring.swift
//  wits
//
//  Calibrated WPI scoring. Raw points stay game-local; WPI flows from
//  game-specific performance into confidence-weighted mastery and domain scores.
//

import Foundation

enum ScoringVersion {
    static let current = "v2_policy_calibrated"
}

struct ScoredRun: Codable, Equatable {
    var performance: Double
    var confidence: Double
    var abilitySignal: Double
    var metrics: [String: Double] = [:]
}

struct ScoredSession: Codable, Equatable {
    var result: GameResult
    var baseScore: Int
    var run: ScoredRun
    var previous: DifficultyState
    var next: DifficultyState
    var aG: Double
}

protocol GameScoringPolicy {
    var targetQuality: Double { get }
    var stepSize: Double { get }
    var maxUp: Double { get }
    var maxDown: Double { get }
    var abilitySignalWeight: Double { get }

    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun
    func nextLevel(from result: GameResult, prior: DifficultyState, run: ScoredRun) -> Double
}

extension GameScoringPolicy {
    var targetQuality: Double { 0.80 }
    var stepSize: Double { 0.30 }
    var maxUp: Double { 0.35 }
    var maxDown: Double { 0.25 }
    var abilitySignalWeight: Double { 0 }

    func nextLevel(from result: GameResult, prior: DifficultyState, run: ScoredRun) -> Double {
        let delta = adaptiveDelta(for: run)
        let candidate = DifficultyState.clamp(prior.level + delta)
        let weight = ScoringMath.clamp(abilitySignalWeight * run.confidence * 0.50, 0, 0.45)
        guard weight > 0 else { return candidate }
        return DifficultyState.clamp(candidate * (1 - weight) + DifficultyState.clamp(run.abilitySignal) * weight)
    }

    func nextState(from result: GameResult, prior: DifficultyState, run: ScoredRun) -> DifficultyState {
        let delta = adaptiveDelta(for: run)
        let performanceMastery = DifficultyState.clamp(prior.masteryOrLevel + delta)
        let weight = ScoringMath.clamp(abilitySignalWeight * run.confidence, 0, 0.70)
        let nextMastery = weight > 0
            ? DifficultyState.clamp(performanceMastery * (1 - weight) + DifficultyState.clamp(run.abilitySignal) * weight)
            : performanceMastery

        let oldDir = prior.lastDirection
        let dir = delta > 0.0001 ? 1 : (delta < -0.0001 ? -1 : 0)
        var reversals = prior.reversals
        if dir != 0, oldDir != 0, dir != oldDir { reversals += 1 }

        let nextConfidence = min(1, prior.confidence + run.confidence * (1 - prior.confidence) * 0.35)
        return DifficultyState(
            level: nextLevel(from: result, prior: prior, run: run),
            mastery: nextMastery,
            confidence: nextConfidence,
            variance: max(0.05, 1 - nextConfidence),
            reversals: reversals,
            lastDirection: dir == 0 ? oldDir : dir,
            sessionsPlayed: prior.sessionsPlayed + 1,
            lastPlayed: result.startedAt,
            scoringVersion: result.game.difficultyScoringVersion
        )
    }

    func adaptiveDelta(for run: ScoredRun) -> Double {
        let error = ScoringMath.clamp(run.performance, 0, 1) - targetQuality
        let rawDelta = stepSize * ScoringMath.clamp(run.confidence, 0, 1) * error / 0.20
        return ScoringMath.clamp(rawDelta, -maxDown, maxUp)
    }
}

enum ScoringPolicies {
    static func policy(for game: GameID) -> any GameScoringPolicy {
        switch game {
        case .arrowStorm, .tileShift, .colorClash:
            ThroughputPolicy(game: game)
        case .crowdControl:
            CrowdControlPolicy()
        case .echoGrid:
            SequenceRecallPolicy(game: game)
        case .lastSeen:
            LastSeenPolicy()
        case .slidePuzzle:
            SlidePuzzlePolicy()
        case .blockEscape:
            BlockEscapePolicy()
        case .pegSolitaire:
            PegSolitairePolicy()
        case .waterSort:
            WaterSortPolicy()
        case .mahjong:
            MahjongPolicy()
        default:
            AccuracyPolicy()
        }
    }
}

enum ScoringEngine {
    static func score(_ result: GameResult, previous: DifficultyState) -> ScoredSession {
        var r = result
        let base = r.baseScore ?? r.score
        let policy = ScoringPolicies.policy(for: r.game)
        let run = policy.score(r, prior: previous)
        let next = policy.nextState(from: r, prior: previous, run: run)
        let aG = ScoringCalibrator.calibratedAbility(game: r.game, mastery: next.mastery)
        let priorAG = ScoringCalibrator.calibratedAbility(game: r.game, mastery: previous.masteryOrLevel)

        r.baseScore = base
        r.previousDifficulty = previous
        r.newDifficulty = next
        r.performanceQuality = run.performance
        r.performanceConfidence = run.confidence
        r.abilitySignal = run.abilitySignal
        r.challengeLevel = previous.level
        r.calibratedAbility = aG
        r.wpiDelta = aG - priorAG
        r.varianceAfter = next.variance
        r.scoringVersion = r.game.difficultyScoringVersion
        r.raw.merge(run.metrics) { _, new in new }
        r.raw["baseScore"] = Double(base)
        r.raw["performanceQuality"] = run.performance
        r.raw["performanceConfidence"] = run.confidence
        r.raw["abilitySignal"] = run.abilitySignal
        r.raw["masteryBefore"] = previous.masteryOrLevel
        r.raw["masteryAfter"] = next.mastery
        r.raw["calibratedAbility"] = aG
        r.raw["wpiDelta"] = aG - priorAG

        return ScoredSession(
            result: r,
            baseScore: base,
            run: run,
            previous: previous,
            next: next,
            aG: aG
        )
    }
}

/// Decides whether a completed adaptive-level result represents a failure
/// that can legitimately be retried through Save Me. Puzzle completion must
/// win over a merely low efficiency grade: clearing a board is never a death.
enum RewardedReviveEligibility {
    static func shouldOffer(for result: GameResult,
                            previous: DifficultyState,
                            alreadyUsed: Bool) -> Bool {
        guard !alreadyUsed, result.game.offersRewardedRevive else { return false }

        switch result.game {
        case .echoGrid:
            // Echo Grid always ends after its fixed round set, so its shared
            // pass grade is the authoritative success/failure signal.
            return gradedFailure(result, previous: previous)

        case .pegSolitaire:
            let solved = (result.raw["solved"] ?? 0) >= 1
            guard solved else { return true }
            let onTarget = (result.raw["onTarget"] ?? 1) >= 1
            // One peg on the required target is an unequivocal clear. An
            // off-target single peg follows the normal grade for that level.
            return onTarget ? false : gradedFailure(result, previous: previous)

        case .mahjong:
            // The rack filling is the only failure exit. A cleared layout is
            // complete even if excessive undos lower its cleanliness grade.
            return (result.raw["solved"] ?? 1) < 1

        case .slidePuzzle, .crossword:
            // Explicit product exclusions: these games never offer Save Me.
            return false

        case .blockEscape, .waterSort, .numberNests:
            // These screens emit a result only after the puzzle is solved.
            return false

        case .arrowStorm, .crowdControl, .colorClash, .tileShift, .lastSeen,
             .split, .blockFit, .fuse, .snake, .tower:
            // Standalone games own their death/continue flow inside the game
            // screen and never pass results through this adaptive gate.
            return false
        }
    }

    private static func gradedFailure(_ result: GameResult,
                                      previous: DifficultyState) -> Bool {
        let quality = ScoringEngine.score(result, previous: previous).run.performance
        return !LevelGrader.passed(quality: quality)
    }
}

enum ScoringCalibrator {
    static let maxWPI = 5000.0

    static func calibratedAbility(game: GameID, mastery: Double) -> Double {
        let norm = normForGame(game)
        let z = (DifficultyState.clamp(mastery) - norm.mean) / max(0.5, norm.sd)
        return ScoringMath.round(ScoringMath.clamp(2500 + 500 * z, 0, maxWPI))
    }

    private static func normForGame(_ game: GameID) -> (mean: Double, sd: Double) {
        // Launch prior until real population norms exist. Keep the full 0...5000
        // scale usable and avoid seed-level-specific ceilings.
        (mean: 5.0, sd: 1.0)
    }
}

struct AccuracyPolicy: GameScoringPolicy {
    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun {
        let trials = max(1, result.trials)
        let confidence = ScoringMath.clamp(Double(trials) / 12.0, 0.30, 1.0)
        return ScoredRun(
            performance: ScoringMath.clamp(result.accuracy, 0, 1),
            confidence: confidence,
            abilitySignal: prior.level,
            metrics: ["policyConfidence": confidence]
        )
    }
}


struct CrowdControlPolicy: GameScoringPolicy {
    var abilitySignalWeight: Double { 0.15 }

    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun {
        let correct = result.raw["correct"] ?? max(0, result.accuracy * Double(max(1, result.trials)))
        let wrong = result.raw["wrong"] ?? max(0, Double(max(1, result.trials)) - correct)
        let total = max(1, correct + wrong)
        let accuracy = ScoringMath.clamp(correct / total, 0, 1)
        let quality = ScoringMath.clamp(0.85 * accuracy + 0.15 * min(1, correct / max(3, prior.level + 2)), 0, 1)
        return ScoredRun(
            performance: quality,
            confidence: ScoringMath.clamp(total / 10.0, 0.35, 1.0),
            abilitySignal: ScoringMath.clamp(prior.level + (accuracy - 0.70) * 2.0, 1, 10),
            metrics: ["trackingAccuracy": accuracy]
        )
    }
}

struct SequenceRecallPolicy: GameScoringPolicy {
    let game: GameID
    var abilitySignalWeight: Double { 0.35 }

    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun {
        let correct = result.raw["correct"] ?? result.raw["perfect"] ?? max(0, result.accuracy * Double(max(1, result.trials)))
        let wrong = result.raw["wrong"] ?? max(0, Double(max(1, result.trials)) - correct)
        let near = result.raw["nearMisses"] ?? 0
        let total = max(1, correct + wrong + near)
        let quality = ScoringMath.clamp((correct + 0.45 * near) / total, 0, 1)
        let signal = result.raw["maxSpan"] ?? result.raw["maxLen"] ?? prior.level
        return ScoredRun(
            performance: quality,
            confidence: ScoringMath.clamp(total / 8.0, 0.35, 1.0),
            abilitySignal: ScoringMath.clamp(signal, 1, 10),
            metrics: ["sequenceQuality": quality, "sequenceSignal": signal]
        )
    }
}

struct ThroughputPolicy: GameScoringPolicy {
    let game: GameID
    var targetQuality: Double { 0.80 }

    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun {
        let trials = max(1, result.trials)
        let correct = max(0, result.raw["correct"] ?? (result.accuracy * Double(trials)))
        let seconds = max(10, (result.raw["timeOnTaskMs"] ?? Double(result.durationMs)) / 1000.0)
        let rcs = correct / seconds
        let ref = rcsReference(level: prior.level)
        let logRatio = log(max(0.01, rcs) / max(0.01, ref))
        let performance = ScoringMath.logistic(ScoringMath.logit(targetQuality) + logRatio)
        let confidence = ScoringMath.clamp(min(Double(trials) / 18.0, seconds / 45.0), 0.35, 1.0)
        return ScoredRun(
            performance: performance,
            confidence: confidence,
            abilitySignal: prior.level,
            metrics: ["rcs": rcs, "rcsRef": ref, "timeOnTaskMs": seconds * 1000]
        )
    }

    private func rcsReference(level: Double) -> Double {
        0.18 + level * 0.04
    }
}




struct LastSeenPolicy: GameScoringPolicy {
    var abilitySignalWeight: Double { 0.30 }

    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun {
        let total = max(1, Double(result.trials))
        let correct = result.raw["correct"] ?? max(0, result.accuracy * total)
        let wrong = result.raw["wrong"] ?? max(0, total - correct)
        let remembered = result.raw["remembered"] ?? correct
        let accuracy = ScoringMath.clamp(correct / max(1, correct + wrong), 0, 1)
        let memoryLoad = ScoringMath.clamp(remembered / max(3, prior.level + 2), 0, 1.2)
        let quality = ScoringMath.clamp(0.75 * accuracy + 0.25 * min(1, memoryLoad), 0, 1)
        return ScoredRun(
            performance: quality,
            confidence: ScoringMath.clamp(total / 14.0, 0.35, 1),
            abilitySignal: ScoringMath.clamp(remembered, 1, 10),
            metrics: ["remembered": remembered, "memoryLoad": memoryLoad]
        )
    }
}





struct SlidePuzzlePolicy: GameScoringPolicy {
    var abilitySignalWeight: Double { 0.20 }

    /// A run only completes on a solve, so quality is pure efficiency: moves
    /// against the Manhattan-derived par (dominant) plus time against par.
    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun {
        let moves = max(1, result.raw["moves"] ?? Double(result.trials))
        let par = max(1, result.raw["parMoves"] ?? moves)
        let seconds = max(1, result.raw["seconds"] ?? Double(result.durationMs) / 1000.0)
        let parSeconds = max(10, result.raw["parSeconds"] ?? (par * 1.15 + 6))
        let moveEfficiency = min(1, par / moves)
        let timeEfficiency = min(1, parSeconds / seconds)
        let quality = ScoringMath.clamp(0.70 * moveEfficiency + 0.30 * timeEfficiency, 0, 1)
        return ScoredRun(
            performance: quality,
            confidence: 1.0,
            // The challenge actually served this run (board size + scramble).
            abilitySignal: result.raw["slideLevel"] ?? prior.level,
            metrics: ["moveEfficiency": moveEfficiency, "timeEfficiency": timeEfficiency]
        )
    }
}

struct BlockEscapePolicy: GameScoringPolicy {
    var abilitySignalWeight: Double { 0.20 }

    /// Block Escape emits a result only after the hero reaches the exit.
    /// Completion is the exam; move count and time are informational stats.
    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun {
        return ScoredRun(
            performance: 1.0,
            confidence: 1.0,
            abilitySignal: result.raw["blockLevel"] ?? prior.level,
            metrics: ["completed": 1]
        )
    }
}

struct WaterSortPolicy: GameScoringPolicy {
    var abilitySignalWeight: Double { 0.20 }

    /// A run only completes on a solve (WaterSort's par is an exact A*
    /// minimum), so quality is pure efficiency: pours against par (dominant)
    /// plus time against par.
    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun {
        let moves = max(1, result.raw["moves"] ?? Double(result.trials))
        let par = max(1, result.raw["parMoves"] ?? moves)
        let seconds = max(1, result.raw["seconds"] ?? Double(result.durationMs) / 1000.0)
        let parSeconds = max(10, result.raw["parSeconds"] ?? (par * 5 + 30))
        let moveEfficiency = min(1, par / moves)
        let timeEfficiency = min(1, parSeconds / seconds)
        let quality = ScoringMath.clamp(0.70 * moveEfficiency + 0.30 * timeEfficiency, 0, 1)
        return ScoredRun(
            performance: quality,
            confidence: 1.0,
            // The challenge actually served this run (colour count + exact par).
            abilitySignal: result.raw["waterLevel"] ?? prior.level,
            metrics: ["moveEfficiency": moveEfficiency, "timeEfficiency": timeEfficiency]
        )
    }
}

struct MahjongPolicy: GameScoringPolicy {
    var abilitySignalWeight: Double { 0.20 }

    /// A cleared board grades on play cleanliness: undos are the real
    /// mistakes (a pick that trapped the rack), blocked-tile taps cost a
    /// little, and time keeps a small weight against a generous scanning
    /// budget. A run that died out of space grades purely on how far it got,
    /// capped below the pass line.
    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun {
        let pairs = max(1, result.raw["pairs"] ?? Double(result.trials))
        let solved = (result.raw["solved"] ?? 1) >= 1
        if !solved {
            let clear = ScoringMath.clamp((result.raw["clearedPairs"] ?? 0) / pairs, 0, 1)
            return ScoredRun(
                performance: ScoringMath.clamp(0.55 * clear, 0, 0.55),
                confidence: 0.9,
                abilitySignal: result.raw["mahjongLevel"] ?? prior.level,
                metrics: ["clearFraction": clear]
            )
        }
        let undos = max(0, result.raw["undos"] ?? 0)
        let blockedTaps = max(0, result.raw["blockedTaps"] ?? 0)
        let seconds = max(1, result.raw["seconds"] ?? Double(result.durationMs) / 1000.0)
        let parSeconds = max(10, result.raw["parSeconds"] ?? (pairs * 6 + 25))
        let cleanliness = min(1, pairs / (pairs + undos + blockedTaps * 0.25))
        let timeEfficiency = min(1, parSeconds / seconds)
        let quality = ScoringMath.clamp(0.30 + 0.60 * cleanliness + 0.10 * timeEfficiency, 0, 1)
        return ScoredRun(
            performance: quality,
            confidence: 1.0,
            abilitySignal: result.raw["mahjongLevel"] ?? prior.level,
            metrics: ["cleanliness": cleanliness, "timeEfficiency": timeEfficiency]
        )
    }
}

struct PegSolitairePolicy: GameScoringPolicy {
    var abilitySignalWeight: Double { 0.20 }

    /// Any solution is exactly startPegs−1 jumps, so there is no move par.
    /// Solving IS the exam: a stranded board never reaches the 1★ pass line
    /// (its clear ratio maps into 0...0.55 as partial mastery signal), an
    /// off-target solve caps below 2★, and a true solve always passes, time
    /// against a generous budget and undo count decide 1–3★.
    static func quality(clear: Double, timeEfficiency: Double,
                        solved: Bool, onTarget: Bool, undos: Double) -> Double {
        let undoPenalty = min(0.25, undos * 0.03)
        if !solved {
            return ScoringMath.clamp(0.55 * clear, 0, 0.55)
        }
        if !onTarget {
            return ScoringMath.clamp(0.58 + 0.12 * timeEfficiency - undoPenalty, 0, 0.72)
        }
        return max(0.60, ScoringMath.clamp(0.62 + 0.38 * timeEfficiency - undoPenalty, 0, 1))
    }

    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun {
        let start = max(2, result.raw["startPegs"] ?? Double(result.trials) + 1)
        let end = max(1, result.raw["endPegs"] ?? 1)
        let clear = ScoringMath.clamp((start - end) / (start - 1), 0, 1)
        let seconds = max(1, result.raw["seconds"] ?? Double(result.durationMs) / 1000.0)
        let parSeconds = max(20, result.raw["parSeconds"] ?? (start * 7 + 20))
        let timeEfficiency = min(1, parSeconds / seconds)
        let quality = Self.quality(clear: clear,
                                   timeEfficiency: timeEfficiency,
                                   solved: (result.raw["solved"] ?? 0) >= 1,
                                   onTarget: (result.raw["onTarget"] ?? 1) >= 1,
                                   undos: result.raw["undos"] ?? 0)
        return ScoredRun(
            performance: quality,
            confidence: 1.0,
            // The planning depth actually served this run.
            abilitySignal: result.raw["pegLevel"] ?? prior.level,
            metrics: ["clearRatio": clear, "timeEfficiency": timeEfficiency]
        )
    }
}



enum ScoringMath {
    static func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, value.isFinite ? value : lo))
    }

    static func round(_ value: Double, places: Int = 0) -> Double {
        let scale = pow(10.0, Double(places))
        return (value * scale).rounded() / scale
    }

    static func logistic(_ x: Double) -> Double {
        1 / (1 + exp(-clamp(x, -40, 40)))
    }

    static func logit(_ p: Double) -> Double {
        let q = clamp(p, 0.001, 0.999)
        return log(q / (1 - q))
    }

    static func clampedRate(_ numerator: Double, _ denominator: Double) -> Double {
        let n = max(1, denominator)
        let raw = numerator / n
        let edge = 1 / (2 * n)
        return clamp(raw, edge, 1 - edge)
    }

    // Peter J. Acklam's inverse-normal approximation.
    static func inverseNormalCDF(_ p: Double) -> Double {
        let p = clamp(p, 0.000001, 0.999999)
        let a = [
            -3.969683028665376e+01, 2.209460984245205e+02,
            -2.759285104469687e+02, 1.383577518672690e+02,
            -3.066479806614716e+01, 2.506628277459239e+00
        ]
        let b = [
            -5.447609879822406e+01, 1.615858368580409e+02,
            -1.556989798598866e+02, 6.680131188771972e+01,
            -1.328068155288572e+01
        ]
        let c = [
            -7.784894002430293e-03, -3.223964580411365e-01,
            -2.400758277161838e+00, -2.549732539343734e+00,
            4.374664141464968e+00, 2.938163982698783e+00
        ]
        let d = [
            7.784695709041462e-03, 3.224671290700398e-01,
            2.445134137142996e+00, 3.754408661907416e+00
        ]
        let plow = 0.02425
        let phigh = 1 - plow
        if p < plow {
            let q = sqrt(-2 * log(p))
            return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
                / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        if p > phigh {
            let q = sqrt(-2 * log(1 - p))
            return -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
                / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        let q = p - 0.5
        let r = q * q
        return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q
            / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
    }
}

#if DEBUG
enum ScoringDiagnostics {
    private static var hasRun = false

    static func runDebugAssertions() {
        guard !hasRun else { return }
        hasRun = true

        testContinuousUpdate()
        testConfidenceWeighting()
        testClamping()
        testRCSMonotonicity()
        testLaunchCalibrationUsesFullScale()
    }

    private static func testContinuousUpdate() {
        let prior = DifficultyState(level: 5, mastery: 5, confidence: 1)
        let policy = AccuracyPolicy()
        let low = GameResult(game: .lastSeen, score: 0, accuracy: 0.849, trials: 20)
        let high = GameResult(game: .lastSeen, score: 0, accuracy: 0.851, trials: 20)
        let lowNext = policy.nextState(from: low, prior: prior, run: policy.score(low, prior: prior))
        let highNext = policy.nextState(from: high, prior: prior, run: policy.score(high, prior: prior))
        assert(abs(highNext.mastery - lowNext.mastery) < 0.01, "Scoring cliff near 85% returned")
        assert(highNext.mastery >= lowNext.mastery, "Higher quality must not lower mastery")
    }

    private static func testConfidenceWeighting() {
        let prior = DifficultyState(level: 5, mastery: 5, confidence: 0)
        let policy = AccuracyPolicy()
        let thin = GameResult(game: .lastSeen, score: 0, accuracy: 0.95, trials: 2)
        let solid = GameResult(game: .lastSeen, score: 0, accuracy: 0.95, trials: 20)
        let thinNext = policy.nextState(from: thin, prior: prior, run: policy.score(thin, prior: prior))
        let solidNext = policy.nextState(from: solid, prior: prior, run: policy.score(solid, prior: prior))
        assert((solidNext.mastery - prior.mastery) > (thinNext.mastery - prior.mastery), "Confidence should scale mastery movement")
    }

    private static func testClamping() {
        let prior = DifficultyState(level: 10, mastery: 10, confidence: 1)
        let policy = AccuracyPolicy()
        let result = GameResult(game: .lastSeen, score: 0, accuracy: 1, trials: 20)
        let next = policy.nextState(from: result, prior: prior, run: policy.score(result, prior: prior))
        assert((1...10).contains(next.mastery), "Mastery escaped the 1...10 bounds")
    }

    private static func testRCSMonotonicity() {
        let policy = ThroughputPolicy(game: .colorClash)
        let prior = DifficultyState(level: 3, mastery: 3)
        var fast = GameResult(game: .colorClash, score: 0, accuracy: 1, trials: 10, durationMs: 45_000)
        fast.raw = ["correct": 10, "timeOnTaskMs": 45_000]
        var slow = GameResult(game: .colorClash, score: 0, accuracy: 1, trials: 10, durationMs: 45_000)
        slow.raw = ["correct": 5, "timeOnTaskMs": 45_000]
        assert(policy.score(fast, prior: prior).performance > policy.score(slow, prior: prior).performance, "RCS should reward higher correct/sec")
    }

    private static func testLaunchCalibrationUsesFullScale() {
        let a = ScoringCalibrator.calibratedAbility(game: .arrowStorm, mastery: 7)
        let b = ScoringCalibrator.calibratedAbility(game: .pegSolitaire, mastery: 7)
        assert(a == b, "Launch calibration should not create seed-specific ceilings")
        assert(ScoringCalibrator.calibratedAbility(game: .lastSeen, mastery: 10) == 5000, "Mastery 10 should reach the top of the WPI scale")
    }
}
#endif
