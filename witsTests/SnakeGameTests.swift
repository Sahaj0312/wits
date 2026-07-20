//
//  SnakeGameTests.swift
//  witsTests
//
//  Snake engine revival behavior.
//

import XCTest
@testable import wits

@MainActor
final class SnakeGameTests: XCTestCase {
    func testRevivePreservesEarnedLengthAndScoreOnSafePath() {
        let game = SnakeEngine()
        let crashedBody = (0..<12).map { SnakeCell(x: 11 - $0, y: 10) }
        game.load(body: crashedBody,
                  foods: [SnakeCell(x: 14, y: 20), SnakeCell(x: 13, y: 20)],
                  score: 8,
                  direction: .right,
                  alive: false)

        game.revive()

        XCTAssertTrue(game.alive)
        XCTAssertEqual(game.score, 8)
        XCTAssertEqual(game.body.count, 12)
        XCTAssertEqual(Set(game.body).count, 12, "the revived body must not overlap itself")
        XCTAssertTrue(zip(game.body, game.body.dropFirst()).allSatisfy { first, second in
            abs(first.x - second.x) + abs(first.y - second.y) == 1
        }, "every revived segment must remain connected")
        XCTAssertTrue(game.foods.allSatisfy { !game.body.contains($0) })

        let headBeforeStep = game.body[0]
        let outcome = game.step(tick: 0.15)
        if case .died = outcome {
            XCTFail("the revived snake must have a safe first move")
        }
        XCTAssertEqual(game.body.count, 12)
        XCTAssertEqual(game.body[0], SnakeCell(x: headBeforeStep.x + 1, y: headBeforeStep.y))
    }

    func testReviveDoesNotLoopWhenFewerThanTwoFoodCellsRemain() {
        let game = SnakeEngine()
        let almostFullBody = Array((0..<SnakeEngine.rows).flatMap { y in
            (0..<SnakeEngine.cols).map { x in SnakeCell(x: x, y: y) }
        }.dropLast())
        game.load(body: almostFullBody,
                  foods: [],
                  score: almostFullBody.count - 4,
                  direction: .right,
                  alive: false)

        game.revive()

        XCTAssertEqual(game.body.count, almostFullBody.count)
        XCTAssertEqual(game.foods.count, 1)
    }
}
