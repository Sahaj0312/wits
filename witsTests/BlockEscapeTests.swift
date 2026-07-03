//
//  BlockEscapeTests.swift
//  witsTests
//
//  Klotski engine: canonical key round-trips, exact generator par, ladder
//  sanity, and move reversibility.
//

import XCTest
@testable import wits

final class BlockEscapeTests: XCTestCase {

    func testKeyDecodeRoundTrip() {
        for level in [1, 9, 17, 27, 35] {
            let spec = KlotskiEngine.spec(forMapLevel: level)
            guard let board = KlotskiEngine.randomSolvedLayout(spec) else {
                XCTFail("layout failed for level \(level)"); continue
            }
            let key = KlotskiEngine.key(board)
            let decoded = KlotskiEngine.decode(key, width: spec.width, height: spec.height)
            XCTAssertEqual(KlotskiEngine.key(decoded), key, "decode must round-trip the canonical key")
            XCTAssertEqual(decoded.blocks.count, board.blocks.count)
            XCTAssertEqual(decoded.blocks[0].w, 2)
            XCTAssertEqual(decoded.blocks[0].h, 2)
        }
    }

    // Bands 1–2 only: their move graphs are a few thousand states, so exact
    // BFS verification stays fast in debug builds. Band 3+ uses the same code
    // path over larger (profiled) components.
    func testGeneratedPuzzleParIsExact() {
        for level in [1, 5, 9, 14] {
            let (board, par) = KlotskiEngine.generate(mapLevel: level)
            XCTAssertFalse(board.isSolved, "generated start must not already be solved")
            XCTAssertEqual(KlotskiEngine.solve(board), par,
                           "level \(level): generator par must equal the true BFS minimum")
        }
    }

    func testGeneratedParTracksLadderTarget() {
        let easy = KlotskiEngine.generate(mapLevel: 1).par
        let mid = KlotskiEngine.generate(mapLevel: 14).par
        XCTAssertGreaterThanOrEqual(easy, 2)
        XCTAssertGreaterThan(mid, easy, "mid-ladder puzzles must be deeper than level 1")
    }

    func testSpecLadderIsMonotonicAndPlaceable() {
        var lastTarget = 0
        for level in 1...40 {
            let spec = KlotskiEngine.spec(forMapLevel: level)
            if level > 1 {
                let previous = KlotskiEngine.spec(forMapLevel: level - 1)
                let sameMix = (spec.width, spec.height, spec.verticals, spec.horizontals, spec.singles)
                    == (previous.width, previous.height, previous.verticals, previous.horizontals, previous.singles)
                if sameMix {
                    XCTAssertGreaterThanOrEqual(spec.targetPar, lastTarget,
                                                "target par must not drop within a band (level \(level))")
                }
            }
            lastTarget = spec.targetPar
            XCTAssertNotNil(KlotskiEngine.randomSolvedLayout(spec), "spec for level \(level) must be placeable")
            let cells = spec.width * spec.height
            let occupied = 4 + spec.verticals * 2 + spec.horizontals * 2 + spec.singles
            XCTAssertLessThanOrEqual(occupied, cells - 2, "level \(level) must leave at least two free cells")
            XCTAssertLessThanOrEqual(cells, 30, "packed key supports at most 30 cells")
        }
    }

    func testMovesAreReversible() {
        let spec = KlotskiEngine.spec(forMapLevel: 12)
        guard let board = KlotskiEngine.randomSolvedLayout(spec) else { return XCTFail("layout failed") }
        for neighbor in KlotskiEngine.neighbors(board) {
            let back = KlotskiEngine.neighbors(neighbor).map { KlotskiEngine.key($0) }
            XCTAssertTrue(back.contains(KlotskiEngine.key(board)), "every move must be undoable")
        }
    }

    func testSolvedDetection() {
        let spec = KlotskiEngine.spec(forMapLevel: 5)
        guard let board = KlotskiEngine.randomSolvedLayout(spec) else { return XCTFail("layout failed") }
        XCTAssertTrue(board.isSolved, "seed layouts place the hero at the exit")
        XCTAssertEqual(KlotskiEngine.solve(board), 0)
    }
}
