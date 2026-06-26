import XCTest
@testable import wits

@MainActor
final class ScoringTests: XCTestCase {
    func testContinuousUpdateHasNoCliffAtEightyFivePercent() {
        let prior = DifficultyState(level: 5, mastery: 5, confidence: 1)
        let policy = AccuracyPolicy()
        let low = GameResult(game: .memoryLock, score: 0, accuracy: 0.849, trials: 20)
        let high = GameResult(game: .memoryLock, score: 0, accuracy: 0.851, trials: 20)

        let lowNext = policy.nextState(from: low, prior: prior, run: policy.score(low, prior: prior))
        let highNext = policy.nextState(from: high, prior: prior, run: policy.score(high, prior: prior))

        XCTAssertLessThan(abs(highNext.mastery - lowNext.mastery), 0.01)
        XCTAssertGreaterThanOrEqual(highNext.mastery, lowNext.mastery)
    }

    func testLowerConfidenceProducesSmallerMasteryMovement() {
        let prior = DifficultyState(level: 5, mastery: 5, confidence: 0)
        let policy = AccuracyPolicy()
        let thin = GameResult(game: .memoryLock, score: 0, accuracy: 0.95, trials: 2)
        let solid = GameResult(game: .memoryLock, score: 0, accuracy: 0.95, trials: 20)

        let thinNext = policy.nextState(from: thin, prior: prior, run: policy.score(thin, prior: prior))
        let solidNext = policy.nextState(from: solid, prior: prior, run: policy.score(solid, prior: prior))

        XCTAssertGreaterThan(solidNext.mastery - prior.mastery, thinNext.mastery - prior.mastery)
    }

    func testMasteryNeverLeavesBounds() {
        let prior = DifficultyState(level: 10, mastery: 10, confidence: 1)
        let policy = AccuracyPolicy()
        let result = GameResult(game: .memoryLock, score: 0, accuracy: 1, trials: 20)
        let next = policy.nextState(from: result, prior: prior, run: policy.score(result, prior: prior))

        XCTAssertGreaterThanOrEqual(next.mastery, 1)
        XCTAssertLessThanOrEqual(next.mastery, 10)
    }

    func testNeverRespondingDoesNotScoreAsMatchBackSkill() {
        var result = GameResult(game: .matchBack, score: 0, accuracy: 0.5, trials: 20)
        result.raw = ["hits": 0, "misses": 10, "falseAlarms": 0, "correctRejections": 10]

        let run = MatchBackPolicy().score(result, prior: .seed(for: .matchBack))

        XCTAssertLessThanOrEqual(run.performance, 0.01)
    }

    func testRCSRewardsHigherCorrectPerSecond() {
        let policy = ThroughputPolicy(game: .numberRush)
        let prior = DifficultyState(level: 3, mastery: 3)
        var fast = GameResult(game: .numberRush, score: 0, accuracy: 1, trials: 10, durationMs: 45_000)
        fast.raw = ["correct": 10, "timeOnTaskMs": 45_000]
        var slow = GameResult(game: .numberRush, score: 0, accuracy: 1, trials: 10, durationMs: 45_000)
        slow.raw = ["correct": 5, "timeOnTaskMs": 45_000]

        XCTAssertGreaterThan(policy.score(fast, prior: prior).performance,
                             policy.score(slow, prior: prior).performance)
    }

    func testSameDomainSessionsAggregateInsteadOfOverwrite() {
        var a = GameResult(game: .arrowStorm, score: 0, accuracy: 1)
        a.calibratedAbility = 3000
        a.performanceConfidence = 1
        var b = GameResult(game: .spotSpeed, score: 0, accuracy: 1)
        b.calibratedAbility = 1000
        b.performanceConfidence = 1

        let merged = ScoringAggregator.mergeDailyScores(
            existingScores: [:],
            existingConfidence: [:],
            existingCounts: [:],
            results: [a, b]
        )

        XCTAssertEqual(merged.scores[CognitiveDomain.focus.rawValue], 2000)
        XCTAssertEqual(merged.counts[CognitiveDomain.focus.rawValue], 2)
    }

    func testBonusMultiplierDoesNotChangeBaseScore() {
        var result = GameResult(game: .numberRush,
                                score: 300,
                                baseScore: 100,
                                bonusMultiplier: 3,
                                accuracy: 1,
                                trials: 10,
                                durationMs: 45_000)
        result.raw = ["correct": 10, "timeOnTaskMs": 45_000]

        let scored = ScoringEngine.score(result, previous: .seed(for: .numberRush))

        XCTAssertEqual(scored.baseScore, 100)
        XCTAssertEqual(scored.displayScore, 300)
    }

    func testWordConnectPersistsUnlockedLevel() {
        var result = GameResult(game: .wordConnect, score: 0, accuracy: 0.9, trials: 10)
        result.raw = ["boardsSolved": 2, "requiredWordsFound": 9, "levelStart": 1, "levelEnd": 2]

        let scored = ScoringEngine.score(result, previous: .seed(for: .wordConnect))

        XCTAssertEqual(scored.next.level, 2)
    }

    func testCrossGameCalibrationUsesGameSpecificNorms() {
        let arrow = ScoringCalibrator.calibratedAbility(game: .arrowStorm, mastery: 7)
        let word = ScoringCalibrator.calibratedAbility(game: .wordConnect, mastery: 7)

        XCTAssertNotEqual(arrow, word)
    }
}
