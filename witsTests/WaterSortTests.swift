//
//  WaterSortTests.swift
//  witsTests
//
//  Water sort engine: pour rules, canonical keys, exact generator par,
//  ladder sanity, and seeded determinism.
//

import XCTest
@testable import wits

final class WaterSortTests: XCTestCase {

    // MARK: Rules

    func testPourRules() {
        // Tubes read bottom → top: [1, 1, 2] has colour 2 on top.
        var tubes: [WaterSortEngine.Tube] = [[1, 1, 2], [2], [], [3, 3, 3, 3], [1]]

        XCTAssertTrue(WaterSortEngine.canPour(tubes, from: 0, to: 1, capacity: 4), "matching top colour")
        XCTAssertTrue(WaterSortEngine.canPour(tubes, from: 0, to: 2, capacity: 4), "empty destination")
        XCTAssertFalse(WaterSortEngine.canPour(tubes, from: 1, to: 4, capacity: 4), "mismatched top colour")
        XCTAssertFalse(WaterSortEngine.canPour(tubes, from: 0, to: 3, capacity: 4), "full destination")
        XCTAssertFalse(WaterSortEngine.canPour(tubes, from: 2, to: 1, capacity: 4), "empty source")
        XCTAssertFalse(WaterSortEngine.canPour(tubes, from: 0, to: 0, capacity: 4), "self pour")

        let moved = WaterSortEngine.pour(&tubes, from: 0, to: 1, capacity: 4)
        XCTAssertEqual(moved, 1)
        XCTAssertEqual(tubes[0], [1, 1])
        XCTAssertEqual(tubes[1], [2, 2])
    }

    func testPourMovesWholeRunUpToSpace() {
        var tubes: [WaterSortEngine.Tube] = [[2, 1, 1, 1], [1], []]
        let moved = WaterSortEngine.pour(&tubes, from: 0, to: 1, capacity: 4)
        XCTAssertEqual(moved, 3, "the whole top run travels when it fits")
        XCTAssertEqual(tubes[0], [2])
        XCTAssertEqual(tubes[1], [1, 1, 1, 1])

        var cramped: [WaterSortEngine.Tube] = [[2, 1, 1, 1], [1, 1, 1], []]
        let partial = WaterSortEngine.pour(&cramped, from: 0, to: 1, capacity: 4)
        XCTAssertEqual(partial, 1, "only what fits moves; the remainder stays")
        XCTAssertEqual(cramped[0], [2, 1, 1])
    }

    func testSolvedDetection() {
        XCTAssertTrue(WaterSortEngine.isSolved([[1, 1, 1, 1], [2, 2, 2, 2], []], capacity: 4))
        XCTAssertFalse(WaterSortEngine.isSolved([[1, 1, 1, 2], [2, 2, 2, 1], []], capacity: 4))
        XCTAssertFalse(WaterSortEngine.isSolved([[1, 1], [1, 1], []], capacity: 4),
                       "a split colour is not sorted even when every tube is mono")
    }

    func testCanonicalKeyIgnoresTubeOrder() {
        let a: [WaterSortEngine.Tube] = [[1, 2], [3], []]
        let b: [WaterSortEngine.Tube] = [[], [3], [1, 2]]
        XCTAssertEqual(WaterSortEngine.key(a), WaterSortEngine.key(b))
        XCTAssertNotEqual(WaterSortEngine.key(a), WaterSortEngine.key([[2, 1], [3], []]),
                          "order inside a tube matters")
    }

    // MARK: Solver

    func testSolverFindsKnownMinimum() {
        // Two pours: 2s onto 2s, then 1s onto 1s (or symmetric).
        let easy: [WaterSortEngine.Tube] = [[1, 1, 2, 2], [2, 2], [1, 1], []]
        XCTAssertEqual(WaterSortEngine.solve(easy, capacity: 4), 2)

        let solved: [WaterSortEngine.Tube] = [[1, 1, 1, 1], []]
        XCTAssertEqual(WaterSortEngine.solve(solved, capacity: 4), 0)
    }

    func testSolverRejectsUnsolvable() {
        // No empty tubes and no matching tops: nothing can ever move.
        let stuck: [WaterSortEngine.Tube] = [[1, 2, 1, 2], [2, 1, 2, 1]]
        XCTAssertNil(WaterSortEngine.solve(stuck, capacity: 4))
    }

    func testSolverRejectsReversiblePourStalemate() {
        // This mirrors a real six-colour dead position. Blue can move from
        // tube 6 to tube 2, but the only resulting move is straight back.
        let stuck: [WaterSortEngine.Tube] = [
            [5, 5], [2, 6], [5, 3, 1, 1], [4, 2, 1, 1],
            [5, 4, 2, 2], [3, 6, 6, 6], [4, 4], [3, 3]
        ]
        XCTAssertTrue(WaterSortEngine.canPour(stuck, from: 5, to: 1, capacity: 4),
                      "the position has a legal-looking pour")
        XCTAssertNil(WaterSortEngine.solve(stuck, capacity: 4),
                     "a reversible pour loop is still a stalemate")

        var loop = stuck
        XCTAssertEqual(WaterSortEngine.pour(&loop, from: 5, to: 1, capacity: 4), 2)
        XCTAssertEqual(WaterSortEngine.pour(&loop, from: 1, to: 5, capacity: 4), 2)
        XCTAssertEqual(loop, stuck)
    }

    // MARK: Generation

    // Small bands only: their searches finish fast in debug builds. Larger
    // colour counts use the same code path, profiled with the -O harness.
    func testGeneratedPuzzleParIsExact() {
        for level in [1, 4, 10] {
            let (tubes, par, spec) = WaterSortEngine.generate(mapLevel: level, seed: 0xA11CE + UInt64(level))
            XCTAssertFalse(WaterSortEngine.isSolved(tubes, capacity: spec.capacity),
                           "generated start must not already be solved")
            XCTAssertEqual(tubes.count, spec.tubeCount)
            XCTAssertEqual(WaterSortEngine.solve(tubes, capacity: spec.capacity), par,
                           "level \(level): generator par must equal the true A* minimum")
        }
    }

    func testGeneratedDealHasExactColorCounts() {
        let (tubes, _, spec) = WaterSortEngine.generate(mapLevel: 6, seed: 42)
        var counts: [UInt8: Int] = [:]
        for tube in tubes {
            for unit in tube { counts[unit, default: 0] += 1 }
        }
        XCTAssertEqual(counts.count, spec.colors)
        for color in 1...spec.colors {
            XCTAssertEqual(counts[UInt8(color)], spec.capacity, "every colour fills exactly one tube")
        }
    }

    func testSeededGenerationIsDeterministic() {
        let a = WaterSortEngine.generate(mapLevel: 5, seed: 99)
        let b = WaterSortEngine.generate(mapLevel: 5, seed: 99)
        XCTAssertEqual(a.tubes, b.tubes)
        XCTAssertEqual(a.par, b.par)
    }

    func testSpecLadderIsMonotonicAndSane() {
        var lastColors = 0
        for level in 1...40 {
            let spec = WaterSortEngine.spec(forMapLevel: level)
            XCTAssertEqual(spec.capacity, 4)
            XCTAssertEqual(spec.extraTubes, 2)
            XCTAssertTrue((3...8).contains(spec.colors), "level \(level) colours in range")
            XCTAssertGreaterThanOrEqual(spec.colors, lastColors, "colour count never drops")
            if spec.colors == lastColors {
                let previous = WaterSortEngine.spec(forMapLevel: level - 1)
                XCTAssertGreaterThanOrEqual(spec.targetPar, previous.targetPar,
                                            "target par must not drop within a band (level \(level))")
            }
            lastColors = spec.colors
        }
        XCTAssertEqual(WaterSortEngine.spec(forMapLevel: 0), WaterSortEngine.spec(forMapLevel: 1))
        XCTAssertEqual(WaterSortEngine.spec(forMapLevel: 99), WaterSortEngine.spec(forMapLevel: 40))
    }
}
