//
//  MahjongTests.swift
//  witsTests
//
//  Mahjong engine: scrambled-layout validity (parity, collisions, support),
//  freeness rules, reverse-play generation (guaranteed-solvable deals
//  verified by replaying the returned solution), face-count invariants,
//  quad-share plans, and seeded determinism.
//

import XCTest
@testable import wits

final class MahjongTests: XCTestCase {

    // MARK: Scrambled layouts

    func testGeneratedBoardsAreStructurallyValid() {
        for level in [1, 6, 12, 18, 26, 35, 40] {
            for seed: UInt64 in [1, 99, 4242] {
                let (tiles, _, spec) = MahjongEngine.generate(mapLevel: level, seed: seed)
                let slots = tiles.map(\.slot)

                XCTAssertEqual(slots.count, spec.tileCount,
                               "level \(level) seed \(seed): board must hold the spec's tiles")
                XCTAssertTrue(slots.count.isMultiple(of: 2))
                XCTAssertEqual(Set(slots).count, slots.count,
                               "level \(level) seed \(seed): duplicate slots")

                // Big-tile bounds: never wider than 5 tiles — depth, not sprawl.
                XCTAssertLessThanOrEqual(slots.map(\.x).max() ?? 0, 8)
                XCTAssertGreaterThanOrEqual(slots.map(\.x).min() ?? 0, 0)

                // No two tiles on the same layer overlap (tiles span 2×2).
                for i in slots.indices {
                    for j in (i + 1)..<slots.count where slots[i].z == slots[j].z {
                        let collides = abs(slots[i].x - slots[j].x) < 2 && abs(slots[i].y - slots[j].y) < 2
                        XCTAssertFalse(collides,
                                       "level \(level) seed \(seed): \(slots[i]) and \(slots[j]) collide")
                    }
                }

                // Every raised tile rests on at least one tile below it.
                for slot in slots where slot.z > 0 {
                    let supported = slots.contains {
                        $0.z == slot.z - 1 && abs($0.x - slot.x) < 2 && abs($0.y - slot.y) < 2
                    }
                    XCTAssertTrue(supported, "level \(level) seed \(seed): floating tile at \(slot)")
                }
            }
        }
    }

    func testScrambledBoardsVaryBetweenRuns() {
        let a = MahjongEngine.generate(mapLevel: 12, seed: 1).tiles.map(\.slot)
        let b = MahjongEngine.generate(mapLevel: 12, seed: 2).tiles.map(\.slot)
        XCTAssertNotEqual(Set(a), Set(b), "different seeds should scramble different boards")
    }

    func testLadderGrowsWithLevel() {
        let small = MahjongEngine.spec(forMapLevel: 1)
        let big = MahjongEngine.spec(forMapLevel: 40)
        XCTAssertLessThan(small.tileCount, big.tileCount)
        XCTAssertLessThan(small.layers, big.layers, "big boards go up, not out")
        // In the rack game duplicates make matching easier, so difficulty
        // means MORE variety (fewer quads); the rack is always the Vita 4.
        XCTAssertGreaterThan(small.quadShare, big.quadShare)
        XCTAssertEqual(small.traySlots, 4)
        XCTAssertEqual(big.traySlots, 4)
    }

    // MARK: Freeness

    func testFreenessRules() {
        // Three tiles in a row: ends are free, the middle is side-blocked.
        let row = [MahjongSlot(x: 0, y: 0, z: 0),
                   MahjongSlot(x: 2, y: 0, z: 0),
                   MahjongSlot(x: 4, y: 0, z: 0)]
        let all = Set(row.indices)
        XCTAssertTrue(MahjongEngine.isFree(0, slots: row, present: all))
        XCTAssertFalse(MahjongEngine.isFree(1, slots: row, present: all))
        XCTAssertTrue(MahjongEngine.isFree(2, slots: row, present: all))

        // Removing an end frees the middle.
        XCTAssertTrue(MahjongEngine.isFree(1, slots: row, present: [1, 2]))
    }

    func testStraddlingTileCoversBothBelow() {
        let slots = [MahjongSlot(x: 0, y: 0, z: 0),
                     MahjongSlot(x: 2, y: 0, z: 0),
                     MahjongSlot(x: 1, y: 0, z: 1)]   // straddles both base tiles
        let all = Set(slots.indices)
        XCTAssertFalse(MahjongEngine.isFree(0, slots: slots, present: all))
        XCTAssertFalse(MahjongEngine.isFree(1, slots: slots, present: all))
        XCTAssertTrue(MahjongEngine.isFree(2, slots: slots, present: all))
    }

    // MARK: Face plans

    func testFacePlanCountsAndQuadShare() {
        // 18 pairs at 0 quads → 18 distinct faces, one pair each.
        let flat = MahjongEngine.facePlan(pairs: 18, quadShare: 0)
        XCTAssertEqual(flat.count, 18)
        XCTAssertEqual(Set(flat).count, 18)

        // High quad share folds pairs into quads but never exceeds the catalog.
        let quads = MahjongEngine.facePlan(pairs: 31, quadShare: 0.9)
        XCTAssertEqual(quads.count, 31)
        let counts = Dictionary(grouping: quads, by: { $0 }).mapValues(\.count)
        XCTAssertTrue(counts.values.allSatisfy { $0 == 1 || $0 == 2 },
                      "a face is dealt as one pair or one quad, never more")
        XCTAssertTrue(counts.values.contains(2), "high quad share must actually produce quads")
        XCTAssertLessThanOrEqual(counts.count, MahjongEngine.catalog.count)
    }

    // MARK: Generation

    func testGeneratedDealsAreSolvableAtEveryBand() {
        for level in [1, 6, 12, 18, 26, 35, 40] {
            for seed: UInt64 in [1, 99, 4242] {
                let (tiles, solution, spec) = MahjongEngine.generate(mapLevel: level, seed: seed)
                let slots = tiles.map(\.slot)

                // Every face appears an even number of times (pairs or quads).
                let counts = Dictionary(grouping: tiles, by: \.face).mapValues(\.count)
                XCTAssertTrue(counts.values.allSatisfy { $0 == 2 || $0 == 4 },
                              "level \(level) seed \(seed): face counts must be 2 or 4")
                XCTAssertEqual(solution.count, spec.tileCount / 2)

                // Replay the returned solution: every step must remove two
                // free, identical tiles, and the board must end empty.
                var present = Set(tiles.indices)
                for (a, b) in solution {
                    XCTAssertEqual(tiles[a].face, tiles[b].face,
                                   "level \(level) seed \(seed): solution pairs different faces")
                    XCTAssertTrue(MahjongEngine.isFree(a, slots: slots, present: present),
                                  "level \(level) seed \(seed): solution removes a blocked tile")
                    XCTAssertTrue(MahjongEngine.isFree(b, slots: slots, present: present),
                                  "level \(level) seed \(seed): solution removes a blocked tile")
                    present.remove(a)
                    present.remove(b)
                }
                XCTAssertTrue(present.isEmpty,
                              "level \(level) seed \(seed): solution must clear the board")
            }
        }
    }

    func testSeededDealsAreDeterministic() {
        let a = MahjongEngine.generate(mapLevel: 20, seed: 777)
        let b = MahjongEngine.generate(mapLevel: 20, seed: 777)
        XCTAssertEqual(a.tiles, b.tiles)

        let c = MahjongEngine.generate(mapLevel: 20, seed: 778)
        XCTAssertNotEqual(a.tiles, c.tiles,
                          "different seeds should produce different deals")
    }

    func testFallbackBoardNeverStrands() {
        // The flat brick board must deal on the first try for any rng state.
        let slots = MahjongEngine.fallbackSlots(count: 26)
        let plan = MahjongEngine.facePlan(pairs: 13, quadShare: 0.5)
        for seed: UInt64 in 1...20 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            XCTAssertNotNil(MahjongEngine.deal(slots: slots, pairFaces: plan, using: &rng),
                            "flat fallback stranded with seed \(seed)")
        }
    }

    func testHasAvailablePairDetection() {
        // Two tiles, same face, both free → a pair is available.
        let slots = [MahjongSlot(x: 0, y: 0, z: 0), MahjongSlot(x: 4, y: 0, z: 0)]
        let face = MahjongFace(suit: .dots, rank: 1)
        let pair = slots.indices.map { MahjongTile(id: $0, face: face, slot: slots[$0]) }
        XCTAssertTrue(MahjongEngine.hasAvailablePair(tiles: pair, present: Set(pair.indices)))

        // Different faces → stuck.
        let mixed = [MahjongTile(id: 0, face: face, slot: slots[0]),
                     MahjongTile(id: 1, face: MahjongFace(suit: .dots, rank: 2), slot: slots[1])]
        XCTAssertFalse(MahjongEngine.hasAvailablePair(tiles: mixed, present: Set(mixed.indices)))
    }

    func testIntroductionOrderCoversCatalogWithoutRepeats() {
        XCTAssertEqual(MahjongEngine.introduction.count, MahjongEngine.catalog.count)
        XCTAssertEqual(Set(MahjongEngine.introduction), Set(MahjongEngine.catalog))
    }
}
