import XCTest
@testable import wits

final class CrosswordTests: XCTestCase {
    func testGeneratedPuzzlesAreValidAcrossDifficultyBands() {
        for level in [1, 13, 29, 40] {
            for seed: UInt64 in [1, 7, 42] {
                let puzzle = CrosswordEngine.generate(mapLevel: level, seed: seed)
                assertValid(puzzle, context: "level \(level), seed \(seed)")
            }
        }
    }

    func testFallbackPuzzlesAreValidAndDeterministic() {
        for level in [1, 13, 29, 40] {
            var solutions = Set<String>()
            for seed: UInt64 in 0..<6 {
                let first = CrosswordEngine.generate(mapLevel: level,
                                                     seed: seed,
                                                     searchBudget: .zero)
                let second = CrosswordEngine.generate(mapLevel: level,
                                                      seed: seed,
                                                      searchBudget: .zero)
                assertValid(first, context: "fallback level \(level), seed \(seed)")
                XCTAssertEqual(first.solution, second.solution)
                XCTAssertEqual(first.words.map(\.answer), second.words.map(\.answer))
                solutions.insert(first.solution.flatMap { $0 }.joined(separator: "|"))
            }
            XCTAssertGreaterThan(solutions.count, 1,
                                 "fallback selection should still provide board variety")
        }
    }

    /// Open runs of two or more cells, matching the engine's slot scan.
    private func slotCount(in isBlock: [[Bool]]) -> Int {
        let size = isBlock.count
        var count = 0
        for isAcross in [true, false] {
            for major in 0..<size {
                var run = 0
                for minor in 0...size {
                    let open: Bool
                    if minor < size {
                        open = isAcross ? !isBlock[major][minor] : !isBlock[minor][major]
                    } else {
                        open = false
                    }
                    if open {
                        run += 1
                    } else {
                        if run >= 2 { count += 1 }
                        run = 0
                    }
                }
            }
        }
        return count
    }

    private func assertValid(_ puzzle: CrosswordPuzzle,
                             context: String,
                             file: StaticString = #filePath,
                             line: UInt = #line) {
        XCTAssertEqual(puzzle.size, 5, context, file: file, line: line)
        XCTAssertEqual(puzzle.isBlock.count, puzzle.size, context, file: file, line: line)
        XCTAssertEqual(puzzle.solution.count, puzzle.size, context, file: file, line: line)
        XCTAssertEqual(puzzle.words.count, slotCount(in: puzzle.isBlock),
                       context, file: file, line: line)
        XCTAssertGreaterThanOrEqual(puzzle.words.count, 6, context, file: file, line: line)
        XCTAssertEqual(Set(puzzle.words.map(\.id)).count, puzzle.words.count,
                       context, file: file, line: line)

        for r in 0..<puzzle.size {
            XCTAssertEqual(puzzle.isBlock[r].count, puzzle.size, context, file: file, line: line)
            XCTAssertEqual(puzzle.solution[r].count, puzzle.size, context, file: file, line: line)
            for c in 0..<puzzle.size {
                XCTAssertEqual(puzzle.solution[r][c].isEmpty, puzzle.isBlock[r][c],
                               context, file: file, line: line)
            }
        }

        for word in puzzle.words {
            let answer = word.cells.map { puzzle.solution[$0.r][$0.c] }.joined()
            XCTAssertEqual(answer, word.answer, "\(context), \(word.id)", file: file, line: line)
            XCTAssertFalse(word.clue.isEmpty, "\(context), \(word.id)", file: file, line: line)
        }
    }
}
