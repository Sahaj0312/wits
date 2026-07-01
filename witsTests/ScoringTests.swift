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
        let policy = NumberRushPolicy()
        let prior = DifficultyState(level: 3, mastery: 3)
        var fast = GameResult(game: .numberRush, score: 0, accuracy: 1, trials: 10, durationMs: 45_000)
        fast.raw = ["correct": 10, "wrong": 0, "timeOnTaskMs": 45_000]
        var slow = GameResult(game: .numberRush, score: 0, accuracy: 1, trials: 10, durationMs: 45_000)
        slow.raw = ["correct": 5, "wrong": 0, "timeOnTaskMs": 45_000]

        XCTAssertGreaterThan(policy.score(fast, prior: prior).performance,
                             policy.score(slow, prior: prior).performance)
    }

    func testNumberRushWrongAnswersReducePerformanceAndMasteryMovement() {
        let policy = NumberRushPolicy()
        let prior = DifficultyState(level: 4, mastery: 4, confidence: 1)
        var clean = GameResult(game: .numberRush, score: 0, accuracy: 1, trials: 8, durationMs: 45_000)
        clean.raw = ["correct": 8, "wrong": 0, "timeOnTaskMs": 45_000]
        var messy = GameResult(game: .numberRush, score: 0, accuracy: 8.0 / 18.0, trials: 18, durationMs: 45_000)
        messy.raw = ["correct": 8, "wrong": 10, "timeOnTaskMs": 45_000]

        let cleanRun = policy.score(clean, prior: prior)
        let messyRun = policy.score(messy, prior: prior)
        let cleanNext = policy.nextState(from: clean, prior: prior, run: cleanRun)
        let messyNext = policy.nextState(from: messy, prior: prior, run: messyRun)

        XCTAssertGreaterThan(cleanRun.performance, messyRun.performance)
        XCTAssertGreaterThan(cleanNext.mastery, messyNext.mastery)
    }

    func testNumberRushTuningAddsOperationsWithoutInflatingThroughputTarget() {
        XCTAssertEqual(NumberRushTuning.operationCount(for: 1), 1)
        XCTAssertEqual(NumberRushTuning.operationCount(for: 4), 3)
        XCTAssertEqual(NumberRushTuning.operationCount(for: 10), 6)
        XCTAssertLessThan(NumberRushTuning.targetCorrectPerSecond(for: 10),
                          NumberRushTuning.targetCorrectPerSecond(for: 2))
    }

    func testSpotSpeedEighteenTrialsReachFullPolicyConfidence() {
        let prior = DifficultyState(level: 3, mastery: 3)
        let result = GameResult(game: .spotSpeed,
                                score: 0,
                                accuracy: 0.80,
                                threshold: 300,
                                trials: SpotSpeedTuning.totalTrials)

        let run = SpotSpeedPolicy().score(result, prior: prior)

        XCTAssertEqual(run.confidence, 1)
        XCTAssertEqual(run.metrics["thresholdMs"], 300)
    }

    func testSpotSpeedLevelCurveSeparatesEarlyLevels() {
        let level2Ms = SpotSpeedTuning.initialPresentationMs(for: 2)
        let level4Ms = SpotSpeedTuning.initialPresentationMs(for: 4)

        XCTAssertGreaterThanOrEqual(level2Ms - level4Ms, 80)
        XCTAssertGreaterThan(SpotSpeedTuning.slotCount(for: 4), SpotSpeedTuning.slotCount(for: 2))
        XCTAssertGreaterThan(SpotSpeedTuning.stimulationLevel(for: 4), SpotSpeedTuning.stimulationLevel(for: 2))
    }

    func testSameDomainSessionsAggregateInsteadOfOverwrite() {
        // arrowStorm and spotSpeed are both focus games; the production rollup
        // (aggregateGameStates) must average them, not keep only one.
        let states: [GameID: DifficultyState] = [
            .arrowStorm: DifficultyState(level: 6, mastery: 6, confidence: 1, sessionsPlayed: 1),
            .spotSpeed: DifficultyState(level: 2, mastery: 2, confidence: 1, sessionsPlayed: 1)
        ]

        let rollup = ScoringAggregator.aggregateGameStates(states)

        XCTAssertEqual(rollup.scores[CognitiveDomain.focus.rawValue], 2000)
        XCTAssertEqual(rollup.counts[CognitiveDomain.focus.rawValue], 2)
    }

    func testWordConnectPersistsUnlockedLevel() {
        var result = GameResult(game: .wordConnect, score: 0, accuracy: 0.9, trials: 10)
        result.raw = ["boardsSolved": 2, "requiredWordsFound": 9, "levelStart": 1, "levelEnd": 2]

        let scored = ScoringEngine.score(result, previous: .seed(for: .wordConnect))

        XCTAssertEqual(scored.next.level, 2)
    }

    func testOneLineCleanSolvedRunOutscoresAssistedRun() {
        let prior = DifficultyState(level: 4, mastery: 4, confidence: 1)
        var clean = GameResult(game: .oneLine, score: 2400, accuracy: 1, trials: 2)
        clean.raw = [
            "boardsSolved": 2,
            "totalEdges": 24,
            "correctEdges": 24,
            "mistakes": 0,
            "hintsUsed": 0,
            "resets": 0,
            "undos": 0,
            "puzzleDifficulty": 4,
            "oneLineMoveQuality": 1
        ]
        var assisted = GameResult(game: .oneLine, score: 1600, accuracy: 0.72, trials: 2)
        assisted.raw = [
            "boardsSolved": 2,
            "totalEdges": 24,
            "correctEdges": 24,
            "mistakes": 3,
            "hintsUsed": 2,
            "resets": 1,
            "undos": 4,
            "puzzleDifficulty": 4,
            "oneLineMoveQuality": 0.75
        ]

        let cleanScored = ScoringEngine.score(clean, previous: prior)
        let assistedScored = ScoringEngine.score(assisted, previous: prior)

        XCTAssertGreaterThan(cleanScored.run.performance, assistedScored.run.performance)
        XCTAssertGreaterThan(cleanScored.next.mastery, assistedScored.next.mastery)
    }

    func testOneLinePuzzleBankHasManyVariantsAndComplexitiesPerLevel() {
        let counts = OneLineScreen.debugPuzzleCountsByLevel
        let edgeCounts = OneLineScreen.debugEdgeCountsByLevel
        let edgeRanges = OneLineScreen.debugEdgeRangesByLevel

        for level in 1...10 {
            XCTAssertGreaterThanOrEqual(counts[level] ?? 0, 36)
            XCTAssertGreaterThanOrEqual(edgeCounts[level]?.count ?? 0, 2)
            XCTAssertGreaterThanOrEqual(edgeCounts[level]?.min() ?? 0, edgeRanges[level]?.lowerBound ?? .max)
            XCTAssertLessThanOrEqual(edgeCounts[level]?.max() ?? .max, edgeRanges[level]?.upperBound ?? 0)
        }
        XCTAssertTrue(OneLineScreen.debugUnreadablePuzzleIDs.isEmpty,
                      "Unreadable One Line puzzles: \(OneLineScreen.debugUnreadablePuzzleIDs.prefix(8))")
    }

    func testLaunchCalibrationUsesFullScaleAndSharedCeiling() {
        XCTAssertEqual(ScoringCalibrator.calibratedAbility(game: .matchBack, mastery: 10), 5000)
        XCTAssertEqual(ScoringCalibrator.calibratedAbility(game: .numberRush, mastery: 10), 5000)
        XCTAssertEqual(ScoringCalibrator.calibratedAbility(game: .matchBack, mastery: 5), 2500)
    }

    func testHeadlineDoesNotDiluteMeasuredDomainsWithUntrainedDomains() {
        let scores = [
            CognitiveDomain.focus.rawValue: 3500.0,
            CognitiveDomain.memory.rawValue: 3500.0,
            CognitiveDomain.math.rawValue: 3500.0,
            CognitiveDomain.language.rawValue: 3500.0
        ]
        let confidence = Dictionary(uniqueKeysWithValues: scores.keys.map { ($0, 1.0) })

        let headline = ScoringAggregator.headline(domainScores: scores, confidence: confidence)

        XCTAssertGreaterThanOrEqual(headline ?? 0, 3400)
    }

    func testPersistentGameStateAggregationUsesAccumulatedConfidence() {
        let states: [GameID: DifficultyState] = [
            .arrowStorm: DifficultyState(level: 7, mastery: 7, confidence: 1, sessionsPlayed: 8),
            .spotSpeed: DifficultyState(level: 7, mastery: 7, confidence: 1, sessionsPlayed: 8)
        ]

        let rollup = ScoringAggregator.aggregateGameStates(states)

        XCTAssertEqual(rollup.counts[CognitiveDomain.focus.rawValue], 2)
        XCTAssertEqual(rollup.confidence[CognitiveDomain.focus.rawValue], 2)
        XCTAssertGreaterThan(rollup.scores[CognitiveDomain.focus.rawValue] ?? 0, 3000)
    }

    func testMatchBackNeverResponderDoesNotRaiseChallengeLevel() {
        let prior = DifficultyState(level: 5, mastery: 5, confidence: 1)
        var result = GameResult(game: .matchBack, score: 0, accuracy: 0.5, trials: 20)
        result.raw = ["hits": 0, "misses": 10, "falseAlarms": 0, "correctRejections": 10]

        let scored = ScoringEngine.score(result, previous: prior)

        XCTAssertLessThan(scored.next.level, prior.level)
    }

    func testTargetForgePerfectSlowRunDoesNotLoseMastery() {
        let prior = DifficultyState(level: 5, mastery: 5, confidence: 1)
        var result = GameResult(game: .estimator, score: 0, accuracy: 1, trials: 16, durationMs: 120_000)
        result.raw = ["exact": 16, "close": 0, "near": 0, "wrong": 0, "forgeQuality": 1, "timeOnTaskMs": 120_000]

        let scored = ScoringEngine.score(result, previous: prior)

        XCTAssertGreaterThanOrEqual(scored.next.mastery, prior.mastery)
    }

    func testTargetForgePolicyFallsBackToAccuracyForLegacyEstimatorRuns() {
        let prior = DifficultyState(level: 5, mastery: 5, confidence: 1)
        let result = GameResult(game: .estimator, score: 0, accuracy: 1, trials: 16, durationMs: 45_000)

        let scored = ScoringEngine.score(result, previous: prior)

        XCTAssertEqual(scored.run.performance, 1)
    }

    func testTargetForgeIgnoresStaleEstimatorDifficulty() {
        let stale = DifficultyState(level: 1.85, mastery: 1.85, confidence: 1, scoringVersion: ScoringVersion.current)

        let normalized = GameID.estimator.difficultyState(from: stale)

        XCTAssertEqual(normalized.level, GameID.estimator.seedLevel)
        XCTAssertEqual(normalized.scoringVersion, GameID.estimator.difficultyScoringVersion)
    }

    func testTargetForgeScoredRunPersistsMechanicsVersion() {
        let prior = DifficultyState.seed(for: .estimator)
        var result = GameResult(game: .estimator, score: 150, accuracy: 1, trials: 1, durationMs: 45_000)
        result.raw = ["exact": 1, "close": 0, "near": 0, "wrong": 0, "forgeQuality": 1, "timeOnTaskMs": 45_000]

        let scored = ScoringEngine.score(result, previous: prior)

        XCTAssertEqual(scored.next.scoringVersion, GameID.estimator.difficultyScoringVersion)
        XCTAssertEqual(scored.result.scoringVersion, GameID.estimator.difficultyScoringVersion)
    }

    func testMissingLiveGamesDoNotUseAccuracyFallbackPolicy() {
        XCTAssertFalse(ScoringPolicies.policy(for: .crowdControl) is AccuracyPolicy)
        XCTAssertFalse(ScoringPolicies.policy(for: .echoGrid) is AccuracyPolicy)
        XCTAssertFalse(ScoringPolicies.policy(for: .pathKeeper) is AccuracyPolicy)
        XCTAssertFalse(ScoringPolicies.policy(for: .oneLine) is AccuracyPolicy)
        XCTAssertTrue(ScoringPolicies.policy(for: .numberRush) is NumberRushPolicy)
        XCTAssertFalse(ScoringPolicies.policy(for: .estimator) is ThroughputPolicy)
        XCTAssertTrue(ScoringPolicies.policy(for: .estimator) is TargetForgePolicy)
    }

    func testEqualMasteryMapsConsistentlyAcrossLaunchPriors() {
        let arrow = ScoringCalibrator.calibratedAbility(game: .arrowStorm, mastery: 7)
        let word = ScoringCalibrator.calibratedAbility(game: .wordConnect, mastery: 7)

        XCTAssertEqual(arrow, word)
    }

    func testTowerCampaignProgressDrivesAdaptiveLevel() {
        let prior = DifficultyState.seed(for: .towerOfHanoi)
        var result = GameResult(game: .towerOfHanoi, score: 500, accuracy: 1, trials: 7, durationMs: 20_000)
        result.raw = ["moves": 7, "optimalMoves": 7, "seconds": 18, "invalidMoves": 0,
                      "hanoiLevel": 36, "hanoiLevelEnd": 36]

        let scored = ScoringEngine.score(result, previous: prior)

        XCTAssertEqual(scored.next.level, 10)
        XCTAssertEqual(TowerPolicy.level(forCampaignLevel: 1), 1)
    }

    func testMemoryLockAbilityFollowsChallengeLevel() {
        let prior = DifficultyState(level: 7, mastery: 7, confidence: 1)
        var result = GameResult(game: .memoryLock, score: 900, accuracy: 1, trials: 3, durationMs: 60_000)
        result.raw = ["wordsSolved": 3, "guesses": 9, "wordLength": 6, "memoryLockLevel": 7]

        let run = MemoryLockPolicy().score(result, prior: prior)

        XCTAssertEqual(run.abilitySignal, 7)
    }

    @MainActor
    func testMemoryLockChallengeScalesWithLevel() {
        XCTAssertEqual(MemoryLockScreen.wordLength(for: 1), 5)
        XCTAssertEqual(MemoryLockScreen.wordLength(for: 8), 6)
        XCTAssertGreaterThan(MemoryLockScreen.clueSeconds(for: 1),
                             MemoryLockScreen.clueSeconds(for: 10))
    }

    func testDomainPrioritiesStalenessTracksActualPlayNotSnapshots() {
        // Every rollup snapshots all trained domains into domain_scores, so
        // staleness must come from per-day domain_session_counts instead.
        func row(_ day: String, played: [String: Int]) -> DailyProgressRow {
            DailyProgressRow(day: day, workout_done: true, games_played: 1,
                             headline_index: 2500,
                             domain_scores: ["focus": 3000, "memory": 3000],
                             domain_confidence: ["focus": 1, "memory": 1],
                             domain_session_counts: played,
                             headline_confidence: 1, coverage_count: 2,
                             migration_offset: nil,
                             scoring_version: ScoringVersion.current,
                             workout_games: nil)
        }
        let days = [row("2026-06-20", played: ["focus": 1]),
                    row("2026-06-29", played: ["focus": 1])]
        let cal = Calendar.current
        let today = cal.date(from: DateComponents(year: 2026, month: 6, day: 30))!

        let priorities = ProgressMath.domainPriorities(days, asOf: today, calendar: cal)

        // Identical weakness (same scores) — memory was never actually played,
        // so it must carry full staleness vs. focus's one idle day.
        let focus = priorities[.focus] ?? 0
        let memory = priorities[.memory] ?? 0
        XCTAssertEqual(memory - focus, ProgressMath.stalenessCap - ProgressMath.stalenessPerDay, accuracy: 0.5)
    }
}

final class NotificationPlannerTests: XCTestCase {
    private func calendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 8, _ minute: Int = 0) -> Date {
        calendar().date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0),
                                             year: year, month: month, day: day,
                                             hour: hour, minute: minute))!
    }

    private func profile(trainingDays: Int = 5,
                         hour: Int = 9,
                         minute: Int = 0,
                         difficulty: String? = nil,
                         encouragement: String? = nil,
                         sleep: String? = nil,
                         trialStartedAt: Date? = nil) -> ProfileSnapshot {
        ProfileSnapshot(
            goals: ["sharpen my focus"],
            difficultyPreference: difficulty,
            encouragementStyle: encouragement,
            sleepHours: sleep,
            trainingDays: trainingDays,
            reminderHour: hour,
            reminderMinute: minute,
            notificationsEnabled: true,
            trialStartedAt: trialStartedAt
        )
    }

    func testTrainingDaysLimitDailyWorkoutReminders() {
        let cal = calendar()
        let now = date(2026, 6, 29, 8) // Monday
        let events = WitsNotificationPlanner.events(
            profile: profile(trainingDays: 3),
            context: WitsNotificationPlanContext(now: now),
            calendar: cal
        )

        XCTAssertEqual(events.filter { $0.kind == .dailyWorkout }.count, 3)
    }

    func testCompletedWorkoutSkipsSameDayWorkoutAndRescue() {
        let cal = calendar()
        let now = date(2026, 6, 29, 8)
        let events = WitsNotificationPlanner.events(
            profile: profile(trainingDays: 7),
            context: WitsNotificationPlanContext(now: now, todayWorkoutDone: true),
            calendar: cal
        )
        let today = cal.startOfDay(for: now)

        XCTAssertFalse(events.contains {
            [.dailyWorkout, .streakRescue].contains($0.kind) && cal.isDate($0.fireDate, inSameDayAs: today)
        })
    }

    func testCompletedWorkoutReplanDropsReactivationNudges() {
        let cal = calendar()
        let now = date(2026, 6, 29, 8)
        let events = WitsNotificationPlanner.events(
            profile: profile(trainingDays: 7),
            context: WitsNotificationPlanContext(
                now: now,
                todayWorkoutDone: true,
                streak: StreakState(current: 1, longest: 1, lastActiveDay: now),
                hasAnyProgress: true
            ),
            calendar: cal
        )

        XCTAssertFalse(events.contains { $0.kind == .reactivation })
    }

    func testReactivationSuppressesSameDayDailyWorkoutNudge() {
        let cal = calendar()
        let now = date(2026, 6, 29, 8)
        let events = WitsNotificationPlanner.events(
            profile: profile(trainingDays: 7),
            context: WitsNotificationPlanContext(
                now: now,
                streak: StreakState(current: 0, longest: 4, lastActiveDay: date(2026, 6, 25)),
                hasAnyProgress: true
            ),
            calendar: cal
        )
        let dailyDays = Set(events.filter { $0.kind == .dailyWorkout }.map { cal.startOfDay(for: $0.fireDate) })
        let reactivationDays = Set(events.filter { $0.kind == .reactivation }.map { cal.startOfDay(for: $0.fireDate) })

        XCTAssertTrue(dailyDays.isDisjoint(with: reactivationDays))
        XCTAssertFalse(reactivationDays.isEmpty)
    }

    func testToneAndDifficultyPersonalizeCopy() {
        let cal = calendar()
        let now = date(2026, 6, 29, 8)
        let standard = WitsNotificationPlanner.events(
            profile: profile(difficulty: "standard", encouragement: "high fives"),
            context: WitsNotificationPlanContext(now: now),
            calendar: cal
        ).first { $0.kind == .dailyWorkout }?.body
        let advanced = WitsNotificationPlanner.events(
            profile: profile(difficulty: "advanced", encouragement: "tough love"),
            context: WitsNotificationPlanContext(now: now),
            calendar: cal
        ).first { $0.kind == .dailyWorkout }?.body

        XCTAssertNotEqual(standard, advanced)
    }

    func testLowSleepAvoidsLateRescueNotification() {
        let cal = calendar()
        let now = date(2026, 6, 29, 8)
        let events = WitsNotificationPlanner.events(
            profile: profile(trainingDays: 7, hour: 21, sleep: "5-6 hours"),
            context: WitsNotificationPlanContext(now: now),
            calendar: cal
        )

        XCTAssertFalse(events.contains { $0.kind == .streakRescue })
    }

    func testLowSleepMatcherDoesNotTreatSixteenHoursAsLowSleep() {
        let cal = calendar()
        let now = date(2026, 6, 29, 8)
        let events = WitsNotificationPlanner.events(
            profile: profile(trainingDays: 7, hour: 16, sleep: "16 hours"),
            context: WitsNotificationPlanContext(now: now),
            calendar: cal
        )

        XCTAssertTrue(events.contains { $0.kind == .streakRescue })
    }

    func testTrialLifecycleSchedulesDeadlineNudges() {
        let cal = calendar()
        let now = date(2026, 6, 29, 8)
        let events = WitsNotificationPlanner.events(
            profile: profile(trainingDays: 7, trialStartedAt: date(2026, 6, 27, 12)),
            context: WitsNotificationPlanContext(now: now),
            calendar: cal
        )
        let kinds = Set(events.map(\.kind))

        XCTAssertTrue(kinds.contains(.trialEndingSoon))
        XCTAssertTrue(kinds.contains(.trialEndsToday))
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
}
