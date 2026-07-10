import XCTest
@testable import wits

final class WeeklyChallengeIdentityTests: XCTestCase {
    func testChallengeIdentityIsStableWithinAnISOWeek() throws {
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-06T12:00:00Z"))
        let later = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-12T23:00:00Z"))
        let first = WeeklyChallenge.current(for: .arrowStorm, now: start)
        let second = WeeklyChallenge.current(for: .arrowStorm, now: later)

        XCTAssertEqual(first.weekID, "2026-W28")
        XCTAssertEqual(first.seed, second.seed)
        XCTAssertEqual(first.leaderboardID, second.leaderboardID)
    }

    func testSeedsChangeByWeekAndGame() throws {
        let firstWeek = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-06T12:00:00Z"))
        let nextWeek = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-13T12:00:00Z"))
        let arrow = WeeklyChallenge.current(for: .arrowStorm, now: firstWeek)
        let color = WeeklyChallenge.current(for: .colorClash, now: firstWeek)
        let nextArrow = WeeklyChallenge.current(for: .arrowStorm, now: nextWeek)

        XCTAssertNotEqual(arrow.seed, color.seed)
        XCTAssertNotEqual(arrow.seed, nextArrow.seed)
    }

    func testSeededGeneratorsAndSlideBoardsRepeatExactly() {
        var a = SeededRandomNumberGenerator(seed: 42)
        var b = SeededRandomNumberGenerator(seed: 42)
        XCTAssertEqual((0..<20).map { _ in a.next() }, (0..<20).map { _ in b.next() })

        var boardA = SeededRandomNumberGenerator(seed: 9_001)
        var boardB = SeededRandomNumberGenerator(seed: 9_001)
        XCTAssertEqual(SlidePuzzleScreen.scrambledTiles(size: 4, depth: 32, using: &boardA),
                       SlidePuzzleScreen.scrambledTiles(size: 4, depth: 32, using: &boardB))
    }

    func testSeededPuzzleGeneratorsRepeatExactly() {
        let blockA = KlotskiEngine.generate(mapLevel: 1, seed: 5150)
        let blockB = KlotskiEngine.generate(mapLevel: 1, seed: 5150)
        XCTAssertEqual(blockA.board, blockB.board)
        XCTAssertEqual(blockA.par, blockB.par)

        let pegA = PegSolitaireEngine.generate(mapLevel: 1, seed: 8181)
        let pegB = PegSolitaireEngine.generate(mapLevel: 1, seed: 8181)
        XCTAssertEqual(pegA.puzzle, pegB.puzzle)
        XCTAssertEqual(pegA.solution, pegB.solution)
    }
}

@MainActor
final class WeeklyChallengeProgressTests: XCTestCase {
    override func setUp() {
        super.setUp()
        for key in [
            "wits.appstate.v1",
            "wits.difficultyProgress.v2",
            "wits.difficultyProgress.migrated.v2",
            "wits.levelProgress.v1"
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func testWeeklyBestOnlyImprovesWithinCurrentWeek() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-08T12:00:00Z"))
        let challenge = WeeklyChallenge.current(for: .lastSeen, now: date)
        let store = LevelProgressStore()

        XCTAssertTrue(store.recordWeekly(challenge: challenge,
                                         score: WeeklyChallengeScore(rankValue: 700,
                                                                     headline: "700 points",
                                                                     detail: "5 remembered")))
        XCTAssertFalse(store.recordWeekly(challenge: challenge,
                                          score: WeeklyChallengeScore(rankValue: 650,
                                                                      headline: "650 points",
                                                                      detail: "4 remembered")))
        XCTAssertEqual(store.weeklyBest(for: challenge)?.score, 700)
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

    func testWeeklyRunDoesNotAdvanceCampaignOrMastery() {
        let app = AppModel()
        let challenge = WeeklyChallenge.current(for: .arrowStorm)
        let before = app.difficultyState(for: .arrowStorm, difficulty: challenge.difficulty)
        let levelBefore = app.levels.currentLevel(for: .arrowStorm, difficulty: challenge.difficulty)
        var result = GameResult(game: .arrowStorm, score: 1_200, accuracy: 1, trials: 20,
                                durationMs: 45_000)
        result.raw = ["correct": 20, "wrong": 0, "timeOnTaskMs": 45_000]

        app.recordWeeklyChallengeResult(result, challenge: challenge)

        XCTAssertEqual(app.difficultyState(for: .arrowStorm, difficulty: challenge.difficulty), before)
        XCTAssertEqual(app.levels.currentLevel(for: .arrowStorm, difficulty: challenge.difficulty), levelBefore)
        XCTAssertEqual(app.levels.totalStars(for: .arrowStorm), 0)
        XCTAssertEqual(app.levels.weeklyBest(for: challenge)?.score, 1_200)
    }
}

