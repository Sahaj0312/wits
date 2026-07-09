//
//  LevelSystemTests.swift
//  witsTests
//
//  Star-map core: ladder math, star grading, gating, frontier/workout level
//  selection, marathon bests, and the one-time adaptive-difficulty seeding.
//

import XCTest
@testable import wits

@MainActor
final class LevelSystemTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "wits.levelProgress.v1")
        UserDefaults.standard.removeObject(forKey: "wits.levelProgress.seeded.v1")
    }

    // MARK: Ladder

    func testLevelCountsArePageMultiplesAndCoverAllGames() {
        for game in GameID.allCases {
            let count = LevelLadder.levelCount(for: game)
            XCTAssertGreaterThanOrEqual(count, 20, "\(game) map too short")
            XCTAssertEqual(count % LevelLadder.pageSize, 0, "\(game) count not a page multiple")
        }
    }

    func testLegacyDifficultySpansFullScaleMonotonically() {
        for game in GameID.allCases {
            let count = LevelLadder.levelCount(for: game)
            XCTAssertEqual(LevelLadder.legacyDifficulty(for: game, level: 1), 1)
            XCTAssertEqual(LevelLadder.legacyDifficulty(for: game, level: count), 10)
            var previous = 0.0
            for level in 1...count {
                let d = LevelLadder.legacyDifficulty(for: game, level: level)
                XCTAssertGreaterThan(d, previous, "\(game) difficulty not strictly increasing at \(level)")
                previous = d
            }
        }
    }

    func testNearestLevelRoundTripsTheMapping() {
        for game in [GameID.colorClash, .echoGrid, .pegSolitaire] {
            let count = LevelLadder.levelCount(for: game)
            for level in [1, count / 2, count] {
                let difficulty = LevelLadder.legacyDifficulty(for: game, level: level)
                XCTAssertEqual(LevelLadder.nearestLevel(for: game, legacyDifficulty: difficulty), level)
            }
        }
    }

    // MARK: Stars

    func testStarThresholds() {
        XCTAssertEqual(StarGrader.stars(quality: 0.59), 0)
        XCTAssertEqual(StarGrader.stars(quality: 0.60), 1)
        XCTAssertEqual(StarGrader.stars(quality: 0.74), 1)
        XCTAssertEqual(StarGrader.stars(quality: 0.75), 2)
        XCTAssertEqual(StarGrader.stars(quality: 0.89), 2)
        XCTAssertEqual(StarGrader.stars(quality: 0.90), 3)
        XCTAssertEqual(StarGrader.stars(quality: 1.0), 3)
    }

    // MARK: Store: gating + frontier

    func testUnlockRequiresPreviousPass() {
        let store = LevelProgressStore()
        XCTAssertTrue(store.isUnlocked(.colorClash, level: 1))
        XCTAssertFalse(store.isUnlocked(.colorClash, level: 2))
        store.recordAttempt(game: .colorClash, level: 1, stars: 1, quality: 0.65)
        XCTAssertTrue(store.isUnlocked(.colorClash, level: 2))
        XCTAssertEqual(store.frontier(for: .colorClash), 2)
    }

    func testPageGateBlocksUntilStarTotalMet() {
        let store = LevelProgressStore()
        // Pass all of page 1 with 1★ each = 10 stars < 18 gate.
        for level in 1...10 {
            store.recordAttempt(game: .echoGrid, level: level, stars: 1, quality: 0.65)
        }
        XCTAssertFalse(store.isPageUnlocked(.echoGrid, page: 1))
        XCTAssertFalse(store.isUnlocked(.echoGrid, level: 11))
        // Frontier is 11 but blocked → workout serves a consolidation replay
        // from page 1 (the weakest-star level).
        XCTAssertEqual(store.frontier(for: .echoGrid), 11)
        XCTAssertLessThanOrEqual(store.workoutLevel(for: .echoGrid), 10)

        // Upgrade eight levels to 2★ → 18 stars, gate opens.
        for level in 1...8 {
            store.recordAttempt(game: .echoGrid, level: level, stars: 2, quality: 0.8)
        }
        XCTAssertTrue(store.isPageUnlocked(.echoGrid, page: 1))
        XCTAssertTrue(store.isUnlocked(.echoGrid, level: 11))
        XCTAssertEqual(store.workoutLevel(for: .echoGrid), 11)
    }

    func testStarsNeverGoDown() {
        let store = LevelProgressStore()
        store.recordAttempt(game: .blockEscape, level: 3, stars: 3, quality: 0.95)
        let improved = store.recordAttempt(game: .blockEscape, level: 3, stars: 1, quality: 0.62)
        XCTAssertFalse(improved)
        XCTAssertEqual(store.stars(for: .blockEscape, level: 3), 3)
        XCTAssertEqual(store.record(for: .blockEscape, level: 3)?.bestQuality, 0.95)
    }

    func testMarathonBestTracksDepthThenScore() {
        let store = LevelProgressStore()
        XCTAssertTrue(store.recordMarathon(game: .colorClash, depth: 8, score: 3000))
        XCTAssertFalse(store.recordMarathon(game: .colorClash, depth: 6, score: 9000))
        XCTAssertTrue(store.recordMarathon(game: .colorClash, depth: 8, score: 3500))
        XCTAssertTrue(store.recordMarathon(game: .colorClash, depth: 9, score: 100))
        XCTAssertEqual(store.marathonBest(for: .colorClash)?.depth, 9)
    }

    // MARK: Seeding

    func testSeedingUnlocksEquivalentFrontierWithOneStar() {
        var difficulty: [GameID: DifficultyState] = [:]
        var state = DifficultyState.seed(for: .colorClash)
        state.level = 5.5   // mid-scale → mid-map frontier
        state.sessionsPlayed = 12
        difficulty[.colorClash] = state

        let store = LevelProgressStore()
        store.seedIfNeeded(from: difficulty)

        let expectedFrontier = LevelLadder.nearestLevel(for: .colorClash, legacyDifficulty: 5.5)
        XCTAssertGreaterThan(expectedFrontier, 1)
        for level in 1..<expectedFrontier {
            XCTAssertEqual(store.stars(for: .colorClash, level: level), 1, "level \(level) should be seeded 1★")
        }
        XCTAssertEqual(store.stars(for: .colorClash, level: expectedFrontier), 0)
        // Gates must not strand a seeded user below their frontier.
        XCTAssertEqual(store.workoutLevel(for: .colorClash), expectedFrontier)

        // Seeding is one-time: a second call must not re-grant anything.
        let second = LevelProgressStore()
        var richer = state
        richer.level = 9
        second.seedIfNeeded(from: [.colorClash: richer])
        XCTAssertEqual(second.stars(for: .colorClash, level: expectedFrontier), 0)
    }

    func testSeededFrontierAtPageBoundaryIsNotGateBlocked() {
        // Frontier exactly at a page's first level: the gate must not bind.
        var state = DifficultyState.seed(for: .echoGrid)
        state.sessionsPlayed = 5
        // echoGrid has 40 levels; difficulty for frontier 21 (page boundary).
        state.level = LevelLadder.legacyDifficulty(for: .echoGrid, level: 21)
        let store = LevelProgressStore()
        store.seedIfNeeded(from: [.echoGrid: state])
        XCTAssertEqual(store.frontier(for: .echoGrid), 21)
        XCTAssertTrue(store.isUnlocked(.echoGrid, level: 21))
        XCTAssertEqual(store.workoutLevel(for: .echoGrid), 21)
    }

    func testSeededUsersNeverPlayersWithoutHistoryUnaffected() {
        let store = LevelProgressStore()
        store.seedIfNeeded(from: [:])
        for game in GameID.allCases {
            XCTAssertEqual(store.frontier(for: game), 1)
            XCTAssertEqual(store.totalStars(for: game), 0)
        }
    }

    // MARK: Marathon math

    func testMarathonPointsScaleWithDepth() {
        let early = MarathonMath.points(level: 2, quality: 1.0)
        let late = MarathonMath.points(level: 30, quality: 0.7)
        XCTAssertGreaterThan(late, early * 5, "late levels must dominate score")
        XCTAssertEqual(MarathonMath.points(level: 10, quality: 0), 0)
    }

}
