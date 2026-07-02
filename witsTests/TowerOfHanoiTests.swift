//
//  TowerOfHanoiTests.swift
//  witsTests
//
//  Random-state Hanoi generator: legality of dealt states, exactness of the
//  BFS optimal, and the campaign's requested-distance contract.
//

import XCTest
@testable import wits

final class TowerOfHanoiTests: XCTestCase {

    func testEncodeDecodeRoundTrip() {
        for disks in 1...6 {
            for _ in 0..<20 {
                let code = Int.random(in: 0..<HanoiGenerator.pow3(disks))
                XCTAssertEqual(HanoiGenerator.encode(HanoiGenerator.decode(code, disks: disks)), code)
            }
        }
    }

    func testNeighborsAreSymmetric() {
        let disks = 4
        for code in 0..<HanoiGenerator.pow3(disks) {
            for next in HanoiGenerator.neighbors(of: code, disks: disks) {
                XCTAssertTrue(HanoiGenerator.neighbors(of: next, disks: disks).contains(code),
                              "move \(code) -> \(next) is not reversible")
            }
        }
    }

    func testBfsMatchesClassicHanoiDistance() {
        // Full stack on peg 0 to full stack on peg 2 must cost 2^n - 1.
        for disks in 2...6 {
            let goal = HanoiGenerator.encode([Int](repeating: 2, count: disks))
            let start = HanoiGenerator.encode([Int](repeating: 0, count: disks))
            let distances = HanoiGenerator.bfs(from: goal, disks: disks)
            XCTAssertEqual(distances[start], (1 << disks) - 1)
        }
    }

    func testGeneratedPuzzleOptimalIsExact() {
        for _ in 0..<25 {
            let disks = Int.random(in: 3...6)
            let target = Int.random(in: 2...((1 << disks) - 1))
            let puzzle = HanoiGenerator.puzzle(disks: disks, targetDistance: target)
            XCTAssertNotEqual(puzzle.start, puzzle.goal)
            XCTAssertLessThanOrEqual(puzzle.optimal, target)
            let distances = HanoiGenerator.bfs(from: HanoiGenerator.encode(puzzle.goal), disks: disks)
            XCTAssertEqual(distances[HanoiGenerator.encode(puzzle.start)], puzzle.optimal)
        }
    }

    func testGeneratorHitsRequestedCampaignDistances() {
        // The campaign ladder's contract: every (disks, moves) rung should be
        // dealt at the exact requested distance essentially always, thanks to
        // the goal re-roll. Spot-check the top rung of each band.
        let rungs: [(disks: Int, moves: Int)] = [(3, 7), (4, 15), (5, 30), (6, 40)]
        for rung in rungs {
            var hits = 0
            for _ in 0..<10 {
                let puzzle = HanoiGenerator.puzzle(disks: rung.disks, targetDistance: rung.moves)
                if puzzle.optimal == rung.moves { hits += 1 }
            }
            XCTAssertGreaterThanOrEqual(hits, 8, "disks \(rung.disks): only \(hits)/10 deals reached \(rung.moves) moves")
        }
    }

    func testStacksFromAssignmentAreLegal() {
        for _ in 0..<20 {
            let disks = Int.random(in: 3...6)
            let assignment = (0..<disks).map { _ in Int.random(in: 0...2) }
            let stacks = HanoiPuzzle.stacks(from: assignment)
            XCTAssertEqual(stacks.flatMap(\.self).sorted(), Array(1...disks))
            for stack in stacks {
                XCTAssertEqual(stack, stack.sorted(by: >), "disks on a peg must be ordered largest to smallest")
            }
        }
    }
}
