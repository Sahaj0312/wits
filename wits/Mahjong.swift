//
//  Mahjong.swift
//  wits
//
//  Mahjong solitaire engine. Tiles stack in layers on a half-tile grid; a
//  tile is free when nothing rests on it and its left or right side is open,
//  and two free tiles with the same face clear together. Every level is a
//  fresh seeded deal built by reverse play — pairs are assigned in a legal
//  removal order — so every board served is guaranteed clearable.
//
//  Traditional tile faces (dots, bamboo, characters, winds, dragons) are
//  centuries-old public-domain iconography; the app draws its own renditions
//  in MahjongScreen.swift. Pure computation here, no SwiftUI.
//
//  Difficulty has two knobs: the layout (tile count and stacking depth) and
//  the share of faces dealt as quads. With every face at two copies a deal
//  can never dead-end (removals only free tiles); quads introduce the classic
//  trap of pairing the wrong two of four.
//

import Foundation

// MARK: - Faces

nonisolated enum MahjongSuit: String, CaseIterable, Sendable {
    case dots, bamboo, characters, winds, dragons
}

nonisolated struct MahjongFace: Hashable, Sendable {
    let suit: MahjongSuit
    let rank: Int      // dots/bamboo/characters 1...9, winds 1...4 (E S W N), dragons 1...3 (red green white)

    var accessibilityName: String {
        switch suit {
        case .dots: "\(rank) of dots"
        case .bamboo: "\(rank) of bamboo"
        case .characters: "\(rank) of characters"
        case .winds: ["east", "south", "west", "north"][max(0, min(3, rank - 1))] + " wind"
        case .dragons: ["red", "green", "white"][max(0, min(2, rank - 1))] + " dragon"
        }
    }
}

// MARK: - Board geometry

/// A tile slot on the stacking grid. Coordinates are half-tile units: a tile
/// occupies [x, x+2) × [y, y+2) on layer z, so slots offset by 1 straddle two
/// tiles of the layer below — the classic mahjong overlap.
nonisolated struct MahjongSlot: Hashable, Sendable {
    let x: Int
    let y: Int
    let z: Int
}

nonisolated struct MahjongTile: Identifiable, Equatable, Sendable {
    let id: Int
    let face: MahjongFace
    let slot: MahjongSlot
}

nonisolated struct MahjongSpec: Equatable, Sendable {
    /// Tiles on the board (always even).
    let tileCount: Int
    /// Stacking depth the scrambled layout may use.
    let layers: Int
    /// Fraction of pairs dealt as the second pair of a quad face. In the rack
    /// game more copies of a face mean easier matches, so difficulty LOWERS
    /// this: early boards repeat faces generously, late boards maximise
    /// variety.
    let quadShare: Double
    /// Rack capacity. Picked tiles wait here until their twin arrives; a full
    /// rack is out of space. Tighter racks demand deeper planning.
    let traySlots: Int
}

// MARK: - Engine

nonisolated enum MahjongEngine {

    // MARK: Face catalog

    /// Full catalog (no flowers/seasons — their group-match special rule adds
    /// noise, not signal).
    static let catalog: [MahjongFace] = {
        var faces: [MahjongFace] = []
        for rank in 1...9 { faces.append(MahjongFace(suit: .dots, rank: rank)) }
        for rank in 1...9 { faces.append(MahjongFace(suit: .bamboo, rank: rank)) }
        for rank in 1...9 { faces.append(MahjongFace(suit: .characters, rank: rank)) }
        for rank in 1...4 { faces.append(MahjongFace(suit: .winds, rank: rank)) }
        for rank in 1...3 { faces.append(MahjongFace(suit: .dragons, rank: rank)) }
        return faces
    }()

    /// Faces in the order levels introduce them: suits interleaved and
    /// same-suit neighbours (6 vs 9 dots) held back, so small boards stay
    /// visually distinct and big boards earn their scanning load.
    static let introduction: [MahjongFace] = {
        var faces: [MahjongFace] = []
        let honors: [MahjongFace] = [
            MahjongFace(suit: .dragons, rank: 1), MahjongFace(suit: .winds, rank: 1),
            MahjongFace(suit: .dragons, rank: 2), MahjongFace(suit: .winds, rank: 3),
            MahjongFace(suit: .dragons, rank: 3), MahjongFace(suit: .winds, rank: 2),
            MahjongFace(suit: .winds, rank: 4),
        ]
        var honorIndex = 0
        for rank in [1, 3, 5, 7, 9, 2, 4, 6, 8] {
            for suit in [MahjongSuit.dots, .characters, .bamboo] {
                faces.append(MahjongFace(suit: suit, rank: rank))
            }
            if honorIndex < honors.count {
                faces.append(honors[honorIndex])
                honorIndex += 1
            }
        }
        return faces
    }()

    // MARK: Level ladder

    /// Frozen exam spec per map level (1...40): bigger, deeper boards and more
    /// face variety (fewer quads). The rack is always 4 slots — the Vita
    /// pressure — and the scrambled layout is rolled fresh from the run's
    /// seed. Depth grows instead of footprint, so tiles stay big.
    static func spec(forMapLevel level: Int) -> MahjongSpec {
        switch min(max(level, 1), 40) {
        case ...4: MahjongSpec(tileCount: 16, layers: 2, quadShare: 0.60, traySlots: 4)
        case ...9: MahjongSpec(tileCount: 26, layers: 2, quadShare: 0.50, traySlots: 4)
        case ...15: MahjongSpec(tileCount: 36, layers: 3, quadShare: 0.40, traySlots: 4)
        case ...22: MahjongSpec(tileCount: 42, layers: 3, quadShare: 0.25, traySlots: 4)
        case ...30: MahjongSpec(tileCount: 54, layers: 4, quadShare: 0.10, traySlots: 4)
        default: MahjongSpec(tileCount: 62, layers: 4, quadShare: 0, traySlots: 4)
        }
    }

    // MARK: Scrambled layouts

    /// Board footprint bounds (half-tile units): width ≤ 5 tiles and ~6 rows,
    /// so tiles render large; big boards go UP (more layers), not out.
    private static let maxX = 8
    private static let maxY = 10

    /// Grows an organic, Vita-style board: a ragged base blob built by
    /// attaching tiles at touching offsets (half-offsets included, so rows
    /// interlock instead of gridding up), then upper tiles scattered wherever
    /// something below supports them. Returns nil when the growth jams; the
    /// caller retries with fresh randomness.
    static func scrambledSlots<R: RandomNumberGenerator>(count: Int,
                                                         layers: Int,
                                                         using rng: inout R) -> [MahjongSlot]? {
        // Layer budgets: the base carries the most, but depth does real work
        // so the footprint (and therefore tile size) stays constant.
        let weights: [Double]
        switch layers {
        case ...1: weights = [1]
        case 2: weights = [0.68, 0.32]
        case 3: weights = [0.46, 0.32, 0.22]
        default: weights = [0.36, 0.27, 0.21, 0.16]
        }
        var budgets = weights.map { Int((Double(count) * $0).rounded(.down)) }
        budgets[0] += count - budgets.reduce(0, +)

        // Touching neighbour offsets for the base, half-offsets first so the
        // blob interlocks; a few gap-makers keep the edge ragged.
        let neighborOffsets: [(Int, Int)] = [
            (2, 0), (-2, 0), (0, 2), (0, -2),
            (2, 1), (2, -1), (-2, 1), (-2, -1),
            (1, 2), (-1, 2), (1, -2), (-1, -2),
            (2, 2), (-2, 2), (2, -2), (-2, -2),
            (3, 0), (-3, 0), (0, 3), (0, -3),
        ]

        var slots: [MahjongSlot] = [MahjongSlot(x: maxX / 2, y: maxY / 2, z: 0)]
        var attempts = 0

        func collides(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            slots.contains { $0.z == z && abs($0.x - x) < 2 && abs($0.y - y) < 2 }
        }

        // Base blob.
        while slots.count < budgets[0] {
            attempts += 1
            if attempts > 4_000 { return nil }
            guard let anchor = slots.filter({ $0.z == 0 }).randomElement(using: &rng) else { return nil }
            let offset = neighborOffsets[Int.random(in: 0..<neighborOffsets.count, using: &rng)]
            let x = anchor.x + offset.0
            let y = anchor.y + offset.1
            guard x >= 0, x <= maxX, y >= 0, y <= maxY, !collides(x, y, 0) else { continue }
            slots.append(MahjongSlot(x: x, y: y, z: 0))
        }

        // Upper layers: land anywhere a lower tile offers support, at any
        // half-offset, so stacks come out scattered rather than pyramided.
        for z in 1..<max(1, layers) where budgets.count > z {
            let lower = slots.filter { $0.z == z - 1 }
            var placed = 0
            while placed < budgets[z] {
                attempts += 1
                if attempts > 8_000 { return nil }
                guard let support = lower.randomElement(using: &rng) else { return nil }
                let x = support.x + Int.random(in: -1...1, using: &rng)
                let y = support.y + Int.random(in: -1...1, using: &rng)
                guard x >= 0, x <= maxX, y >= 0, y <= maxY, !collides(x, y, z) else { continue }
                slots.append(MahjongSlot(x: x, y: y, z: z))
                placed += 1
            }
        }

        // Compact to the origin so the screen can center the bounding box.
        let minX = slots.map(\.x).min() ?? 0
        let minY = slots.map(\.y).min() ?? 0
        return slots.map { MahjongSlot(x: $0.x - minX, y: $0.y - minY, z: $0.z) }
    }

    /// Last-resort board: flat brick-offset rows. Row ends are always free,
    /// so reverse-play dealing can never strand on it.
    static func fallbackSlots(count: Int) -> [MahjongSlot] {
        (0..<count).map { index in
            let row = index / 6
            let col = index % 6
            return MahjongSlot(x: col * 2 + (row.isMultiple(of: 2) ? 0 : 1),
                               y: row * 2,
                               z: 0)
        }
    }

    /// One face per pair (a quad face appears twice). Deterministic for a
    /// (pairs, quadShare) so a level's identity is stable; the deal shuffles.
    static func facePlan(pairs: Int, quadShare: Double) -> [MahjongFace] {
        let quadFaces = min(pairs / 2, Int(Double(pairs) * quadShare) / 2)
        let singleFaces = pairs - quadFaces * 2
        let chosen = Array(introduction.prefix(quadFaces + singleFaces))
        var plan: [MahjongFace] = []
        for (index, face) in chosen.enumerated() {
            plan.append(face)
            if index < quadFaces { plan.append(face) }
        }
        return plan
    }

    // MARK: Rules

    /// Free = nothing overlaps it on any layer above, and at least one of its
    /// sides (left or right) has no touching same-layer neighbour.
    static func isFree(_ index: Int, slots: [MahjongSlot], present: Set<Int>) -> Bool {
        let slot = slots[index]
        var leftBlocked = false
        var rightBlocked = false
        for other in present where other != index {
            let o = slots[other]
            if o.z > slot.z, abs(o.x - slot.x) < 2, abs(o.y - slot.y) < 2 { return false }
            if o.z == slot.z, abs(o.y - slot.y) < 2 {
                if o.x == slot.x - 2 { leftBlocked = true }
                if o.x == slot.x + 2 { rightBlocked = true }
            }
        }
        return !(leftBlocked && rightBlocked)
    }

    static func freeIndices(slots: [MahjongSlot], present: Set<Int>) -> [Int] {
        present.filter { isFree($0, slots: slots, present: present) }.sorted()
    }

    /// Whether any two free tiles share a face — false means the player is
    /// stuck (recoverable through undo).
    static func hasAvailablePair(tiles: [MahjongTile], present: Set<Int>) -> Bool {
        let slots = tiles.map(\.slot)
        let free = freeIndices(slots: slots, present: present)
        var seen = Set<MahjongFace>()
        for index in free {
            if seen.contains(tiles[index].face) { return true }
            seen.insert(tiles[index].face)
        }
        return false
    }

    // MARK: Generation

    /// Assign faces by playing the board in reverse: repeatedly pick two free
    /// slots, give them the next pair, remove them. The pick order is itself
    /// a full solution, so the deal is clearable by construction. Returns nil
    /// when the layout strands a lone free slot (the caller retries).
    static func deal<R: RandomNumberGenerator>(slots: [MahjongSlot],
                                               pairFaces: [MahjongFace],
                                               using rng: inout R) -> (tiles: [MahjongTile], solution: [(Int, Int)])? {
        precondition(pairFaces.count * 2 == slots.count, "layout size must be twice the pair count")
        var present = Set(slots.indices)
        var faceFor = [MahjongFace?](repeating: nil, count: slots.count)
        var solution: [(Int, Int)] = []
        var pairs = pairFaces
        pairs.shuffle(using: &rng)

        while !present.isEmpty {
            var free = freeIndices(slots: slots, present: present)
            guard free.count >= 2 else { return nil }
            let a = free.remove(at: Int.random(in: 0..<free.count, using: &rng))
            let b = free.remove(at: Int.random(in: 0..<free.count, using: &rng))
            let face = pairs.removeLast()
            faceFor[a] = face
            faceFor[b] = face
            present.remove(a)
            present.remove(b)
            solution.append((a, b))
        }

        let tiles = slots.indices.map { MahjongTile(id: $0, face: faceFor[$0]!, slot: slots[$0]) }
        // The pick order removed free pairs from the live board, exactly as a
        // player would — so it IS the forward solution, unreversed.
        return (tiles, solution)
    }

    static func generate(mapLevel: Int,
                         seed: UInt64) -> (tiles: [MahjongTile], solution: [(Int, Int)], spec: MahjongSpec) {
        var rng = SeededRandomNumberGenerator(seed: seed)
        let spec = spec(forMapLevel: mapLevel)
        let plan = facePlan(pairs: spec.tileCount / 2, quadShare: spec.quadShare)

        // Roll a scrambled board; if its shape strands the dealer, roll again.
        for _ in 0..<40 {
            guard let slots = scrambledSlots(count: spec.tileCount,
                                             layers: spec.layers,
                                             using: &rng) else { continue }
            for _ in 0..<20 {
                if let dealt = deal(slots: slots, pairFaces: plan, using: &rng) {
                    return (dealt.tiles, dealt.solution, spec)
                }
            }
        }
        // Unreachable in practice. The flat brick board can never strand.
        let flat = fallbackSlots(count: spec.tileCount)
        while true {
            if let dealt = deal(slots: flat, pairFaces: plan, using: &rng) {
                return (dealt.tiles, dealt.solution, spec)
            }
        }
    }
}
