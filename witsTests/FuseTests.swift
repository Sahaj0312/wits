//
//  FuseTests.swift
//  witsTests
//
//  Fuse engine: slide/fuse rules (single fusion per cell, fusions resolve
//  toward the swipe), scoring, spawn accounting, seeded determinism, and
//  jammed-board detection.
//

import XCTest
@testable import wits

@MainActor
final class FuseTests: XCTestCase {

    /// Row-major 4×4 board: 0 empty, else the number.
    private func engine(_ values: [Int], seed: UInt64 = 7) -> FuseEngine {
        let g = FuseEngine(seed: seed)
        g.load(values: values)
        return g
    }

    private func value(_ g: FuseEngine, _ r: Int, _ c: Int) -> Int {
        g.tile(atRow: r, col: c)?.value ?? 0
    }

    func testSlideLeftFusesAndPays() {
        let g = engine([
            2, 2, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, 0,
        ])
        XCTAssertTrue(g.slide(.left))
        let outcome = g.settle()
        XCTAssertEqual(outcome.points, 4)
        XCTAssertEqual(outcome.fusions, 1)
        XCTAssertEqual(value(g, 0, 0), 4)
        XCTAssertEqual(g.score, 4)
        XCTAssertEqual(g.bestTile, 4)
        XCTAssertEqual(g.tiles.count, 2, "exactly one tile spawns per settled move")
    }

    func testACellFusesOnlyOncePerSwipe() {
        let g = engine([
            2, 2, 2, 2,
            0, 0, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, 0,
        ])
        XCTAssertTrue(g.slide(.left))
        let outcome = g.settle()
        XCTAssertEqual(outcome.points, 8)
        XCTAssertEqual(value(g, 0, 0), 4)
        XCTAssertEqual(value(g, 0, 1), 4, "2,2,2,2 must become 4,4 — never 8")
    }

    func testCascadePairsFuseIndependently() {
        let g = engine([
            4, 4, 8, 8,
            0, 0, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, 0,
        ])
        XCTAssertTrue(g.slide(.left))
        let outcome = g.settle()
        XCTAssertEqual(outcome.points, 24)
        XCTAssertEqual(value(g, 0, 0), 8)
        XCTAssertEqual(value(g, 0, 1), 16,
                       "the fresh 8 must not chain-fuse into the pair's 8")
    }

    func testFusionResolvesTowardTheSwipe() {
        let g = engine([
            0, 2, 2, 2,
            0, 0, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, 0,
        ])
        XCTAssertTrue(g.slide(.left))
        g.settle()
        XCTAssertEqual(value(g, 0, 0), 4, "the two cells nearest the wall pair up")
        XCTAssertEqual(value(g, 0, 1), 2)
    }

    func testVerticalSlideUsesColumns() {
        let g = engine([
            2, 0, 0, 0,
            2, 0, 0, 0,
            0, 0, 0, 0,
            4, 0, 0, 0,
        ])
        XCTAssertTrue(g.slide(.down))
        g.settle()
        XCTAssertEqual(value(g, 3, 0), 4)
        XCTAssertEqual(value(g, 2, 0), 4)
    }

    func testSlideWithoutEffectReturnsFalse() {
        let g = engine([
            2, 4, 8, 16,
            0, 0, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, 0,
        ])
        XCTAssertFalse(g.slide(.left), "a wall-packed distinct row cannot move left")
        XCTAssertEqual(g.moves, 0)
        XCTAssertEqual(g.tiles.count, 4, "a rejected swipe must not spawn")
    }

    func testJammedBoardDies() {
        let g = engine([
            2, 4, 8, 16,
            32, 64, 128, 256,
            2, 4, 8, 16,
            32, 64, 128, 256,
        ])
        XCTAssertFalse(g.alive)
        XCTAssertFalse(g.slide(.left))
        XCTAssertFalse(g.slide(.up))
    }

    func testReviveRemovesFourWeakestCellsAndRestoresMovement() {
        let g = engine([
            2, 4, 8, 16,
            32, 64, 128, 256,
            2, 4, 8, 16,
            32, 64, 128, 256,
        ])
        XCTAssertFalse(g.alive)

        g.revive()

        XCTAssertTrue(g.alive)
        XCTAssertEqual(g.tiles.count, 12)
        XCTAssertTrue(g.anyMoveAvailable)
    }

    func testFullBoardWithAdjacentPairStaysAlive() {
        let g = engine([
            2, 2, 8, 16,
            32, 64, 128, 256,
            2, 4, 8, 16,
            32, 64, 128, 256,
        ])
        XCTAssertTrue(g.alive, "a full board with an equal adjacent pair is still playable")
    }

    func testSeededRunsAreIdentical() {
        let a = FuseEngine(seed: 42)
        let b = FuseEngine(seed: 42)
        let dirs: [FuseSwipe] = [.left, .up, .right, .down]
        for i in 0..<40 {
            let dir = dirs[i % dirs.count]
            let movedA = a.slide(dir)
            let movedB = b.slide(dir)
            XCTAssertEqual(movedA, movedB, "same seed + same swipes must stay in lockstep")
            if movedA { a.settle() }
            if movedB { b.settle() }
        }
        XCTAssertEqual(a.score, b.score)
        let cellsA = a.tiles.map { [$0.row, $0.col, $0.value] }.sorted { "\($0)" < "\($1)" }
        let cellsB = b.tiles.map { [$0.row, $0.col, $0.value] }.sorted { "\($0)" < "\($1)" }
        XCTAssertEqual(cellsA, cellsB)
    }

    func testFreshEngineStartsWithTwoTiles() {
        let g = FuseEngine(seed: 3)
        XCTAssertEqual(g.tiles.count, 2)
        XCTAssertTrue(g.tiles.allSatisfy { $0.value == 2 || $0.value == 4 })
        XCTAssertTrue(g.alive)
    }
}
