//
//  SlidePuzzle.swift
//  wits
//
//  Classic 15-puzzle. Slide the numbered tiles through the one empty square
//  until they read in order. Adaptive: bigger boards and deeper scrambles
//  with level.
//

import SwiftUI

struct SlidePuzzleScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    @State private var tiles: [Int]      // index = cell, value = tile, 0 = blank
    @State private var moves = 0
    @State private var elapsed = 0.0
    @State private var timerStartedAt = Date()
    @State private var hint = "tap a tile in line with the gap to slide it"
    @State private var flashCell: Int?
    @State private var finished = false

    private let startedAt = Date()
    private let level: Double
    private let size: Int
    private let scrambleDepth: Int
    private let manhattanStart: Int
    private let parMoves: Int

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        self.level = cfg.difficulty.level
        let spec = Self.boardSpec(for: cfg.difficulty.level)
        self.size = spec.size
        self.scrambleDepth = spec.depth
        var rng = cfg.makeRandomGenerator()
        let scrambled = Self.scrambledTiles(size: spec.size, depth: spec.depth, using: &rng)
        self.manhattanStart = Self.manhattan(scrambled, size: spec.size)
        self.parMoves = Self.par(manhattan: manhattanStart, size: spec.size)
        _tiles = State(initialValue: scrambled)
    }

    private var tileCount: Int { size * size - 1 }

    private var tilesInPlace: Int {
        (0..<tileCount).filter { tiles[$0] == $0 + 1 }.count
    }

    private var parSeconds: Double {
        Double(parMoves) * 1.15 + 6
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background
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

                    SlideBoard(
                        size: size,
                        tiles: tiles,
                        flashCell: flashCell,
                        tapTile: tapCell
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: min(geo.size.height * 0.52, geo.size.width))
                    .padding(.horizontal, 18)
                    .padding(.top, 18)

                    Spacer(minLength: 24)

                    progressStrip
                        .padding(.horizontal, WitsMetrics.screenPadding)
                        .padding(.bottom, 12)
                }
            }
        }
        .task { await runTimer() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Number nudge")
    }

    private var background: some View {
        GameStageBackground(game: .slidePuzzle)
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

    private var progressStrip: some View {
        VStack(spacing: 8) {
            HStack {
                Label("\(size)×\(size) board", systemImage: "square.grid.3x3.topleft.filled")
                Spacer()
                Text("in place \(tilesInPlace)/\(tileCount)")
                Spacer()
                Text("par \(parMoves)")
            }
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.78))

            ProgressView(value: min(1, Double(tilesInPlace) / Double(tileCount)))
                .tint(Color(red: 0.24, green: 0.82, blue: 0.20))
                .background(.white.opacity(0.16), in: Capsule())
        }
    }

    private func tapCell(_ cell: Int) {
        guard !finished else { return }
        guard let blank = tiles.firstIndex(of: 0), cell != blank else { return }

        let (row, col) = (cell / size, cell % size)
        let (blankRow, blankCol) = (blank / size, blank % size)
        guard row == blankRow || col == blankCol else {
            flash(cell)
            hint = "that tile can't reach the gap — pick one in its row or column"
            cfg.report(.nearMiss)
            return
        }

        var moved = 0
        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
            if row == blankRow {
                let dir = col > blankCol ? 1 : -1
                var gap = blankCol
                for x in stride(from: blankCol + dir, through: col, by: dir) {
                    tiles[row * size + gap] = tiles[row * size + x]
                    tiles[row * size + x] = 0
                    gap = x
                    moved += 1
                }
            } else {
                let dir = row > blankRow ? 1 : -1
                var gap = blankRow
                for y in stride(from: blankRow + dir, through: row, by: dir) {
                    tiles[gap * size + col] = tiles[y * size + col]
                    tiles[y * size + col] = 0
                    gap = y
                    moved += 1
                }
            }
            moves += moved
        }
        hint = ""
        GameFeel.shared.play(.correct(combo: max(1, min(6, tilesInPlace / 2))))
        checkCompletion()
    }

    private func checkCompletion() {
        guard Self.isSolved(tiles) else { return }
        finished = true
        GameFeel.shared.play(.newBest)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            finish()
        }
    }

    private func finish() {
        let seconds = max(1, elapsed)
        let moveEfficiency = min(1, Double(parMoves) / Double(max(1, moves)))
        let timeEfficiency = min(1, parSeconds / seconds)
        let accuracy = max(0, min(1, moveEfficiency * 0.70 + timeEfficiency * 0.30))
        let score = max(0, Int((Double(parMoves) * 24 + moveEfficiency * 1100 + timeEfficiency * 700).rounded()))

        var result = GameResult(game: .slidePuzzle, score: score, accuracy: accuracy)
        result.trials = moves
        result.startedAt = startedAt
        result.durationMs = Int(seconds * 1000)
        result.raw = [
            "efficiency": (moveEfficiency * 100).rounded(),
            "moves": Double(moves),
            "parMoves": Double(parMoves),
            "parSeconds": parSeconds.rounded(),
            "manhattan": Double(manhattanStart),
            "seconds": seconds.rounded(),
            "gridSize": Double(size),
            "scrambleDepth": Double(scrambleDepth),
            "slideLevel": level
        ]
        onResult(result)
    }

    private func flash(_ cell: Int) {
        flashCell = cell
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            if flashCell == cell { flashCell = nil }
        }
    }

    private func showHelp() {
        GameFeel.shared.uiTap()
        hint = "put the tiles back in order, 1 to \(tileCount). tap any tile in line with the gap"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if !finished {
                hint = "tap a tile in line with the gap to slide it"
            }
        }
    }

    private func runTimer() async {
        timerStartedAt = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            guard !finished else { return }
            elapsed = cfg.activeElapsed(since: timerStartedAt)
        }
    }

    // MARK: Board math

    /// Level 1…10 → board side + scramble depth. Board size is the staircase
    /// (steps at 4 and 8); depth ramps smoothly with the *continuous* level
    /// inside each band, so every fractional adaptive gain deepens the next
    /// board a little. Each new size starts shallower than the previous
    /// band's end — a fresh, learnable start instead of a wall.
    static func boardSpec(for level: Double) -> (size: Int, depth: Int) {
        let l = min(10, max(1, level))
        if l < 4 {
            let t = (l - 1) / 3
            return (3, Int((8 + t * 16).rounded()))     // 8 → 24
        }
        if l < 8 {
            let t = (l - 4) / 4
            return (4, Int((14 + t * 46).rounded()))    // 14 → 60
        }
        let t = (l - 8) / 2
        return (5, Int((36 + t * 54).rounded()))        // 36 → 90
    }

    /// Scramble by random-walking the blank — always solvable. Boards are
    /// re-rolled until their Manhattan distance lands in a small window
    /// around the level's target, so two boards at the same level feel
    /// comparably hard instead of swinging with walk luck.
    static func scrambledTiles(size: Int, depth: Int) -> [Int] {
        var rng = SystemRandomNumberGenerator()
        return scrambledTiles(size: size, depth: depth, using: &rng)
    }

    static func scrambledTiles<R: RandomNumberGenerator>(size: Int,
                                                          depth: Int,
                                                          using rng: inout R) -> [Int] {
        let target = targetManhattan(size: size, depth: depth)
        let tolerance = max(2, target / 6)
        var best: [Int] = []
        var bestGap = Int.max
        for _ in 0..<24 {
            let tiles = randomWalk(size: size, depth: depth, using: &rng)
            guard !isSolved(tiles) else { continue }
            let gap = abs(manhattan(tiles, size: size) - target)
            if gap <= tolerance { return tiles }
            if gap < bestGap {
                best = tiles
                bestGap = gap
            }
        }
        while best.isEmpty {
            let tiles = randomWalk(size: size, depth: depth, using: &rng)
            if !isSolved(tiles) { best = tiles }
        }
        return best
    }

    /// The Manhattan distance a `depth`-step walk is steered toward: ~0.85
    /// per step while the walk is short, saturating near the board's
    /// fully-mixed average (≈14 / 38 / 77 for 3×3 / 4×4 / 5×5).
    static func targetManhattan(size: Int, depth: Int) -> Int {
        let mixed = size == 3 ? 14.2 : (size == 4 ? 37.5 : 76.8)
        return max(3, Int(min(Double(depth) * 0.85, mixed * 0.9).rounded()))
    }

    /// One scramble attempt: `depth` random blank moves from solved, never
    /// immediately undoing the previous step so depth ≈ real disorder.
    private static func randomWalk<R: RandomNumberGenerator>(size: Int,
                                                              depth: Int,
                                                              using rng: inout R) -> [Int] {
        var tiles = Array(1..<(size * size)) + [0]
        var blank = size * size - 1
        var previous = -1
        var done = 0
        while done < depth {
            var candidates: [Int] = []
            let (row, col) = (blank / size, blank % size)
            if row > 0 { candidates.append(blank - size) }
            if row < size - 1 { candidates.append(blank + size) }
            if col > 0 { candidates.append(blank - 1) }
            if col < size - 1 { candidates.append(blank + 1) }
            candidates.removeAll { $0 == previous }
            guard let pick = candidates.randomElement(using: &rng) else { continue }
            tiles[blank] = tiles[pick]
            tiles[pick] = 0
            previous = blank
            blank = pick
            done += 1
        }
        return tiles
    }

    static func isSolved(_ tiles: [Int]) -> Bool {
        for (i, v) in tiles.enumerated() where v > 0 {
            if v != i + 1 { return false }
        }
        return true
    }

    /// Sum of every tile's Manhattan distance from home — a lower bound on the
    /// remaining moves, used to derive a human par for efficiency scoring.
    static func manhattan(_ tiles: [Int], size: Int) -> Int {
        var total = 0
        for (i, v) in tiles.enumerated() where v > 0 {
            let target = v - 1
            total += abs(i / size - target / size) + abs(i % size - target % size)
        }
        return total
    }

    static func par(manhattan: Int, size: Int) -> Int {
        let factor: Double = size <= 3 ? 1.9 : (size == 4 ? 2.1 : 2.3)
        return max(6, Int((Double(manhattan) * factor).rounded()))
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct SlideBoard: View {
    var size: Int
    var tiles: [Int]
    var flashCell: Int?
    var tapTile: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let spacing: CGFloat = 7
            let inset: CGFloat = 10
            let cell = (side - inset * 2 - spacing * CGFloat(size - 1)) / CGFloat(size)

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.28))
                    .frame(width: side, height: side)

                ForEach(1..<(size * size), id: \.self) { value in
                    if let index = tiles.firstIndex(of: value) {
                        SlideTile(
                            value: value,
                            inPlace: index == value - 1,
                            flashing: flashCell == index,
                            cell: cell
                        )
                        .position(position(index, cell: cell, spacing: spacing, inset: inset, side: side))
                        .onTapGesture { tapTile(index) }
                    }
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.22, dampingFraction: 0.86), value: tiles)
        }
    }

    private func position(_ index: Int, cell: CGFloat, spacing: CGFloat, inset: CGFloat, side: CGFloat) -> CGPoint {
        let row = CGFloat(index / size)
        let col = CGFloat(index % size)
        return CGPoint(
            x: inset + col * (cell + spacing) + cell / 2,
            y: inset + row * (cell + spacing) + cell / 2
        )
    }
}

private struct SlideTile: View {
    var value: Int
    var inPlace: Bool
    var flashing: Bool
    var cell: CGFloat
    private var world: GameWorld { GameID.slidePuzzle.world }

    var body: some View {
        RoundedRectangle(cornerRadius: max(5, cell * 0.10), style: .continuous)
            .fill(inPlace ? world.secondary : world.raised)
            .overlay(
                RoundedRectangle(cornerRadius: max(5, cell * 0.10), style: .continuous)
                    .strokeBorder(flashing ? world.accent : world.ink.opacity(0.18), lineWidth: flashing ? 3 : 1.5)
            )
            .overlay {
                Text("\(value)")
                    .font(.system(size: cell * 0.42, weight: .heavy, design: .rounded))
                    .foregroundStyle(world.ink)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
            }
            .frame(width: cell, height: cell)
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            .animation(.easeOut(duration: 0.16), value: flashing)
            .animation(.easeOut(duration: 0.2), value: inPlace)
            .accessibilityLabel("Tile \(value)")
    }
}
