//
//  BlockEscapeTests.swift
//  witsTests
//
//  Runtime catalog integrity, deterministic selection, board shape, and core
//  Klotski move behavior. Expensive full-graph generation stays offline.
//

import XCTest
@testable import wits

final class BlockEscapeTests: XCTestCase {

    func testBundledCatalogHasThousandsOfUniqueBoardsPerBand() {
        for band in KlotskiDifficultyBand.allCases {
            let entries = KlotskiEngine.catalogEntries(for: band)
            XCTAssertEqual(entries.count, KlotskiEngine.boardsPerBand, "\(band.title) catalog size")
            XCTAssertEqual(Set(entries.map(\.key)).count, entries.count, "\(band.title) keys must be unique")
            XCTAssertEqual(KlotskiEngine.catalogDepthRange(for: band), band.catalogDepths)
        }
    }

    func testCatalogBoardsMatchTheirDifficultyRecipe() {
        for band in KlotskiDifficultyBand.allCases {
            let generated = KlotskiEngine.generate(band: band, seed: 0xC0FFEE)
            let board = generated.board
            let spec = band.spec

            XCTAssertEqual(board.width, spec.width)
            XCTAssertEqual(board.height, spec.height)
            XCTAssertFalse(board.isSolved, "catalog must not serve an already-solved board")
            XCTAssertEqual(board.blocks.filter { $0.w == 2 && $0.h == 2 }.count, 1)
            XCTAssertEqual(board.blocks.filter { $0.w == 1 && $0.h == 2 }.count, spec.verticals)
            XCTAssertEqual(board.blocks.filter { $0.w == 2 && $0.h == 1 }.count, spec.horizontals)
            XCTAssertEqual(board.blocks.filter { $0.w == 1 && $0.h == 1 }.count, spec.singles)
        }
    }

    func testSeededCatalogSelectionIsDeterministic() {
        for band in KlotskiDifficultyBand.allCases {
            let first = KlotskiEngine.generate(band: band, seed: 123_456)
            let second = KlotskiEngine.generate(band: band, seed: 123_456)
            XCTAssertEqual(first.key, second.key)
            XCTAssertEqual(first.board, second.board)
        }
    }

    func testCatalogSelectionHasBroadVariety() {
        for band in KlotskiDifficultyBand.allCases {
            let keys = Set((0..<1_000).map {
                KlotskiEngine.generate(band: band, seed: UInt64($0)).key
            })
            XCTAssertGreaterThan(keys.count, 700, "\(band.title) should draw broadly from its catalog")
        }
    }

    func testRecentBoardCanBeExcluded() {
        let first = KlotskiEngine.generate(band: .hard, seed: 42)
        let next = KlotskiEngine.generate(band: .hard, seed: 42, excluding: [first.key])
        XCTAssertNotEqual(next.key, first.key)
    }

    func testKeyDecodeRoundTrip() {
        for band in KlotskiDifficultyBand.allCases {
            let board = KlotskiEngine.generate(band: band, seed: 987).board
            let key = KlotskiEngine.key(board)
            let decoded = KlotskiEngine.decode(key, width: board.width, height: board.height)
            XCTAssertEqual(KlotskiEngine.key(decoded), key)
            XCTAssertEqual(decoded.blocks.count, board.blocks.count)
        }
    }

    func testStoredEasyDepthIsExact() throws {
        let entry = try XCTUnwrap(KlotskiEngine.catalogEntries(for: .easy).first)
        let spec = KlotskiDifficultyBand.easy.spec
        let board = KlotskiEngine.decode(entry.key, width: spec.width, height: spec.height)
        XCTAssertEqual(KlotskiEngine.solve(board), entry.depth)
    }

    func testMovesAreReversible() {
        let board = KlotskiEngine.generate(band: .medium, seed: 321).board
        for neighbor in KlotskiEngine.neighbors(board) {
            let reverseKeys = KlotskiEngine.neighbors(neighbor).map(KlotskiEngine.key)
            XCTAssertTrue(reverseKeys.contains(KlotskiEngine.key(board)), "every move must be undoable")
        }
    }

    func testSolvedDetection() {
        let board = KlotskiBoard(width: 4, height: 4,
                                 blocks: [KlotskiBlock(x: 1, y: 2, w: 2, h: 2)])
        XCTAssertTrue(board.isSolved)
        XCTAssertEqual(KlotskiEngine.solve(board), 0)
    }
}
