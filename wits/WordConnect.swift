//
//  WordConnect.swift
//  wits
//
//  Language fluency game. Drag through a letter wheel to solve crossword-style
//  boards; intersections make the hidden words constrained instead of random.
//

import SwiftUI

struct WordConnectScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private static let gameSeconds = 45.0

    private enum Direction { case across, down }

    private struct Cell: Hashable {
        let row: Int
        let col: Int
    }

    private struct Entry: Identifiable {
        let id = UUID()
        let word: String
        let row: Int
        let col: Int
        let direction: Direction

        func cells() -> [Cell] {
            word.indices.enumerated().map { offset, _ in
                switch direction {
                case .across: Cell(row: row, col: col + offset)
                case .down: Cell(row: row + offset, col: col)
                }
            }
        }
    }

    private struct Puzzle: Identifiable {
        let id = UUID()
        let letters: [String]
        let required: [String]
        let bonus: [String]
        let difficulty: Int

        var rows: Int { (cells.keys.map(\.row).max() ?? 0) + 1 }
        var columns: Int { (cells.keys.map(\.col).max() ?? 0) + 1 }
        var entries: [Entry] { Self.layout(required) }

        var cells: [Cell: String] {
            var out: [Cell: String] = [:]
            for entry in entries {
                for (index, cell) in entry.cells().enumerated() {
                    out[cell] = String(entry.word[entry.word.index(entry.word.startIndex, offsetBy: index)])
                }
            }
            return out
        }

        func isSolved(_ cell: Cell, found: Set<String>) -> Bool {
            entries.contains { entry in found.contains(entry.word) && entry.cells().contains(cell) }
        }

        func isActive(_ cell: Cell, currentWord: String) -> Bool {
            entries.contains { entry in entry.word == currentWord && entry.cells().contains(cell) }
        }

        private static func layout(_ words: [String]) -> [Entry] {
            guard let first = words.first else { return [] }
            var entries = [Entry(word: first, row: 0, col: 0, direction: .across)]
            var occupied = cells(for: entries)

            for word in words.dropFirst() {
                var placed: Entry?
                let existing = occupied.sorted { a, b in
                    a.key.row == b.key.row ? a.key.col < b.key.col : a.key.row < b.key.row
                }

                for (targetCell, targetLetter) in existing where placed == nil {
                    for (offset, letter) in word.enumerated() where String(letter) == targetLetter {
                        let candidates = [
                            Entry(word: word, row: targetCell.row - offset, col: targetCell.col, direction: .down),
                            Entry(word: word, row: targetCell.row, col: targetCell.col - offset, direction: .across)
                        ]
                        if let match = candidates.first(where: { canPlace($0, occupied: occupied) }) {
                            placed = match
                            break
                        }
                    }
                }

                if placed == nil {
                    let maxRow = entries.flatMap { $0.cells().map(\.row) }.max() ?? 0
                    placed = Entry(word: word, row: maxRow + 2, col: 0, direction: .across)
                }

                if let placed {
                    entries.append(placed)
                    occupied = cells(for: entries)
                }
            }

            let minRow = entries.flatMap { $0.cells().map(\.row) }.min() ?? 0
            let minCol = entries.flatMap { $0.cells().map(\.col) }.min() ?? 0
            return entries.map {
                Entry(word: $0.word, row: $0.row - minRow, col: $0.col - minCol, direction: $0.direction)
            }
        }

        private static func canPlace(_ entry: Entry, occupied: [Cell: String]) -> Bool {
            var overlaps = 0
            for (offset, cell) in entry.cells().enumerated() {
                let letter = String(entry.word[entry.word.index(entry.word.startIndex, offsetBy: offset)])
                if let existing = occupied[cell] {
                    guard existing == letter else { return false }
                    overlaps += 1
                }
            }
            return overlaps > 0
        }

        private static func cells(for entries: [Entry]) -> [Cell: String] {
            var out: [Cell: String] = [:]
            for entry in entries {
                for (offset, cell) in entry.cells().enumerated() {
                    out[cell] = String(entry.word[entry.word.index(entry.word.startIndex, offsetBy: offset)])
                }
            }
            return out
        }
    }

    @State private var puzzle: Puzzle
    @State private var letters: [String]
    @State private var selectedIndices: [Int] = []
    @State private var found: Set<String> = []
    @State private var timeLeft = gameSeconds
    @State private var score = 0
    @State private var attempts = 0
    @State private var correct = 0
    @State private var wrong = 0
    @State private var streak = 0
    @State private var bestStreak = 0
    @State private var wordsFound = 0
    @State private var boardsSolved = 0
    @State private var feedback: Bool?
    @State private var dragMoved = false
    @State private var gestureActive = false
    @State private var finished = false

    private let startedAt = Date()
    private let level: Double

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        self.level = cfg.difficulty.level
        let p = Self.makePuzzle(level: cfg.difficulty.level)
        _puzzle = State(initialValue: p)
        _letters = State(initialValue: p.letters.shuffled())
    }

    private var currentWord: String {
        selectedIndices.map { letters[$0] }.joined()
    }

    private var foundRequiredCount: Int {
        puzzle.required.filter { found.contains($0) }.count
    }

    private var multiplier: Int { min(6, 1 + streak / 3) }
    private var validWords: Set<String> { Set(puzzle.required + puzzle.bonus) }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 12) {
                if !cfg.isSurvival { topBar }
                targetBoard

                Spacer(minLength: 4)

                currentWordPill
                letterWheel
                actionRow
            }
            .padding(.horizontal, WitsMetrics.screenPadding)
            .padding(.top, 18)
            .padding(.bottom, 12)
        }
        .task { await runTimer() }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(light: 0xEDF5FF, dark: 0x172B55),
                Color(light: 0xF3F5F9, dark: 0x131A2C)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            Image(systemName: "textformat.abc")
                .font(.system(size: 154, weight: .heavy))
                .foregroundStyle(Color.witsAccent.opacity(0.08))
                .offset(x: 26, y: 78)
        }
    }

    private var topBar: some View {
        VStack(spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Text("\(score)").foregroundStyle(Color.witsAccent)) pts")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                    .monospacedDigit()
                if multiplier > 1 {
                    Text("x\(multiplier)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.witsAccent.opacity(0.14), in: Capsule())
                }
                Spacer()
                Text("\(Int(ceil(timeLeft)))s")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsMuted)
                    .monospacedDigit()
            }
            ProgressTrack(fraction: timeLeft / Self.gameSeconds, animated: false)
        }
    }

    private var targetBoard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("word grid")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsMuted)
                    Text("\(foundRequiredCount)/\(puzzle.required.count)")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                        .monospacedDigit()
                }
                Spacer()
                if boardsSolved > 0 {
                    Text("\(boardsSolved) cleared")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.witsAccent.opacity(0.14), in: Capsule())
                }
            }

            crosswordGrid
                .frame(maxWidth: .infinity)
                .frame(height: CGFloat(puzzle.rows) * 38 + CGFloat(max(0, puzzle.rows - 1)) * 5)
                .frame(minHeight: 130, maxHeight: 246)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.witsCard.opacity(0.94), in: RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous))
        .shadow(color: .witsShadow, radius: 12, y: 7)
        .id(puzzle.id)
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private var crosswordGrid: some View {
        GeometryReader { geo in
            let gap: CGFloat = 5
            let columns = max(1, puzzle.columns)
            let rows = max(1, puzzle.rows)
            let cell = min(
                38,
                min(
                    (geo.size.width - CGFloat(columns - 1) * gap) / CGFloat(columns),
                    (geo.size.height - CGFloat(rows - 1) * gap) / CGFloat(rows)
                )
            )
            let totalWidth = CGFloat(columns) * cell + CGFloat(columns - 1) * gap
            let totalHeight = CGFloat(rows) * cell + CGFloat(rows - 1) * gap
            let x0 = (geo.size.width - totalWidth) / 2
            let y0 = (geo.size.height - totalHeight) / 2

            ZStack(alignment: .topLeading) {
                ForEach(Array(puzzle.cells.keys), id: \.self) { cellCoord in
                    let solved = puzzle.isSolved(cellCoord, found: found)
                    let active = puzzle.isActive(cellCoord, currentWord: currentWord)
                    Text(solved ? (puzzle.cells[cellCoord] ?? "") : "")
                        .font(.system(size: min(20, cell * 0.52), weight: .heavy, design: .rounded))
                        .foregroundStyle(solved ? Color.witsAccent : Color.witsInk)
                        .frame(width: cell, height: cell)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(solved ? Color.witsAccent.opacity(0.18) : Color.witsTint)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(active ? Color.witsAccent : Color.witsLine, lineWidth: active ? 2.5 : 1.5)
                        )
                        .position(
                            x: x0 + CGFloat(cellCoord.col) * (cell + gap) + cell / 2,
                            y: y0 + CGFloat(cellCoord.row) * (cell + gap) + cell / 2
                        )
                }
            }
        }
        .accessibilityLabel("crossword word grid")
    }

    private var currentWordPill: some View {
        Text(currentWord.isEmpty ? "make a word" : currentWord)
            .font(.system(size: currentWord.count > 6 ? 22 : 26, weight: .heavy, design: .rounded))
            .foregroundStyle(currentWord.isEmpty ? Color.witsFaint : Color.witsAccent)
            .monospaced()
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.witsCard.opacity(0.95), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(feedback == true ? Color.witsAccent : feedback == false ? Color.witsWarm : Color.witsLine, lineWidth: 2)
            )
            .animation(.easeOut(duration: 0.14), value: feedback)
    }

    private var letterWheel: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size * 0.32
            let hitRadius = max(34, min(42, size * 0.16))

            ZStack {
                Circle()
                    .fill(Color.witsCard.opacity(0.76))
                    .overlay(Circle().strokeBorder(Color.witsLine, lineWidth: 2))
                    .shadow(color: .witsShadow, radius: 16, y: 10)

                Canvas { ctx, _ in
                    guard selectedIndices.count > 1 else { return }
                    var path = Path()
                    for (offset, index) in selectedIndices.enumerated() {
                        let point = Self.wheelPoint(index: index, count: letters.count, radius: radius, center: center)
                        if offset == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    ctx.stroke(
                        path,
                        with: .color(.witsAccent.opacity(0.82)),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
                    )
                }

                ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                    letterNode(letter, selected: selectedIndices.contains(index), size: hitRadius * 2)
                        .position(Self.wheelPoint(index: index, count: letters.count, radius: radius, center: center))
                }
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        if !gestureActive {
                            selectedIndices.removeAll()
                            dragMoved = false
                            gestureActive = true
                        }
                        if Self.distance(value.startLocation, value.location) > 8 { dragMoved = true }
                        selectLetter(at: value.location, center: center, radius: radius, hitRadius: hitRadius)
                    }
                    .onEnded { _ in
                        if dragMoved, currentWord.count >= 2 { submit() }
                        else { selectedIndices.removeAll() }
                        dragMoved = false
                        gestureActive = false
                    }
            )
        }
        .frame(height: 260)
        .padding(.top, 2)
    }

    private func letterNode(_ letter: String, selected: Bool, size: CGFloat) -> some View {
        Text(letter)
            .font(.system(size: min(31, size * 0.43), weight: .heavy, design: .rounded))
            .foregroundStyle(selected ? .white : Color.witsInk)
            .frame(width: size, height: size)
            .background(selected ? Color.witsAccent : Color.witsTint, in: Circle())
            .overlay(Circle().strokeBorder(selected ? Color.witsAccent.opacity(0.3) : Color.witsLine, lineWidth: 2))
            .shadow(color: selected ? Color.witsAccent.opacity(0.25) : Color.witsShadow, radius: selected ? 10 : 4, y: 3)
            .accessibilityLabel(letter)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            iconButton("shuffle", systemName: "shuffle") {
                selectedIndices.removeAll()
                withAnimation(.easeOut(duration: 0.16)) { letters.shuffle() }
            }
            iconButton("clear", systemName: "delete.left.fill") {
                selectedIndices.removeAll()
            }
            Spacer(minLength: 0)
        }
    }

    private func iconButton(_ label: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Color.witsInk)
                .frame(width: 50, height: 50)
                .background(Color.witsCard.opacity(0.95), in: Circle())
                .overlay(Circle().strokeBorder(Color.witsLine, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func selectLetter(at location: CGPoint, center: CGPoint, radius: CGFloat, hitRadius: CGFloat) {
        guard !finished else { return }
        guard let index = nearestLetter(to: location, center: center, radius: radius, hitRadius: hitRadius) else { return }
        appendSelection(index)
    }

    private func appendSelection(_ index: Int) {
        if selectedIndices.last == index { return }
        if selectedIndices.dropLast().last == index {
            selectedIndices.removeLast()
        } else if !selectedIndices.contains(index) {
            selectedIndices.append(index)
        }
    }

    private func nearestLetter(to point: CGPoint, center: CGPoint, radius: CGFloat, hitRadius: CGFloat) -> Int? {
        let points = letters.indices.map { Self.wheelPoint(index: $0, count: letters.count, radius: radius, center: center) }
        guard let nearest = points.enumerated().min(by: { Self.distance($0.element, point) < Self.distance($1.element, point) }) else {
            return nil
        }
        return Self.distance(nearest.element, point) <= hitRadius ? nearest.offset : nil
    }

    private func submit() {
        guard !finished else { return }
        let word = currentWord.uppercased()
        guard word.count >= 2 else { return }

        if found.contains(word) {
            flash(false)
            selectedIndices.removeAll()
            return
        }

        attempts += 1
        if validWords.contains(word) {
            correct += 1
            streak += 1
            bestStreak = max(bestStreak, streak)
            wordsFound += 1
            found.insert(word)
            let points = word.count * 40
            score += points * multiplier
            cfg.report(.hit, points: points, combo: streak)
            flash(true)
            selectedIndices.removeAll()

            if foundRequiredCount >= puzzle.required.count {
                boardsSolved += 1
                score += cfg.isSurvival ? 0 : 250
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                    guard !finished else { return }
                    nextPuzzle()
                }
            }
        } else {
            wrong += 1
            streak = 0
            cfg.report(.miss)
            flash(false)
            selectedIndices.removeAll()
        }
    }

    private func flash(_ ok: Bool) {
        feedback = ok
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            feedback = nil
        }
    }

    private func nextPuzzle() {
        let p = Self.makePuzzle(level: level + Double(boardsSolved) * 0.35)
        withAnimation(.easeOut(duration: 0.18)) {
            puzzle = p
            letters = p.letters.shuffled()
            found.removeAll()
            selectedIndices.removeAll()
        }
    }

    private func runTimer() async {
        let start = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(40))
            guard !finished else { return }
            if cfg.isSurvival { continue }
            timeLeft = max(0, Self.gameSeconds - Date().timeIntervalSince(start))
            if timeLeft <= 0 {
                finish()
                return
            }
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        let accuracy = attempts > 0 ? Double(correct) / Double(attempts) : 0
        var result = GameResult(game: .wordConnect, score: score, accuracy: accuracy)
        result.trials = attempts
        result.startedAt = startedAt
        result.durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        result.raw = [
            "bestStreak": Double(bestStreak),
            "wordsFound": Double(wordsFound),
            "boardsSolved": Double(boardsSolved),
            "wrong": Double(wrong)
        ]
        onResult(result)
    }

    private static func wheelPoint(index: Int, count: Int, radius: CGFloat, center: CGPoint) -> CGPoint {
        let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(max(1, count))
        return CGPoint(
            x: center.x + CGFloat(cos(angle)) * radius,
            y: center.y + CGFloat(sin(angle)) * radius
        )
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func makePuzzle(level: Double) -> Puzzle {
        let cap = level < 2 ? 1 : level < 5 ? 2 : level < 8 ? 3 : 4
        let pool = bank.filter { $0.difficulty <= cap }
        return (pool.randomElement() ?? bank[0])
    }

    private static let bank: [Puzzle] = [
        Puzzle(
            letters: ["C", "A", "T"],
            required: ["CAT", "ACT"],
            bonus: ["AT"],
            difficulty: 1
        ),
        Puzzle(
            letters: ["P", "L", "A", "Y"],
            required: ["PLAY", "LAY", "PAY"],
            bonus: ["PAL"],
            difficulty: 1
        ),
        Puzzle(
            letters: ["R", "I", "S", "E"],
            required: ["RISE", "SIRE", "IRE"],
            bonus: ["SIR"],
            difficulty: 1
        ),
        Puzzle(
            letters: ["M", "A", "R", "S"],
            required: ["MARS", "ARMS", "RAM"],
            bonus: ["ARM"],
            difficulty: 1
        ),
        Puzzle(
            letters: ["T", "R", "A", "I", "N"],
            required: ["TRAIN", "RAIN", "RANT", "TAR"],
            bonus: ["ART", "AIR", "TIN"],
            difficulty: 2
        ),
        Puzzle(
            letters: ["B", "R", "A", "I", "N"],
            required: ["BRAIN", "RAIN", "BARN", "BRAN"],
            bonus: ["AIR", "RAN"],
            difficulty: 2
        ),
        Puzzle(
            letters: ["S", "H", "A", "R", "P"],
            required: ["SHARP", "HARP", "RASH", "SPAR"],
            bonus: ["HAS", "ASH"],
            difficulty: 2
        ),
        Puzzle(
            letters: ["C", "L", "E", "A", "R"],
            required: ["CLEAR", "LACE", "RACE", "REAL"],
            bonus: ["CARE", "EAR", "ARC"],
            difficulty: 2
        ),
        Puzzle(
            letters: ["S", "T", "O", "N", "E"],
            required: ["STONE", "TONES", "NOTES", "ONSET", "TONE"],
            bonus: ["NOTE", "ONES"],
            difficulty: 3
        ),
        Puzzle(
            letters: ["L", "E", "A", "R", "N"],
            required: ["LEARN", "NEAR", "LANE", "REAL"],
            bonus: ["EARN", "EARL", "LEAN"],
            difficulty: 3
        ),
        Puzzle(
            letters: ["C", "R", "A", "F", "T"],
            required: ["CRAFT", "FACT", "RAFT", "CART"],
            bonus: ["ACT", "ART", "FAR"],
            difficulty: 3
        ),
        Puzzle(
            letters: ["S", "P", "A", "R", "K"],
            required: ["SPARK", "PARK", "SPAR", "RASP"],
            bonus: ["ARK", "ASK"],
            difficulty: 3
        ),
        Puzzle(
            letters: ["B", "R", "I", "G", "H", "T"],
            required: ["BRIGHT", "BIRTH", "RIGHT", "GIRTH"],
            bonus: ["GIRT", "HIT", "RIB"],
            difficulty: 4
        ),
        Puzzle(
            letters: ["M", "A", "R", "K", "E", "T"],
            required: ["MARKET", "MAKER", "TAKER", "RATE"],
            bonus: ["TEAM", "TEAR", "MAKE"],
            difficulty: 4
        ),
        Puzzle(
            letters: ["P", "L", "A", "N", "E", "T"],
            required: ["PLANET", "PLANE", "PLANT", "PANEL"],
            bonus: ["LANE", "PEAT", "LEANT"],
            difficulty: 4
        )
    ]
}
