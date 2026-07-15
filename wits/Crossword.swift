//
//  Crossword.swift
//  wits
//
//  Mini-crossword engine. Every level is a fresh 5×5 grid: a block template
//  (randomly mirrored for variety) sets the shape, and a seeded backtracking
//  fill drops wits-original clue-bank words (CrosswordBank.swift) into the
//  slots — most-constrained slot first. Difficulty comes from the shape (the
//  "twist" template doubles the five-letter crossings) and from biasing the
//  fill toward rarer vocabulary. A small set of prevalidated fills guarantees
//  startup if a randomized search reaches its short wall-clock budget.
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

    /// One letter shared by two slots. Keeping the offsets lets the solver
    /// shrink only the affected candidate domain when it places a word.
    private struct Crossing {
        let otherSlot: Int
        let ownOffset: Int
        let otherOffset: Int
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
    /// thrashing. Returns nil when the node/time budget runs dry or the task
    /// is cancelled.
    private static func fill<R: RandomNumberGenerator>(
        template: [String],
        tierCap: Int,
        tierBias: Int,
        deadline: ContinuousClock.Instant,
        using rng: inout R
    ) -> [(slot: Slot, entry: CrosswordEntry)]? {
        let slots = slots(in: template)
        var assigned = [Int](repeating: -1, count: slots.count)
        // Counts, not a set: a word also blocks its S-variants, and two
        // placed words may block the same string.
        var usedAnswers: [String: Int] = [:]
        var budget = 12_000
        var stopped = false

        // Per-length candidate pools, shuffled once per attempt. Slots of the
        // same length can safely share an ordering; rebuilding and sorting
        // the same 700-word pool for every slot was a large part of the load
        // delay in unoptimized builds. The tier bias
        // is a WEAK noisy preference, never a strict ordering: front-loading
        // one tier funnels the whole search into that tier's subspace, and
        // the single-tier subspaces are too thin to fill from — a strict
        // sort here made easy levels hang for seconds in profiling.
        var poolsByLength: [Int: [CrosswordEntry]] = [:]
        for length in Set(slots.map { $0.cells.count }) {
            var pool = (CrosswordBank.byLength[length] ?? [])
                .filter { $0.tier <= tierCap }
            pool.shuffle(using: &rng)
            if tierBias != 0 {
                let keys = pool.map { Double($0.tier) * Double(-tierBias) + Double.random(in: 0..<3.2, using: &rng) }
                pool = zip(pool, keys).sorted { $0.1 < $1.1 }.map(\.0)
            }
            poolsByLength[length] = pool
        }
        let pools = slots.map { poolsByLength[$0.cells.count] ?? [] }
        let poolLetters: [[[UInt8]]] = pools.map { $0.map { Array($0.answer.utf8) } }

        // Build the tiny crossing graph once. The old solver rescanned every
        // word in every unfilled slot at every search node; in an unoptimized
        // app build that turned a nominal 12k-node cap into minutes of work.
        // Domains below are filtered as crossings are fixed, so most later
        // nodes inspect only a handful of candidates.
        var uses: [CrosswordCellPos: [(slot: Int, offset: Int)]] = [:]
        for slot in slots.indices {
            for (offset, cell) in slots[slot].cells.enumerated() {
                uses[cell, default: []].append((slot, offset))
            }
        }
        var crossings = [[Crossing]](repeating: [], count: slots.count)
        for occupants in uses.values where occupants.count == 2 {
            let first = occupants[0]
            let second = occupants[1]
            crossings[first.slot].append(Crossing(otherSlot: second.slot,
                                                  ownOffset: first.offset,
                                                  otherOffset: second.offset))
            crossings[second.slot].append(Crossing(otherSlot: first.slot,
                                                   ownOffset: second.offset,
                                                   otherOffset: first.offset))
        }
        var domains: [[Int]] = poolLetters.map { Array($0.indices) }

        /// A word, its plural, and its singular all count as one root.
        func variants(of answer: String) -> [String] {
            var list = [answer, answer + "S"]
            if answer.hasSuffix("S") { list.append(String(answer.dropLast())) }
            return list
        }

        func isUnused(_ slot: Int, _ index: Int) -> Bool {
            return usedAnswers[pools[slot][index].answer, default: 0] == 0
        }

        /// Candidate count, stopping at `limit` — the MRV scan only needs to
        /// know whether a slot beats the current best.
        func candidateCount(for slot: Int, limit: Int) -> Int {
            var count = 0
            for index in domains[slot] where isUnused(slot, index) {
                count += 1
                if count >= limit { return count }
            }
            return count
        }

        func candidateIndexes(for slot: Int) -> [Int] {
            domains[slot].filter { isUnused(slot, $0) }
        }

        func solve() -> Bool {
            if stopped { return false }
            budget -= 1
            if budget <= 0 { return false }
            // Checking periodically keeps the hot recursion cheap while
            // enforcing a real wall-clock bound (and promptly honoring a
            // cancelled screen task).
            if budget.isMultiple(of: 64),
               (Task.isCancelled || ContinuousClock.now >= deadline) {
                stopped = true
                return false
            }

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

                // Forward-check just the words that cross this one. Save the
                // previous arrays so backtracking remains allocation-light
                // and deterministic for a given seed.
                var savedDomains: [(slot: Int, candidates: [Int])] = []
                var viable = true
                for crossing in crossings[bestSlot] where assigned[crossing.otherSlot] == -1 {
                    let other = crossing.otherSlot
                    let previous = domains[other]
                    let required = word[crossing.ownOffset]
                    let filtered = previous.filter {
                        poolLetters[other][$0][crossing.otherOffset] == required
                    }
                    if filtered.count != previous.count {
                        savedDomains.append((other, previous))
                        domains[other] = filtered
                    }
                    if filtered.isEmpty {
                        viable = false
                        break
                    }
                }

                if viable && solve() { return true }
                for saved in savedDomains.reversed() {
                    domains[saved.slot] = saved.candidates
                }
                assigned[bestSlot] = -1
                for blocked in variants(of: entry.answer) { usedAnswers[blocked]! -= 1 }
                if stopped || budget <= 0 { return false }
            }
            return false
        }

        guard solve() else { return nil }
        return slots.indices.map { (slots[$0], pools[$0][assigned[$0]]) }
    }

    // MARK: Generation

    static func generate(mapLevel: Int,
                         seed: UInt64,
                         searchBudget: Duration = .milliseconds(600)) -> CrosswordPuzzle {
        var rng = SeededRandomNumberGenerator(seed: seed)
        return generate(mapLevel: mapLevel,
                        using: &rng,
                        searchBudget: searchBudget,
                        fallbackSelector: seed)
    }

    static func generate<R: RandomNumberGenerator>(
        mapLevel: Int,
        using rng: inout R,
        searchBudget: Duration = .milliseconds(600)
    ) -> CrosswordPuzzle {
        generate(mapLevel: mapLevel,
                 using: &rng,
                 searchBudget: searchBudget,
                 fallbackSelector: 0)
    }

    private static func generate<R: RandomNumberGenerator>(
        mapLevel: Int,
        using rng: inout R,
        searchBudget: Duration,
        fallbackSelector: UInt64
    ) -> CrosswordPuzzle {
        let spec = spec(forMapLevel: mapLevel)
        let deadline = ContinuousClock.now.advanced(by: searchBudget)

        // Try the requested shape, then the easier staircase, but never keep
        // the player behind a spinner past the shared wall-clock budget.
        generation: for template in [spec.template, stairTemplate] {
            for _ in 0..<6 {
                guard !Task.isCancelled, ContinuousClock.now < deadline else {
                    break generation
                }
                let shaped = variant(of: template, using: &rng)
                if let filled = fill(template: shaped,
                                     tierCap: spec.tierCap,
                                     tierBias: spec.tierBias,
                                     deadline: deadline,
                                     using: &rng) {
                    return assemble(template: shaped, filled: filled, parSeconds: spec.parSeconds)
                }
            }
        }

        // A time budget, cancellation, or an unusually hostile shuffle can
        // all land here. These fills were generated from the same clue bank
        // and are assembled without search, so startup always completes.
        return fallbackPuzzle(for: spec, selector: fallbackSelector)
    }

    // MARK: Prevalidated fallback fills

    private struct FallbackFill {
        let template: [String]
        /// Across in row order, then down in column order (the same order as
        /// `slots(in:)`).
        let answers: [String]
    }

    private static let stairFallbacks = [
        FallbackFill(template: ["...##", "....#", ".....", "#....", "##..."],
                     answers: ["DIM", "AREA", "DOLLS", "NOSE", "NOW", "DAD", "IRON", "MELON", "ALSO", "SEW"]),
        FallbackFill(template: ["##...", "#....", ".....", "....#", "...##"],
                     answers: ["MUG", "TONE", "FRUIT", "EAST", "EYE", "FEE", "TRAY", "MOUSE", "UNIT", "GET"]),
        FallbackFill(template: ["...##", "....#", ".....", "#....", "##..."],
                     answers: ["ADD", "SOIL", "HOMES", "REAL", "SPY", "ASH", "DOOR", "DIMES", "LEAP", "SLY"]),
        FallbackFill(template: ["##...", "#....", ".....", "....#", "...##"],
                     answers: ["CUP", "ROPE", "BACON", "ICON", "TEA", "BIT", "RACE", "COCOA", "UPON", "PEN"]),
        FallbackFill(template: ["...##", "....#", ".....", "#....", "##..."],
                     answers: ["ATE", "PODS", "PAGES", "DEEP", "SKY", "APP", "TOAD", "EDGES", "SEEK", "SPY"]),
        FallbackFill(template: ["##...", "#....", ".....", "....#", "...##"],
                     answers: ["SIT", "TIDE", "DOZEN", "AREA", "YES", "DAY", "TORE", "SIZES", "IDEA", "TEN"])
    ]

    private static let twistFallbacks = [
        FallbackFill(template: ["##...", ".....", ".....", ".....", "...##"],
                     answers: ["MOB", "STOVE", "PANEL", "ALERT", "SLY", "SPAS", "TALL", "MONEY", "OVER", "BELT"]),
        FallbackFill(template: ["##...", ".....", ".....", ".....", "...##"],
                     answers: ["LOW", "SHAPE", "TUNES", "AGENT", "YES", "STAY", "HUGE", "LANES", "OPEN", "WEST"]),
        FallbackFill(template: ["##...", ".....", ".....", ".....", "...##"],
                     answers: ["MOB", "STOVE", "PANEL", "ALERT", "SKY", "SPAS", "TALK", "MONEY", "OVER", "BELT"]),
        FallbackFill(template: ["##...", ".....", ".....", ".....", "...##"],
                     answers: ["ROW", "STOVE", "TAPES", "ALERT", "YES", "STAY", "TALE", "ROPES", "OVER", "WEST"]),
        FallbackFill(template: ["##...", ".....", ".....", ".....", "...##"],
                     answers: ["COW", "STOVE", "NAMES", "ALERT", "PET", "SNAP", "TALE", "COMET", "OVER", "WEST"]),
        FallbackFill(template: ["##...", ".....", ".....", ".....", "...##"],
                     answers: ["LOT", "SHAPE", "TUNES", "AGENT", "YES", "STAY", "HUGE", "LANES", "OPEN", "TEST"])
    ]

    private static let entriesByAnswer: [String: CrosswordEntry] = {
        Dictionary(uniqueKeysWithValues: CrosswordBank.byLength.values
            .flatMap { $0 }
            .map { ($0.answer, $0) })
    }()

    private static func fallbackPuzzle(for spec: CrosswordSpec, selector: UInt64) -> CrosswordPuzzle {
        let choices = spec.template == twistTemplate ? twistFallbacks : stairFallbacks
        let fallback = choices[Int(selector % UInt64(choices.count))]
        let fallbackSlots = slots(in: fallback.template)
        precondition(fallbackSlots.count == fallback.answers.count)
        let filled = zip(fallbackSlots, fallback.answers).map { slot, answer in
            guard let entry = entriesByAnswer[answer] else {
                preconditionFailure("missing crossword fallback answer: \(answer)")
            }
            return (slot: slot, entry: entry)
        }
        return assemble(template: fallback.template,
                        filled: filled,
                        parSeconds: spec.parSeconds)
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
