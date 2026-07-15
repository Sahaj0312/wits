//
//  BlockFitTests.swift
//  witsTests
//
//  Block Fit engine: placement rules, line clears, combo scoring, seeded
//  determinism, and sudden-death detection.
//

import XCTest
@testable import wits

@MainActor
final class BlockFitTests: XCTestCase {

    private func piece(_ pairs: [(Int, Int)], color: Int = 1, id: Int = 999) -> BlockPiece {
        BlockPiece(id: id, cells: pairs.map { BlockCell(r: $0.0, c: $0.1) }, color: color)
    }

    private func emptyBoard() -> [Int] {
        Array(repeating: 0, count: BlockFitGame.side * BlockFitGame.side)
    }

    // MARK: Placement rules

    func testPlacementRejectsOverlapAndOutOfBounds() {
        let game = BlockFitGame(seed: 1)
        var board = emptyBoard()
        board[0] = 2  // (0,0) occupied
        let domino = piece([(0, 0), (0, 1)])
        game.load(board: board, hand: [domino, nil, nil])

        XCTAssertFalse(game.canPlace(domino, atRow: 0, col: 0), "overlap must be rejected")
        XCTAssertFalse(game.canPlace(domino, atRow: 0, col: 7), "out of bounds must be rejected")
        XCTAssertTrue(game.canPlace(domino, atRow: 1, col: 0))
        XCTAssertNil(game.place(handIndex: 0, atRow: 0, col: 0))
    }

    // MARK: Clears and scoring

    func testRowAndColumnClearTogether() {
        let game = BlockFitGame(seed: 1)
        var board = emptyBoard()
        for c in 0..<7 { board[c] = 1 }                      // row 0, missing (0,7)
        for r in 1..<8 { board[r * 8 + 7] = 1 }              // col 7, missing (0,7)
        game.load(board: board, hand: [piece([(0, 0)]), nil, nil])

        let placement = game.place(handIndex: 0, atRow: 0, col: 7)

        XCTAssertEqual(placement?.lines, 2)
        for c in 0..<8 { XCTAssertEqual(game.color(atRow: 0, col: c), 0) }
        for r in 0..<8 { XCTAssertEqual(game.color(atRow: r, col: 7), 0) }
        // 1 placed cell + 10 * 2 lines² * combo 1 = 41.
        XCTAssertEqual(game.score, 41)
        XCTAssertEqual(game.linesCleared, 2)
        XCTAssertEqual(game.combo, 1)
    }

    func testComboBuildsAndResets() {
        let game = BlockFitGame(seed: 2)
        var board = emptyBoard()
        for c in 0..<7 { board[c] = 1 }          // row 0, missing (0,7)
        for c in 0..<7 { board[8 + c] = 1 }      // row 1, missing (1,7)
        game.load(board: board, hand: [piece([(0, 0)], id: 1),
                                       piece([(0, 0)], id: 2),
                                       piece([(0, 0)], id: 3)])

        XCTAssertEqual(game.place(handIndex: 0, atRow: 0, col: 7)?.lines, 1)
        XCTAssertEqual(game.combo, 1)

        XCTAssertEqual(game.place(handIndex: 1, atRow: 4, col: 4)?.lines, 0)
        XCTAssertEqual(game.combo, 0, "a non-clearing placement resets the streak")

        XCTAssertEqual(game.place(handIndex: 2, atRow: 1, col: 7)?.lines, 1)
        XCTAssertEqual(game.combo, 1)
        XCTAssertEqual(game.bestCombo, 1)
        XCTAssertEqual(game.linesCleared, 2)
    }

    func testConsecutiveClearsMultiplyPoints() {
        let game = BlockFitGame(seed: 3)
        var board = emptyBoard()
        for c in 0..<7 { board[c] = 1 }
        for c in 0..<7 { board[8 + c] = 1 }
        game.load(board: board, hand: [piece([(0, 0)], id: 1),
                                       piece([(0, 0)], id: 2),
                                       nil])

        let first = game.place(handIndex: 0, atRow: 0, col: 7)
        let second = game.place(handIndex: 1, atRow: 1, col: 7)

        XCTAssertEqual(first?.points, 1 + 10)      // combo ×1
        XCTAssertEqual(second?.points, 1 + 20)     // combo ×2
        XCTAssertEqual(game.bestCombo, 2)
    }

    // MARK: Determinism

    func testSeededDealsAreReproducible() {
        let a = BlockFitGame(seed: 42)
        let b = BlockFitGame(seed: 42)
        XCTAssertEqual(a.hand.map { $0?.cells }, b.hand.map { $0?.cells })
        XCTAssertEqual(a.hand.map { $0?.color }, b.hand.map { $0?.color })
    }

    func testDealStreamIndependentOfPlacementChoices() {
        // Same seed, different placement positions: the refill after the hand
        // empties must be identical — the weekly ladder depends on it.
        let a = BlockFitGame(seed: 7)
        let b = BlockFitGame(seed: 7)
        let ones: [BlockPiece?] = [piece([(0, 0)], id: 1),
                                   piece([(0, 0)], id: 2),
                                   piece([(0, 0)], id: 3)]
        a.load(board: emptyBoard(), hand: ones)
        b.load(board: emptyBoard(), hand: ones)

        for slot in 0..<3 {
            XCTAssertNotNil(a.place(handIndex: slot, atRow: 0, col: slot))
            XCTAssertNotNil(b.place(handIndex: slot, atRow: 5, col: slot + 3))
        }

        XCTAssertEqual(a.hand.map { $0?.cells }, b.hand.map { $0?.cells })
        XCTAssertEqual(a.hand.map { $0?.color }, b.hand.map { $0?.color })
    }

    func testNextHandPreviewBecomesTheNextDeal() {
        let game = BlockFitGame(seed: 9)
        let previewIDs = game.nextHand.map(\.id)
        XCTAssertEqual(previewIDs.count, 3)

        let ones: [BlockPiece?] = [piece([(0, 0)], id: 101),
                                   piece([(0, 0)], id: 102),
                                   piece([(0, 0)], id: 103)]
        game.load(board: emptyBoard(), hand: ones)
        for slot in 0..<3 {
            XCTAssertNotNil(game.place(handIndex: slot, atRow: 0, col: slot))
        }

        XCTAssertEqual(game.hand.map { $0?.id }, previewIDs,
                       "the shown preview must be exactly the hand that gets dealt")
        XCTAssertEqual(game.nextHand.count, 3, "a fresh preview is drawn after the deal")
    }

    func testOpeningHandsAreGentle() {
        let game = BlockFitGame(seed: 21)
        let openingHands = [game.hand.compactMap { $0 }, game.nextHand]

        for hand in openingHands {
            XCTAssertEqual(hand.count, BlockFitGame.handSize)
            XCTAssertGreaterThanOrEqual(hand.filter(BlockFitShapes.isCompact).count, 2,
                                        "the first two hands should offer at least two flexible pieces")
            XCTAssertFalse(hand.contains(where: BlockFitShapes.isBulky),
                           "board-breakers should not cut the opening short")
        }
    }

    func testEveryLaterHandHasACompactPieceAndAtMostOneBulkyPiece() {
        let game = BlockFitGame(seed: 33)

        for dealIndex in 0..<20 {
            let hand = game.nextHand
            XCTAssertTrue(hand.contains(where: BlockFitShapes.isCompact),
                          "deal \(dealIndex) needs a flexible piece")
            XCTAssertLessThanOrEqual(hand.filter(BlockFitShapes.isBulky).count, 1,
                                     "deal \(dealIndex) should not stack board-breakers")

            // Spend a disposable hand to advance the deterministic preview.
            game.load(board: emptyBoard(), hand: [piece([(0, 0)], id: dealIndex * 3 + 1),
                                                   piece([(0, 0)], id: dealIndex * 3 + 2),
                                                   piece([(0, 0)], id: dealIndex * 3 + 3)])
            for slot in 0..<BlockFitGame.handSize {
                XCTAssertNotNil(game.place(handIndex: slot, atRow: 0, col: slot))
            }
        }
    }

    // MARK: Sudden death

    func testDeadWhenNothingInHandFits() {
        let game = BlockFitGame(seed: 4)
        var board = Array(repeating: 1, count: 64)
        board[0] = 0  // one free cell, but the hand holds a domino
        game.load(board: board, hand: [piece([(0, 0), (0, 1)]), nil, nil])
        XCTAssertFalse(game.alive)
    }

    func testPlacementThatStrandsTheHandEndsTheRun() {
        let game = BlockFitGame(seed: 5)
        // Checkerboard: single holes everywhere, no line completable, and no
        // open 3×3 region for the second piece.
        var board = emptyBoard()
        for r in 0..<8 {
            for c in 0..<8 where (r + c).isMultiple(of: 2) { board[r * 8 + c] = 1 }
        }
        let single = piece([(0, 0)], id: 1)
        let square3 = piece((0..<3).flatMap { r in (0..<3).map { (r, $0) } }, id: 2)
        game.load(board: board, hand: [single, square3, nil])
        XCTAssertTrue(game.alive, "the 1×1 still fits, so the run is live")

        let placement = game.place(handIndex: 0, atRow: 0, col: 1)

        XCTAssertNotNil(placement)
        XCTAssertEqual(placement?.lines, 0)
        XCTAssertFalse(game.alive, "only the 3×3 remains and it fits nowhere")
    }
}
