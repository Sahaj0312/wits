//
//  BlockEscape.swift
//  wits
//
//  Klotski-style sliding blocks. Mixed-size blocks jam a small tray; slide
//  them along rows and columns to walk the big 2×2 block out the bottom exit.
//  Every level is procedurally generated with an exact BFS par: the generator
//  builds a random solved layout, explores its whole move graph, and serves a
//  start position whose true minimum solve length matches the level's target
//  — so boards never repeat and efficiency scoring is honest.
//

import SwiftUI

// MARK: - Engine

struct KlotskiBlock: Equatable, Hashable {
    var x: Int
    var y: Int
    let w: Int
    let h: Int
}

struct KlotskiBoard: Equatable {
    let width: Int
    let height: Int
    /// blocks[0] is always the 2×2 hero.
    var blocks: [KlotskiBlock]

    var exitX: Int { (width - 2) / 2 }
    var isSolved: Bool { blocks[0].x == exitX && blocks[0].y == height - 2 }
}

struct KlotskiSpec: Equatable {
    let width: Int
    let height: Int
    let verticals: Int    // 1×2 upright blocks
    let horizontals: Int  // 2×1 flat blocks
    let singles: Int      // 1×1 blocks
    let targetPar: Int
}

enum KlotskiEngine {
    /// States are canonical by cell shape-class (same-shaped blocks are
    /// interchangeable), packed 3 bits per cell into two UInt64s (≤ 30 cells).
    struct Key: Hashable {
        var a: UInt64 = 0
        var b: UInt64 = 0

        mutating func set(_ cell: Int, _ value: UInt64) {
            if cell < 21 { a |= value << (UInt64(cell) * 3) }
            else { b |= value << (UInt64(cell - 21) * 3) }
        }
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

    // MARK: Level ladder

    /// Frozen exam spec per map level (1...40): tray, block mix, and the
    /// minimum-move target the generator aims the start position at. Bands
    /// step sideways-then-up like the other ladders — a new tray or a denser
    /// mix resets the par ramp. Mixes are profiled: each keeps its full move
    /// graph small enough to enumerate (≤ ~150k canonical states) while its
    /// deepest positions comfortably cover the band's par targets. Bigger or
    /// emptier trays blow up the state space without getting deeper, so the
    /// ladder tops out at the classic 4×5, two-empty density (par ≤ ~77).
    static func spec(forMapLevel level: Int) -> KlotskiSpec {
        let n = min(max(level, 1), 40)
        switch n {
        case ...8:
            return KlotskiSpec(width: 4, height: 4, verticals: 1, horizontals: 1, singles: 2,
                               targetPar: 3 + n)                       // 4...11 (component max ~11)
        case ...16:
            return KlotskiSpec(width: 4, height: 4, verticals: 2, horizontals: 1, singles: 3,
                               targetPar: 9 + (n - 8))                 // 10...17 (max ~18)
        case ...26:
            return KlotskiSpec(width: 4, height: 5, verticals: 3, horizontals: 2, singles: 3,
                               targetPar: 15 + (n - 16) * 3)           // 18...45 (max ~78)
        case ...34:
            return KlotskiSpec(width: 4, height: 5, verticals: 4, horizontals: 1, singles: 4,
                               targetPar: 40 + (n - 26) * 4)           // 44...72 (classic, max ~77)
        default:
            return KlotskiSpec(width: 4, height: 5, verticals: 4, horizontals: 1, singles: 4,
                               targetPar: 72 + (n - 34))               // 73...78
        }
    }

    /// A random legal layout with the hero already at the exit (solved), used
    /// as the seed whose move graph the generator explores.
    static func randomSolvedLayout(_ spec: KlotskiSpec) -> KlotskiBoard? {
        outer: for _ in 0..<40 {
            var board = KlotskiBoard(width: spec.width, height: spec.height,
                                     blocks: [KlotskiBlock(x: (spec.width - 2) / 2, y: spec.height - 2, w: 2, h: 2)])
            var occ = occupancy(board)
            var shapes: [(w: Int, h: Int)] = []
            shapes.append(contentsOf: Array(repeating: (1, 2), count: spec.verticals))
            shapes.append(contentsOf: Array(repeating: (2, 1), count: spec.horizontals))
            shapes.append(contentsOf: Array(repeating: (1, 1), count: spec.singles))
            for shape in shapes {
                let candidates = (0..<(spec.width * spec.height)).shuffled()
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

    /// Generate a puzzle for a map level. Two BFS passes over one random
    /// component: enumerate every position reachable from a solved layout,
    /// then walk distances back from every solved position in it and serve
    /// the state whose exact par lands closest to the level's target.
    static func generate(mapLevel: Int, attempts: Int = 6, cap: Int = 400_000) -> (board: KlotskiBoard, par: Int) {
        let spec = spec(forMapLevel: mapLevel)
        var best: (KlotskiBoard, Int)?
        for _ in 0..<attempts {
            guard let seed = randomSolvedLayout(spec),
                  let component = explore(from: seed, cap: cap) else { continue }
            let distances = distancesFromGoals(component: component, width: spec.width, height: spec.height)
            // A random layout can jam into a tiny locked pocket of the move
            // graph — reject components too shallow to host a real puzzle.
            let deepest = distances.values.max() ?? 0
            guard deepest >= min(spec.targetPar, 4) else { continue }
            guard let picked = pickStart(distances, target: spec.targetPar) else { continue }
            let board = decode(picked.key, width: spec.width, height: spec.height)
            if picked.par >= spec.targetPar { return (board, picked.par) }
            if best == nil || abs(picked.par - spec.targetPar) < abs(best!.1 - spec.targetPar) {
                best = (board, picked.par)
            }
        }
        if let best { return best }
        // Unreachable in practice; serve a minimal solvable tray so a run can
        // never fail to start.
        let fallback = KlotskiBoard(width: 4, height: 4,
                                    blocks: [KlotskiBlock(x: 1, y: 0, w: 2, h: 2),
                                             KlotskiBlock(x: 0, y: 3, w: 1, h: 1),
                                             KlotskiBlock(x: 3, y: 3, w: 1, h: 1)])
        let par = solve(fallback) ?? 2
        return (fallback, par)
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
                for n in neighbors(state) {
                    guard visited.insert(key(n)).inserted else { continue }
                    if n.isSolved { goals.append(n) }
                    next.append(n)
                }
            }
            if visited.count > cap { return nil }
            frontier = next
        }
        return (visited, goals)
    }

    /// Multi-source BFS from every solved state: exact distance-to-solve for
    /// each state in the component.
    private static func distancesFromGoals(component: (states: Set<Key>, goals: [KlotskiBoard]),
                                           width: Int, height: Int) -> [Key: Int] {
        var dist: [Key: Int] = [:]
        var frontier: [KlotskiBoard] = []
        for goal in component.goals {
            dist[key(goal)] = 0
            frontier.append(goal)
        }
        var depth = 0
        while !frontier.isEmpty {
            depth += 1
            var next: [KlotskiBoard] = []
            for state in frontier {
                for n in neighbors(state) {
                    let k = key(n)
                    guard dist[k] == nil else { continue }
                    dist[k] = depth
                    next.append(n)
                }
            }
            frontier = next
        }
        return dist
    }

    private static func pickStart(_ distances: [Key: Int], target: Int) -> (key: Key, par: Int)? {
        var best: (Key, Int)?
        for (k, d) in distances where d >= 2 {
            if d == target { return (k, d) }
            if best == nil || abs(d - target) < abs(best!.1 - target) { best = (k, d) }
        }
        return best
    }
}

// MARK: - Screen

struct BlockEscapeScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    @State private var board: KlotskiBoard?
    @State private var par = 0
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
    private let mapLevel: Int

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        self.level = cfg.difficulty.level
        self.mapLevel = cfg.mapLevel ?? LevelLadder.nearestLevel(for: .blockEscape, legacyDifficulty: cfg.difficulty.level)
    }

    /// Time budget prices in planning, not just execution — deep thought on a
    /// hard tray shouldn't tank the grade.
    private var parSeconds: Double { Double(par) * 5.0 + 30 }

    /// Full move credit within ~20% of par: par is BFS-optimal, and matching a
    /// computer within a fifth is mastery for a human.
    private var graceMoves: Int { Int(ceil(Double(par) * 1.2)) + 1 }

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
                            .font(.witsBody(14, weight: .semibold))
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
        HStack(spacing: 10) {
            Spacer()
                .frame(width: 38)

            HStack(spacing: 16) {
                Text(Self.clock(elapsed))
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 66, alignment: .leading)
                Spacer(minLength: 0)
                Text("moves: \(moves)")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 42)
            .background(Color.black.opacity(0.35), in: Capsule())

            Button {
                showHelp()
            } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show rule reminder")
        }
    }

    private func progressStrip(_ board: KlotskiBoard) -> some View {
        VStack(spacing: 8) {
            HStack {
                Label("\(board.width)×\(board.height) tray", systemImage: "square.split.2x2.fill")
                Spacer()
                Text("par \(par)")
            }
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.78))

            ProgressView(value: min(1, Double(moves) / Double(max(1, graceMoves))))
                .tint(moves <= graceMoves ? Color(red: 0.24, green: 0.82, blue: 0.20) : Color.witsWarm)
                .background(.white.opacity(0.16), in: Capsule())
        }
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
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.28))

            // exit notch under the hero's target columns
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.witsAccent)
                .frame(width: cell * 2 - 8, height: 5)
                .offset(x: inset + CGFloat(board.exitX) * cell + 4, y: trayH - 4)
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Color.witsAccent)
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
        return RoundedRectangle(cornerRadius: max(8, cell * 0.14), style: .continuous)
            .fill(hero ? Color(red: 0.91, green: 0.36, blue: 0.31) : Color(red: 0.96, green: 0.92, blue: 0.82))
            .overlay(
                RoundedRectangle(cornerRadius: max(8, cell * 0.14), style: .continuous)
                    .strokeBorder(Color.black.opacity(0.12), lineWidth: 1.5)
            )
            .overlay {
                if hero {
                    Image(systemName: "arrow.down")
                        .font(.system(size: cell * 0.34, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.85))
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
            let target = mapLevel
            let generated = await Task.detached(priority: .userInitiated) {
                KlotskiEngine.generate(mapLevel: target)
            }.value
            board = generated.board
            par = generated.par
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
        let moveEfficiency = min(1, Double(graceMoves) / Double(max(1, moves)))
        let timeEfficiency = min(1, parSeconds / seconds)
        // Escaping at all earns the floor, and move quality dominates the rest,
        // so a slow, deliberate near-optimal solve still grades to 3 stars.
        // Time keeps a small weight to reward decisiveness at the margins.
        let accuracy = max(0, min(1, 0.30 + moveEfficiency * 0.60 + timeEfficiency * 0.10))
        let score = max(0, Int((Double(par) * 24 + moveEfficiency * 1300 + timeEfficiency * 500).rounded()))

        var result = GameResult(game: .blockEscape, score: score, accuracy: accuracy)
        result.trials = moves
        result.startedAt = startedAt
        result.durationMs = Int(seconds * 1000)
        result.raw = [
            "efficiency": (moveEfficiency * 100).rounded(),
            "moves": Double(moves),
            "parMoves": Double(par),
            "graceMoves": Double(graceMoves),
            "parSeconds": parSeconds.rounded(),
            "seconds": seconds.rounded(),
            "trayWidth": Double(board?.width ?? 0),
            "trayHeight": Double(board?.height ?? 0),
            "blocks": Double(board?.blocks.count ?? 0),
            "blockLevel": level
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
