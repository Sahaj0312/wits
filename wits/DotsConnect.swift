//
//  DotsConnect.swift
//  wits
//
//  Flow-style reasoning puzzle: connect matching dot pairs, fill every square,
//  and never let paths cross. Hand-authored solutions keep every board solvable
//  and make hints deterministic.
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

    private struct Cell: Hashable {
        let row: Int
        let col: Int
    }

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

    private static let palette: [Color] = [
        Color(red: 0.13, green: 0.70, blue: 1.00),
        Color(red: 0.98, green: 0.29, blue: 0.78),
        Color(red: 1.00, green: 0.54, blue: 0.12),
        Color(red: 0.21, green: 0.95, blue: 0.08),
        Color(red: 0.56, green: 0.41, blue: 0.86)
    ]

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        self.level = max(1, min(10, Int(floor(cfg.difficulty.level))))
        let first = Self.pickPuzzle(level: cfg.difficulty.level, excluding: [])
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
                    Spacer(minLength: 0)
                    board
                        .frame(width: min(geo.size.width - WitsMetrics.screenPadding * 2, geo.size.height * 0.58))
                    Spacer(minLength: 0)
                    hintRow
                }
                .padding(.horizontal, WitsMetrics.screenPadding)
                .padding(.top, geo.safeAreaInsets.top + 8)
                .padding(.bottom, geo.safeAreaInsets.bottom + 12)
            }
        }
        .onAppear { resetPaths() }
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    finish()
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(.white.opacity(0.20), in: Circle())
                }
                .buttonStyle(.plain)

                Text("\(boardIndex)/\(Self.boardsPerRun)")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
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
                puzzle = Self.pickPuzzle(level: Double(level), excluding: [puzzle.id])
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
        let accuracy = Double(max(0, solved * 3 - mistakes - hintsUsed)) / Double(Self.boardsPerRun * 3)
        var result = GameResult(game: .dotsConnect, score: score, accuracy: max(0, min(1, accuracy)))
        result.trials = Self.boardsPerRun
        result.startedAt = startedAt
        result.durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        result.raw = [
            "boardsSolved": Double(solved),
            "bestStreak": Double(bestStreak),
            "hintsUsed": Double(hintsUsed),
            "mistakes": Double(mistakes),
            "gridSize": Double(puzzle.size)
        ]
        onResult(result)
    }

    private static func pickPuzzle(level: Double, excluding excludedIDs: [Puzzle.ID]) -> Puzzle {
        let tier = level < 4 ? 1 : level < 8 ? 2 : 3
        let pool = puzzles.filter { $0.difficulty <= tier }
        return pool.filter { !excludedIDs.contains($0.id) }.randomElement() ?? pool.randomElement() ?? puzzles[0]
    }

    private static let puzzles: [Puzzle] = [
        Puzzle(size: 5, paths: [
            [Cell(row: 0, col: 0), Cell(row: 1, col: 0), Cell(row: 2, col: 0), Cell(row: 3, col: 0), Cell(row: 4, col: 0)],
            [Cell(row: 0, col: 1), Cell(row: 0, col: 2), Cell(row: 0, col: 3), Cell(row: 0, col: 4), Cell(row: 1, col: 4), Cell(row: 2, col: 4), Cell(row: 3, col: 4), Cell(row: 4, col: 4)],
            [Cell(row: 1, col: 1), Cell(row: 1, col: 2), Cell(row: 1, col: 3), Cell(row: 2, col: 3), Cell(row: 3, col: 3), Cell(row: 3, col: 2), Cell(row: 2, col: 2)],
            [Cell(row: 2, col: 1), Cell(row: 3, col: 1), Cell(row: 4, col: 1), Cell(row: 4, col: 2), Cell(row: 4, col: 3)]
        ], difficulty: 1),
        Puzzle(size: 5, paths: [
            [Cell(row: 0, col: 0), Cell(row: 0, col: 1), Cell(row: 0, col: 2), Cell(row: 0, col: 3), Cell(row: 0, col: 4)],
            [Cell(row: 1, col: 0), Cell(row: 1, col: 1), Cell(row: 1, col: 2), Cell(row: 1, col: 3), Cell(row: 1, col: 4), Cell(row: 2, col: 4), Cell(row: 3, col: 4), Cell(row: 4, col: 4)],
            [Cell(row: 2, col: 0), Cell(row: 3, col: 0), Cell(row: 4, col: 0), Cell(row: 4, col: 1), Cell(row: 3, col: 1), Cell(row: 2, col: 1)],
            [Cell(row: 2, col: 2), Cell(row: 2, col: 3), Cell(row: 3, col: 3), Cell(row: 3, col: 2), Cell(row: 4, col: 2), Cell(row: 4, col: 3)]
        ], difficulty: 1),
        Puzzle(size: 6, paths: [
            [Cell(row: 0, col: 0), Cell(row: 1, col: 0), Cell(row: 2, col: 0), Cell(row: 3, col: 0), Cell(row: 4, col: 0), Cell(row: 5, col: 0)],
            [Cell(row: 0, col: 1), Cell(row: 0, col: 2), Cell(row: 0, col: 3), Cell(row: 0, col: 4), Cell(row: 0, col: 5), Cell(row: 1, col: 5), Cell(row: 2, col: 5), Cell(row: 3, col: 5)],
            [Cell(row: 1, col: 1), Cell(row: 1, col: 2), Cell(row: 2, col: 2), Cell(row: 3, col: 2), Cell(row: 3, col: 1), Cell(row: 2, col: 1)],
            [Cell(row: 1, col: 3), Cell(row: 1, col: 4), Cell(row: 2, col: 4), Cell(row: 3, col: 4), Cell(row: 4, col: 4), Cell(row: 4, col: 5), Cell(row: 5, col: 5)],
            [Cell(row: 2, col: 3), Cell(row: 3, col: 3), Cell(row: 4, col: 3), Cell(row: 5, col: 3), Cell(row: 5, col: 2), Cell(row: 5, col: 1), Cell(row: 4, col: 1), Cell(row: 4, col: 2), Cell(row: 5, col: 4)]
        ], difficulty: 2)
    ]
}
