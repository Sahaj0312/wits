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
    func testDirectionControlsScaleAcrossScreenSizes() {
        let compact = SnakePlayLayout(availableSize: CGSize(width: 320, height: 568))
        let standard = SnakePlayLayout(availableSize: CGSize(width: 393, height: 852))
        let tablet = SnakePlayLayout(availableSize: CGSize(width: 820, height: 1_180))

        XCTAssertEqual(compact.directionButtonSide, 68.16, accuracy: 0.01)
        XCTAssertGreaterThan(standard.directionButtonSide, compact.directionButtonSide)
        XCTAssertLessThan(standard.directionButtonSide, tablet.directionButtonSide)
        XCTAssertEqual(tablet.directionButtonSide, 104, accuracy: 0.01)
        XCTAssertLessThanOrEqual(3 * compact.directionButtonSide
                                 + 2 * compact.directionButtonSpacing,
                                 320)
        XCTAssertEqual(standard.boardSize.width / standard.boardSize.height,
                       CGFloat(SnakeEngine.cols) / CGFloat(SnakeEngine.rows),
                       accuracy: 0.001)

        for (layout, availableHeight) in [(compact, CGFloat(568)),
                                          (standard, CGFloat(852)),
                                          (tablet, CGFloat(1_180))] {
            let controlsHeight = layout.directionButtonSide * 2
                + layout.directionButtonSpacing
            let occupiedHeight = 10 + 44 + 10 + layout.boardSize.height
                + 7 + controlsHeight + 10
            XCTAssertLessThanOrEqual(occupiedHeight, availableHeight + 0.01)
        }
    }

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
