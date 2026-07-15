//
//  NumberNestsTests.swift
//  witsTests
//
//  Arithmetic-cage generation: determinism, valid Latin squares, connected
//  cage coverage, target arithmetic, unique solutions, and level scaling.
//

import XCTest
@testable import wits

@MainActor
final class NumberNestsTests: XCTestCase {
    func testBoardSizeScalesAcrossDifficultyBands() {
        XCTAssertEqual(NumberNestsEngine.boardSize(mapLevel: 1), 3)
        XCTAssertEqual(NumberNestsEngine.boardSize(mapLevel: 5), 3)
        XCTAssertEqual(NumberNestsEngine.boardSize(mapLevel: 6), 4)
        XCTAssertEqual(NumberNestsEngine.boardSize(mapLevel: 15), 5)
        XCTAssertEqual(NumberNestsEngine.boardSize(mapLevel: 26), 6)
    }

    func testSeededGenerationIsDeterministic() {
        let first = NumberNestsEngine.generate(mapLevel: 14, seed: 867_5309)
        let second = NumberNestsEngine.generate(mapLevel: 14, seed: 867_5309)
        XCTAssertEqual(first, second)
    }

    func testGeneratedPuzzlesAreValidAndUniqueAcrossBands() {
        for level in [1, 8, 18, 30] {
            for seed in [UInt64(1), UInt64(42)] {
                let puzzle = NumberNestsEngine.generate(mapLevel: level, seed: seed)
                XCTAssertTrue(puzzle.isValidSolution(puzzle.solution),
                              "invalid solution at level \(level), seed \(seed)")
                XCTAssertEqual(NumberNestsEngine.solutionCount(for: puzzle), 1,
                               "puzzle must be unique at level \(level), seed \(seed)")
                assertCompleteConnectedCoverage(puzzle)
            }
        }
    }

    private func assertCompleteConnectedCoverage(_ puzzle: NumberNestsPuzzle,
                                                 file: StaticString = #filePath,
                                                 line: UInt = #line) {
        let allCells = puzzle.cages.flatMap(\.cells)
        XCTAssertEqual(allCells.count, puzzle.size * puzzle.size, file: file, line: line)
        XCTAssertEqual(Set(allCells).count, puzzle.size * puzzle.size, file: file, line: line)

        for cage in puzzle.cages {
            XCTAssertTrue(cage.accepts(cage.cells.map { puzzle.solution[$0.r][$0.c] }),
                          "cage \(cage.id) target does not match its solution",
                          file: file, line: line)
            var visited: Set<NumberNestPosition> = []
            var frontier = [cage.cells[0]]
            let cells = Set(cage.cells)
            while let current = frontier.popLast() {
                guard visited.insert(current).inserted else { continue }
                let neighbours = [NumberNestPosition(r: current.r - 1, c: current.c),
                                  NumberNestPosition(r: current.r + 1, c: current.c),
                                  NumberNestPosition(r: current.r, c: current.c - 1),
                                  NumberNestPosition(r: current.r, c: current.c + 1)]
                frontier.append(contentsOf: neighbours.filter { cells.contains($0) && !visited.contains($0) })
            }
            XCTAssertEqual(visited, cells, "cage \(cage.id) is disconnected", file: file, line: line)
        }
    }
}
