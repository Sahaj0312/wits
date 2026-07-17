import XCTest
@testable import wits

@MainActor
final class ScoringTests: XCTestCase {
    func testContinuousUpdateHasNoCliffAtEightyFivePercent() {
        let prior = DifficultyState(level: 5, mastery: 5, confidence: 1)
        let policy = AccuracyPolicy()
        let low = GameResult(game: .lastSeen, score: 0, accuracy: 0.849, trials: 20)
        let high = GameResult(game: .lastSeen, score: 0, accuracy: 0.851, trials: 20)

        let lowNext = policy.nextState(from: low, prior: prior, run: policy.score(low, prior: prior))
        let highNext = policy.nextState(from: high, prior: prior, run: policy.score(high, prior: prior))

        XCTAssertLessThan(abs(highNext.mastery - lowNext.mastery), 0.01)
        XCTAssertGreaterThanOrEqual(highNext.mastery, lowNext.mastery)
    }

    func testLowerConfidenceProducesSmallerMasteryMovement() {
        let prior = DifficultyState(level: 5, mastery: 5, confidence: 0)
        let policy = AccuracyPolicy()
        let thin = GameResult(game: .lastSeen, score: 0, accuracy: 0.95, trials: 2)
        let solid = GameResult(game: .lastSeen, score: 0, accuracy: 0.95, trials: 20)

        let thinNext = policy.nextState(from: thin, prior: prior, run: policy.score(thin, prior: prior))
        let solidNext = policy.nextState(from: solid, prior: prior, run: policy.score(solid, prior: prior))

        XCTAssertGreaterThan(solidNext.mastery - prior.mastery, thinNext.mastery - prior.mastery)
    }

    func testMasteryNeverLeavesBounds() {
        let prior = DifficultyState(level: 10, mastery: 10, confidence: 1)
        let policy = AccuracyPolicy()
        let result = GameResult(game: .lastSeen, score: 0, accuracy: 1, trials: 20)
        let next = policy.nextState(from: result, prior: prior, run: policy.score(result, prior: prior))

        XCTAssertGreaterThanOrEqual(next.mastery, 1)
        XCTAssertLessThanOrEqual(next.mastery, 10)
    }

    func testRCSRewardsHigherCorrectPerSecond() {
        let policy = ThroughputPolicy(game: .colorClash)
        let prior = DifficultyState(level: 3, mastery: 3)
        var fast = GameResult(game: .colorClash, score: 0, accuracy: 1, trials: 10, durationMs: 45_000)
        fast.raw = ["correct": 10, "wrong": 0, "timeOnTaskMs": 45_000]
        var slow = GameResult(game: .colorClash, score: 0, accuracy: 1, trials: 10, durationMs: 45_000)
        slow.raw = ["correct": 5, "wrong": 0, "timeOnTaskMs": 45_000]

        XCTAssertGreaterThan(policy.score(fast, prior: prior).performance,
                             policy.score(slow, prior: prior).performance)
    }

    func testLaunchCalibrationUsesFullScaleAndSharedCeiling() {
        XCTAssertEqual(ScoringCalibrator.calibratedAbility(game: .lastSeen, mastery: 10), 5000)
        XCTAssertEqual(ScoringCalibrator.calibratedAbility(game: .echoGrid, mastery: 10), 5000)
        XCTAssertEqual(ScoringCalibrator.calibratedAbility(game: .lastSeen, mastery: 5), 2500)
    }

    func testLiveGamesDoNotUseAccuracyFallbackPolicy() {
        XCTAssertFalse(ScoringPolicies.policy(for: .crowdControl) is AccuracyPolicy)
        XCTAssertFalse(ScoringPolicies.policy(for: .echoGrid) is AccuracyPolicy)
        XCTAssertFalse(ScoringPolicies.policy(for: .arrowStorm) is AccuracyPolicy)
        XCTAssertFalse(ScoringPolicies.policy(for: .slidePuzzle) is AccuracyPolicy)
        XCTAssertFalse(ScoringPolicies.policy(for: .blockEscape) is AccuracyPolicy)
        XCTAssertFalse(ScoringPolicies.policy(for: .pegSolitaire) is AccuracyPolicy)
        XCTAssertFalse(ScoringPolicies.policy(for: .lastSeen) is AccuracyPolicy)
    }

    func testBlockEscapeCompletionIsAlwaysAPass() {
        let prior = DifficultyState(level: 6, mastery: 6, confidence: 1)
        var result = GameResult(game: .blockEscape, score: 0, accuracy: 1, trials: 250, durationMs: 900_000)
        result.raw = ["completed": 1, "moves": 250, "seconds": 900, "blockLevel": 6]

        let run = BlockEscapePolicy().score(result, prior: prior)

        XCTAssertEqual(run.performance, 1)
        XCTAssertTrue(LevelGrader.passed(quality: run.performance))
    }

    func testRewardedReviveEligibilityAcrossEveryAdaptiveGame() {
        let prior = DifficultyState(level: 5, mastery: 5, confidence: 1)

        var echoPass = GameResult(game: .echoGrid, score: 8, accuracy: 1, trials: 8)
        echoPass.raw = ["correct": 8, "wrong": 0, "nearMisses": 0]
        var echoFail = GameResult(game: .echoGrid, score: 0, accuracy: 0, trials: 8)
        echoFail.raw = ["correct": 0, "wrong": 8, "nearMisses": 0]
        XCTAssertFalse(RewardedReviveEligibility.shouldOffer(for: echoPass,
                                                             previous: prior,
                                                             alreadyUsed: false))
        XCTAssertTrue(RewardedReviveEligibility.shouldOffer(for: echoFail,
                                                            previous: prior,
                                                            alreadyUsed: false))

        var pegClear = GameResult(game: .pegSolitaire, score: 500, accuracy: 1, trials: 12)
        pegClear.raw = ["solved": 1, "onTarget": 1]
        var pegFailure = pegClear
        pegFailure.raw = ["solved": 0, "onTarget": 0]
        XCTAssertFalse(RewardedReviveEligibility.shouldOffer(for: pegClear,
                                                             previous: prior,
                                                             alreadyUsed: false))
        XCTAssertTrue(RewardedReviveEligibility.shouldOffer(for: pegFailure,
                                                            previous: prior,
                                                            alreadyUsed: false))

        var mahjongClear = GameResult(game: .mahjong, score: 500, accuracy: 1, trials: 12)
        mahjongClear.raw = ["solved": 1]
        var mahjongFailure = mahjongClear
        mahjongFailure.raw = ["solved": 0]
        XCTAssertFalse(RewardedReviveEligibility.shouldOffer(for: mahjongClear,
                                                             previous: prior,
                                                             alreadyUsed: false))
        XCTAssertTrue(RewardedReviveEligibility.shouldOffer(for: mahjongFailure,
                                                            previous: prior,
                                                            alreadyUsed: false))

        // These puzzle screens only emit results after a successful clear.
        for game in [GameID.blockEscape, .waterSort, .numberNests] {
            let clear = GameResult(game: game, score: 1, accuracy: 0, trials: 100)
            XCTAssertFalse(RewardedReviveEligibility.shouldOffer(for: clear,
                                                                 previous: prior,
                                                                 alreadyUsed: false),
                           "\(game.rawValue) clears must never show Save Me")
        }

        // Product exclusions stay excluded even for a deliberately poor run.
        for game in [GameID.slidePuzzle, .crossword] {
            let result = GameResult(game: game, score: 0, accuracy: 0, trials: 10)
            XCTAssertFalse(RewardedReviveEligibility.shouldOffer(for: result,
                                                                 previous: prior,
                                                                 alreadyUsed: false))
        }
    }

    func testRewardedReviveCanOnlyBeUsedOnce() {
        let prior = DifficultyState(level: 5, mastery: 5, confidence: 1)
        var failure = GameResult(game: .pegSolitaire, score: 0, accuracy: 0, trials: 5)
        failure.raw = ["solved": 0]

        XCTAssertFalse(RewardedReviveEligibility.shouldOffer(for: failure,
                                                             previous: prior,
                                                             alreadyUsed: true))
    }

    func testEqualMasteryMapsConsistentlyAcrossLaunchPriors() {
        let arrow = ScoringCalibrator.calibratedAbility(game: .arrowStorm, mastery: 7)
        let pegs = ScoringCalibrator.calibratedAbility(game: .pegSolitaire, mastery: 7)

        XCTAssertEqual(arrow, pegs)
    }
}

@MainActor
final class SlidePuzzleTests: XCTestCase {
    func testSlidePuzzleEfficientSolveRaisesLevelAndSloppySolveLowersIt() {
        let prior = DifficultyState(level: 5, mastery: 5, confidence: 1)

        var clean = GameResult(game: .slidePuzzle, score: 0, accuracy: 0.95, trials: 40, durationMs: 45_000)
        clean.raw = ["moves": 40, "parMoves": 44, "parSeconds": 57, "seconds": 45, "slideLevel": 5]
        var sloppy = GameResult(game: .slidePuzzle, score: 0, accuracy: 0.4, trials: 130, durationMs: 180_000)
        sloppy.raw = ["moves": 130, "parMoves": 44, "parSeconds": 57, "seconds": 180, "slideLevel": 5]

        let cleanScored = ScoringEngine.score(clean, previous: prior)
        let sloppyScored = ScoringEngine.score(sloppy, previous: prior)

        XCTAssertGreaterThan(cleanScored.next.level, prior.level)
        XCTAssertLessThan(sloppyScored.next.level, prior.level)
        XCTAssertGreaterThan(cleanScored.run.performance, sloppyScored.run.performance)
    }

    func testSlidePuzzleScrambleProducesValidUnsolvedBoards() {
        for level in stride(from: 1.0, through: 10.0, by: 1.0) {
            let spec = SlidePuzzleScreen.boardSpec(for: level)
            let tiles = SlidePuzzleScreen.scrambledTiles(size: spec.size, depth: spec.depth)

            XCTAssertEqual(tiles.count, spec.size * spec.size)
            XCTAssertEqual(Set(tiles), Set(0..<(spec.size * spec.size)), "Scramble must be a permutation")
            XCTAssertFalse(SlidePuzzleScreen.isSolved(tiles), "Scramble must not hand out a solved board")

            let manhattan = SlidePuzzleScreen.manhattan(tiles, size: spec.size)
            XCTAssertGreaterThan(manhattan, 0)
            XCTAssertLessThanOrEqual(manhattan, spec.depth, "Manhattan distance can't exceed the scramble walk length")
        }
    }

    func testSlidePuzzleDifficultyBandsScaleWithLevel() {
        let low = SlidePuzzleScreen.boardSpec(for: 1)
        let mid = SlidePuzzleScreen.boardSpec(for: 5)
        let high = SlidePuzzleScreen.boardSpec(for: 10)

        XCTAssertEqual(low.size, 3)
        XCTAssertEqual(mid.size, 4)
        XCTAssertEqual(high.size, 5)
        XCTAssertLessThan(low.depth, mid.depth)
        XCTAssertLessThan(mid.depth, high.depth)
    }

    func testSlidePuzzleDepthRampsWithFractionalLevelAndDipsAtNewBoardSizes() {
        // Every adaptive gain (~+0.3/run) must show up as a deeper scramble,
        // not three identical boards followed by a cliff.
        XCTAssertLessThan(SlidePuzzleScreen.boardSpec(for: 1).depth,
                          SlidePuzzleScreen.boardSpec(for: 1.7).depth)
        XCTAssertLessThan(SlidePuzzleScreen.boardSpec(for: 1.7).depth,
                          SlidePuzzleScreen.boardSpec(for: 2.4).depth)

        // A new board size starts shallower than the previous band's end.
        XCTAssertLessThan(SlidePuzzleScreen.boardSpec(for: 4).depth,
                          SlidePuzzleScreen.boardSpec(for: 3.9).depth)
        XCTAssertLessThan(SlidePuzzleScreen.boardSpec(for: 8).depth,
                          SlidePuzzleScreen.boardSpec(for: 7.9).depth)
    }

    func testSlidePuzzleScrambleDifficultyIsConsistentAtAFixedLevel() {
        let spec = SlidePuzzleScreen.boardSpec(for: 1)
        let distances = (0..<12).map { _ in
            SlidePuzzleScreen.manhattan(
                SlidePuzzleScreen.scrambledTiles(size: spec.size, depth: spec.depth),
                size: spec.size
            )
        }

        XCTAssertGreaterThanOrEqual(distances.min() ?? 0, 4, "A level-1 board should never be nearly solved")
        XCTAssertLessThanOrEqual((distances.max() ?? 0) - (distances.min() ?? 0), 6,
                                 "Same-level boards should feel comparably hard")
    }
}
