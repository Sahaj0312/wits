//
//  WaterSort.swift
//  wits
//
//  Liquid-sorting engine. Tubes hold four units of colour; a pour moves the
//  top run onto a matching colour or into an empty tube. Every level is a
//  fresh random deal whose exact minimum pour count is found with A* before
//  the board is served, so puzzles never repeat and par is honest.
//
//  Pure computation (no SwiftUI): the screen lives in WaterSortScreen.swift,
//  and this file compiles standalone in the scratchpad -O profiling harness.
//

import Foundation

nonisolated struct WaterSortSpec: Equatable {
    let colors: Int
    let extraTubes: Int
    let capacity: Int
    let targetPar: Int

    var tubeCount: Int { colors + extraTubes }
}

nonisolated enum WaterSortEngine {
    /// One tube, bottom → top. Values are 1-based colour indices; capacity 4.
    typealias Tube = [UInt8]

    // MARK: Rules

    /// Complete = full of a single colour.
    static func isComplete(_ tube: Tube, capacity: Int) -> Bool {
        tube.count == capacity && tube.dropFirst().allSatisfy { $0 == tube[0] }
    }

    static func isSolved(_ tubes: [Tube], capacity: Int) -> Bool {
        tubes.allSatisfy { $0.isEmpty || isComplete($0, capacity: capacity) }
    }

    /// The colour on top and how many consecutive units of it sit there.
    static func topRun(_ tube: Tube) -> (color: UInt8, count: Int)? {
        guard let top = tube.last else { return nil }
        var count = 0
        for value in tube.reversed() {
            guard value == top else { break }
            count += 1
        }
        return (top, count)
    }

    static func canPour(_ tubes: [Tube], from: Int, to: Int, capacity: Int) -> Bool {
        guard from != to, let run = topRun(tubes[from]), tubes[to].count < capacity else { return false }
        return tubes[to].isEmpty || tubes[to].last == run.color
    }

    /// Pours as much of the top run as fits; the remainder stays. One pour is
    /// one move regardless of how many units travel.
    @discardableResult
    static func pour(_ tubes: inout [Tube], from: Int, to: Int, capacity: Int) -> Int {
        guard canPour(tubes, from: from, to: to, capacity: capacity),
              let run = topRun(tubes[from]) else { return 0 }
        let moved = min(run.count, capacity - tubes[to].count)
        tubes[from].removeLast(moved)
        tubes[to].append(contentsOf: Array(repeating: run.color, count: moved))
        return moved
    }

    // MARK: Canonical key

    /// Tube order never matters, so states are canonical by sorted packed
    /// tubes: 4 bits per unit plus the fill count on top.
    static func key(_ tubes: [Tube]) -> [UInt32] {
        var packed = tubes.map { tube in
            var value = UInt32(tube.count) << 16
            for (slot, color) in tube.enumerated() {
                value |= UInt32(color) << (slot * 4)
            }
            return value
        }
        packed.sort()
        return packed
    }

    // MARK: Optimal solve (A*)

    /// Segments above the solved baseline. A pour merges at most one colour
    /// run into another, so this never overestimates, admissible and
    /// consistent, which keeps the A* below exact without reopening.
    private static func heuristic(_ tubes: [Tube]) -> Int {
        var segments = 0
        var present = Set<UInt8>()
        for tube in tubes {
            var previous: UInt8 = 0
            for value in tube {
                present.insert(value)
                if value != previous { segments += 1; previous = value }
            }
        }
        return max(0, segments - present.count)
    }

    /// Solver neighbours prune pours a shortest solution never needs: pouring
    /// out of a finished tube, shuffling a single-colour tube into an empty,
    /// and duplicate empty destinations (all empties are interchangeable).
    private static func neighbors(_ tubes: [Tube], capacity: Int) -> [[Tube]] {
        var result: [[Tube]] = []
        let firstEmpty = tubes.firstIndex(where: \.isEmpty)
        for from in tubes.indices {
            guard let run = topRun(tubes[from]), !isComplete(tubes[from], capacity: capacity) else { continue }
            let sourceIsMono = run.count == tubes[from].count
            for to in tubes.indices where to != from {
                if tubes[to].isEmpty {
                    guard to == firstEmpty, !sourceIsMono else { continue }
                } else {
                    guard tubes[to].last == run.color, tubes[to].count < capacity else { continue }
                }
                var next = tubes
                pour(&next, from: from, to: to, capacity: capacity)
                result.append(next)
            }
        }
        return result
    }

    private struct OpenNode {
        let f: Int
        let g: Int
        let tubes: [Tube]
    }

    /// Exact minimum pours to solve, or nil when unsolvable or the search
    /// outgrows the cap (the generator rejects those deals).
    static func solve(_ tubes: [Tube], capacity: Int, nodeCap: Int = 200_000) -> Int? {
        if isSolved(tubes, capacity: capacity) { return 0 }

        // Binary min-heap on (f, then deeper g first, ties resolve toward
        // finished plans, which cuts expansions roughly in half).
        var heap: [OpenNode] = []
        func push(_ node: OpenNode) {
            heap.append(node)
            var child = heap.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                let c = heap[child], p = heap[parent]
                guard c.f < p.f || (c.f == p.f && c.g > p.g) else { break }
                heap.swapAt(child, parent)
                child = parent
            }
        }
        func pop() -> OpenNode? {
            guard let top = heap.first else { return nil }
            heap[0] = heap[heap.count - 1]
            heap.removeLast()
            var parent = 0
            while true {
                let left = parent * 2 + 1, right = left + 1
                var best = parent
                if left < heap.count,
                   heap[left].f < heap[best].f || (heap[left].f == heap[best].f && heap[left].g > heap[best].g) { best = left }
                if right < heap.count,
                   heap[right].f < heap[best].f || (heap[right].f == heap[best].f && heap[right].g > heap[best].g) { best = right }
                guard best != parent else { break }
                heap.swapAt(parent, best)
                parent = best
            }
            return top
        }

        var bestG: [[UInt32]: Int] = [key(tubes): 0]
        push(OpenNode(f: heuristic(tubes), g: 0, tubes: tubes))
        var expanded = 0

        while let node = pop() {
            expanded += 1
            if expanded > nodeCap { return nil }
            if let recorded = bestG[key(node.tubes)], recorded < node.g { continue }
            for next in neighbors(node.tubes, capacity: capacity) {
                let g = node.g + 1
                let k = key(next)
                if let seen = bestG[k], seen <= g { continue }
                bestG[k] = g
                if isSolved(next, capacity: capacity) { return g }
                push(OpenNode(f: g + heuristic(next), g: g, tubes: next))
            }
        }
        return nil
    }

    // MARK: Level ladder

    /// Frozen exam spec per map level (1...40). Colour count sets the tray;
    /// the par target picks among random deals inside the band, stepping
    /// sideways-then-up like the other ladders. Each band's ramp spans the
    /// natural optimal range of random deals at that colour count (profiled
    /// with the -O harness: 4 colours ≈ 8–13, 5 ≈ 11–18, 6 ≈ 13–20,
    /// 7 ≈ 18–24, 8 ≈ 21–28) so the generator can honestly hit the target.
    static func spec(forMapLevel level: Int) -> WaterSortSpec {
        let n = min(max(level, 1), 40)
        switch n {
        case ...2:
            return WaterSortSpec(colors: 3, extraTubes: 2, capacity: 4, targetPar: 6 + n)          // 7...8
        case ...8:
            return WaterSortSpec(colors: 4, extraTubes: 2, capacity: 4, targetPar: 8 + (n - 3))    // 8...13
        case ...15:
            return WaterSortSpec(colors: 5, extraTubes: 2, capacity: 4, targetPar: 10 + (n - 8))   // 11...17
        case ...23:
            return WaterSortSpec(colors: 6, extraTubes: 2, capacity: 4, targetPar: 12 + (n - 15))  // 13...20
        case ...31:
            return WaterSortSpec(colors: 7, extraTubes: 2, capacity: 4, targetPar: 16 + (n - 23))  // 17...24
        default:
            return WaterSortSpec(colors: 8, extraTubes: 2, capacity: 4, targetPar: 19 + (n - 31))  // 20...28
        }
    }

    // MARK: Generation

    /// Every colour appears exactly `capacity` times, dealt at random into the
    /// first `colors` tubes; the extras start empty.
    static func randomDeal<R: RandomNumberGenerator>(_ spec: WaterSortSpec, using rng: inout R) -> [Tube] {
        var units: [UInt8] = []
        for color in 1...spec.colors {
            units.append(contentsOf: Array(repeating: UInt8(color), count: spec.capacity))
        }
        units.shuffle(using: &rng)
        var tubes: [Tube] = []
        for index in 0..<spec.colors {
            tubes.append(Array(units[(index * spec.capacity)..<((index + 1) * spec.capacity)]))
        }
        tubes.append(contentsOf: Array(repeating: [], count: spec.extraTubes))
        return tubes
    }

    static func generate(mapLevel: Int, attempts: Int = 14) -> (tubes: [Tube], par: Int, spec: WaterSortSpec) {
        var rng = SystemRandomNumberGenerator()
        return generate(mapLevel: mapLevel, attempts: attempts, using: &rng)
    }

    static func generate(mapLevel: Int, seed: UInt64, attempts: Int = 14) -> (tubes: [Tube], par: Int, spec: WaterSortSpec) {
        var rng = SeededRandomNumberGenerator(seed: seed)
        return generate(mapLevel: mapLevel, attempts: attempts, using: &rng)
    }

    /// Deal, solve, repeat: serve the deal whose exact par lands closest to
    /// the level's target (ties prefer the deeper puzzle). Unsolvable deals
    /// and searches that outgrow the cap are simply rejected.
    static func generate<R: RandomNumberGenerator>(mapLevel: Int,
                                                   attempts: Int,
                                                   using rng: inout R) -> (tubes: [Tube], par: Int, spec: WaterSortSpec) {
        let spec = spec(forMapLevel: mapLevel)
        var best: (tubes: [Tube], par: Int)?
        for _ in 0..<attempts {
            let deal = randomDeal(spec, using: &rng)
            guard !isSolved(deal, capacity: spec.capacity),
                  let par = solve(deal, capacity: spec.capacity), par >= 2 else { continue }
            if par == spec.targetPar { return (deal, par, spec) }
            let gap = abs(par - spec.targetPar)
            if let current = best {
                let currentGap = abs(current.par - spec.targetPar)
                if gap < currentGap || (gap == currentGap && par > current.par) { best = (deal, par) }
            } else {
                best = (deal, par)
            }
        }
        if let best { return (best.tubes, best.par, spec) }
        // Unreachable in practice; serve a two-pour tray so a run can never
        // fail to start.
        var tubes: [Tube] = [[1, 1, 2, 2], [2, 2], [1, 1], []]
        tubes.append(contentsOf: Array(repeating: [], count: max(0, spec.tubeCount - tubes.count)))
        let par = solve(tubes, capacity: spec.capacity) ?? 2
        return (tubes, par, spec)
    }
}
