//
//  RandomnessTests.swift
//  witsTests
//
//  Seeded procedural engines remain reproducible for tests and diagnostics.
//

import XCTest
@testable import wits

final class RandomnessTests: XCTestCase {
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
