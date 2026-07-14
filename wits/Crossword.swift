//
//  Crossword.swift
//  wits
//
//  Mini-crossword engine. Every level is a fresh 5×5 grid: a block template
//  (randomly mirrored for variety) sets the shape, and a seeded backtracking
//  fill drops wits-original clue-bank words (CrosswordBank.swift) into the
//  slots — most-constrained slot first — so puzzles never repeat and every
//  fill is guaranteed valid. Difficulty comes from the shape (the "twist"
//  template doubles the five-letter crossings) and from biasing the fill
//  toward rarer vocabulary.
//
//  Both shipped templates were profiled against the bank in a standalone -O
//  harness: the staircase fills in ~800 nodes, the twist in ~4–9k, and both
//  succeeded on every tested seed. Fully open shapes (4+ five-slots on both
//  axes) need a far larger dictionary and are deliberately not used.
//
//  Pure computation (no SwiftUI): the screen lives in CrosswordScreen.swift.
//

import Foundation

nonisolated struct CrosswordCellPos: Hashable, Sendable {
    let r: Int
    let c: Int
}

nonisolated struct CrosswordWord: Identifiable, Sendable {
    let number: Int
    let isAcross: Bool
    let cells: [CrosswordCellPos]
    let answer: String
    let clue: String

    var id: String { "\(number)\(isAcross ? "A" : "D")" }
    var label: String { "\(number)\(isAcross ? "A" : "D")" }
}

nonisolated struct CrosswordPuzzle: Sendable {
    let size: Int
    let isBlock: [[Bool]]
    let numbers: [[Int]]        // 0 = unnumbered
    let words: [CrosswordWord]  // across by number, then down by number
    let solution: [[String]]    // "" on blocks
    let parSeconds: Double
}

nonisolated struct CrosswordSpec {
    let template: [String]
    let tierCap: Int
    /// -1 reaches for everyday words first, 0 is neutral, +1 reaches for
    /// rarer vocabulary first.
    let tierBias: Int
    let parSeconds: Double
}

nonisolated enum CrosswordEngine {

    // MARK: Level ladder

    /// The two verified 5×5 shapes. The staircase carries two five-letter
    /// answers; the twist carries four, so far more of the grid is
    /// double-crossed.
    static let stairTemplate = ["##...", "#....", ".....", "....#", "...##"]
    static let twistTemplate = ["##...", ".....", ".....", ".....", "...##"]

    /// Frozen exam spec per map level (1...40): shape, vocabulary reach, and
    /// a time par sized to the grid's difficulty.
    static func spec(forMapLevel level: Int) -> CrosswordSpec {
        let n = min(max(level, 1), 40)
        switch n {
        case ...5:
            return CrosswordSpec(template: stairTemplate, tierCap: 2, tierBias: 0, parSeconds: 100)
        case ...12:
            return CrosswordSpec(template: stairTemplate, tierCap: 2, tierBias: 0, parSeconds: 115)
        case ...19:
            return CrosswordSpec(template: twistTemplate, tierCap: 2, tierBias: 0, parSeconds: 160)
        case ...28:
            return CrosswordSpec(template: twistTemplate, tierCap: 2, tierBias: 0, parSeconds: 180)
        default:
            return CrosswordSpec(template: twistTemplate, tierCap: 3, tierBias: 1, parSeconds: 210)
        }
    }

    // MARK: Slots

    /// One run of open cells awaiting a word.
    private struct Slot {
        let isAcross: Bool
        let cells: [CrosswordCellPos]
    }

    private static func slots(in template: [String]) -> [Slot] {
        let size = template.count
        let rows = template.map(Array.init)
        var found: [Slot] = []

        func scan(isAcross: Bool) {
            for major in 0..<size {
                var run: [CrosswordCellPos] = []
                for minor in 0...size {
                    var open = false
                    if minor < size {
                        let (r, c) = isAcross ? (major, minor) : (minor, major)
                        open = rows[r][c] == "."
                    }
                    if open {
                        let (r, c) = isAcross ? (major, minor) : (minor, major)
                        run.append(CrosswordCellPos(r: r, c: c))
                    } else {
                        if run.count >= 2 { found.append(Slot(isAcross: isAcross, cells: run)) }
                        run = []
                    }
                }
            }
        }
        scan(isAcross: true)
        scan(isAcross: false)
        return found
    }

    /// Mirrored/flipped variants share the original's fill difficulty but
    /// read as different boards.
    private static func variant<R: RandomNumberGenerator>(of template: [String], using rng: inout R) -> [String] {
        var shaped = template
        if Bool.random(using: &rng) { shaped = shaped.map { String($0.reversed()) } }
        if Bool.random(using: &rng) { shaped = shaped.reversed() }
        return shaped
    }

    // MARK: Fill

    /// Fills the template's slots from the clue bank, most-constrained slot
    /// first, with a node budget so a doomed shuffle fails fast instead of
    /// thrashing. Returns nil only when the budget runs dry.
    private static func fill<R: RandomNumberGenerator>(
        template: [String],
        tierCap: Int,
        tierBias: Int,
        using rng: inout R
    ) -> [(slot: Slot, entry: CrosswordEntry)]? {
        let slots = slots(in: template)
        let size = template.count
        var grid = [UInt8](repeating: 0, count: size * size)
        var assigned = [Int](repeating: -1, count: slots.count)
        // Counts, not a set: a word also blocks its S-variants, and two
        // placed words may block the same string.
        var usedAnswers: [String: Int] = [:]
        var budget = 12_000

        // Per-slot candidate pools, shuffled once per attempt. The tier bias
        // is a WEAK noisy preference, never a strict ordering: front-loading
        // one tier funnels the whole search into that tier's subspace, and
        // the single-tier subspaces are too thin to fill from — a strict
        // sort here made easy levels hang for seconds in profiling.
        let pools: [[CrosswordEntry]] = slots.map { slot in
            var pool = (CrosswordBank.byLength[slot.cells.count] ?? [])
                .filter { $0.tier <= tierCap }
            pool.shuffle(using: &rng)
            if tierBias != 0 {
                let keys = pool.map { Double($0.tier) * Double(-tierBias) + Double.random(in: 0..<3.2, using: &rng) }
                pool = zip(pool, keys).sorted { $0.1 < $1.1 }.map(\.0)
            }
            return pool
        }
        let poolLetters: [[[UInt8]]] = pools.map { $0.map { Array($0.answer.utf8) } }
        let cellIndexes: [[Int]] = slots.map { $0.cells.map { $0.r * size + $0.c } }

        /// A word, its plural, and its singular all count as one root.
        func variants(of answer: String) -> [String] {
            var list = [answer, answer + "S"]
            if answer.hasSuffix("S") { list.append(String(answer.dropLast())) }
            return list
        }

        func fits(_ slot: Int, _ index: Int) -> Bool {
            // Letters first: a byte mismatch kills most candidates without
            // paying for the used-answer string lookup.
            let word = poolLetters[slot][index]
            let cells = cellIndexes[slot]
            for (offset, cell) in cells.enumerated() {
                let fixed = grid[cell]
                if fixed != 0 && fixed != word[offset] { return false }
            }
            return usedAnswers[pools[slot][index].answer, default: 0] == 0
        }

        /// Candidate count, stopping at `limit` — the MRV scan only needs to
        /// know whether a slot beats the current best.
        func candidateCount(for slot: Int, limit: Int) -> Int {
            var count = 0
            for index in poolLetters[slot].indices where fits(slot, index) {
                count += 1
                if count >= limit { return count }
            }
            return count
        }

        func candidateIndexes(for slot: Int) -> [Int] {
            poolLetters[slot].indices.filter { fits(slot, $0) }
        }

        func solve() -> Bool {
            budget -= 1
            if budget <= 0 { return false }

            // Most-constrained unassigned slot next.
            var bestSlot = -1
            var bestCount = Int.max
            for slot in slots.indices where assigned[slot] == -1 {
                let count = candidateCount(for: slot, limit: bestCount)
                if count == 0 { return false }
                if count < bestCount {
                    bestSlot = slot
                    bestCount = count
                }
            }
            if bestSlot == -1 { return true }
            let bestOptions = candidateIndexes(for: bestSlot)

            for option in bestOptions {
                let entry = pools[bestSlot][option]
                let word = poolLetters[bestSlot][option]
                assigned[bestSlot] = option
                for blocked in variants(of: entry.answer) { usedAnswers[blocked, default: 0] += 1 }
                var written: [Int] = []
                for (offset, cell) in cellIndexes[bestSlot].enumerated() where grid[cell] == 0 {
                    grid[cell] = word[offset]
                    written.append(cell)
                }
                if solve() { return true }
                assigned[bestSlot] = -1
                for blocked in variants(of: entry.answer) { usedAnswers[blocked]! -= 1 }
                for cell in written { grid[cell] = 0 }
                if budget <= 0 { return false }
            }
            return false
        }

        guard solve() else { return nil }
        return slots.indices.map { (slots[$0], pools[$0][assigned[$0]]) }
    }

    // MARK: Generation

    static func generate(mapLevel: Int, seed: UInt64) -> CrosswordPuzzle {
        var rng = SeededRandomNumberGenerator(seed: seed)
        return generate(mapLevel: mapLevel, using: &rng)
    }

    static func generate<R: RandomNumberGenerator>(mapLevel: Int, using rng: inout R) -> CrosswordPuzzle {
        let spec = spec(forMapLevel: mapLevel)

        // A few shuffled attempts on the target shape, then the staircase,
        // which filled on every profiled seed — a level must never fail to
        // load.
        for template in [spec.template, stairTemplate] {
            for _ in 0..<6 {
                let shaped = variant(of: template, using: &rng)
                if let filled = fill(template: shaped,
                                     tierCap: spec.tierCap,
                                     tierBias: spec.tierBias,
                                     using: &rng) {
                    return assemble(template: shaped, filled: filled, parSeconds: spec.parSeconds)
                }
            }
        }
        // Truly unreachable: an empty bank would be a build error, not a
        // runtime state. Fail loudly in development.
        fatalError("crossword generation exhausted every template")
    }

    private static func assemble(template: [String],
                                 filled: [(slot: Slot, entry: CrosswordEntry)],
                                 parSeconds: Double) -> CrosswordPuzzle {
        let size = template.count
        let rows = template.map(Array.init)
        let isBlock = rows.map { $0.map { $0 == "#" } }

        // Standard numbering: row-major, a cell numbers if it starts a word.
        var numbers = [[Int]](repeating: [Int](repeating: 0, count: size), count: size)
        var next = 1
        for r in 0..<size {
            for c in 0..<size where !isBlock[r][c] {
                let startsAcross = (c == 0 || isBlock[r][c - 1]) && c + 1 < size && !isBlock[r][c + 1]
                let startsDown = (r == 0 || isBlock[r - 1][c]) && r + 1 < size && !isBlock[r + 1][c]
                if startsAcross || startsDown {
                    numbers[r][c] = next
                    next += 1
                }
            }
        }

        var solution = [[String]](repeating: [String](repeating: "", count: size), count: size)
        var words: [CrosswordWord] = []
        for (slot, entry) in filled {
            let letters = Array(entry.answer)
            for (offset, cell) in slot.cells.enumerated() {
                solution[cell.r][cell.c] = String(letters[offset])
            }
            let head = slot.cells[0]
            words.append(CrosswordWord(number: numbers[head.r][head.c],
                                       isAcross: slot.isAcross,
                                       cells: slot.cells,
                                       answer: entry.answer,
                                       clue: entry.clue))
        }
        words.sort { a, b in
            if a.isAcross != b.isAcross { return a.isAcross }
            return a.number < b.number
        }

        return CrosswordPuzzle(size: size,
                               isBlock: isBlock,
                               numbers: numbers,
                               words: words,
                               solution: solution,
                               parSeconds: parSeconds)
    }
}
