//
//  PegSolitaireTests.swift
//  witsTests
//
//  Peg solitaire engine: shape parsing, jump legality, generator guarantees
//  (solvable by construction — the recorded solution must replay to a single
//  peg), and ladder sanity.
//

import XCTest
@testable import wits

final class PegSolitaireTests: XCTestCase {

    func testShapeParsing() {
        let expected: [PegSolitaireEngine.Shape: Int] = [
            .diamond13: 13, .square25: 25, .english33: 33, .european37: 37,
            .wiegleb45: 45, .triangle15: 15, .star13: 13, .trapezoid18: 18, .hexagon19: 19
        ]
        for (shape, count) in expected {
            XCTAssertEqual(shape.parsed.holes.count, count, "\(shape) hole count")
        }
        for shape in PegSolitaireEngine.Shape.allCases {
            let b = shape.parsed
            XCTAssertTrue(b.holes.contains(b.center), "\(shape) center must be a hole")
        }
    }

    func testHexJumpsRunAlongAxialDirections() {
        // On the hex triangle, the apex peg jumps along the staggered axis:
        // apex (row 0, col 4) over (row 1, col 4) into (row 2, col 4) uses
        // direction (0, +1) — and the square-lattice diagonal (row 1, col 3)
        // must not create extra jump directions beyond the six axial ones.
        let board = PegSolitaireEngine.Shape.triangle15.parsed
        let apex = 4, below = 1 * board.cols + 4, landing = 2 * board.cols + 4
        let puzzle = PegPuzzle(cols: board.cols, rows: board.rows, holes: board.holes,
                               pegs: [apex, below], target: nil, hex: true)
        let moves = PegSolitaireEngine.legalMoves(puzzle)
        XCTAssertTrue(moves.contains(PegMove(from: apex, over: below, to: landing)))
        XCTAssertEqual(moves.count, 1, "only the axial jump should exist from the apex pair")
    }

    func testJumpsNeverWrapRows() {
        // A peg at a row edge must not jump "around" onto the next row.
        let board = PegSolitaireEngine.Shape.square25.parsed
        // pegs at (3,0), (4,0); empty everywhere else — the only jump along
        // that row would land at x=5 which is off-board, and must not appear
        // as a wrapped move onto row 1.
        let puzzle = PegPuzzle(cols: board.cols, rows: board.rows, holes: board.holes,
                               pegs: [3, 4], target: nil)
        let moves = PegSolitaireEngine.legalMoves(puzzle)
        XCTAssertFalse(moves.contains { $0.from == 3 && $0.to / board.cols != 0 },
                       "horizontal jumps must stay on their row")
        XCTAssertFalse(moves.contains { $0.from % board.cols == 3 && $0.to % board.cols > 4 })
    }

    func testGeneratedBoardsReplayToOnePeg() {
        for level in [1, 6, 10, 14, 18, 22, 26, 30, 34, 40] {
            let (puzzle, solution) = PegSolitaireEngine.generate(mapLevel: level)
            XCTAssertGreaterThanOrEqual(puzzle.pegs.count, 2, "level \(level) must start with 2+ pegs")
            XCTAssertEqual(solution.count, puzzle.pegs.count - 1,
                           "a solution is always pegs−1 jumps (level \(level))")
            var replay = puzzle
            for move in solution {
                XCTAssertTrue(PegSolitaireEngine.legalMoves(replay).contains(move),
                              "recorded solution step must be legal (level \(level))")
                PegSolitaireEngine.apply(move, to: &replay)
            }
            XCTAssertTrue(replay.isCleared, "solution must clear to one peg (level \(level))")
            XCTAssertTrue(replay.isOnTarget, "solution must finish on the target when one is set (level \(level))")
        }
    }

    func testGeneratorHitsRequestedPegCounts() {
        // Small boards should hit their exact requested peg count reliably.
        for level in [1, 5, 9, 13, 17] {
            let spec = PegSolitaireEngine.spec(forMapLevel: level)
            let (puzzle, _) = PegSolitaireEngine.generate(mapLevel: level)
            XCTAssertEqual(puzzle.pegs.count, spec.pegs, "level \(level) should reach its peg target")
        }
    }

    // Solving gates the pass: a stranded board must NEVER pass, no matter
    // how much of it was cleared (regression: stuck runs used to pass).
    func testStuckRunsNeverPass() {
        for clear in [0.5, 0.85, 0.93, 1.0] {
            let q = PegSolitairePolicy.quality(clear: clear, timeEfficiency: 1.0,
                                               solved: false, onTarget: false, undos: 0)
            XCTAssertLessThan(q, LevelGrader.passQuality,
                              "stuck at clear=\(clear) must not pass")
        }
    }

    func testSolveGrading() {
        // clean fast solve grades far above the pass line
        let clean = PegSolitairePolicy.quality(clear: 1, timeEfficiency: 0.9,
                                               solved: true, onTarget: true, undos: 0)
        XCTAssertGreaterThanOrEqual(clean, 0.9)
        // slow undo-heavy solve still passes
        let scrappy = PegSolitairePolicy.quality(clear: 1, timeEfficiency: 0.1,
                                                 solved: true, onTarget: true, undos: 10)
        XCTAssertGreaterThanOrEqual(scrappy, LevelGrader.passQuality)
        // solving but missing the required target hole passes, graded below a clean solve
        let offTarget = PegSolitairePolicy.quality(clear: 1, timeEfficiency: 1,
                                                   solved: true, onTarget: false, undos: 0)
        XCTAssertGreaterThanOrEqual(offTarget, LevelGrader.passQuality)
        XCTAssertLessThan(offTarget, clean)
    }

    func testSpecLadderIsSaneAndMonotonicPerBand() {
        var lastPegs = 0
        for level in 1...40 {
            let spec = PegSolitaireEngine.spec(forMapLevel: level)
            let holes = spec.shape.parsed.holes.count
            XCTAssertLessThanOrEqual(spec.pegs, holes - 1, "level \(level) must leave an empty hole")
            XCTAssertGreaterThanOrEqual(spec.pegs, 4)
            if level > 1, spec.shape == PegSolitaireEngine.spec(forMapLevel: level - 1).shape,
               spec.targetRequired == PegSolitaireEngine.spec(forMapLevel: level - 1).targetRequired {
                XCTAssertGreaterThanOrEqual(spec.pegs, lastPegs,
                                            "peg count must not drop within a band (level \(level))")
            }
            lastPegs = spec.pegs
        }
        // level 40 caps the ladder on the big German board, classic rules
        let top = PegSolitaireEngine.spec(forMapLevel: 40)
        XCTAssertEqual(top.shape, .wiegleb45)
        XCTAssertEqual(top.pegs, 28)
        XCTAssertTrue(top.targetRequired)
    }
}
