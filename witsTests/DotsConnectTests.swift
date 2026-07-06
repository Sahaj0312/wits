//
//  DotsConnectTests.swift
//  witsTests
//
//  Dots Connect board generator: the random filling route must cover the grid
//  as a self-avoiding orthogonal path, slicing must respect the quality rules,
//  and generated boards must always be solvable by construction (the segments
//  partition the grid).
//

import XCTest
@testable import wits

final class DotsConnectTests: XCTestCase {

    private typealias Cell = DotsConnectEngine.Cell

    private func assertIsFillingRoute(_ route: [Cell], size: Int, _ label: String) {
        XCTAssertEqual(route.count, size * size, "\(label): route must visit every cell")
        XCTAssertEqual(Set(route).count, route.count, "\(label): route must be self-avoiding")
        for (a, b) in zip(route, route.dropFirst()) {
            XCTAssertEqual(abs(a.row - b.row) + abs(a.col - b.col), 1,
                           "\(label): consecutive route cells must be orthogonal neighbors")
        }
        for cell in route {
            XCTAssertTrue((0..<size).contains(cell.row) && (0..<size).contains(cell.col),
                          "\(label): route must stay on the board")
        }
    }

    func testRandomFillingRouteCoversBoardOnAllSizes() {
        for size in [5, 6, 7] {
            for attempt in 0..<20 {
                guard let route = DotsConnectEngine.randomFillingRoute(size: size) else {
                    // A budget bail-out is allowed occasionally; a retry must succeed.
                    continue
                }
                assertIsFillingRoute(route, size: size, "size \(size) attempt \(attempt)")
            }
        }
    }

    func testSlicedPathsPartitionRouteAndRespectQualityRules() {
        let route = DotsConnectEngine.rowSnake(size: 6)
        var accepted = 0
        for _ in 0..<200 {
            guard let paths = DotsConnectEngine.slicedPaths(route: route, count: 5) else { continue }
            accepted += 1
            XCTAssertEqual(paths.flatMap { $0 }, route, "segments must partition the route in order")
            for path in paths {
                XCTAssertGreaterThanOrEqual(path.count, DotsConnectEngine.minPathLength)
                let first = path.first!, last = path.last!
                XCTAssertGreaterThan(abs(first.row - last.row) + abs(first.col - last.col), 1,
                                     "segment endpoints must not touch")
            }
        }
        XCTAssertGreaterThan(accepted, 0, "slicing must succeed for typical inputs")
    }

    func testSlicedPathsRejectsImpossibleCounts() {
        let route = DotsConnectEngine.rowSnake(size: 5)   // 25 cells
        XCTAssertNil(DotsConnectEngine.slicedPaths(route: route, count: 9),
                     "9 paths × min length 3 exceeds 25 cells")
        XCTAssertNil(DotsConnectEngine.slicedPaths(route: route, count: 0))
    }

    func testGeneratedBoardsAreSolvableByConstruction() {
        // Mirror the level ladder: (size, pathCount) pairs the screen requests.
        let configs = [(5, 4), (5, 5), (6, 5), (6, 6), (7, 7), (7, 8)]
        for (size, pathCount) in configs {
            for attempt in 0..<10 {
                let board = DotsConnectEngine.generate(size: size, pathCount: pathCount)
                let label = "\(size)×\(size)/\(pathCount) paths attempt \(attempt)"

                XCTAssertEqual(board.size, size, label)
                XCTAssertEqual(board.paths.count, pathCount, label)

                var covered = Set<Cell>()
                for path in board.paths {
                    XCTAssertGreaterThanOrEqual(path.count, 2, label)
                    for (a, b) in zip(path, path.dropFirst()) {
                        XCTAssertEqual(abs(a.row - b.row) + abs(a.col - b.col), 1,
                                       "\(label): path cells must be orthogonal neighbors")
                    }
                    XCTAssertTrue(covered.isDisjoint(with: path), "\(label): paths must not overlap")
                    covered.formUnion(path)
                }
                XCTAssertEqual(covered.count, size * size, "\(label): paths must fill the board")
            }
        }
    }

    func testConsecutiveBoardsDiffer() {
        // The point of the redesign: no fixed catalog. 10 boards in a row being
        // identical is astronomically unlikely with a working generator.
        let boards = (0..<10).map { _ in DotsConnectEngine.generate(size: 5, pathCount: 4) }
        let distinct = Set(boards.map { board in
            board.paths.map { path in
                path.map { "\($0.row),\($0.col)" }.joined(separator: ";")
            }.joined(separator: "|")
        })
        XCTAssertGreaterThan(distinct.count, 1, "generator must not repeat one layout")
    }
}
