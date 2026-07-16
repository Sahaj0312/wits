//
//  LevelSystemTests.swift
//  witsTests
//
//  Infinite difficulty tracks: tuning math, isolated progression, persistence,
//  migration, grading, and Split's retained endless best.
//

import XCTest
@testable import wits

@MainActor
final class LevelSystemTests: XCTestCase {

    override func setUp() {
        super.setUp()
        for key in [
            "wits.appstate.v1",
            "wits.difficultyProgress.v2",
            "wits.difficultyProgress.migrated.v2",
            "wits.levelProgress.v1",
            "wits.levelProgress.seeded.v1"
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: Difficulty scale

    func testDifficultyTracksStartInDistinctOrderedBands() {
        let starts = ChallengeDifficulty.allCases.map {
            DifficultyScale.legacyDifficulty(for: $0, level: 1)
        }
        XCTAssertEqual(starts.count, 4)
        XCTAssertEqual(starts[0], 1, accuracy: 0.0001)
        XCTAssertTrue(zip(starts, starts.dropFirst()).allSatisfy(<))
        XCTAssertLessThan(starts.last ?? 10, 10)
    }

    func testEveryTrackRampsMonotonicallyWithoutExceedingEngineBounds() {
        for difficulty in ChallengeDifficulty.allCases {
            var previous = 0.0
            for level in [1, 2, 8, 50, 1_000, 1_000_000] {
                let value = DifficultyScale.legacyDifficulty(for: difficulty, level: level)
                XCTAssertGreaterThanOrEqual(value, previous)
                XCTAssertGreaterThanOrEqual(value, 1)
                XCTAssertLessThanOrEqual(value, 10)
                previous = value
            }
        }
    }

    func testInfiniteTrackLevelsAlwaysMapToSafeContentSteps() {
        for game in GameID.allCases {
            for difficulty in ChallengeDifficulty.allCases {
                let content = DifficultyScale.contentLevel(for: game,
                                                           difficulty: difficulty,
                                                           trackLevel: 1_000_000)
                XCTAssertGreaterThanOrEqual(content, 1)
                XCTAssertLessThanOrEqual(content, DifficultyScale.contentCeiling(for: game))
            }
        }
    }

    // MARK: Grading

    func testPassThreshold() {
        XCTAssertFalse(LevelGrader.passed(quality: 0.59))
        XCTAssertTrue(LevelGrader.passed(quality: 0.60))
        XCTAssertTrue(LevelGrader.passed(quality: 0.95))
    }

    // MARK: Independent tracks

    func testAdvancingEasyDoesNotAdvanceHard() {
        let store = LevelProgressStore()
        for level in 1...8 {
            store.recordAttempt(game: .blockEscape,
                                difficulty: .easy,
                                level: level,
                                quality: 0.65)
        }

        XCTAssertEqual(store.currentLevel(for: .blockEscape, difficulty: .easy), 9)
        XCTAssertEqual(store.currentLevel(for: .blockEscape, difficulty: .hard), 1)
    }

    func testFailureDoesNotAdvanceTrack() {
        let store = LevelProgressStore()
        store.recordAttempt(game: .echoGrid,
                            difficulty: .medium,
                            level: 1,
                            quality: 0.42)
        XCTAssertEqual(store.currentLevel(for: .echoGrid, difficulty: .medium), 1)
        XCTAssertFalse(store.hasPassed(game: .echoGrid, difficulty: .medium, level: 1))
    }

    func testTrackHasNoFiniteLevelCeiling() {
        let store = LevelProgressStore()
        for level in 1...250 {
            store.recordAttempt(game: .colorClash,
                                difficulty: .extraHard,
                                level: level,
                                quality: 0.65)
        }
        XCTAssertEqual(store.currentLevel(for: .colorClash, difficulty: .extraHard), 251)
    }

    func testPassAndQualityNeverGoDown() {
        let store = LevelProgressStore()
        store.recordAttempt(game: .pegSolitaire,
                            difficulty: .hard,
                            level: 1,
                            quality: 0.95)
        let improved = store.recordAttempt(game: .pegSolitaire,
                                           difficulty: .hard,
                                           level: 1,
                                           quality: 0.62)
        XCTAssertFalse(improved)
        XCTAssertTrue(store.hasPassed(game: .pegSolitaire, difficulty: .hard, level: 1))
        XCTAssertEqual(store.record(for: .pegSolitaire,
                                    difficulty: .hard,
                                    level: 1)?.bestQuality, 0.95)
    }

    func testSelectionAndProgressPersist() {
        var store: LevelProgressStore? = LevelProgressStore()
        store?.select(.extraHard, for: .slidePuzzle)
        store?.recordAttempt(game: .slidePuzzle,
                             difficulty: .extraHard,
                             level: 1,
                             quality: 0.8)
        store = nil

        let reloaded = LevelProgressStore()
        XCTAssertEqual(reloaded.selectedDifficulty(for: .slidePuzzle), .extraHard)
        XCTAssertEqual(reloaded.currentLevel(for: .slidePuzzle, difficulty: .extraHard), 2)
        XCTAssertEqual(reloaded.currentLevel(for: .slidePuzzle, difficulty: .easy), 1)
    }

    func testStoredStarRecordsDecodeAsPassed() {
        let starEraJSON = """
        {"tracks":[{"game":"blockEscape","difficulty":"easy","progress":\
        {"unlockedLevel":2,"records":{"1":{"stars":2,"bestQuality":0.8}}}}],\
        "selections":[],"marathon":[]}
        """
        UserDefaults.standard.set(Data(starEraJSON.utf8),
                                  forKey: "wits.difficultyProgress.v2")

        let store = LevelProgressStore()
        XCTAssertTrue(store.hasPassed(game: .blockEscape, difficulty: .easy, level: 1))
        XCTAssertEqual(store.record(for: .blockEscape,
                                    difficulty: .easy,
                                    level: 1)?.bestQuality, 0.8)
        XCTAssertEqual(store.currentLevel(for: .blockEscape, difficulty: .easy), 2)
    }

    // MARK: Migration

    func testAdaptiveMigrationSeedsOnlyTheMatchingTrack() {
        var state = DifficultyState.seed(for: .lastSeen)
        state.level = 6.5
        state.sessionsPlayed = 12

        let store = LevelProgressStore()
        store.migrateIfNeeded(from: [.lastSeen: state])

        XCTAssertEqual(store.selectedDifficulty(for: .lastSeen), .hard)
        XCTAssertGreaterThan(store.currentLevel(for: .lastSeen, difficulty: .hard), 1)
        XCTAssertEqual(store.currentLevel(for: .lastSeen, difficulty: .easy), 1)
        XCTAssertEqual(store.currentLevel(for: .lastSeen, difficulty: .medium), 1)
        XCTAssertEqual(store.currentLevel(for: .lastSeen, difficulty: .extraHard), 1)
    }

    // MARK: Split endless best

    func testMarathonBestTracksDepthThenScore() {
        let store = LevelProgressStore()
        XCTAssertTrue(store.recordMarathon(game: .split, depth: 8, score: 3_000))
        XCTAssertFalse(store.recordMarathon(game: .split, depth: 6, score: 9_000))
        XCTAssertTrue(store.recordMarathon(game: .split, depth: 8, score: 3_500))
        XCTAssertTrue(store.recordMarathon(game: .split, depth: 9, score: 100))
        XCTAssertEqual(store.marathonBest(for: .split)?.depth, 9)
    }

    func testSplitDepthBreaksEqualLevelTies() {
        let store = LevelProgressStore()
        XCTAssertTrue(store.recordMarathon(game: .split, depth: 8, depthFraction: 0.2, score: 1_000))
        XCTAssertTrue(store.recordMarathon(game: .split, depth: 8, depthFraction: 0.7, score: 900))
        XCTAssertFalse(store.recordMarathon(game: .split, depth: 8, depthFraction: 0.5, score: 9_000))
        XCTAssertEqual(store.marathonBest(for: .split)?.depthFraction, 0.7)
    }

    func testCampaignMasteryIsIndependentByDifficulty() {
        let app = AppModel()
        let hardBefore = app.difficultyState(for: .lastSeen, difficulty: .hard)
        var result = GameResult(game: .lastSeen, score: 900, accuracy: 1, trials: 20)
        result.raw = [
            "correct": 20,
            "wrong": 0,
            "remembered": 8,
            "trackLevel": 1,
            "difficultyTrack": Double(ChallengeDifficulty.easy.ordinal)
        ]

        app.recordGameResult(result)

        XCTAssertGreaterThan(app.difficultyState(for: .lastSeen, difficulty: .easy).sessionsPlayed, 0)
        XCTAssertEqual(app.difficultyState(for: .lastSeen, difficulty: .hard), hardBefore)
    }

    func testMarathonPointsScaleWithDepth() {
        let early = MarathonMath.points(level: 2, quality: 1.0)
        let late = MarathonMath.points(level: 30, quality: 0.7)
        XCTAssertGreaterThan(late, early * 5)
        XCTAssertEqual(MarathonMath.points(level: 10, quality: 0), 0)
    }

    func testRewardedReviveIsAvailableForEveryIntendedGame() {
        let excluded = Set(GameID.allCases.filter { !$0.offersRewardedRevive })
        XCTAssertEqual(excluded, Set([.slidePuzzle, .crossword]))
        XCTAssertEqual(GameID.allCases.filter(\.offersRewardedRevive).count, 16)
    }
}
