//
//  BlockEscape.swift
//  wits
//
//  Klotski-style sliding blocks. Mixed-size blocks jam a small tray; slide
//  them along rows and columns to walk the big 2×2 block out the bottom exit.
//  Boards are selected from an offline-generated catalog of solvable starts.
//  Runtime setup only reads a compact key and decodes it, so even the hardest
//  trays appear immediately. Completing the escape is the pass condition.
//

import Foundation
#if !BLOCK_ESCAPE_CATALOG_TOOL
import SwiftUI
#endif

// MARK: - Engine

nonisolated struct KlotskiBlock: Equatable, Hashable, Sendable {
    var x: Int
    var y: Int
    let w: Int
    let h: Int
}

nonisolated struct KlotskiBoard: Equatable, Sendable {
    let width: Int
    let height: Int
    /// blocks[0] is always the 2×2 hero.
    var blocks: [KlotskiBlock]

    var exitX: Int { (width - 2) / 2 }
    var isSolved: Bool { blocks[0].x == exitX && blocks[0].y == height - 2 }
}

nonisolated struct KlotskiSpec: Equatable, Sendable {
    let width: Int
    let height: Int
    let verticals: Int    // 1×2 upright blocks
    let horizontals: Int  // 2×1 flat blocks
    let singles: Int      // 1×1 blocks
}

nonisolated enum KlotskiDifficultyBand: Int, CaseIterable, Sendable {
    case easy
    case medium
    case hard
    case extraHard

    var title: String {
        switch self {
        case .easy: "easy"
        case .medium: "medium"
        case .hard: "hard"
        case .extraHard: "extra hard"
        }
    }

    var spec: KlotskiSpec {
        switch self {
        case .easy:
            KlotskiSpec(width: 4, height: 4, verticals: 1, horizontals: 1, singles: 2)
        case .medium, .hard:
            KlotskiSpec(width: 4, height: 5, verticals: 3, horizontals: 2, singles: 3)
        case .extraHard:
            KlotskiSpec(width: 4, height: 5, verticals: 4, horizontals: 1, singles: 4)
        }
    }

    var catalogDepths: ClosedRange<Int> {
        switch self {
        case .easy: 4...10
        case .medium: 12...27
        case .hard: 28...48
        case .extraHard: 35...77
        }
    }
}

// Pure computation. Runtime board selection does no graph search.
nonisolated enum KlotskiEngine {
    /// States are canonical by cell shape-class (same-shaped blocks are
    /// interchangeable), packed 3 bits per cell into two UInt64s (≤ 30 cells).
    struct Key: Hashable, Sendable {
        var a: UInt64 = 0
        var b: UInt64 = 0

        mutating func set(_ cell: Int, _ value: UInt64) {
            if cell < 21 { a |= value << (UInt64(cell) * 3) }
            else { b |= value << (UInt64(cell - 21) * 3) }
        }
    }

    struct CatalogEntry: Equatable, Sendable {
        let key: Key
        let depth: Int
    }

    private static func shapeClass(_ b: KlotskiBlock) -> UInt64 {
        switch (b.w, b.h) {
        case (2, 2): 4
        case (1, 2): 3
        case (2, 1): 2
        default: 1
        }
    }

    static func key(_ board: KlotskiBoard) -> Key {
        // Every covered cell carries its block's shape class. Same-shaped
        // blocks are interchangeable, and the greedy row-major decode below
        // recovers the exact block set for this shape vocabulary.
        var k = Key()
        for block in board.blocks {
            let cls = shapeClass(block)
            for dy in 0..<block.h {
                for dx in 0..<block.w {
                    k.set((block.y + dy) * board.width + (block.x + dx), cls)
                }
            }
        }
        return k
    }

    /// Rebuild a board from a canonical key by greedy row-major scanning.
    static func decode(_ key: Key, width: Int, height: Int) -> KlotskiBoard {
        func cls(_ cell: Int) -> UInt64 {
            cell < 21 ? (key.a >> (UInt64(cell) * 3)) & 7 : (key.b >> (UInt64(cell - 21) * 3)) & 7
        }
        var used = [Bool](repeating: false, count: width * height)
        var hero: KlotskiBlock?
        var others: [KlotskiBlock] = []
        for cell in 0..<(width * height) where !used[cell] && cls(cell) != 0 {
            let (x, y) = (cell % width, cell / width)
            let block: KlotskiBlock
            switch cls(cell) {
            case 4: block = KlotskiBlock(x: x, y: y, w: 2, h: 2)
            case 3: block = KlotskiBlock(x: x, y: y, w: 1, h: 2)
            case 2: block = KlotskiBlock(x: x, y: y, w: 2, h: 1)
            default: block = KlotskiBlock(x: x, y: y, w: 1, h: 1)
            }
            for dy in 0..<block.h {
                for dx in 0..<block.w {
                    used[(y + dy) * width + (x + dx)] = true
                }
            }
            if block.w == 2 && block.h == 2 { hero = block } else { others.append(block) }
        }
        return KlotskiBoard(width: width, height: height, blocks: [hero!] + others)
    }

    private static func occupancy(_ board: KlotskiBoard) -> [Int] {
        var occ = [Int](repeating: -1, count: board.width * board.height)
        for (i, b) in board.blocks.enumerated() {
            for dy in 0..<b.h {
                for dx in 0..<b.w {
                    occ[(b.y + dy) * board.width + (b.x + dx)] = i
                }
            }
        }
        return occ
    }

    /// One move = one block sliding any distance along one axis. Each distinct
    /// resting cell along the way is a neighbor of cost 1.
    static func neighbors(_ board: KlotskiBoard) -> [KlotskiBoard] {
        let occ = occupancy(board)
        var result: [KlotskiBoard] = []
        for (i, block) in board.blocks.enumerated() {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                var steps = 1
                while fits(block, moved: (dx * steps, dy * steps), asIndex: i, occ: occ, board: board) {
                    var next = board
                    next.blocks[i].x += dx * steps
                    next.blocks[i].y += dy * steps
                    result.append(next)
                    steps += 1
                }
            }
        }
        return result
    }

    private static func fits(_ block: KlotskiBlock, moved delta: (Int, Int), asIndex i: Int,
                             occ: [Int], board: KlotskiBoard) -> Bool {
        let (nx, ny) = (block.x + delta.0, block.y + delta.1)
        guard nx >= 0, ny >= 0, nx + block.w <= board.width, ny + block.h <= board.height else { return false }
        for dy in 0..<block.h {
            for dx in 0..<block.w {
                let owner = occ[(ny + dy) * board.width + (nx + dx)]
                if owner != -1 && owner != i { return false }
            }
        }
        return true
    }

    /// How many cells a block can slide in a direction on this board.
    static func freedom(_ board: KlotskiBoard, blockIndex i: Int) -> (left: Int, right: Int, up: Int, down: Int) {
        let occ = occupancy(board)
        let block = board.blocks[i]
        func run(_ dx: Int, _ dy: Int) -> Int {
            var steps = 0
            while fits(block, moved: (dx * (steps + 1), dy * (steps + 1)), asIndex: i, occ: occ, board: board) {
                steps += 1
            }
            return steps
        }
        return (run(-1, 0), run(1, 0), run(0, -1), run(0, 1))
    }

    /// Exact minimum moves to solve, or nil when unsolvable / above the cap.
    static func solve(_ board: KlotskiBoard, cap: Int = 400_000) -> Int? {
        if board.isSolved { return 0 }
        var visited: Set<Key> = [key(board)]
        var frontier = [board]
        var depth = 0
        while !frontier.isEmpty, visited.count < cap {
            depth += 1
            var next: [KlotskiBoard] = []
            for state in frontier {
                for n in neighbors(state) {
                    let k = key(n)
                    guard visited.insert(k).inserted else { continue }
                    if n.isSolved { return depth }
                    next.append(n)
                }
            }
            frontier = next
        }
        return nil
    }

    // MARK: Runtime catalog

    static let boardsPerBand = 2_500

    static func generate(band: KlotskiDifficultyBand,
                         seed: UInt64,
                         excluding: Set<Key> = []) -> (board: KlotskiBoard, key: Key) {
        let entries = catalogEntries(for: band)
        guard !entries.isEmpty else { return fallbackPuzzle() }

        var rng = SeededRandomNumberGenerator(seed: seed)
        let start = Int(rng.next() % UInt64(entries.count))
        let selected = (0..<entries.count)
            .lazy
            .map { entries[(start + $0) % entries.count] }
            .first { !excluding.contains($0.key) } ?? entries[start]
        return (decode(selected.key, width: band.spec.width, height: band.spec.height), selected.key)
    }

    static func catalogEntries(for band: KlotskiDifficultyBand) -> [CatalogEntry] {
        guard bundledCatalog.indices.contains(band.rawValue) else { return [] }
        return bundledCatalog[band.rawValue]
    }

    static func catalogCount(for band: KlotskiDifficultyBand) -> Int {
        catalogEntries(for: band).count
    }

    static func catalogDepthRange(for band: KlotskiDifficultyBand) -> ClosedRange<Int>? {
        let depths = catalogEntries(for: band).map(\.depth)
        guard let minimum = depths.min(), let maximum = depths.max() else { return nil }
        return minimum...maximum
    }

    static func catalog(from data: Data) throws -> [[CatalogEntry]] {
        var reader = CatalogReader(data: data)
        guard try reader.readBytes(count: 8) == Array("WITSBE01".utf8) else {
            throw CatalogError.invalidMagic
        }

        var catalog: [[CatalogEntry]] = []
        for band in KlotskiDifficultyBand.allCases {
            let count = Int(try reader.readUInt32())
            guard count > 0, count <= 100_000 else { throw CatalogError.invalidCount }
            var entries: [CatalogEntry] = []
            entries.reserveCapacity(count)
            var seen: Set<Key> = []
            for _ in 0..<count {
                let entry = CatalogEntry(
                    key: Key(a: try reader.readUInt64(), b: try reader.readUInt64()),
                    depth: Int(try reader.readByte())
                )
                guard band.catalogDepths.contains(entry.depth),
                      seen.insert(entry.key).inserted,
                      key(entry.key, matches: band.spec) else {
                    throw CatalogError.invalidEntry
                }
                entries.append(entry)
            }
            catalog.append(entries)
        }
        guard reader.isAtEnd else { throw CatalogError.trailingData }
        return catalog
    }

    private static let bundledCatalog: [[CatalogEntry]] = {
        guard let url = Bundle.main.url(forResource: "BlockEscapeBoards", withExtension: "bin"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? catalog(from: data)) ?? []
    }()

    private static func fallbackPuzzle() -> (board: KlotskiBoard, key: Key) {
        let board = KlotskiBoard(width: 4, height: 4,
                                 blocks: [KlotskiBlock(x: 1, y: 0, w: 2, h: 2),
                                          KlotskiBlock(x: 0, y: 3, w: 1, h: 1),
                                          KlotskiBlock(x: 3, y: 3, w: 1, h: 1)])
        return (board, key(board))
    }

    private static func key(_ key: Key, matches spec: KlotskiSpec) -> Bool {
        func shapeClass(at cell: Int) -> UInt64 {
            cell < 21
                ? (key.a >> (UInt64(cell) * 3)) & 7
                : (key.b >> (UInt64(cell - 21) * 3)) & 7
        }

        var used = [Bool](repeating: false, count: spec.width * spec.height)
        var counts = [Int](repeating: 0, count: 5)
        for cell in used.indices where !used[cell] && shapeClass(at: cell) != 0 {
            let value = shapeClass(at: cell)
            guard value <= 4 else { return false }
            let (width, height): (Int, Int)
            switch value {
            case 4: (width, height) = (2, 2)
            case 3: (width, height) = (1, 2)
            case 2: (width, height) = (2, 1)
            default: (width, height) = (1, 1)
            }
            let x = cell % spec.width
            let y = cell / spec.width
            guard x + width <= spec.width, y + height <= spec.height else { return false }
            for dy in 0..<height {
                for dx in 0..<width {
                    let index = (y + dy) * spec.width + x + dx
                    guard !used[index], shapeClass(at: index) == value else { return false }
                    used[index] = true
                }
            }
            counts[Int(value)] += 1
        }
        return counts[4] == 1
            && counts[3] == spec.verticals
            && counts[2] == spec.horizontals
            && counts[1] == spec.singles
    }

    private struct CatalogReader {
        let bytes: [UInt8]
        var offset = 0

        init(data: Data) { bytes = Array(data) }
        var isAtEnd: Bool { offset == bytes.count }

        mutating func readBytes(count: Int) throws -> [UInt8] {
            guard count >= 0, offset + count <= bytes.count else { throw CatalogError.truncated }
            defer { offset += count }
            return Array(bytes[offset..<(offset + count)])
        }

        mutating func readByte() throws -> UInt8 {
            guard offset < bytes.count else { throw CatalogError.truncated }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func readUInt32() throws -> UInt32 {
            let value = try readBytes(count: 4)
            return value.enumerated().reduce(0) { $0 | UInt32($1.element) << ($1.offset * 8) }
        }

        mutating func readUInt64() throws -> UInt64 {
            let value = try readBytes(count: 8)
            return value.enumerated().reduce(0) { $0 | UInt64($1.element) << ($1.offset * 8) }
        }
    }

    enum CatalogError: Error {
        case invalidMagic
        case invalidCount
        case invalidEntry
        case trailingData
        case truncated
    }

#if BLOCK_ESCAPE_CATALOG_TOOL
    /// A random legal layout with the hero already at the exit, used only to
    /// build the bundled catalog during development.
    private static func randomSolvedLayout<R: RandomNumberGenerator>(_ spec: KlotskiSpec,
                                                                      using rng: inout R) -> KlotskiBoard? {
        outer: for _ in 0..<40 {
            var board = KlotskiBoard(width: spec.width, height: spec.height,
                                     blocks: [KlotskiBlock(x: (spec.width - 2) / 2, y: spec.height - 2, w: 2, h: 2)])
            var occ = occupancy(board)
            var shapes: [(w: Int, h: Int)] = []
            shapes.append(contentsOf: Array(repeating: (1, 2), count: spec.verticals))
            shapes.append(contentsOf: Array(repeating: (2, 1), count: spec.horizontals))
            shapes.append(contentsOf: Array(repeating: (1, 1), count: spec.singles))
            for shape in shapes {
                let candidates = (0..<(spec.width * spec.height)).shuffled(using: &rng)
                var placed = false
                for cell in candidates {
                    let (x, y) = (cell % spec.width, cell / spec.width)
                    let block = KlotskiBlock(x: x, y: y, w: shape.w, h: shape.h)
                    guard x + shape.w <= spec.width, y + shape.h <= spec.height else { continue }
                    var free = true
                    for dy in 0..<shape.h {
                        for dx in 0..<shape.w where occ[(y + dy) * spec.width + (x + dx)] != -1 {
                            free = false
                        }
                    }
                    guard free else { continue }
                    board.blocks.append(block)
                    for dy in 0..<shape.h {
                        for dx in 0..<shape.w {
                            occ[(y + dy) * spec.width + (x + dx)] = board.blocks.count - 1
                        }
                    }
                    placed = true
                    break
                }
                if !placed { continue outer }
            }
            return board
        }
        return nil
    }

    /// Every state reachable from `seed` (moves are reversible, so this is the
    /// full component), or nil when it outgrows the cap.
    private static func explore(from seed: KlotskiBoard, cap: Int) -> (states: Set<Key>, goals: [KlotskiBoard])? {
        var visited: Set<Key> = [key(seed)]
        var goals: [KlotskiBoard] = seed.isSolved ? [seed] : []
        var frontier = [seed]
        while !frontier.isEmpty {
            var next: [KlotskiBoard] = []
            for state in frontier {
                for nextBoard in neighbors(state) {
                    guard visited.insert(key(nextBoard)).inserted else { continue }
                    if nextBoard.isSolved { goals.append(nextBoard) }
                    next.append(nextBoard)
                }
            }
            if visited.count > cap { return nil }
            frontier = next
        }
        return (visited, goals)
    }

    /// Multi-source BFS from every solved state: exact distance-to-solve for
    /// each state in the component.
    private static func distancesFromGoals(component: (states: Set<Key>, goals: [KlotskiBoard])) -> [Key: Int] {
        var distances: [Key: Int] = [:]
        var frontier: [KlotskiBoard] = []
        for goal in component.goals {
            distances[key(goal)] = 0
            frontier.append(goal)
        }
        var depth = 0
        while !frontier.isEmpty {
            depth += 1
            var next: [KlotskiBoard] = []
            for state in frontier {
                for nextBoard in neighbors(state) {
                    let nextKey = key(nextBoard)
                    guard distances[nextKey] == nil else { continue }
                    distances[nextKey] = depth
                    next.append(nextBoard)
                }
            }
            frontier = next
        }
        return distances
    }

    /// Offline-only catalog builder. Runtime builds never include this graph
    /// enumeration path; they only decode keys from the generated asset.
    static func catalogEntries(spec: KlotskiSpec,
                               depths: ClosedRange<Int>,
                               count: Int,
                               seed: UInt64) -> [(key: Key, depth: Int)] {
        var rng = SeededRandomNumberGenerator(seed: seed)
        var candidates: [Key: Int] = [:]
        var knownStates: Set<Key> = []

        for _ in 0..<200 where candidates.count < count {
            guard let solved = randomSolvedLayout(spec, using: &rng) else { continue }
            let solvedKey = key(solved)
            guard !knownStates.contains(solvedKey),
                  let component = explore(from: solved, cap: 400_000) else { continue }
            knownStates.formUnion(component.states)
            let distances = distancesFromGoals(component: component)
            for (key, depth) in distances where depths.contains(depth) {
                candidates[key] = depth
            }
        }

        precondition(candidates.count >= count,
                     "catalog recipe produced \(candidates.count), needs \(count)")
        var entries = candidates.map { (key: $0.key, depth: $0.value) }
        entries.shuffle(using: &rng)
        return Array(entries.prefix(count))
    }
#endif
}

// MARK: - Screen

#if !BLOCK_ESCAPE_CATALOG_TOOL
@MainActor
private enum BlockEscapeRecentBoards {
    private static let historyLimit = 40

    static func excludedKeys(for band: KlotskiDifficultyBand) -> Set<KlotskiEngine.Key> {
        Set(UserDefaults.standard.stringArray(forKey: storageKey(for: band))?.compactMap(parse) ?? [])
    }

    static func record(_ key: KlotskiEngine.Key, for band: KlotskiDifficultyBand) {
        let encoded = encode(key)
        var history = UserDefaults.standard.stringArray(forKey: storageKey(for: band)) ?? []
        history.removeAll { $0 == encoded }
        history.insert(encoded, at: 0)
        UserDefaults.standard.set(Array(history.prefix(historyLimit)), forKey: storageKey(for: band))
    }

    private static func storageKey(for band: KlotskiDifficultyBand) -> String {
        "wits.blockEscape.recent.\(band.rawValue)"
    }

    private static func encode(_ key: KlotskiEngine.Key) -> String {
        "\(key.a):\(key.b)"
    }

    private static func parse(_ value: String) -> KlotskiEngine.Key? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let a = UInt64(parts[0]),
              let b = UInt64(parts[1]) else { return nil }
        return KlotskiEngine.Key(a: a, b: b)
    }
}

struct BlockEscapeScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    @State private var board: KlotskiBoard?
    @State private var moves = 0
    @State private var elapsed = 0.0
    @State private var timerStartedAt = Date()
    @State private var hint = "slide the blocks. walk the big one to the exit"
    @State private var dragIndex: Int?
    @State private var dragOffset: CGSize = .zero
    @State private var finished = false
    @State private var escaped = false

    private let startedAt = Date()
    private let level: Double
    private let band: KlotskiDifficultyBand
    private var world: GameWorld { GameID.blockEscape.world }

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        self.level = cfg.difficulty.level
        self.band = Self.difficultyBand(for: cfg)
    }

    private static func difficultyBand(for cfg: GameConfig) -> KlotskiDifficultyBand {
        if let difficulty = cfg.difficultyTrack {
            switch difficulty {
            case .easy: return .easy
            case .medium: return .medium
            case .hard: return .hard
            case .extraHard: return .extraHard
            }
        }
        let level = cfg.difficulty.level
        if level < 3.25 { return .easy }
        if level < 5.5 { return .medium }
        if level < 7.75 { return .hard }
        return .extraHard
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                GameStageBackground(game: .blockEscape)
                if let board {
                    VStack(spacing: 0) {
                        topBar
                            .padding(.top, 8)
                            .padding(.horizontal, WitsMetrics.screenPadding)

                        Spacer(minLength: 24)

                        Text(hint)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.horizontal, WitsMetrics.screenPadding)
                            .opacity(hint.isEmpty ? 0 : 1)
                            .animation(.easeOut(duration: 0.18), value: hint)

                        trayView(board, in: geo.size)
                            .padding(.top, 18)

                        Spacer(minLength: 24)

                        progressStrip(board)
                            .padding(.horizontal, WitsMetrics.screenPadding)
                            .padding(.bottom, 12)
                    }
                } else {
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(.white)
                        Text("laying out the tray…")
                            .font(.system(size: 14, weight: .semibold, design: world.bodyDesign))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
        .task { await setUpAndRun() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Block escape")
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            Spacer()
                .frame(width: 38)

            HStack(spacing: 10) {
                Text(Self.clock(elapsed))
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(minWidth: 54, alignment: .leading)
                Spacer(minLength: 0)
                Text("moves: \(moves)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Color.black.opacity(0.35), in: Capsule())

            Button {
                showHelp()
            } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show rule reminder")
        }
    }

    private func progressStrip(_ board: KlotskiBoard) -> some View {
        HStack {
            Label("\(board.width)×\(board.height) tray", systemImage: "square.split.2x2.fill")
            Spacer()
            Text(band.title)
        }
        .font(.system(size: 13, weight: .heavy, design: .rounded))
        .foregroundStyle(.white.opacity(0.78))
    }

    // MARK: Tray

    private func trayView(_ board: KlotskiBoard, in size: CGSize) -> some View {
        let inset: CGFloat = 10
        let maxW = size.width - 36
        let maxH = size.height * 0.56
        let cell = min((maxW - inset * 2) / CGFloat(board.width),
                       (maxH - inset * 2) / CGFloat(board.height))
        let trayW = cell * CGFloat(board.width) + inset * 2
        let trayH = cell * CGFloat(board.height) + inset * 2

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(world.surface.opacity(0.88))

            // exit notch under the hero's target columns
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(world.accent)
                .frame(width: cell * 2 - 8, height: 5)
                .offset(x: inset + CGFloat(board.exitX) * cell + 4, y: trayH - 4)
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(world.accent)
                .offset(x: inset + CGFloat(board.exitX) * cell + cell - 7, y: trayH + 6)

            ForEach(board.blocks.indices, id: \.self) { i in
                blockView(board.blocks[i], hero: i == 0, cell: cell)
                    .offset(x: inset + CGFloat(board.blocks[i].x) * cell,
                            y: inset + CGFloat(board.blocks[i].y) * cell)
                    .offset(dragIndex == i ? dragOffset : .zero)
                    .offset(y: escaped && i == 0 ? cell * 2.4 : 0)
                    .opacity(escaped && i == 0 ? 0 : 1)
                    .gesture(dragGesture(for: i, cell: cell))
                    .animation(.spring(response: 0.24, dampingFraction: 0.85), value: board.blocks[i])
                    .animation(.easeIn(duration: 0.45), value: escaped)
            }
        }
        .frame(width: trayW, height: trayH)
        .animation(.spring(response: 0.24, dampingFraction: 0.85), value: dragIndex)
    }

    private func blockView(_ block: KlotskiBlock, hero: Bool, cell: CGFloat) -> some View {
        let gap: CGFloat = 3
        return RoundedRectangle(cornerRadius: max(5, cell * 0.10), style: .continuous)
            .fill(hero ? world.accent : world.secondary)
            .overlay(
                RoundedRectangle(cornerRadius: max(5, cell * 0.10), style: .continuous)
                    .strokeBorder(Color.black.opacity(0.12), lineWidth: 1.5)
            )
            .overlay {
                if hero {
                    Image(systemName: "arrow.down")
                        .font(.system(size: cell * 0.34, weight: .heavy))
                        .foregroundStyle(world.background.opacity(0.88))
                }
            }
            .frame(width: cell * CGFloat(block.w) - gap * 2, height: cell * CGFloat(block.h) - gap * 2)
            .padding(gap)
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            .accessibilityLabel(hero ? "Big block" : "Block")
    }

    private func dragGesture(for i: Int, cell: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { g in
                guard !finished, let board else { return }
                dragIndex = i
                let free = KlotskiEngine.freedom(board, blockIndex: i)
                if abs(g.translation.width) >= abs(g.translation.height) {
                    let x = min(max(g.translation.width, -CGFloat(free.left) * cell), CGFloat(free.right) * cell)
                    dragOffset = CGSize(width: x, height: 0)
                } else {
                    let y = min(max(g.translation.height, -CGFloat(free.up) * cell), CGFloat(free.down) * cell)
                    dragOffset = CGSize(width: 0, height: y)
                }
            }
            .onEnded { _ in
                guard !finished, board != nil else { dragIndex = nil; dragOffset = .zero; return }
                let dx = Int((dragOffset.width / cell).rounded())
                let dy = Int((dragOffset.height / cell).rounded())
                dragIndex = nil
                dragOffset = .zero
                guard dx != 0 || dy != 0 else { return }
                board?.blocks[i].x += dx
                board?.blocks[i].y += dy
                moves += 1
                hint = ""
                GameFeel.shared.play(.correct(combo: 1))
                checkCompletion()
            }
    }

    // MARK: Flow

    private func setUpAndRun() async {
        if board == nil {
            let selectedBand = band
            let seed = cfg.resolvedRandomSeed()
            let excluded = BlockEscapeRecentBoards.excludedKeys(for: selectedBand)
            let generated = await Task.detached(priority: .userInitiated) {
                KlotskiEngine.generate(band: selectedBand, seed: seed, excluding: excluded)
            }.value
            board = generated.board
            BlockEscapeRecentBoards.record(generated.key, for: selectedBand)
            timerStartedAt = Date()
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            guard !finished else { return }
            elapsed = cfg.activeElapsed(since: timerStartedAt)
        }
    }

    private func checkCompletion() {
        guard board?.isSolved == true, !finished else { return }
        finished = true
        GameFeel.shared.play(.newBest)
        escaped = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            finish()
        }
    }

    private func finish() {
        let seconds = max(1, elapsed)
        // Moves remain a local best stat, but progression is pass/fail: this
        // result only exists after the hero reaches the exit.
        let score = max(0, 10_000 - moves * 100 - Int(seconds.rounded()))

        var result = GameResult(game: .blockEscape, score: score, accuracy: 1)
        result.trials = moves
        result.startedAt = startedAt
        result.durationMs = Int(seconds * 1000)
        result.raw = [
            "moves": Double(moves),
            "seconds": seconds.rounded(),
            "trayWidth": Double(board?.width ?? 0),
            "trayHeight": Double(board?.height ?? 0),
            "blocks": Double(board?.blocks.count ?? 0),
            "blockLevel": level,
            "completed": 1
        ]
        onResult(result)
    }

    private func showHelp() {
        hint = "blocks slide along rows and columns. get the red block to the bottom exit"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if !finished {
                hint = ""
            }
        }
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
#endif
