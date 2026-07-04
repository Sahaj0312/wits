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
        case .spotSpeed:
            SpotSpeedPolicy()
        case .matchBack:
            MatchBackPolicy()
        case .numberRush:
            NumberRushPolicy()
        case .arrowStorm, .tileShift, .oddOneOut, .colorClash:
            ThroughputPolicy(game: game)
        case .estimator:
            TargetForgePolicy()
        case .crowdControl:
            CrowdControlPolicy()
        case .echoGrid, .pathKeeper:
            SequenceRecallPolicy(game: game)
        case .lastSeen:
            LastSeenPolicy()
        case .towerOfHanoi:
            TowerPolicy()
        case .slidePuzzle:
            SlidePuzzlePolicy()
        case .blockEscape:
            BlockEscapePolicy()
        case .pegSolitaire:
            PegSolitairePolicy()
        case .dotsConnect:
            DotsPolicy()
        case .oneLine:
            OneLinePolicy()
        case .wordConnect:
            WordConnectPolicy()
        case .ruleFinder:
            RuleFinderPolicy()
        case .memoryLock:
            MemoryLockPolicy()
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

enum ScoringAggregator {
    static let neutralWPI = 2500.0
    static let shrinkage = 0.10

    /// The production daily rollup: fold every played game's persistent state
    /// into confidence-weighted per-domain scores.
    static func aggregateGameStates(_ states: [GameID: DifficultyState]) -> (scores: [String: Double], confidence: [String: Double], counts: [String: Int]) {
        var sums: [String: Double] = [:]
        var weights: [String: Double] = [:]
        var counts: [String: Int] = [:]

        for (game, state) in states where state.sessionsPlayed > 0 || state.confidence > 0 {
            let key = game.domain.rawValue
            let weight = ScoringMath.clamp(state.confidence, 0.10, 1.0)
            let score = ScoringCalibrator.calibratedAbility(game: game, mastery: state.mastery)
            sums[key, default: 0] += score * weight
            weights[key, default: 0] += weight
            counts[key, default: 0] += 1
        }

        var scores: [String: Double] = [:]
        for (key, sum) in sums {
            scores[key] = ScoringMath.round(sum / max(0.001, weights[key] ?? 0))
        }
        return (scores, weights, counts)
    }

    static func displayDomainScore(_ score: Double, confidence: Double) -> Double {
        let c = max(0, confidence)
        return ScoringMath.round((c * score + shrinkage * neutralWPI) / max(0.001, c + shrinkage))
    }

    static func displayDomainScores(domainScores: [String: Double], confidence: [String: Double]) -> [String: Double] {
        var displayed: [String: Double] = [:]
        for (key, score) in domainScores {
            displayed[key] = displayDomainScore(score, confidence: confidence[key] ?? 1)
        }
        return displayed
    }

    static func headline(domainScores: [String: Double], confidence: [String: Double]) -> Double? {
        guard !domainScores.isEmpty else { return nil }
        let values = CognitiveDomain.allCases.compactMap { domain -> Double? in
            let key = domain.rawValue
            guard let score = domainScores[key] else { return nil }
            return displayDomainScore(score, confidence: confidence[key] ?? 1)
        }
        guard !values.isEmpty else { return nil }
        return ScoringMath.round(values.reduce(0, +) / Double(values.count))
    }

    static func headlineConfidence(_ confidence: [String: Double]) -> Double {
        guard !CognitiveDomain.allCases.isEmpty else { return 0 }
        let capped = CognitiveDomain.allCases.reduce(0.0) { partial, domain in
            partial + min(1, max(0, confidence[domain.rawValue] ?? 0))
        }
        return ScoringMath.round(capped / Double(CognitiveDomain.allCases.count), places: 3)
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

struct TargetForgePolicy: GameScoringPolicy {
    var targetQuality: Double { 0.72 }
    var abilitySignalWeight: Double { 0.10 }

    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun {
        let exact = max(0, result.raw["exact"] ?? 0)
        let close = max(0, result.raw["close"] ?? 0)
        let near = max(0, result.raw["near"] ?? 0)
        let wrong = max(0, result.raw["wrong"] ?? 0)
        let rawTotal = exact + close + near + wrong
        let total = rawTotal > 0 ? rawTotal : Double(max(1, result.trials))
        let quality = result.raw["forgeQuality"]
            ?? (rawTotal > 0
                ? ScoringMath.clamp((exact + close * 0.65 + near * 0.30) / total, 0, 1)
                : ScoringMath.clamp(result.accuracy, 0, 1))
        let seconds = max(10, (result.raw["timeOnTaskMs"] ?? Double(result.durationMs)) / 1000.0)
        let confidence = ScoringMath.clamp(min(total / 12.0, seconds / 45.0), 0.35, 1.0)
        let exactRate = rawTotal > 0 ? exact / total : ScoringMath.clamp(result.accuracy, 0, 1)
        let ability = ScoringMath.clamp(prior.masteryOrLevel + (quality - targetQuality) * 2.0 + exactRate * 0.35, 1, 10)
        return ScoredRun(
            performance: ScoringMath.clamp(quality, 0, 1),
            confidence: confidence,
            abilitySignal: ability,
            metrics: [
                "targetForgeQuality": quality,
                "exactRate": exactRate,
                "avgError": result.raw["avgError"] ?? 0
            ]
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
        switch game {
        case .numberRush:
            return NumberRushTuning.targetCorrectPerSecond(for: level)
        case .estimator:
            return 0.14 + level * 0.025
        default:
            return 0.18 + level * 0.04
        }
    }
}

struct NumberRushPolicy: GameScoringPolicy {
    var targetQuality: Double { 0.80 }

    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun {
        let trials = max(1, result.trials)
        let correct = max(0, result.raw["correct"] ?? (result.accuracy * Double(trials)))
        let wrong = max(0, result.raw["wrong"] ?? (Double(trials) - correct))
        let total = max(1, correct + wrong)
        let seconds = max(10, (result.raw["timeOnTaskMs"] ?? Double(result.durationMs)) / 1000.0)
        let rcs = correct / seconds
        let ref = NumberRushTuning.targetCorrectPerSecond(for: prior.level)
        let logRatio = log(max(0.01, rcs) / max(0.01, ref))
        let throughput = ScoringMath.logistic(ScoringMath.logit(targetQuality) + logRatio)
        let accuracy = ScoringMath.clamp(correct / total, 0, 1)
        let accuracyPenalty = 0.65 + 0.35 * accuracy
        let performance = ScoringMath.clamp(throughput * accuracyPenalty, 0, 1)
        let confidence = ScoringMath.clamp(min(total / 18.0, seconds / 45.0), 0.35, 1.0)
        return ScoredRun(
            performance: performance,
            confidence: confidence,
            abilitySignal: prior.level,
            metrics: [
                "rcs": rcs,
                "rcsRef": ref,
                "numberRushThroughput": throughput,
                "numberRushAccuracy": accuracy,
                "timeOnTaskMs": seconds * 1000
            ]
        )
    }
}

struct SpotSpeedPolicy: GameScoringPolicy {
    var abilitySignalWeight: Double { 0.45 }

    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun {
        let startMs = SpotSpeedTuning.initialPresentationMs(for: prior.level)
        let finalMs = result.threshold ?? result.raw["thresholdMs"] ?? startMs
        let accuracy = ScoringMath.clamp(result.accuracy, 0, 1)
        let confidence = ScoringMath.clamp(Double(max(1, result.trials)) / Double(SpotSpeedTuning.totalTrials), 0.45, 1.0)
        let ability = ScoringMath.clamp(1 + log2(700.0 / max(SpotSpeedTuning.minPresentationMs, finalMs)) * 2.2, 1, 10)
        let thresholdScore = ScoringMath.logistic(ScoringMath.logit(targetQuality) + (ability - prior.masteryOrLevel) * 0.75)
        let performance = ScoringMath.clamp(0.55 * accuracy + 0.45 * thresholdScore, 0, 1)
        return ScoredRun(
            performance: performance,
            confidence: confidence,
            abilitySignal: ability,
            metrics: ["thresholdMs": finalMs, "thresholdScore": thresholdScore]
        )
    }
}

struct MatchBackPolicy: GameScoringPolicy {
    var targetQuality: Double { 0.68 }
    var abilitySignalWeight: Double { 0.10 }

    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun {
        let hits = result.raw["hits"] ?? max(0, result.accuracy * Double(result.trials))
        let misses = result.raw["misses"] ?? 0
        let falseAlarms = result.raw["falseAlarms"] ?? 0
        let total = Double(max(1, result.trials))
        let correctRejections = max(0, total - hits - misses - falseAlarms)
        let hitRate = ScoringMath.clampedRate(hits, hits + misses)
        let falseAlarmRate = ScoringMath.clampedRate(falseAlarms, falseAlarms + correctRejections)
        let dPrime = ScoringMath.inverseNormalCDF(hitRate) - ScoringMath.inverseNormalCDF(falseAlarmRate)
        let responses = hits + falseAlarms
        let performance = responses <= 0 ? 0 : ScoringMath.logistic(dPrime / 1.35)
        let evidence = hits + misses + falseAlarms
        let confidence = ScoringMath.clamp(evidence / 8.0, 0.35, 1.0)
        return ScoredRun(
            performance: performance,
            confidence: confidence,
            abilitySignal: result.threshold ?? prior.level,
            metrics: [
                "dPrime": dPrime,
                "hits": hits,
                "misses": misses,
                "falseAlarms": falseAlarms,
                "correctRejections": correctRejections
            ]
        )
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

struct RuleFinderPolicy: GameScoringPolicy {
    var abilitySignalWeight: Double { 0.25 }

    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun {
        let accuracy = ScoringMath.clamp(result.accuracy, 0, 1)
        let avgTier = result.raw["avgTier"] ?? result.threshold ?? 1
        let median = Double(result.medianRTms ?? Int(result.raw["medianRTms"] ?? 0))
        let par = parMedianMs(tier: avgTier)
        let speed: Double
        if median > 0 {
            speed = ScoringMath.clamp(par / median, 0.5, 1.25)
        } else {
            speed = 1.0
        }
        let normSpeed = ScoringMath.clamp((speed - 0.5) / 0.75, 0, 1)
        let performance = ScoringMath.clamp(0.80 * accuracy + 0.20 * normSpeed, 0, 1)
        let confidence = ScoringMath.clamp(Double(max(1, result.trials)) / 10.0, 0.45, 1.0)
        return ScoredRun(
            performance: performance,
            confidence: confidence,
            abilitySignal: ScoringMath.clamp(avgTier * 2, 1, 10),
            metrics: ["speedScore": normSpeed, "avgTier": avgTier]
        )
    }

    private func parMedianMs(tier: Double) -> Double {
        let t = Int(ScoringMath.clamp(tier.rounded(), 1, 5))
        return [0, 6000, 8000, 10500, 13500, 16500][t]
    }
}

struct DotsPolicy: GameScoringPolicy {
    var abilitySignalWeight: Double { 0.20 }

    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun {
        let boards = result.raw["boardsSolved"] ?? 0
        let perRun = max(1, Double(result.trials))
        let completion = ScoringMath.clamp(boards / perRun, 0, 1)
        let mistakes = result.raw["mistakes"] ?? 0
        let hints = result.raw["hintsUsed"] ?? 0
        let quality = ScoringMath.clamp(completion - min(0.25, mistakes * 0.03) - min(0.25, hints * 0.10), 0, 1)
        let confidence = boards > 0 ? 0.75 + 0.25 * completion : 0.35
        return ScoredRun(
            performance: quality,
            confidence: confidence,
            abilitySignal: result.raw["puzzleDifficulty"] ?? prior.level,
            metrics: ["completion": completion]
        )
    }
}

struct OneLinePolicy: GameScoringPolicy {
    var targetQuality: Double { 0.82 }
    var stepSize: Double { 0.34 }
    var maxUp: Double { 0.40 }
    var maxDown: Double { 0.28 }
    var abilitySignalWeight: Double { 0.25 }

    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun {
        let boards = result.raw["boardsSolved"] ?? 0
        let perRun = max(1, Double(result.trials))
        let completion = ScoringMath.clamp(boards / perRun, 0, 1)
        let totalEdges = max(1, result.raw["totalEdges"] ?? result.raw["correctEdges"] ?? perRun)
        let mistakes = result.raw["mistakes"] ?? 0
        let hints = result.raw["hintsUsed"] ?? 0
        let resets = result.raw["resets"] ?? 0
        let undos = result.raw["undos"] ?? 0
        let moveQuality = result.raw["oneLineMoveQuality"]
            ?? ScoringMath.clamp(totalEdges / max(totalEdges, totalEdges + mistakes + hints * 2 + resets * 2), 0, 1)
        let assistPenalty = min(0.36, mistakes * 0.035 + hints * 0.085 + resets * 0.065 + undos * 0.012)
        let quality = ScoringMath.clamp(0.68 * completion + 0.32 * moveQuality - assistPenalty, 0, 1)
        let difficulty = result.raw["avgPuzzleDifficulty"] ?? result.raw["puzzleDifficulty"] ?? result.raw["levelStart"] ?? prior.level
        let ability = ScoringMath.clamp(difficulty + (moveQuality - targetQuality) * 1.2 - min(0.7, assistPenalty), 1, 10)
        let confidence = completion >= 1 ? 0.95 : ScoringMath.clamp(0.45 + 0.45 * completion, 0.40, 0.90)
        return ScoredRun(
            performance: quality,
            confidence: confidence,
            abilitySignal: ability,
            metrics: [
                "completion": completion,
                "oneLineQuality": quality,
                "oneLineMoveQuality": moveQuality
            ]
        )
    }
}

struct TowerPolicy: GameScoringPolicy {
    var abilitySignalWeight: Double { 0.20 }

    /// Workout Tower is a fixed 36-level campaign the game persists itself;
    /// map campaign progress (1...36) onto the shared 1...10 level scale.
    static func level(forCampaignLevel campaign: Double) -> Double {
        DifficultyState.clamp(1 + (campaign - 1) * 9.0 / 35.0)
    }

    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun {
        let moves = max(1, result.raw["moves"] ?? Double(result.trials))
        let optimal = max(1, result.raw["optimalMoves"] ?? moves)
        let seconds = max(1, result.raw["seconds"] ?? Double(result.durationMs) / 1000.0)
        // The game reports its own time budget (random-state puzzles get a
        // looser per-move allowance); fall back to the legacy 2.65s/move.
        let targetSeconds = result.raw["targetSeconds"] ?? optimal * 2.65
        let invalid = result.raw["invalidMoves"] ?? 0
        let moveEfficiency = min(1, optimal / moves)
        let timeEfficiency = min(1, targetSeconds / seconds)
        let quality = ScoringMath.clamp(0.75 * moveEfficiency + 0.25 * timeEfficiency - min(0.35, invalid * 0.10), 0, 1)
        let campaign = result.raw["hanoiLevel"]
        return ScoredRun(
            performance: quality,
            confidence: 1.0,
            abilitySignal: campaign.map(Self.level(forCampaignLevel:)) ?? prior.level,
            metrics: ["moveEfficiency": moveEfficiency, "timeEfficiency": timeEfficiency]
        )
    }

    func nextLevel(from result: GameResult, prior: DifficultyState, run: ScoredRun) -> Double {
        // Keep the adaptive level in lockstep with the campaign so the card's
        // "level" reflects the challenge actually served next run.
        guard let end = result.raw["hanoiLevelEnd"] ?? result.raw["hanoiLevel"] else {
            return DifficultyState.clamp(prior.level + adaptiveDelta(for: run))
        }
        return Self.level(forCampaignLevel: end)
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

    /// A run only completes on a solve (BlockEscape's par is an exact BFS
    /// minimum), so quality is pure efficiency: moves against par (dominant)
    /// plus time against par.
    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun {
        let moves = max(1, result.raw["moves"] ?? Double(result.trials))
        let par = max(1, result.raw["parMoves"] ?? moves)
        let seconds = max(1, result.raw["seconds"] ?? Double(result.durationMs) / 1000.0)
        let parSeconds = max(10, result.raw["parSeconds"] ?? (par * 2.4 + 10))
        let moveEfficiency = min(1, par / moves)
        let timeEfficiency = min(1, parSeconds / seconds)
        let quality = ScoringMath.clamp(0.70 * moveEfficiency + 0.30 * timeEfficiency, 0, 1)
        return ScoredRun(
            performance: quality,
            confidence: 1.0,
            // The challenge actually served this run (tray + exact par).
            abilitySignal: result.raw["blockLevel"] ?? prior.level,
            metrics: ["moveEfficiency": moveEfficiency, "timeEfficiency": timeEfficiency]
        )
    }
}

struct PegSolitairePolicy: GameScoringPolicy {
    var abilitySignalWeight: Double { 0.20 }

    /// Any solution is exactly startPegs−1 jumps, so there is no move par.
    /// Solving IS the exam: a stranded board never reaches the 1★ pass line
    /// (its clear ratio maps into 0...0.55 as partial mastery signal), an
    /// off-target solve caps below 2★, and a true solve always passes — time
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

struct WordConnectPolicy: GameScoringPolicy {
    var abilitySignalWeight: Double { 0.35 }

    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun {
        let solved = result.raw["boardsSolved"] ?? 0
        let perRun = 2.0
        let completion = ScoringMath.clamp(solved / perRun, 0, 1)
        let attempts = max(1, Double(result.trials))
        let correct = (result.raw["requiredWordsFound"] ?? 0) + (result.raw["bonusWordsFound"] ?? 0)
        let accuracy = ScoringMath.clamp(correct / attempts, 0, 1)
        let hints = result.raw["hintsUsed"] ?? 0
        let quality = ScoringMath.clamp(0.65 * completion + 0.35 * accuracy - min(0.25, hints * 0.08), 0, 1)
        let confidence = solved >= perRun ? 1.0 : 0.55
        return ScoredRun(
            performance: quality,
            confidence: confidence,
            abilitySignal: result.raw["levelEnd"] ?? result.raw["levelStart"] ?? prior.level,
            metrics: ["completion": completion, "wordAccuracy": accuracy]
        )
    }

    func nextLevel(from result: GameResult, prior: DifficultyState, run: ScoredRun) -> Double {
        if let levelEnd = result.raw["levelEnd"] {
            return DifficultyState.clamp(levelEnd)
        }
        return DifficultyState.clamp((result.raw["levelStart"] ?? prior.level).rounded(.down))
    }
}

struct MemoryLockPolicy: GameScoringPolicy {
    var abilitySignalWeight: Double { 0.25 }

    func score(_ result: GameResult, prior: DifficultyState) -> ScoredRun {
        let solved = result.raw["wordsSolved"] ?? max(0, result.accuracy * Double(max(1, result.trials)))
        let total = max(1, Double(result.trials))
        let completion = ScoringMath.clamp(solved / total, 0, 1)
        let guesses = result.raw["guesses"] ?? total
        let efficiency = ScoringMath.clamp(1 - max(0, guesses - solved) / max(1, guesses), 0, 1)
        let quality = ScoringMath.clamp(0.75 * completion + 0.25 * efficiency, 0, 1)
        return ScoredRun(
            performance: quality,
            confidence: ScoringMath.clamp(total / 4.0, 0.45, 1),
            // The challenge level the run was actually served at. Legacy rows
            // (before the game was adaptive) have no key → neutral prior.level.
            abilitySignal: result.raw["memoryLockLevel"] ?? prior.level,
            metrics: ["completion": completion, "solveEfficiency": efficiency]
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
        testDPrimeAntiGaming()
        testRCSMonotonicity()
        testDailyAggregation()
        testWordConnectLevelPersistence()
        testLaunchCalibrationUsesFullScale()
        testMatchBackLevelAntiGaming()
    }

    private static func testContinuousUpdate() {
        let prior = DifficultyState(level: 5, mastery: 5, confidence: 1)
        let policy = AccuracyPolicy()
        let low = GameResult(game: .memoryLock, score: 0, accuracy: 0.849, trials: 20)
        let high = GameResult(game: .memoryLock, score: 0, accuracy: 0.851, trials: 20)
        let lowNext = policy.nextState(from: low, prior: prior, run: policy.score(low, prior: prior))
        let highNext = policy.nextState(from: high, prior: prior, run: policy.score(high, prior: prior))
        assert(abs(highNext.mastery - lowNext.mastery) < 0.01, "Scoring cliff near 85% returned")
        assert(highNext.mastery >= lowNext.mastery, "Higher quality must not lower mastery")
    }

    private static func testConfidenceWeighting() {
        let prior = DifficultyState(level: 5, mastery: 5, confidence: 0)
        let policy = AccuracyPolicy()
        let thin = GameResult(game: .memoryLock, score: 0, accuracy: 0.95, trials: 2)
        let solid = GameResult(game: .memoryLock, score: 0, accuracy: 0.95, trials: 20)
        let thinNext = policy.nextState(from: thin, prior: prior, run: policy.score(thin, prior: prior))
        let solidNext = policy.nextState(from: solid, prior: prior, run: policy.score(solid, prior: prior))
        assert((solidNext.mastery - prior.mastery) > (thinNext.mastery - prior.mastery), "Confidence should scale mastery movement")
    }

    private static func testClamping() {
        let prior = DifficultyState(level: 10, mastery: 10, confidence: 1)
        let policy = AccuracyPolicy()
        let result = GameResult(game: .memoryLock, score: 0, accuracy: 1, trials: 20)
        let next = policy.nextState(from: result, prior: prior, run: policy.score(result, prior: prior))
        assert((1...10).contains(next.mastery), "Mastery escaped the 1...10 bounds")
    }

    private static func testDPrimeAntiGaming() {
        var result = GameResult(game: .matchBack, score: 0, accuracy: 0.5, trials: 20)
        result.raw = ["hits": 0, "misses": 10, "falseAlarms": 0, "correctRejections": 10]
        let run = MatchBackPolicy().score(result, prior: .seed(for: .matchBack))
        assert(run.performance <= 0.01, "Never-responding should not score as real skill")
    }

    private static func testRCSMonotonicity() {
        let policy = ThroughputPolicy(game: .numberRush)
        let prior = DifficultyState(level: 3, mastery: 3)
        var fast = GameResult(game: .numberRush, score: 0, accuracy: 1, trials: 10, durationMs: 45_000)
        fast.raw = ["correct": 10, "timeOnTaskMs": 45_000]
        var slow = GameResult(game: .numberRush, score: 0, accuracy: 1, trials: 10, durationMs: 45_000)
        slow.raw = ["correct": 5, "timeOnTaskMs": 45_000]
        assert(policy.score(fast, prior: prior).performance > policy.score(slow, prior: prior).performance, "RCS should reward higher correct/sec")
    }

    private static func testDailyAggregation() {
        let states: [GameID: DifficultyState] = [
            .arrowStorm: DifficultyState(level: 6, mastery: 6, confidence: 1, sessionsPlayed: 1),
            .spotSpeed: DifficultyState(level: 2, mastery: 2, confidence: 1, sessionsPlayed: 1)
        ]
        let rollup = ScoringAggregator.aggregateGameStates(states)
        assert(rollup.scores[CognitiveDomain.focus.rawValue] == 2000, "Same-domain games should aggregate, not overwrite")
        assert(rollup.counts[CognitiveDomain.focus.rawValue] == 2, "Domain count should include both games")
    }

    private static func testWordConnectLevelPersistence() {
        var result = GameResult(game: .wordConnect, score: 0, accuracy: 0.9, trials: 10)
        result.raw = ["boardsSolved": 2, "requiredWordsFound": 9, "levelStart": 1, "levelEnd": 2]
        let scored = ScoringEngine.score(result, previous: .seed(for: .wordConnect))
        assert(scored.next.level == 2, "WordConnect must persist the unlocked level")
    }

    private static func testLaunchCalibrationUsesFullScale() {
        let a = ScoringCalibrator.calibratedAbility(game: .arrowStorm, mastery: 7)
        let b = ScoringCalibrator.calibratedAbility(game: .wordConnect, mastery: 7)
        assert(a == b, "Launch calibration should not create seed-specific ceilings")
        assert(ScoringCalibrator.calibratedAbility(game: .matchBack, mastery: 10) == 5000, "Mastery 10 should reach the top of the WPI scale")
    }

    private static func testMatchBackLevelAntiGaming() {
        let prior = DifficultyState(level: 5, mastery: 5, confidence: 1)
        var result = GameResult(game: .matchBack, score: 0, accuracy: 0.5, trials: 20)
        result.raw = ["hits": 0, "misses": 10, "falseAlarms": 0, "correctRejections": 10]
        let scored = ScoringEngine.score(result, previous: prior)
        assert(scored.next.level < prior.level, "Never-responding should not raise MatchBack challenge level")
    }
}
#endif
