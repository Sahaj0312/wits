//
//  OneLine.swift
//  wits
//
//  One-stroke graph puzzle. Draw every segment exactly once. Puzzles are built
//  from generated Euler trails, so each board is solvable while still varying
//  by level, graph size, layout, and edge density.
//

import SwiftUI

struct OneLineSafeAreaBackground: View {
    var body: some View {
        ZStack {
            Color.witsBg
            LinearGradient(
                colors: [
                    Color.witsAccent.opacity(0.12),
                    Color.witsWarm.opacity(0.07),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct OneLineScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private static let boardsPerRun = 3
    private static let maxHintsPerRun = 3
    private static let hintPenalty = 180
    private static let resetPenalty = 80

    private struct Node: Identifiable {
        let id: Int
        let point: CGPoint
    }

    private struct Edge: Identifiable, Hashable {
        let id: Int
        let a: Int
        let b: Int

        func connects(_ lhs: Int, _ rhs: Int) -> Bool {
            (a == lhs && b == rhs) || (a == rhs && b == lhs)
        }

        func other(_ node: Int) -> Int {
            node == a ? b : a
        }
    }

    private struct Puzzle: Identifiable {
        let id: String
        let difficulty: Int
        let variant: Int
        let nodes: [Node]
        let edges: [Edge]
        let solutionStart: Int

        var complexityLabel: String {
            switch edges.count {
            case ..<8: "light"
            case 8..<14: "steady"
            case 14..<21: "dense"
            default: "expert"
            }
        }

        func node(_ id: Int) -> Node? {
            nodes.first { $0.id == id }
        }

        func edge(id: Int) -> Edge? {
            edges.first { $0.id == id }
        }

        func edge(between a: Int, and b: Int, excluding used: Set<Int>) -> Edge? {
            edges.first { edge in
                !used.contains(edge.id) && edge.connects(a, b)
            }
        }

        func unusedEdges(from node: Int, excluding used: Set<Int>) -> [Edge] {
            edges.filter { !used.contains($0.id) && ($0.a == node || $0.b == node) }
        }
    }

    private struct LevelSpec {
        let level: Int
        let nodeRange: ClosedRange<Int>
        let edgeRange: ClosedRange<Int>
    }

    private struct Pair: Hashable {
        let a: Int
        let b: Int

        init(_ lhs: Int, _ rhs: Int) {
            self.a = min(lhs, rhs)
            self.b = max(lhs, rhs)
        }
    }

    private enum BoardLayout: CaseIterable {
        case ring, grid, lattice, split, diamond
    }

    private struct SeededRandom {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }

        mutating func int(in range: ClosedRange<Int>) -> Int {
            let width = UInt64(range.upperBound - range.lowerBound + 1)
            return range.lowerBound + Int(next() % width)
        }

        mutating func double(in range: ClosedRange<Double>) -> Double {
            let unit = Double(next() & 0xFFFF_FFFF) / Double(UInt32.max)
            return range.lowerBound + unit * (range.upperBound - range.lowerBound)
        }

        mutating func shuffled<T>(_ values: [T]) -> [T] {
            var out = values
            guard out.count > 1 else { return out }
            for index in stride(from: out.count - 1, through: 1, by: -1) {
                let swapIndex = int(in: 0...index)
                out.swapAt(index, swapIndex)
            }
            return out
        }
    }

    @State private var puzzle: Puzzle
    @State private var recentPuzzleIDs: [String] = []
    @State private var boardIndex = 1
    @State private var currentNode: Int?
    @State private var usedEdges: Set<Int> = []
    @State private var routeNodes: [Int] = []
    @State private var routeEdges: [Int] = []
    @State private var lastDragNode: Int?
    @State private var hintedEdgeID: Int?
    @State private var hintedStartID: Int?
    @State private var boardSolved = false
    @State private var finished = false
    @State private var score = 0
    @State private var solvedBoards = 0
    @State private var perfectBoards = 0
    @State private var cleanStreak = 0
    @State private var bestStreak = 0
    @State private var mistakes = 0
    @State private var hintsUsed = 0
    @State private var resets = 0
    @State private var undos = 0
    @State private var boardMistakes = 0
    @State private var boardHints = 0
    @State private var boardResets = 0
    @State private var boardUndos = 0
    @State private var validTraversals = 0
    @State private var solvedEdges = 0
    @State private var presentedEdges: Int
    @State private var cumulativePuzzleDifficulty: Int
    @State private var hardestPuzzleDifficulty: Int
    @State private var shakeTrigger = 0
    @State private var flash: Bool?

    private let startedAt = Date()
    private let runLevel: Int

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        self.runLevel = max(1, min(10, Int(floor(cfg.difficulty.level))))
        let first = Self.pickPuzzle(level: cfg.difficulty.level, boardIndex: 1, excluding: [])
        _puzzle = State(initialValue: first)
        _presentedEdges = State(initialValue: first.edges.count)
        _cumulativePuzzleDifficulty = State(initialValue: first.difficulty)
        _hardestPuzzleDifficulty = State(initialValue: first.difficulty)
    }

    private var progressFraction: Double {
        let completed = Double(boardIndex - 1) / Double(Self.boardsPerRun)
        let current = puzzle.edges.isEmpty ? 0 : Double(usedEdges.count) / Double(puzzle.edges.count * Self.boardsPerRun)
        return min(1, max(0, completed + current))
    }

    private var hintsRemaining: Int {
        max(0, Self.maxHintsPerRun - hintsUsed)
    }

    private var canUndo: Bool {
        !boardSolved && (currentNode != nil || !routeEdges.isEmpty)
    }

    private var canReset: Bool {
        !boardSolved && (currentNode != nil || !usedEdges.isEmpty)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let boardWidth = min(width - 28, 520)
            let availableHeight = max(300, geo.size.height - 230)
            let boardHeight = min(availableHeight, boardWidth * 1.10)
            let controlInset = max(18, min(42, width * 0.09))
            let controlSize = min(72, max(56, (width - controlInset * 2 - 56) / 3))

            ZStack {
                OneLineSafeAreaBackground()
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, WitsMetrics.screenPadding)
                        .padding(.top, 14)

                    Spacer(minLength: 12)

                    board
                        .frame(width: boardWidth, height: boardHeight)
                        .modifier(WitsShake(trigger: shakeTrigger, intensity: 7))

                    Spacer(minLength: 14)

                    controlBar(buttonSize: controlSize)
                        .padding(.horizontal, controlInset)
                        .padding(.bottom, 16)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                        .foregroundStyle(Color.witsInk)
                        .frame(width: 44, height: 44)
                        .background(Color.witsCard.opacity(0.86), in: Circle())
                        .overlay(Circle().strokeBorder(Color.witsLine, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("pause game")

                VStack(alignment: .leading, spacing: 6) {
                    Text("one line")
                        .font(.system(size: 21, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        headerChip("level \(puzzle.difficulty)")
                        headerChip("board \(boardIndex)/\(Self.boardsPerRun)")
                        headerChip("\(puzzle.edges.count) lines")
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(score)")
                        .font(.system(size: 25, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                        .monospacedDigit()
                    Text("score")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsFaint)
                }
                .frame(minWidth: 72, alignment: .trailing)
            }

            OneLineProgressBar(fraction: progressFraction)
                .frame(height: 8)
        }
    }

    private func headerChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.witsMuted)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.witsTint, in: Capsule())
    }

    private var board: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                subtleGrid(in: size)

                ForEach(puzzle.edges) { edge in
                    if !usedEdges.contains(edge.id) {
                        edgePath(edge, in: size)
                            .stroke(Color.witsLine.opacity(0.82),
                                    style: StrokeStyle(lineWidth: edgeWidth(in: size), lineCap: .round, lineJoin: .round))
                    }
                }

                if let hintedEdgeID, let edge = puzzle.edge(id: hintedEdgeID), !usedEdges.contains(edge.id) {
                    edgePath(edge, in: size)
                        .stroke(Color.witsWarm.opacity(0.92),
                                style: StrokeStyle(lineWidth: edgeWidth(in: size) + 4, lineCap: .round, lineJoin: .round, dash: [10, 8]))
                }

                ForEach(puzzle.edges) { edge in
                    if usedEdges.contains(edge.id) {
                        edgePath(edge, in: size)
                            .stroke(Color.witsAccent,
                                    style: StrokeStyle(lineWidth: edgeWidth(in: size) + 3, lineCap: .round, lineJoin: .round))
                    }
                }

                ForEach(puzzle.nodes) { node in
                    nodeView(node, in: size)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard let node = hitNode(at: value.location, in: size), node != lastDragNode else { return }
                        lastDragNode = node
                        tapNode(node)
                    }
                    .onEnded { _ in
                        lastDragNode = nil
                    }
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(flash == true ? Color.witsAccent.opacity(0.34) : flash == false ? Color.witsWarm.opacity(0.40) : .clear,
                                  lineWidth: 3)
                    .allowsHitTesting(false)
            }
        }
    }

    private func subtleGrid(in size: CGSize) -> some View {
        Canvas { ctx, canvasSize in
            let step = max(38, min(canvasSize.width, canvasSize.height) / 7)
            var path = Path()
            var x: CGFloat = 0
            while x <= canvasSize.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= canvasSize.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: canvasSize.width, y: y))
                y += step
            }
            ctx.stroke(path, with: .color(Color.witsLine.opacity(0.16)), lineWidth: 1)
        }
    }

    private func controlBar(buttonSize: CGFloat) -> some View {
        HStack(spacing: 18) {
            OneLineIconButton(symbol: "arrow.uturn.backward", accessibilityLabel: "undo", size: buttonSize, enabled: canUndo, action: undo)
            OneLineIconButton(symbol: "arrow.counterclockwise", accessibilityLabel: "reset", size: buttonSize, enabled: canReset, action: resetBoard)
            OneLineIconButton(symbol: "lightbulb", accessibilityLabel: "hint", size: buttonSize, enabled: hintsRemaining > 0 && !boardSolved, badge: "\(hintsRemaining)", action: useHint)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.witsCard.opacity(0.88), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.witsLine, lineWidth: 1))
        .shadow(color: Color.witsShadow, radius: 10, y: 6)
    }

    private func nodeView(_ node: Node, in size: CGSize) -> some View {
        let diameter = nodeDiameter(in: size)
        let isCurrent = currentNode == node.id
        let isStartHint = hintedStartID == node.id
        return Circle()
            .fill(isCurrent ? Color.witsWarm : Color.witsCard)
            .frame(width: diameter, height: diameter)
            .overlay {
                Circle()
                    .strokeBorder(isStartHint ? Color.witsWarm : Color.witsAccent,
                                  lineWidth: isCurrent || isStartHint ? 4 : 2.5)
            }
            .shadow(color: (isCurrent ? Color.witsWarm : Color.witsAccent).opacity(isCurrent ? 0.34 : 0.18),
                    radius: isCurrent ? 12 : 7,
                    y: 4)
            .scaleEffect(isCurrent ? 1.08 : 1)
            .position(point(for: node.id, in: size))
            .onTapGesture { tapNode(node.id) }
            .accessibilityLabel("node \(node.id)")
            .accessibilityAddTraits(.isButton)
            .animation(.easeOut(duration: 0.14), value: isCurrent)
            .animation(.easeOut(duration: 0.14), value: isStartHint)
    }

    private func edgePath(_ edge: Edge, in size: CGSize) -> Path {
        var path = Path()
        path.move(to: point(for: edge.a, in: size))
        path.addLine(to: point(for: edge.b, in: size))
        return path
    }

    private func point(for nodeID: Int, in size: CGSize) -> CGPoint {
        guard let node = puzzle.node(nodeID) else { return .zero }
        let inset = max(26, min(size.width, size.height) * 0.085)
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
        return CGPoint(
            x: rect.minX + node.point.x * rect.width,
            y: rect.minY + node.point.y * rect.height
        )
    }

    private func edgeWidth(in size: CGSize) -> CGFloat {
        max(4.2, min(size.width, size.height) * 0.011)
    }

    private func nodeDiameter(in size: CGSize) -> CGFloat {
        max(28, min(52, min(size.width, size.height) * 0.082))
    }

    private func hitNode(at location: CGPoint, in size: CGSize) -> Int? {
        let radius = nodeDiameter(in: size) * 0.82
        let candidates = puzzle.nodes.map { node -> (id: Int, distance: CGFloat) in
            let p = point(for: node.id, in: size)
            return (node.id, hypot(p.x - location.x, p.y - location.y))
        }
        guard let nearest = candidates.min(by: { $0.distance < $1.distance }), nearest.distance <= radius else {
            return nil
        }
        return nearest.id
    }

    private func tapNode(_ nodeID: Int) {
        guard !finished, !boardSolved, !cfg.isPaused else { return }
        defer {
            if hintedStartID == nodeID { hintedStartID = nil }
        }

        guard let from = currentNode else {
            currentNode = nodeID
            routeNodes = [nodeID]
            hintedEdgeID = nil
            return
        }

        guard from != nodeID else { return }
        guard let edge = puzzle.edge(between: from, and: nodeID, excluding: usedEdges) else {
            registerMistake()
            return
        }

        usedEdges.insert(edge.id)
        routeEdges.append(edge.id)
        routeNodes.append(nodeID)
        currentNode = nodeID
        hintedEdgeID = nil
        hintedStartID = nil
        validTraversals += 1

        if usedEdges.count == puzzle.edges.count {
            solveBoard()
        }
    }

    private func undo() {
        guard !boardSolved else { return }
        if let edgeID = routeEdges.popLast() {
            usedEdges.remove(edgeID)
            if !routeNodes.isEmpty { routeNodes.removeLast() }
            currentNode = routeNodes.last
            undos += 1
            boardUndos += 1
            hintedEdgeID = nil
            cfg.report(.nearMiss)
        } else if currentNode != nil {
            currentNode = nil
            routeNodes.removeAll()
            hintedStartID = nil
        }
    }

    private func resetBoard() {
        guard canReset else { return }
        usedEdges.removeAll()
        routeEdges.removeAll()
        routeNodes.removeAll()
        currentNode = nil
        hintedEdgeID = nil
        hintedStartID = nil
        resets += 1
        boardResets += 1
        score = max(0, score - Self.resetPenalty)
        cfg.report(.nearMiss)
    }

    private func useHint() {
        guard hintsRemaining > 0, !boardSolved else { return }
        let remaining = puzzle.edges.filter { !usedEdges.contains($0.id) }
        guard !remaining.isEmpty else { return }

        if let currentNode {
            if let trail = Self.eulerTrail(from: currentNode, edges: remaining), let next = trail.first {
                hintedEdgeID = next
                hintedStartID = nil
            } else if let edge = puzzle.unusedEdges(from: currentNode, excluding: usedEdges).first {
                hintedEdgeID = edge.id
                hintedStartID = nil
            } else {
                registerMistake()
                return
            }
        } else {
            hintedStartID = suggestedStartNode(for: remaining)
            hintedEdgeID = nil
        }

        hintsUsed += 1
        boardHints += 1
        score = max(0, score - Self.hintPenalty)
        cfg.report(.nearMiss)
    }

    private func suggestedStartNode(for edges: [Edge]) -> Int {
        let degrees = Self.degrees(for: edges)
        let odd = degrees.keys.sorted().filter { !(degrees[$0] ?? 0).isMultiple(of: 2) }
        return odd.first ?? puzzle.solutionStart
    }

    private func registerMistake() {
        mistakes += 1
        boardMistakes += 1
        hintedEdgeID = nil
        hintedStartID = nil
        flashFeedback(false)
        shakeTrigger += 1
        cfg.report(.miss)
    }

    private func solveBoard() {
        guard !boardSolved else { return }
        boardSolved = true
        solvedBoards += 1
        solvedEdges += puzzle.edges.count

        let clean = boardMistakes == 0 && boardHints == 0 && boardResets == 0
        if clean {
            perfectBoards += 1
            cleanStreak += 1
        } else {
            cleanStreak = 0
        }
        bestStreak = max(bestStreak, cleanStreak)

        let complexity = puzzle.edges.count * 44 + puzzle.nodes.count * 16 + puzzle.difficulty * 42
        let cleanBonus = clean ? 280 : max(0, 180 - boardMistakes * 45 - boardHints * 70 - boardResets * 55 - boardUndos * 12)
        let points = max(220, 420 + complexity + cleanBonus)
        score += points
        flashFeedback(true)
        cfg.report(.hit, points: points, combo: solvedBoards)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
            guard !finished else { return }
            if boardIndex >= Self.boardsPerRun {
                finish()
            } else {
                recentPuzzleIDs.append(puzzle.id)
                recentPuzzleIDs = Array(recentPuzzleIDs.suffix(12))
                boardIndex += 1
                let next = Self.pickPuzzle(level: Double(runLevel), boardIndex: boardIndex, excluding: recentPuzzleIDs)
                puzzle = next
                presentedEdges += next.edges.count
                cumulativePuzzleDifficulty += next.difficulty
                hardestPuzzleDifficulty = max(hardestPuzzleDifficulty, next.difficulty)
                resetBoardState()
            }
        }
    }

    private func resetBoardState() {
        currentNode = nil
        usedEdges.removeAll()
        routeNodes.removeAll()
        routeEdges.removeAll()
        hintedEdgeID = nil
        hintedStartID = nil
        boardSolved = false
        boardMistakes = 0
        boardHints = 0
        boardResets = 0
        boardUndos = 0
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

        let currentBoardEdges = boardSolved ? 0 : usedEdges.count
        let correctEdges = solvedEdges + currentBoardEdges
        let totalEdges = max(1, presentedEdges)
        let completion = Double(solvedBoards) / Double(Self.boardsPerRun)
        let assistCost = Double(mistakes) * 0.035
            + Double(hintsUsed) * 0.085
            + Double(resets) * 0.065
            + Double(undos) * 0.012
        let moveQuality = Double(max(0, correctEdges)) / Double(max(totalEdges, correctEdges + mistakes + hintsUsed * 2 + resets * 2))
        let accuracy = max(0, min(1, 0.68 * completion + 0.32 * moveQuality - min(0.42, assistCost)))
        let avgPuzzleDifficulty = Double(cumulativePuzzleDifficulty) / Double(max(1, boardIndex))

        var result = GameResult(game: .oneLine, score: score, accuracy: accuracy)
        result.trials = Self.boardsPerRun
        result.startedAt = startedAt
        result.durationMs = Int(cfg.activeElapsed(since: startedAt) * 1000)
        result.raw = [
            "boardsSolved": Double(solvedBoards),
            "perfectBoards": Double(perfectBoards),
            "bestStreak": Double(bestStreak),
            "mistakes": Double(mistakes),
            "hintsUsed": Double(hintsUsed),
            "resets": Double(resets),
            "undos": Double(undos),
            "correctEdges": Double(correctEdges),
            "validTraversals": Double(validTraversals),
            "totalEdges": Double(totalEdges),
            "levelStart": Double(runLevel),
            "avgPuzzleDifficulty": avgPuzzleDifficulty,
            "puzzleDifficulty": Double(hardestPuzzleDifficulty),
            "oneLineMoveQuality": moveQuality,
            "timeOnTaskMs": Double(result.durationMs)
        ]
        onResult(result)
    }

    private static func pickPuzzle(level: Double, boardIndex: Int, excluding excludedIDs: [String]) -> Puzzle {
        let targetLevel = boardLevel(base: min(10, max(1, Int(floor(level)))), boardIndex: boardIndex)
        let exactPool = puzzlesByLevel[targetLevel] ?? []
        let nearbyPool = puzzles.filter { max(1, targetLevel - 1)...min(10, targetLevel + 1) ~= $0.difficulty }
        let pool = exactPool.isEmpty ? nearbyPool : exactPool
        let fresh = pool.filter { !excludedIDs.contains($0.id) }
        return fresh.randomElement() ?? pool.randomElement() ?? puzzles[0]
    }

    private static func boardLevel(base: Int, boardIndex: Int) -> Int {
        min(10, max(1, base + boardIndex - 1))
    }

    private static let puzzles: [Puzzle] = makePuzzles()
    private static let puzzlesByLevel: [Int: [Puzzle]] = Dictionary(grouping: puzzles, by: \.difficulty)

    private static let specs: [LevelSpec] = [
        LevelSpec(level: 1, nodeRange: 4...5, edgeRange: 5...6),
        LevelSpec(level: 2, nodeRange: 5...6, edgeRange: 6...8),
        LevelSpec(level: 3, nodeRange: 6...7, edgeRange: 8...10),
        LevelSpec(level: 4, nodeRange: 7...8, edgeRange: 10...13),
        LevelSpec(level: 5, nodeRange: 8...9, edgeRange: 12...15),
        LevelSpec(level: 6, nodeRange: 8...10, edgeRange: 14...18),
        LevelSpec(level: 7, nodeRange: 9...11, edgeRange: 16...21),
        LevelSpec(level: 8, nodeRange: 10...12, edgeRange: 19...24),
        LevelSpec(level: 9, nodeRange: 11...13, edgeRange: 22...27),
        LevelSpec(level: 10, nodeRange: 12...14, edgeRange: 25...30)
    ]

    private static func makePuzzles() -> [Puzzle] {
        specs.flatMap { spec in
            (0..<40).map { variant in
                makePuzzle(spec: spec, variant: variant)
            }
        }
    }

    private static func makePuzzle(spec: LevelSpec, variant: Int) -> Puzzle {
        let nodeSpan = spec.nodeRange.upperBound - spec.nodeRange.lowerBound + 1
        let edgeSpan = spec.edgeRange.upperBound - spec.edgeRange.lowerBound + 1
        let preferredNodeCount = spec.nodeRange.lowerBound + (variant + variant / 7) % nodeSpan
        let edgeCount = spec.edgeRange.lowerBound + (variant + variant / 3 + spec.level) % edgeSpan
        let layoutOffset = (variant + spec.level) % BoardLayout.allCases.count
        let layouts = Array(BoardLayout.allCases.dropFirst(layoutOffset)) + Array(BoardLayout.allCases.prefix(layoutOffset))
        let nodeCounts = uniqueInts([preferredNodeCount, spec.nodeRange.upperBound] + Array(spec.nodeRange).reversed())

        for nodeCount in nodeCounts {
            for (layoutAttempt, layout) in layouts.enumerated() {
                var rng = SeededRandom(seed: UInt64(spec.level * 10_000 + variant * 97 + nodeCount * 13 + layoutAttempt * 19 + 31))
                let points = makePoints(count: nodeCount, layout: layout, level: spec.level, variant: variant, rng: &rng)
                let targetEdges = min(edgeCount, nodeCount * (nodeCount - 1) / 2)
                let candidatePairs = candidates(points: points, level: spec.level, layout: layout, relaxed: false)
                let relaxedPairs = candidates(points: points, level: spec.level, layout: layout, relaxed: true)

                if let trail = makeTrail(nodeCount: nodeCount,
                                         targetEdges: targetEdges,
                                         candidatePairs: candidatePairs,
                                         variant: variant)
                    ?? makeTrail(nodeCount: nodeCount,
                                 targetEdges: targetEdges,
                                 candidatePairs: relaxedPairs,
                                 variant: variant)
                    ?? makeTrail(nodeCount: nodeCount,
                                 targetEdges: targetEdges,
                                 candidatePairs: allPairs(count: nodeCount),
                                 variant: variant) {
                    let candidate = makePuzzle(spec: spec, variant: variant, points: points, trail: trail)
                    if shapeIsReadable(candidate, spec: spec) {
                        return candidate
                    }
                }
            }
        }

        let nodeCount = spec.nodeRange.upperBound
        var rng = SeededRandom(seed: UInt64(spec.level * 10_000 + variant * 97 + 31))
        let points = makePoints(count: nodeCount, layout: .grid, level: spec.level, variant: variant, rng: &rng)
        let trail = Array(0..<nodeCount) + [0]
        return makePuzzle(spec: spec, variant: variant, points: points, trail: trail)
    }

    private static func makePuzzle(spec: LevelSpec, variant: Int, points: [CGPoint], trail: [Int]) -> Puzzle {
        let usedOldNodes = Array(Set(trail)).sorted()
        let remap = Dictionary(uniqueKeysWithValues: usedOldNodes.enumerated().map { newID, oldID in (oldID, newID) })
        let nodes = usedOldNodes.map { oldID in
            Node(id: remap[oldID] ?? oldID, point: points[oldID])
        }
        var edges: [Edge] = []
        var seen: Set<Pair> = []
        for (lhs, rhs) in zip(trail, trail.dropFirst()) {
            guard let a = remap[lhs], let b = remap[rhs], a != b else { continue }
            let key = Pair(a, b)
            guard seen.insert(key).inserted else { continue }
            edges.append(Edge(id: edges.count, a: a, b: b))
        }

        return Puzzle(
            id: "one-line-l\(spec.level)-v\(variant)-n\(nodes.count)-e\(edges.count)",
            difficulty: spec.level,
            variant: variant,
            nodes: nodes,
            edges: edges,
            solutionStart: remap[trail.first ?? 0] ?? 0
        )
    }

    private static func uniqueInts(_ values: [Int]) -> [Int] {
        var seen: Set<Int> = []
        var unique: [Int] = []
        for value in values where seen.insert(value).inserted {
            unique.append(value)
        }
        return unique
    }

    private static func shapeIsReadable(_ puzzle: Puzzle, spec: LevelSpec) -> Bool {
        guard spec.edgeRange.contains(puzzle.edges.count) else { return false }
        guard puzzle.nodes.count >= spec.nodeRange.lowerBound else { return false }

        let points = puzzle.nodes.map(\.point)
        let area = convexHullArea(points)
        let minArea = spec.level <= 2 ? 0.055 : min(0.13, 0.065 + Double(spec.level) * 0.006)
        guard area >= minArea else { return false }

        if spec.level >= 3, abs(linearCorrelation(points)) > 0.88 {
            return false
        }

        let angleBuckets = Set(puzzle.edges.map { edgeAngleBucket($0, nodes: puzzle.nodes) })
        return angleBuckets.count >= (spec.level <= 2 ? 2 : 3)
    }

    private static func convexHullArea(_ points: [CGPoint]) -> Double {
        let hull = convexHull(points)
        guard hull.count >= 3 else { return 0 }

        var sum = 0.0
        for index in hull.indices {
            let next = hull.index(after: index) == hull.endIndex ? hull.startIndex : hull.index(after: index)
            sum += Double(hull[index].x * hull[next].y - hull[next].x * hull[index].y)
        }
        return abs(sum) / 2
    }

    private static func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        let sorted = points.sorted {
            if abs($0.x - $1.x) > 0.0001 {
                return $0.x < $1.x
            }
            return $0.y < $1.y
        }
        guard sorted.count > 2 else { return sorted }

        func cross(_ origin: CGPoint, _ lhs: CGPoint, _ rhs: CGPoint) -> Double {
            Double((lhs.x - origin.x) * (rhs.y - origin.y) - (lhs.y - origin.y) * (rhs.x - origin.x))
        }

        var lower: [CGPoint] = []
        for point in sorted {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }

        var upper: [CGPoint] = []
        for point in sorted.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }

        return Array(lower.dropLast()) + Array(upper.dropLast())
    }

    private static func linearCorrelation(_ points: [CGPoint]) -> Double {
        guard points.count > 2 else { return 0 }
        let count = Double(points.count)
        let meanX = points.reduce(0) { $0 + Double($1.x) } / count
        let meanY = points.reduce(0) { $0 + Double($1.y) } / count
        let centered = points.map { (x: Double($0.x) - meanX, y: Double($0.y) - meanY) }
        let numerator = centered.reduce(0) { $0 + $1.x * $1.y }
        let xVariance = centered.reduce(0) { $0 + $1.x * $1.x }
        let yVariance = centered.reduce(0) { $0 + $1.y * $1.y }
        let denominator = sqrt(xVariance * yVariance)
        guard denominator > 0.0001 else { return 0 }
        return numerator / denominator
    }

    private static func edgeAngleBucket(_ edge: Edge, nodes: [Node]) -> Int {
        guard let lhs = nodes.first(where: { $0.id == edge.a }),
              let rhs = nodes.first(where: { $0.id == edge.b }) else {
            return 0
        }
        let angle = atan2(Double(rhs.point.y - lhs.point.y), Double(rhs.point.x - lhs.point.x))
        let normalized = angle < 0 ? angle + Double.pi : angle
        return Int((normalized / Double.pi * 8).rounded())
    }

    private static func makePoints(count: Int, layout: BoardLayout, level: Int, variant: Int, rng: inout SeededRandom) -> [CGPoint] {
        switch layout {
        case .ring:
            let rotation = Double(variant % count) / Double(count) * Double.pi * 2
            let squash = variant.isMultiple(of: 2) ? 1.0 : 0.90
            return (0..<count).map { index in
                let angle = rotation + Double(index) / Double(count) * Double.pi * 2
                let rx = 0.38 * squash + rng.double(in: -0.006...0.006)
                let ry = 0.34 / squash + rng.double(in: -0.006...0.006)
                return normalizedPoint(x: 0.5 + cos(angle) * rx, y: 0.5 + sin(angle) * ry)
            }
        case .grid:
            let cols = Int(ceil(sqrt(Double(count))))
            let rows = Int(ceil(Double(count) / Double(cols)))
            return (0..<count).map { index in
                let row = index / cols
                let col = index % cols
                let x = (Double(col) + 0.5) / Double(cols)
                let y = (Double(row) + 0.5) / Double(rows)
                return normalizedPoint(x: x + rng.double(in: -0.012...0.012),
                                       y: y + rng.double(in: -0.012...0.012))
            }
        case .lattice:
            let rows = latticeRows(for: count)
            var points: [CGPoint] = []
            for (rowIndex, slots) in rows.enumerated() {
                let y = 0.16 + Double(rowIndex) / Double(max(1, rows.count - 1)) * 0.68
                let spacing = slots <= 2 ? 0.30 : 0.24
                let spread = spacing * Double(slots - 1)
                let offset = rows.count > 2 && !rowIndex.isMultiple(of: 2) ? spacing * 0.18 : -spacing * 0.18
                for slot in 0..<slots {
                    let x = 0.5 - spread / 2 + Double(slot) * spacing + offset
                    points.append(normalizedPoint(x: x + rng.double(in: -0.007...0.007),
                                                  y: y + rng.double(in: -0.007...0.007)))
                }
            }
            return Array(points.prefix(count))
        case .split:
            return (0..<count).map { index in
                let side = index.isMultiple(of: 2) ? 0.25 : 0.75
                let laneIndex = index / 2
                let lanes = max(2, Int(ceil(Double(count) / 2.0)))
                return normalizedPoint(x: side + rng.double(in: -0.018...0.018),
                                       y: 0.12 + Double(laneIndex) / Double(max(1, lanes - 1)) * 0.76 + rng.double(in: -0.010...0.010))
            }
        case .diamond:
            let rows = diamondRows(for: count)
            var points: [CGPoint] = []
            for (rowIndex, slots) in rows.enumerated() {
                let y = 0.10 + Double(rowIndex) / Double(max(1, rows.count - 1)) * 0.80
                for slot in 0..<slots {
                    let spread = 0.24 * Double(slots - 1)
                    let x = 0.5 - spread / 2 + Double(slot) * 0.24
                    points.append(normalizedPoint(x: x + rng.double(in: -0.008...0.008),
                                                  y: y + rng.double(in: -0.008...0.008)))
                }
            }
            return Array(points.prefix(count))
        }
    }

    private static func diamondRows(for count: Int) -> [Int] {
        return switch count {
        case 0...3: [max(1, count)]
        case 4: [1, 2, 1]
        case 5: [1, 3, 1]
        case 6: [1, 2, 2, 1]
        case 7: [1, 2, 3, 1]
        case 8: [1, 2, 3, 2]
        case 9: [1, 2, 3, 2, 1]
        case 10: [1, 2, 3, 3, 1]
        case 11: [1, 2, 3, 3, 2]
        case 12: [1, 2, 3, 4, 2]
        case 13: [1, 2, 3, 4, 2, 1]
        default: [1, 2, 3, 4, 3, 1]
        }
    }

    private static func latticeRows(for count: Int) -> [Int] {
        return switch count {
        case 0...3: [max(1, count)]
        case 4: [2, 2]
        case 5: [2, 3]
        case 6: [3, 3]
        case 7: [2, 3, 2]
        case 8: [3, 2, 3]
        case 9: [3, 3, 3]
        case 10: [3, 4, 3]
        case 11: [3, 4, 4]
        case 12: [3, 4, 3, 2]
        case 13: [3, 4, 4, 2]
        default: [3, 4, 4, 3]
        }
    }

    private static func normalizedPoint(x: Double, y: Double) -> CGPoint {
        CGPoint(x: min(0.94, max(0.06, x)), y: min(0.94, max(0.06, y)))
    }

    private static func candidates(points: [CGPoint], level: Int, layout: BoardLayout, relaxed: Bool) -> [Pair] {
        let maxDistance: Double
        switch layout {
        case .split:
            maxDistance = relaxed ? 0.72 : 0.58
        case .ring:
            maxDistance = relaxed ? 0.74 : (level <= 4 ? 0.54 : 0.64)
        case .grid, .lattice, .diamond:
            maxDistance = relaxed ? 0.68 : (level <= 5 ? 0.46 : 0.55)
        }
        let minDistance = 0.08
        let designed = designedPairs(count: points.count, layout: layout, level: level, relaxed: relaxed)
        let pairs = allPairs(count: points.count).map { pair -> (pair: Pair, distance: Double, centerDistance: Double) in
            let lhs = points[pair.a]
            let rhs = points[pair.b]
            let dx = Double(lhs.x - rhs.x)
            let dy = Double(lhs.y - rhs.y)
            let midpointX = Double(lhs.x + rhs.x) / 2
            let midpointY = Double(lhs.y + rhs.y) / 2
            let centerDx = midpointX - 0.5
            let centerDy = midpointY - 0.5
            return (pair, sqrt(dx * dx + dy * dy), sqrt(centerDx * centerDx + centerDy * centerDy))
        }
        let filtered = pairs
            .filter { $0.distance >= minDistance && $0.distance <= maxDistance }
            .sorted {
                if abs($0.distance - $1.distance) > 0.0001 {
                    return $0.distance < $1.distance
                }
                return $0.centerDistance < $1.centerDistance
            }
            .map(\.pair)
        let ordered = uniquePairs(designed + filtered)
        return ordered.isEmpty ? allPairs(count: points.count) : ordered
    }

    private static func designedPairs(count: Int, layout: BoardLayout, level: Int, relaxed: Bool) -> [Pair] {
        guard count > 1 else { return [] }
        var pairs: [Pair] = []

        func add(_ lhs: Int, _ rhs: Int) {
            guard lhs != rhs, 0..<count ~= lhs, 0..<count ~= rhs else { return }
            pairs.append(Pair(lhs, rhs))
        }

        switch layout {
        case .ring:
            for step in [1, 2, 3] where step < count {
                guard step == 1 || level >= 4 || relaxed else { continue }
                guard step <= 2 || level >= 7 || relaxed else { continue }
                for index in 0..<count {
                    add(index, (index + step) % count)
                }
            }
        case .grid:
            let cols = Int(ceil(sqrt(Double(count))))
            let rows = Int(ceil(Double(count) / Double(cols)))
            func id(row: Int, col: Int) -> Int? {
                guard row >= 0, row < rows, col >= 0, col < cols else { return nil }
                let index = row * cols + col
                return index < count ? index : nil
            }
            func addIfPresent(_ lhs: Int?, _ rhs: Int?) {
                guard let lhs = lhs, let rhs = rhs else { return }
                add(lhs, rhs)
            }

            for row in 0..<rows {
                for col in 0..<cols {
                    addIfPresent(id(row: row, col: col), id(row: row, col: col + 1))
                    addIfPresent(id(row: row, col: col), id(row: row + 1, col: col))
                }
            }
            if level >= 5 || relaxed {
                for row in 0..<rows {
                    for col in 0..<cols {
                        addIfPresent(id(row: row, col: col), id(row: row + 1, col: col + 1))
                        addIfPresent(id(row: row, col: col), id(row: row + 1, col: col - 1))
                    }
                }
            }
        case .lattice:
            let rows = latticeRows(for: count)
            var metadata: [(row: Int, slot: Int, x: Double)] = []
            for (rowIndex, slots) in rows.enumerated() {
                let spacing = slots <= 2 ? 0.30 : 0.24
                let spread = spacing * Double(slots - 1)
                let offset = rows.count > 2 && !rowIndex.isMultiple(of: 2) ? spacing * 0.18 : -spacing * 0.18
                for slot in 0..<slots where metadata.count < count {
                    let x = 0.5 - spread / 2 + Double(slot) * spacing + offset
                    metadata.append((rowIndex, slot, x))
                }
            }
            for lhs in metadata.indices {
                for rhs in metadata.indices where rhs > lhs {
                    let rowGap = abs(metadata[lhs].row - metadata[rhs].row)
                    let slotGap = abs(metadata[lhs].slot - metadata[rhs].slot)
                    let xGap = abs(metadata[lhs].x - metadata[rhs].x)
                    if rowGap == 0, slotGap == 1 {
                        add(lhs, rhs)
                    } else if rowGap == 1, xGap <= 0.19 {
                        add(lhs, rhs)
                    } else if (level >= 6 || relaxed), rowGap <= 2, xGap <= 0.30 {
                        add(lhs, rhs)
                    }
                }
            }
        case .split:
            let lanes = Int(ceil(Double(count) / 2.0))
            func left(_ lane: Int) -> Int? {
                let index = lane * 2
                return index < count ? index : nil
            }
            func right(_ lane: Int) -> Int? {
                let index = lane * 2 + 1
                return index < count ? index : nil
            }
            func addIfPresent(_ lhs: Int?, _ rhs: Int?) {
                guard let lhs = lhs, let rhs = rhs else { return }
                add(lhs, rhs)
            }

            for lane in 0..<lanes {
                addIfPresent(left(lane), right(lane))
                addIfPresent(left(lane), left(lane + 1))
                addIfPresent(right(lane), right(lane + 1))
            }
            if level >= 4 || relaxed {
                for lane in 0..<lanes {
                    addIfPresent(left(lane), right(lane + 1))
                    addIfPresent(right(lane), left(lane + 1))
                }
            }
        case .diamond:
            let rows = diamondRows(for: count)
            var metadata: [(row: Int, slot: Int, x: Double)] = []
            for (rowIndex, slots) in rows.enumerated() {
                for slot in 0..<slots where metadata.count < count {
                    let spread = 0.24 * Double(slots - 1)
                    let x = 0.5 - spread / 2 + Double(slot) * 0.24
                    metadata.append((rowIndex, slot, x))
                }
            }
            for lhs in metadata.indices {
                for rhs in metadata.indices where rhs > lhs {
                    let rowGap = abs(metadata[lhs].row - metadata[rhs].row)
                    let slotGap = abs(metadata[lhs].slot - metadata[rhs].slot)
                    let xGap = abs(metadata[lhs].x - metadata[rhs].x)
                    if rowGap == 0, slotGap == 1 {
                        add(lhs, rhs)
                    } else if rowGap == 1, xGap <= 0.14 {
                        add(lhs, rhs)
                    } else if (level >= 6 || relaxed), rowGap <= 2, xGap <= 0.25 {
                        add(lhs, rhs)
                    }
                }
            }
        }

        return uniquePairs(pairs)
    }

    private static func uniquePairs(_ pairs: [Pair]) -> [Pair] {
        var seen: Set<Pair> = []
        var unique: [Pair] = []
        for pair in pairs where seen.insert(pair).inserted {
            unique.append(pair)
        }
        return unique
    }

    private static func allPairs(count: Int) -> [Pair] {
        guard count > 1 else { return [] }
        var pairs: [Pair] = []
        for lhs in 0..<(count - 1) {
            for rhs in (lhs + 1)..<count {
                pairs.append(Pair(lhs, rhs))
            }
        }
        return pairs
    }

    private static func makeTrail(nodeCount: Int, targetEdges: Int, candidatePairs: [Pair], variant: Int) -> [Int]? {
        guard nodeCount > 1, targetEdges > 0 else { return nil }
        let pairRanks = Dictionary(uniqueKeysWithValues: candidatePairs.enumerated().map { ($0.element, $0.offset) })
        var adjacency: [Int: [Int]] = [:]
        for pair in candidatePairs {
            adjacency[pair.a, default: []].append(pair.b)
            adjacency[pair.b, default: []].append(pair.a)
        }
        for node in adjacency.keys {
            adjacency[node]?.sort {
                (pairRanks[Pair(node, $0)] ?? 999) < (pairRanks[Pair(node, $1)] ?? 999)
            }
        }

        let starts = Array(0..<nodeCount)
        let offset = variant % max(1, nodeCount)
        let orderedStarts = Array(starts.dropFirst(offset)) + Array(starts.prefix(offset))

        var explored = 0
        let explorationLimit = max(4_000, targetEdges * nodeCount * 70)

        func search(current: Int, used: inout Set<Pair>, visits: inout [Int], trail: inout [Int]) -> [Int]? {
            explored += 1
            guard explored <= explorationLimit else { return nil }

            if used.count == targetEdges {
                let usedNodeCount = Set(trail).count
                return usedNodeCount >= min(nodeCount, max(4, nodeCount - 1)) ? trail : nil
            }

            let options = (adjacency[current] ?? [])
                .filter { !used.contains(Pair(current, $0)) }
                .sorted {
                    candidateScore($0, from: current, used: used, visits: visits, adjacency: adjacency, pairRanks: pairRanks)
                        > candidateScore($1, from: current, used: used, visits: visits, adjacency: adjacency, pairRanks: pairRanks)
                }
            guard !options.isEmpty else { return nil }

            for next in options {
                let pair = Pair(current, next)
                used.insert(pair)
                visits[next] += 1
                trail.append(next)

                if let solved = search(current: next, used: &used, visits: &visits, trail: &trail) {
                    return solved
                }

                trail.removeLast()
                visits[next] -= 1
                used.remove(pair)
            }

            return nil
        }

        for start in orderedStarts {
            var used: Set<Pair> = []
            var visits = Array(repeating: 0, count: nodeCount)
            var trail = [start]
            visits[start] += 1

            if let solved = search(current: start, used: &used, visits: &visits, trail: &trail) {
                return solved
            }
        }
        return nil
    }

    private static func candidateScore(_ node: Int,
                                       from current: Int,
                                       used: Set<Pair>,
                                       visits: [Int],
                                       adjacency: [Int: [Int]],
                                       pairRanks: [Pair: Int]) -> Int {
        let onward = (adjacency[node] ?? []).filter { !used.contains(Pair(node, $0)) && $0 != current }.count
        let newNodeBonus = visits[node] == 0 ? 12 : 0
        let revisitPenalty = min(6, visits[node] * 2)
        let rank = pairRanks[Pair(current, node)] ?? 999
        return newNodeBonus + onward * 2 - revisitPenalty - rank / 3
    }

    private static func eulerTrail(from start: Int, edges: [Edge]) -> [Int]? {
        guard !edges.isEmpty else { return [] }
        let degrees = degrees(for: edges)
        let odd = degrees.keys.filter { !(degrees[$0] ?? 0).isMultiple(of: 2) }
        guard odd.isEmpty || (odd.count == 2 && odd.contains(start)) else { return nil }
        guard graphIsConnected(from: start, edges: edges) else { return nil }

        var adjacency: [Int: [Edge]] = [:]
        for edge in edges {
            adjacency[edge.a, default: []].append(edge)
            adjacency[edge.b, default: []].append(edge)
        }

        var used: Set<Int> = []
        var stack: [(node: Int, incoming: Int?)] = [(start, nil)]
        var trail: [Int] = []

        while let top = stack.last {
            if let next = popUnusedEdge(from: top.node, adjacency: &adjacency, used: used) {
                used.insert(next.id)
                stack.append((next.other(top.node), next.id))
            } else {
                let finished = stack.removeLast()
                if let incoming = finished.incoming {
                    trail.append(incoming)
                }
            }
        }

        let ordered = trail.reversed()
        guard ordered.count == edges.count else { return nil }
        return Array(ordered)
    }

    private static func popUnusedEdge(from node: Int, adjacency: inout [Int: [Edge]], used: Set<Int>) -> Edge? {
        while var bucket = adjacency[node], !bucket.isEmpty {
            let edge = bucket.removeLast()
            adjacency[node] = bucket
            if !used.contains(edge.id) {
                return edge
            }
        }
        return nil
    }

    private static func degrees(for edges: [Edge]) -> [Int: Int] {
        var degrees: [Int: Int] = [:]
        for edge in edges {
            degrees[edge.a, default: 0] += 1
            degrees[edge.b, default: 0] += 1
        }
        return degrees
    }

    private static func graphIsConnected(from start: Int, edges: [Edge]) -> Bool {
        let active = Set(edges.flatMap { [$0.a, $0.b] })
        guard active.contains(start) else { return false }

        var seen: Set<Int> = [start]
        var stack = [start]
        while let node = stack.popLast() {
            for edge in edges where edge.a == node || edge.b == node {
                let next = edge.other(node)
                if seen.insert(next).inserted {
                    stack.append(next)
                }
            }
        }
        return active.isSubset(of: seen)
    }
}

#if DEBUG
extension OneLineScreen {
    static var debugPuzzleCountsByLevel: [Int: Int] {
        Dictionary(uniqueKeysWithValues: (1...10).map { level in
            (level, puzzlesByLevel[level]?.count ?? 0)
        })
    }

    static var debugEdgeCountsByLevel: [Int: Set<Int>] {
        Dictionary(uniqueKeysWithValues: (1...10).map { level in
            (level, Set((puzzlesByLevel[level] ?? []).map { $0.edges.count }))
        })
    }

    static var debugEdgeRangesByLevel: [Int: ClosedRange<Int>] {
        Dictionary(uniqueKeysWithValues: specs.map { ($0.level, $0.edgeRange) })
    }

    static var debugUnreadablePuzzleIDs: [String] {
        puzzles.compactMap { puzzle in
            guard let spec = specs.first(where: { $0.level == puzzle.difficulty }) else { return puzzle.id }
            return shapeIsReadable(puzzle, spec: spec) ? nil : puzzle.id
        }
    }
}
#endif

private struct OneLineProgressBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.witsLine)
                Capsule()
                    .fill(Color.witsAccent)
                    .frame(width: max(0, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .animation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.24), value: fraction)
    }
}

private struct OneLineIconButton: View {
    var symbol: String
    var accessibilityLabel: String
    var size: CGFloat
    var enabled: Bool
    var badge: String?
    var action: () -> Void

    init(symbol: String,
         accessibilityLabel: String,
         size: CGFloat,
         enabled: Bool,
         badge: String? = nil,
         action: @escaping () -> Void) {
        self.symbol = symbol
        self.accessibilityLabel = accessibilityLabel
        self.size = size
        self.enabled = enabled
        self.badge = badge
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.34, weight: .heavy))
                    .foregroundStyle(enabled ? Color.witsInk : Color.witsFaint)
                    .frame(width: size, height: size)
                    .background(enabled ? Color.witsTint : Color.witsTint.opacity(0.55), in: Circle())
                    .overlay(Circle().strokeBorder(enabled ? Color.witsAccent.opacity(0.45) : Color.witsLine, lineWidth: 1.5))
                if let badge, enabled {
                    Text(badge)
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Color.witsWarm, in: Circle())
                        .offset(x: 2, y: -2)
                }
            }
            .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(accessibilityLabel)
    }
}
