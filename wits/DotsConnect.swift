//
//  DotsConnect.swift
//  wits
//
//  Flow-style reasoning puzzle: connect matching dot pairs, fill every square,
//  and never let paths cross. Boards come from DotsConnectEngine: a random
//  space-filling route sliced into color segments, so every board is fresh and
//  the slicing itself is the solution hints replay.
//

import SwiftUI

struct DotsConnectSafeAreaBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(light: 0x6C0588, dark: 0x49056C),
                Color(light: 0x135DB7, dark: 0x12366D)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct DotsConnectScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private static let boardsPerRun = 3
    private static let boardPoints = 500
    private static let hintPenalty = 150
    private static let maxHintsPerRun = 2

    private typealias Cell = DotsConnectEngine.Cell

    private struct Puzzle: Identifiable {
        let id = UUID()
        let size: Int
        let paths: [[Cell]]
        let difficulty: Int

        var endpoints: [Int: Set<Cell>] {
            Dictionary(uniqueKeysWithValues: paths.enumerated().map { index, path in
                (index, Set([path.first!, path.last!]))
            })
        }
    }

    @State private var puzzle: Puzzle
    @State private var boardIndex = 1
    @State private var paths: [Int: [Cell]] = [:]
    @State private var activeColor: Int?
    @State private var score = 0
    @State private var solved = 0
    @State private var mistakes = 0
    @State private var hintsUsed = 0
    @State private var bestStreak = 0
    @State private var streak = 0
    @State private var finished = false
    @State private var flash: Bool?

    private let startedAt = Date()
    private let level: Int
    nonisolated private static let maxPathCount = 8

    private static let palette: [Color] = [
        Color(red: 0.13, green: 0.70, blue: 1.00),
        Color(red: 0.98, green: 0.29, blue: 0.78),
        Color(red: 1.00, green: 0.54, blue: 0.12),
        Color(red: 0.21, green: 0.95, blue: 0.08),
        Color(red: 0.56, green: 0.41, blue: 0.86),
        Color(red: 1.00, green: 0.27, blue: 0.21),
        Color(red: 0.99, green: 0.86, blue: 0.18),
        Color(red: 0.22, green: 0.90, blue: 0.78)
    ]

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        self.level = max(1, min(10, Int(floor(cfg.difficulty.level))))
        let first = Self.generatePuzzle(level: cfg.difficulty.level)
        _puzzle = State(initialValue: first)
    }

    private var fillFraction: Double {
        let filled = Set(paths.values.flatMap { $0 }).count + endpointCells.subtracting(Set(paths.values.flatMap { $0 })).count
        return Double(filled) / Double(puzzle.size * puzzle.size)
    }

    private var endpointCells: Set<Cell> {
        Set(puzzle.paths.flatMap { [$0.first!, $0.last!] })
    }

    private var hintsRemaining: Int {
        max(0, Self.maxHintsPerRun - hintsUsed)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                DotsConnectSafeAreaBackground()
                VStack(spacing: 12) {
                    topBar
                        .padding(.horizontal, WitsMetrics.screenPadding)
                    Spacer(minLength: 0)
                    // The board is square, so on tall screens its width is the
                    // binding constraint — hug the screen edges to maximize it.
                    // 184 = top bar + hint row + stack gaps and paddings, so the
                    // height branch keeps the board from overflowing on short
                    // layouts (landscape, iPad splits).
                    board
                        .frame(width: min(geo.size.width - 20, geo.size.height - 184))
                    Spacer(minLength: 0)
                    hintRow
                        .padding(.horizontal, WitsMetrics.screenPadding)
                }
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
        }
        .onAppear { resetPaths() }
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    if cfg.pauseController != nil {
                        cfg.pause()
                    } else {
                        finish()
                    }
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(.white.opacity(0.20), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("pause game")

                VStack(spacing: 1) {
                    Text("level \(level)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                    Text("board \(boardIndex)/\(Self.boardsPerRun)")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(.white.opacity(0.14), in: Capsule())

                HStack(spacing: 8) {
                    Text("score")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .textCase(.lowercase)
                    Text("\(score)")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(.white.opacity(0.14), in: Capsule())
            }

            ProgressTrack(fraction: fillFraction, animated: true)
                .tint(.white)
                .overlay(
                    Capsule()
                        .fill(Self.palette[min(1, Self.palette.count - 1)].opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .scaleEffect(x: fillFraction, y: 1, anchor: .leading)
                )
        }
    }

    private var board: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / CGFloat(puzzle.size)

            boardLayers(cell: cell)
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard !finished, !isRoundSolved else { return }
                        guard let cellCoord = cellCoord(at: value.location, cellSize: cell) else { return }
                        handleDrag(to: cellCoord)
                    }
                    .onEnded { _ in
                        activeColor = nil
                        checkSolved()
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Color(light: 0x271348, dark: 0x130A2A).opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(flash == true ? Color.witsAccent : flash == false ? Color.witsWarm : .clear, lineWidth: 3)
        )
    }

    private func boardLayers(cell: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            gridDots(cell: cell)
            pathStrokes(cell: cell)
            endpointDots(cell: cell)
        }
    }

    private func gridDots(cell: CGFloat) -> some View {
        ForEach(0..<puzzle.size, id: \.self) { row in
            ForEach(0..<puzzle.size, id: \.self) { col in
                let cellCoord = Cell(row: row, col: col)
                Circle()
                    .fill(dotColor(for: cellCoord).opacity(0.25))
                    .frame(width: cell * 0.68, height: cell * 0.68)
                    .position(point(for: cellCoord, cell: cell))
            }
        }
    }

    private func pathStrokes(cell: CGFloat) -> some View {
        ForEach(Array(paths.keys).sorted(), id: \.self) { color in
            if let path = paths[color], path.count > 1 {
                pathShape(path, cell: cell)
                    .stroke(Self.palette[color], style: StrokeStyle(lineWidth: cell * 0.38, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func endpointDots(cell: CGFloat) -> some View {
        ForEach(Array(puzzle.paths.enumerated()), id: \.offset) { color, solution in
            ForEach([solution.first!, solution.last!], id: \.self) { endpoint in
                Circle()
                    .fill(Self.palette[color])
                    .frame(width: cell * 0.40, height: cell * 0.40)
                    .position(point(for: endpoint, cell: cell))
            }
        }
    }

    private var hintRow: some View {
        HStack {
            Spacer()
            Button(action: useHint) {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                    Text("hint")
                }
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .frame(height: 48)
                .background(hintsRemaining == 0 ? Color.witsFaint.opacity(0.35) : Color(red: 0.83, green: 0.03, blue: 0.45), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(hintsRemaining == 0 || unsolvedColors.isEmpty)
        }
    }

    private func point(for cellCoord: Cell, cell: CGFloat) -> CGPoint {
        CGPoint(x: CGFloat(cellCoord.col) * cell + cell / 2, y: CGFloat(cellCoord.row) * cell + cell / 2)
    }

    private func cellCoord(at point: CGPoint, cellSize: CGFloat) -> Cell? {
        let row = Int(point.y / cellSize)
        let col = Int(point.x / cellSize)
        guard row >= 0, row < puzzle.size, col >= 0, col < puzzle.size else { return nil }
        return Cell(row: row, col: col)
    }

    private func pathShape(_ path: [Cell], cell: CGFloat) -> Path {
        var out = Path()
        for (index, cellCoord) in path.enumerated() {
            let point = point(for: cellCoord, cell: cell)
            if index == 0 { out.move(to: point) }
            else { out.addLine(to: point) }
        }
        return out
    }

    private func dotColor(for cellCoord: Cell) -> Color {
        if let color = endpointColor(cellCoord) { return Self.palette[color] }
        return Color.white.opacity(0.22)
    }

    private func endpointColor(_ cellCoord: Cell) -> Int? {
        puzzle.paths.firstIndex { path in
            path.first == cellCoord || path.last == cellCoord
        }
    }

    private func owner(of cellCoord: Cell) -> Int? {
        for (color, path) in paths where path.contains(cellCoord) {
            return color
        }
        return endpointColor(cellCoord)
    }

    private func handleDrag(to cellCoord: Cell) {
        if activeColor == nil {
            guard let color = endpointColor(cellCoord) else { return }
            activeColor = color
            paths[color] = [cellCoord]
            return
        }

        guard let color = activeColor, var path = paths[color], let last = path.last else { return }
        guard isNeighbor(last, cellCoord) || last == cellCoord else { return }
        if last == cellCoord { return }

        if path.count >= 2, path[path.count - 2] == cellCoord {
            path.removeLast()
            paths[color] = path
            return
        }

        // A path whose last cell is the far endpoint is complete: it can be
        // backtracked (above) or restarted, but never extended through the dot.
        if path.count > 1, (puzzle.endpoints[color] ?? []).contains(last) {
            return
        }

        if let owner = owner(of: cellCoord), owner != color {
            mistakes += 1
            flashFeedback(false)
            return
        }

        if let endpoint = endpointColor(cellCoord), endpoint == color {
            let endSet = puzzle.endpoints[color] ?? []
            guard endSet.contains(cellCoord) else { return }
        } else if endpointColor(cellCoord) != nil {
            return
        }

        if let existing = path.firstIndex(of: cellCoord) {
            paths[color] = Array(path.prefix(existing + 1))
            return
        }

        path.append(cellCoord)
        paths[color] = path
    }

    private func isNeighbor(_ a: Cell, _ b: Cell) -> Bool {
        abs(a.row - b.row) + abs(a.col - b.col) == 1
    }

    private var isRoundSolved: Bool {
        guard connectedColors.count == puzzle.paths.count else { return false }
        let filled = Set(paths.values.flatMap { $0 })
        return filled.count == puzzle.size * puzzle.size
    }

    private var connectedColors: Set<Int> {
        Set(paths.compactMap { color, path in
            guard let first = path.first, let last = path.last else { return nil }
            let endpoints = puzzle.endpoints[color] ?? []
            return endpoints == Set([first, last]) ? color : nil
        })
    }

    private var unsolvedColors: [Int] {
        puzzle.paths.indices.filter { !connectedColors.contains($0) }
    }

    private func checkSolved() {
        guard isRoundSolved else { return }
        solved += 1
        streak += 1
        bestStreak = max(bestStreak, streak)
        let clearBonus = max(0, 150 - hintsUsed * 40 - mistakes * 10)
        score += Self.boardPoints + clearBonus
        cfg.report(.hit, points: Self.boardPoints + clearBonus, combo: streak)
        flashFeedback(true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            guard !finished else { return }
            if boardIndex >= Self.boardsPerRun {
                finish()
            } else {
                boardIndex += 1
                puzzle = Self.generatePuzzle(level: Double(level))
                resetPaths()
            }
        }
    }

    private func useHint() {
        guard hintsRemaining > 0, let color = unsolvedColors.first else { return }
        let solution = puzzle.paths[color]
        var newPaths = paths
        for (otherColor, path) in paths where otherColor != color {
            let kept = path.filter { !solution.contains($0) }
            newPaths[otherColor] = kept.count >= 1 ? kept : []
        }
        newPaths[color] = solution
        paths = newPaths
        hintsUsed += 1
        mistakes += 1
        streak = 0
        score = max(0, score - Self.hintPenalty)
        cfg.report(.miss)
        checkSolved()
    }

    private func resetPaths() {
        activeColor = nil
        paths = Dictionary(uniqueKeysWithValues: puzzle.paths.indices.map { color in
            (color, [])
        })
        flash = nil
    }

    private func flashFeedback(_ ok: Bool) {
        flash = ok
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            flash = nil
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        let completion = Double(solved) / Double(Self.boardsPerRun)
        let penalty = min(0.35, Double(mistakes) * 0.03 + Double(hintsUsed) * 0.10)
        let accuracy = max(0, completion - penalty)
        var result = GameResult(game: .dotsConnect, score: score, accuracy: max(0, min(1, accuracy)))
        result.trials = Self.boardsPerRun
        result.startedAt = startedAt
        result.durationMs = Int(cfg.activeElapsed(since: startedAt) * 1000)
        result.raw = [
            "boardsSolved": Double(solved),
            "bestStreak": Double(bestStreak),
            "hintsUsed": Double(hintsUsed),
            "mistakes": Double(mistakes),
            "gridSize": Double(puzzle.size),
            "levelStart": Double(level),
            "puzzleDifficulty": Double(puzzle.difficulty)
        ]
        onResult(result)
    }

    private static func generatePuzzle(level: Double) -> Puzzle {
        let levelNumber = min(10, max(1, Int(floor(level))))
        let size = levelNumber <= 3 ? 5 : levelNumber <= 6 ? 6 : 7
        let pathCount = min(maxPathCount, max(4, 3 + Int(ceil(Double(levelNumber) / 2.0))))
        let board = DotsConnectEngine.generate(size: size, pathCount: pathCount)
        return Puzzle(size: board.size, paths: board.paths, difficulty: levelNumber)
    }
}

// MARK: - Board generation

/// Procedural Flow-board generator: a random space-filling route (self-avoiding
/// path visiting every cell) sliced into color segments. The slicing is itself
/// a solution, so every board is solvable by construction, and randomizing the
/// route means there is no fixed catalog of snakes and spirals to memorize.
enum DotsConnectEngine {
    struct Cell: Hashable {
        let row: Int
        let col: Int
    }

    struct Board {
        let size: Int
        let paths: [[Cell]]
    }

    static let minPathLength = 3

    static func generate(size: Int, pathCount: Int) -> Board {
        for _ in 0..<40 {
            guard let route = randomFillingRoute(size: size) else { continue }
            for _ in 0..<30 {
                if let paths = slicedPaths(route: route, count: pathCount) {
                    return Board(size: size, paths: paths)
                }
            }
        }

        // Backstop so the screen always gets a board (practically unreachable):
        // a plain row snake split into equal runs, no quality checks.
        let route = rowSnake(size: size)
        let base = route.count / pathCount
        var lengths = Array(repeating: base, count: pathCount)
        for index in 0..<(route.count - base * pathCount) { lengths[index] += 1 }
        var paths: [[Cell]] = []
        var start = 0
        for length in lengths {
            paths.append(Array(route[start..<(start + length)]))
            start += length
        }
        return Board(size: size, paths: paths)
    }

    /// Random self-avoiding route through every cell: backtracking DFS from a
    /// random start that visits tight cells first (Warnsdorff's heuristic), so
    /// dead ends stay rare even at 7×7. The step budget abandons the rare
    /// hopeless start instead of grinding; callers just retry.
    static func randomFillingRoute(size: Int) -> [Cell]? {
        let total = size * size
        var visited = Array(repeating: false, count: total)
        var route: [Cell] = []
        var steps = 0

        func neighbors(_ c: Cell) -> [Cell] {
            var out: [Cell] = []
            if c.row > 0 { out.append(Cell(row: c.row - 1, col: c.col)) }
            if c.row < size - 1 { out.append(Cell(row: c.row + 1, col: c.col)) }
            if c.col > 0 { out.append(Cell(row: c.row, col: c.col - 1)) }
            if c.col < size - 1 { out.append(Cell(row: c.row, col: c.col + 1)) }
            return out
        }
        func exits(_ c: Cell) -> Int {
            neighbors(c).filter { !visited[$0.row * size + $0.col] }.count
        }
        func extend() -> Bool {
            if route.count == total { return true }
            steps += 1
            if steps > 3_000 { return false }
            let options = neighbors(route.last!)
                .filter { !visited[$0.row * size + $0.col] }
                .shuffled()
                .sorted { exits($0) < exits($1) }
            for next in options {
                visited[next.row * size + next.col] = true
                route.append(next)
                if extend() { return true }
                route.removeLast()
                visited[next.row * size + next.col] = false
            }
            return false
        }

        let start = Cell(row: Int.random(in: 0..<size), col: Int.random(in: 0..<size))
        visited[start.row * size + start.col] = true
        route.append(start)
        return extend() ? route : nil
    }

    /// Cut the route into `count` segments of random lengths. Returns nil —
    /// caller retries with fresh cuts — when a segment would be shorter than
    /// `minPathLength`, hog the board, or end orthogonally adjacent to its own
    /// start (touching endpoints solve with a single flick and read as noise).
    static func slicedPaths(route: [Cell], count: Int) -> [[Cell]]? {
        guard count > 0 else { return nil }
        let extra = route.count - minPathLength * count
        guard extra >= 0 else { return nil }
        let maxLength = max(minPathLength, route.count * 2 / count)

        var lengths = Array(repeating: minPathLength, count: count)
        for _ in 0..<extra { lengths[Int.random(in: 0..<count)] += 1 }

        var paths: [[Cell]] = []
        var start = 0
        for length in lengths {
            guard length <= maxLength else { return nil }
            let segment = Array(route[start..<(start + length)])
            guard let first = segment.first, let last = segment.last,
                  abs(first.row - last.row) + abs(first.col - last.col) > 1 else { return nil }
            paths.append(segment)
            start += length
        }
        return paths
    }

    static func rowSnake(size: Int) -> [Cell] {
        var cells: [Cell] = []
        for row in 0..<size {
            let columns = row.isMultiple(of: 2) ? Array(0..<size) : Array((0..<size).reversed())
            for col in columns { cells.append(Cell(row: row, col: col)) }
        }
        return cells
    }
}
