//
//  SplitSurvivalTests.swift
//  witsTests
//
//  Split Survival rewarded-restart progress behavior.
//

import XCTest
@testable import wits

@MainActor
final class SplitSurvivalTests: XCTestCase {
    func testRewardedRevivePreservesFurthestDepthForRunRecording() {
        let game = SplitGame(seed: 7)
        let start = Date(timeIntervalSinceReferenceDate: 10_000)

        game.flap()
        game.tick(start)
        for step in 1...12 {
            game.flap()
            game.tick(start.addingTimeInterval(Double(step) / 30))
        }
        let depthBeforeRevive = game.depthIntoLevel
        XCTAssertGreaterThan(depthBeforeRevive, 0)

        game.revive()

        XCTAssertEqual(game.depthIntoLevel, 0)
        XCTAssertEqual(game.furthestDepthIntoLevel, depthBeforeRevive, accuracy: 0.000_001)

        let resumedAt = start.addingTimeInterval(1)
        game.flap()
        game.tick(resumedAt)
        for step in 1...3 {
            game.flap()
            game.tick(resumedAt.addingTimeInterval(Double(step) / 30))
        }

        XCTAssertLessThan(game.depthIntoLevel, depthBeforeRevive)
        XCTAssertEqual(game.furthestDepthIntoLevel, depthBeforeRevive, accuracy: 0.000_001)
    }
}
