//
//  WordConnect.swift
//  wits
//
//  Language fluency game. Drag through a letter wheel to solve crossword-style
//  boards; intersections make the hidden words constrained instead of random.
//

import SwiftUI
import UIKit

private enum WordConnectStyle {
    static let tabletopTop = Color(light: 0xDDEBE0, dark: 0x142A25)
    static let tabletopMid = Color(light: 0xEEF4E9, dark: 0x142139)
    static let tabletopBottom = Color(light: 0xF8EED9, dark: 0x101827)
    static let paperTop = Color(light: 0xFFF9EA, dark: 0x28324E)
    static let paperBottom = Color(light: 0xF4E7C9, dark: 0x1A223B)
    static let paperEdge = Color(light: 0xBBAF92, dark: 0xEDF0F8, lightAlpha: 0.42, darkAlpha: 0.18)
    static let blankCell = Color(light: 0xFFFDF3, dark: 0x202945)
    static let blankCellEdge = Color(light: 0x897E66, dark: 0xEDF0F8, lightAlpha: 0.32, darkAlpha: 0.16)
    static let ink = Color(light: 0x173F2D, dark: 0xE7F6EC)
    static let mutedInk = Color(light: 0x173F2D, dark: 0xE7F6EC, lightAlpha: 0.62, darkAlpha: 0.62)
    static let tileTop = Color(light: 0x2F7A4F, dark: 0x55C97A)
    static let tile = Color(light: 0x1F5A3B, dark: 0x2FA45C)
    static let tileDeep = Color(light: 0x143926, dark: 0x1D6B40)
    static let tileText = Color(light: 0xFFFDF5, dark: 0xF7FFF8)
    static let sage = Color(light: 0xB9D1BE, dark: 0x26443A)
    static let amber = Color.witsGold

    static var paperGradient: LinearGradient {
        LinearGradient(colors: [paperTop, paperBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var tileGradient: LinearGradient {
        LinearGradient(colors: [tileTop, tile], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var selectedTileGradient: LinearGradient {
        LinearGradient(colors: [tileTop, tileDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct WordConnectSafeAreaBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: WordConnectStyle.tabletopTop, location: 0),
                    .init(color: WordConnectStyle.tabletopMid, location: 0.58),
                    .init(color: WordConnectStyle.tabletopBottom, location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "leaf.fill")
                .font(.system(size: 190, weight: .regular))
                .foregroundStyle(WordConnectStyle.tile.opacity(0.12))
                .rotationEffect(.degrees(-18))
                .offset(x: -126, y: 310)
            Image(systemName: "book.closed.fill")
                .font(.system(size: 150, weight: .regular))
                .foregroundStyle(WordConnectStyle.paperEdge.opacity(0.22))
                .rotationEffect(.degrees(-14))
                .offset(x: 148, y: 356)
        }
        .ignoresSafeArea()
    }
}

struct WordConnectScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private static let recentPuzzleDefaultsKey = "wits.wordConnect.recentPuzzles"
    private static let recentPuzzleLimit = 12
    private static let boardsPerRun = 2
    private static let requiredWordPoints = 100
    private static let bonusWordPoints = 20
    private static let hintPenalty = 75
    private static let maxHintsPerBoard = 2

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

        var key: String { required.joined(separator: "|") }
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
            let ordered = ([first] + words.dropFirst().sorted { lhs, rhs in
                lhs.count == rhs.count ? lhs < rhs : lhs.count > rhs.count
            })
            let seed = [Entry(word: ordered[0], row: 0, col: 0, direction: .across)]
            return normalize(solve(entries: seed, remaining: Array(ordered.dropFirst())) ?? separatedLayout(ordered))
        }

        private static func canPlace(_ entry: Entry, entries: [Entry]) -> Bool {
            let occupied = cells(for: entries)
            var overlaps = 0
            let before: Cell
            let after: Cell
            switch entry.direction {
            case .across:
                before = Cell(row: entry.row, col: entry.col - 1)
                after = Cell(row: entry.row, col: entry.col + entry.word.count)
            case .down:
                before = Cell(row: entry.row - 1, col: entry.col)
                after = Cell(row: entry.row + entry.word.count, col: entry.col)
            }
            guard occupied[before] == nil, occupied[after] == nil else { return false }

            for (offset, cell) in entry.cells().enumerated() {
                let letter = String(entry.word[entry.word.index(entry.word.startIndex, offsetBy: offset)])
                if let existing = occupied[cell] {
                    guard existing == letter else { return false }
                    guard entries
                        .filter({ $0.direction == entry.direction })
                        .allSatisfy({ !$0.cells().contains(cell) }) else {
                        return false
                    }
                    overlaps += 1
                } else {
                    let sideCells: [Cell]
                    switch entry.direction {
                    case .across:
                        sideCells = [Cell(row: cell.row - 1, col: cell.col), Cell(row: cell.row + 1, col: cell.col)]
                    case .down:
                        sideCells = [Cell(row: cell.row, col: cell.col - 1), Cell(row: cell.row, col: cell.col + 1)]
                    }
                    guard sideCells.allSatisfy({ occupied[$0] == nil }) else { return false }
                }
            }
            return overlaps > 0 && boardRunsAreEntries(entries + [entry])
        }

        private static func solve(entries: [Entry], remaining: [String]) -> [Entry]? {
            guard !remaining.isEmpty else { return entries }

            let options = remaining.indices.map { index in
                (index: index, candidates: candidates(for: remaining[index], entries: entries))
            }
            guard let next = options.min(by: { lhs, rhs in
                if lhs.candidates.count != rhs.candidates.count { return lhs.candidates.count < rhs.candidates.count }
                return remaining[lhs.index].count > remaining[rhs.index].count
            }), !next.candidates.isEmpty else {
                return nil
            }

            var rest = remaining
            rest.remove(at: next.index)
            let sortedCandidates = next.candidates.sorted { lhs, rhs in
                let a = metrics(for: entries + [lhs])
                let b = metrics(for: entries + [rhs])
                if a.area != b.area { return a.area < b.area }
                if a.rows != b.rows { return a.rows < b.rows }
                return a.columns < b.columns
            }

            for candidate in sortedCandidates {
                if let solved = solve(entries: entries + [candidate], remaining: rest) {
                    return solved
                }
            }
            return nil
        }

        private static func candidates(for word: String, entries: [Entry]) -> [Entry] {
            let occupied = cells(for: entries)
            let existing = occupied.sorted { a, b in
                a.key.row == b.key.row ? a.key.col < b.key.col : a.key.row < b.key.row
            }

            var candidates: [Entry] = []
            for (targetCell, targetLetter) in existing {
                for (offset, letter) in word.enumerated() where String(letter) == targetLetter {
                    candidates.append(contentsOf: [
                        Entry(word: word, row: targetCell.row - offset, col: targetCell.col, direction: .down),
                        Entry(word: word, row: targetCell.row, col: targetCell.col - offset, direction: .across)
                    ])
                }
            }
            return candidates.filter { canPlace($0, entries: entries) }
        }

        private static func boardRunsAreEntries(_ entries: [Entry]) -> Bool {
            let occupied = cells(for: entries)
            let expectedRuns = Set(entries.map { BoardRun(cells: $0.cells(), word: $0.word) })

            for cell in occupied.keys {
                if occupied[Cell(row: cell.row, col: cell.col - 1)] == nil,
                   occupied[Cell(row: cell.row, col: cell.col + 1)] != nil {
                    let run = run(from: cell, deltaRow: 0, deltaCol: 1, occupied: occupied)
                    guard run.cells.count == 1 || expectedRuns.contains(run) else { return false }
                }
                if occupied[Cell(row: cell.row - 1, col: cell.col)] == nil,
                   occupied[Cell(row: cell.row + 1, col: cell.col)] != nil {
                    let run = run(from: cell, deltaRow: 1, deltaCol: 0, occupied: occupied)
                    guard run.cells.count == 1 || expectedRuns.contains(run) else { return false }
                }
            }
            return true
        }

        private static func run(from start: Cell, deltaRow: Int, deltaCol: Int, occupied: [Cell: String]) -> BoardRun {
            var cells: [Cell] = []
            var letters: [String] = []
            var cell = start
            while let letter = occupied[cell] {
                cells.append(cell)
                letters.append(letter)
                cell = Cell(row: cell.row + deltaRow, col: cell.col + deltaCol)
            }
            return BoardRun(cells: cells, word: letters.joined())
        }

        private static func normalize(_ entries: [Entry]) -> [Entry] {
            let minRow = entries.flatMap { $0.cells().map(\.row) }.min() ?? 0
            let minCol = entries.flatMap { $0.cells().map(\.col) }.min() ?? 0
            return entries.map {
                Entry(word: $0.word, row: $0.row - minRow, col: $0.col - minCol, direction: $0.direction)
            }
        }

        private static func separatedLayout(_ words: [String]) -> [Entry] {
            var row = 0
            return words.map { word in
                defer { row += 2 }
                return Entry(word: word, row: row, col: 0, direction: .across)
            }
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

        private static func metrics(for entries: [Entry]) -> (rows: Int, columns: Int, area: Int) {
            let all = entries.flatMap { $0.cells() }
            let minRow = all.map(\.row).min() ?? 0
            let maxRow = all.map(\.row).max() ?? 0
            let minCol = all.map(\.col).min() ?? 0
            let maxCol = all.map(\.col).max() ?? 0
            let rows = maxRow - minRow + 1
            let columns = maxCol - minCol + 1
            return (rows, columns, rows * columns)
        }
    }

    private struct BoardRun: Hashable {
        let cells: [Cell]
        let word: String
    }

    @State private var puzzle: Puzzle
    @State private var letters: [String]
    @State private var selectedIndices: [Int] = []
    @State private var found: Set<String> = []
    @State private var score = 0
    @State private var attempts = 0
    @State private var correct = 0
    @State private var wrong = 0
    @State private var hintsUsed = 0
    @State private var streak = 0
    @State private var bestStreak = 0
    @State private var requiredWordsFoundTotal = 0
    @State private var bonusWordsFoundTotal = 0
    @State private var boardsSolved = 0
    @State private var foundBonus: [String] = []
    @State private var hintedCells: Set<Cell> = []
    @State private var boardHintsUsed = 0
    @State private var feedback: Bool?
    @State private var dragMoved = false
    @State private var gestureActive = false
    @State private var finished = false
    @State private var recentPuzzleKeys: [String]
    @State private var guessedWords: [String] = []

    private let startedAt = Date()
    private let currentLevel: Int

    private struct ScreenLayout {
        var spacing: CGFloat
        var topPadding: CGFloat
        var bottomPadding: CGFloat
        var boardHeight: CGFloat
        var wordPillHeight: CGFloat
        var bonusHeight: CGFloat
        var wheelHeight: CGFloat
        var buttonSize: CGFloat
    }

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        let seededLevel = Self.levelNumber(cfg.difficulty.level)
        self.currentLevel = seededLevel
        let recent = Self.loadRecentPuzzleKeys()
        let p = Self.makePuzzle(level: Double(seededLevel), avoiding: recent)
        _puzzle = State(initialValue: p)
        _letters = State(initialValue: p.letters.shuffled())
        _recentPuzzleKeys = State(initialValue: Self.recordRecentPuzzle(p.key, in: recent))
    }

    private var currentWord: String {
        selectedIndices.map { letters[$0] }.joined()
    }

    private var foundRequiredCount: Int {
        puzzle.required.filter { found.contains($0) }.count
    }

    private var multiplier: Int { min(6, 1 + streak / 3) }
    private var hintsRemaining: Int { max(0, Self.maxHintsPerBoard - boardHintsUsed) }
    private var runProgress: Double {
        let boardFraction = puzzle.required.isEmpty ? 0 : Double(foundRequiredCount) / Double(puzzle.required.count)
        return max(0, min(1, (Double(boardsSolved) + boardFraction) / Double(Self.boardsPerRun)))
    }
    private var crosswordBoardHeight: CGFloat {
        let ideal = CGFloat(puzzle.rows) * 38 + CGFloat(max(0, puzzle.rows - 1)) * 5
        return min(246, max(130, ideal))
    }
    private var targetBoardIdealHeight: CGFloat {
        min(326, max(226, crosswordBoardHeight + 86))
    }

    var body: some View {
        GeometryReader { geo in
            let layout = Self.layout(for: geo.size,
                                     bonusVisible: false,
                                     hasTopBar: !cfg.isSurvival,
                                     idealBoardHeight: targetBoardIdealHeight,
                                     topSafeInset: 0,
                                     bottomSafeInset: 0)
            let bonusOverlayHeight: CGFloat = geo.size.height < 760 ? 30 : 34
            ZStack {
                background.ignoresSafeArea()
                VStack(spacing: layout.spacing) {
                    if !cfg.isSurvival { topBar }
                    targetBoard(height: layout.boardHeight)

                    Spacer(minLength: 0)

                    currentWordPill(height: layout.wordPillHeight)
                        .overlay(alignment: .topLeading) {
                            bonusRow(height: bonusOverlayHeight)
                                .offset(y: -bonusOverlayHeight - max(6, layout.spacing))
                        }
                    letterWheel(height: layout.wheelHeight)
                    actionRow(buttonSize: layout.buttonSize)
                }
                .padding(.horizontal, WitsMetrics.screenPadding)
                .padding(.top, layout.topPadding)
                .padding(.bottom, layout.bottomPadding)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private static func layout(for size: CGSize,
                               bonusVisible: Bool,
                               hasTopBar: Bool,
                               idealBoardHeight: CGFloat,
                               topSafeInset: CGFloat,
                               bottomSafeInset: CGFloat) -> ScreenLayout {
        let compact = size.height < 760
        let spacing: CGFloat = compact ? 7 : 10
        let topPadding: CGFloat = (compact ? 8 : 10) + topSafeInset
        let bottomPadding: CGFloat = (compact ? 8 : 10) + bottomSafeInset
        let wordPillHeight: CGFloat = compact ? 42 : 48
        let bonusHeight: CGFloat = bonusVisible ? (compact ? 30 : 34) : 0
        let buttonSize: CGFloat = compact ? 42 : 48
        let topBarHeight: CGFloat = hasTopBar ? (compact ? 52 : 56) : 0
        let childCount = 4 + (hasTopBar ? 1 : 0) + (bonusVisible ? 1 : 0) + 1
        let spacingHeight = CGFloat(max(0, childCount - 1)) * spacing
        let reservedHeight = topPadding + bottomPadding + topBarHeight + wordPillHeight + bonusHeight + buttonSize + spacingHeight
        let availableHeight = max(0, size.height - reservedHeight)
        let maxWheelHeight = min(size.width - WitsMetrics.screenPadding * 2, compact ? 224 : 260)
        let minWheelHeight: CGFloat = compact ? 168 : 190
        let minBoardHeight: CGFloat = compact ? 218 : 242
        let targetWheelHeight = min(maxWheelHeight, max(minWheelHeight, availableHeight * (compact ? 0.42 : 0.43)))
        var boardHeight = min(idealBoardHeight, max(minBoardHeight, availableHeight - targetWheelHeight))
        var wheelHeight = min(maxWheelHeight, max(minWheelHeight, availableHeight - boardHeight))

        if boardHeight + wheelHeight > availableHeight {
            let overflow = boardHeight + wheelHeight - availableHeight
            let wheelShrink = min(overflow, max(0, wheelHeight - minWheelHeight))
            wheelHeight -= wheelShrink
            boardHeight = max(190, boardHeight - (overflow - wheelShrink))
        }

        return ScreenLayout(spacing: spacing,
                            topPadding: topPadding,
                            bottomPadding: bottomPadding,
                            boardHeight: boardHeight,
                            wordPillHeight: wordPillHeight,
                            bonusHeight: bonusHeight,
                            wheelHeight: wheelHeight,
                            buttonSize: buttonSize)
    }

    private var background: some View {
        WordConnectSafeAreaBackground()
            .overlay(alignment: .topTrailing) {
                Image(systemName: "textformat.abc")
                    .font(.system(size: 134, weight: .heavy))
                    .foregroundStyle(WordConnectStyle.tile.opacity(0.07))
                    .offset(x: 20, y: 82)
            }
            .overlay(alignment: .bottomLeading) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 112, weight: .regular))
                    .foregroundStyle(WordConnectStyle.tile.opacity(0.10))
                    .rotationEffect(.degrees(28))
                    .offset(x: -30, y: -12)
            }
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                statusPill(icon: "book.closed.fill", text: "lvl \(currentLevel)")
                statusPill(icon: "square.grid.3x3.fill", text: "\(min(boardsSolved + 1, Self.boardsPerRun))/\(Self.boardsPerRun)")
                statusPill(icon: "star.fill", text: "\(score)", tint: WordConnectStyle.amber)
            }
            .padding(.leading, 34)

            ProgressTrack(fraction: runProgress, animated: true, tint: WordConnectStyle.tile)
        }
    }

    private func statusPill(icon: String, text: String, tint: Color = WordConnectStyle.tile) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .heavy))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.12), in: Circle())
            Text(text)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(WordConnectStyle.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(WordConnectStyle.paperTop.opacity(0.82), in: Capsule())
        .overlay(Capsule().strokeBorder(WordConnectStyle.paperEdge, lineWidth: 1))
        .shadow(color: Color.witsShadow.opacity(0.7), radius: 7, y: 4)
    }

    private func targetBoard(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 9) {
                    Image(systemName: "textformat.abc")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(WordConnectStyle.tile)
                        .frame(width: 32, height: 32)
                        .background(WordConnectStyle.sage.opacity(0.55), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("word grid")
                            .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(WordConnectStyle.mutedInk)
                        Text("\(foundRequiredCount)/\(puzzle.required.count) found")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(WordConnectStyle.ink)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                }
                Spacer()
                if !cfg.isSurvival {
                    Text("board \(min(boardsSolved + 1, Self.boardsPerRun))/\(Self.boardsPerRun)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(WordConnectStyle.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(WordConnectStyle.sage.opacity(0.72), in: Capsule())
                        .overlay(Capsule().strokeBorder(WordConnectStyle.paperEdge, lineWidth: 1))
                }
            }

            crosswordGrid
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
        }
        .padding(16)
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WordConnectStyle.paperGradient, in: RoundedRectangle(cornerRadius: WitsMetrics.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WitsMetrics.panelRadius, style: .continuous)
                .strokeBorder(WordConnectStyle.paperEdge, lineWidth: 1.5)
        )
        .overlay {
            RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                .strokeBorder(WordConnectStyle.paperEdge.opacity(0.55), lineWidth: 1)
                .padding(8)
        }
        .shadow(color: .witsShadow, radius: 16, y: 9)
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
                ForEach(Array(puzzle.cells.keys).sorted {
                    $0.row == $1.row ? $0.col < $1.col : $0.row < $1.row
                }, id: \.self) { cellCoord in
                    let solved = puzzle.isSolved(cellCoord, found: found)
                    let active = puzzle.isActive(cellCoord, currentWord: currentWord)
                    let hinted = hintedCells.contains(cellCoord)
                    crosswordCell(letter: puzzle.cells[cellCoord] ?? "",
                                  solved: solved,
                                  active: active,
                                  hinted: hinted,
                                  size: cell)
                        .position(
                            x: x0 + CGFloat(cellCoord.col) * (cell + gap) + cell / 2,
                            y: y0 + CGFloat(cellCoord.row) * (cell + gap) + cell / 2
                        )
                }
            }
        }
        .accessibilityLabel("crossword word grid")
    }

    private func crosswordCell(letter: String, solved: Bool, active: Bool, hinted: Bool, size: CGFloat) -> some View {
        let corner = max(8, size * 0.23)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let border = active ? WordConnectStyle.amber : hinted ? WordConnectStyle.amber : WordConnectStyle.blankCellEdge
        let lineWidth: CGFloat = active ? 2.8 : 1.2

        return ZStack {
            if solved {
                shape.fill(WordConnectStyle.tileGradient)
            } else if hinted {
                shape.fill(WordConnectStyle.amber.opacity(0.18))
            } else {
                shape.fill(WordConnectStyle.blankCell)
            }

            Text(solved || hinted ? letter : "")
                .font(.system(size: min(21, size * 0.55), weight: .heavy, design: .rounded))
                .foregroundStyle(solved ? WordConnectStyle.tileText : hinted ? WordConnectStyle.amber : WordConnectStyle.ink)
                .monospaced()
                .minimumScaleFactor(0.78)
        }
        .frame(width: size, height: size)
        .overlay(shape.strokeBorder(border, lineWidth: lineWidth))
        .shadow(color: solved ? WordConnectStyle.tileDeep.opacity(0.20) : Color.witsShadow.opacity(0.45),
                radius: solved ? 4 : 2,
                y: solved ? 2 : 1)
        .animation(.easeOut(duration: 0.16), value: solved)
        .animation(.easeOut(duration: 0.16), value: active)
    }

    private func currentWordPill(height: CGFloat) -> some View {
        ZStack {
            if currentWord.isEmpty {
                Capsule().fill(WordConnectStyle.paperGradient)
            } else {
                Capsule().fill(WordConnectStyle.selectedTileGradient)
            }

            if currentWord.isEmpty {
                Text("make a word")
                    .font(.system(size: height * 0.42, weight: .heavy, design: .rounded))
                    .foregroundStyle(WordConnectStyle.mutedInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 22)
            } else {
                Text(currentWord)
                    .font(.system(size: currentWord.count > 6 ? height * 0.43 : height * 0.52, weight: .heavy, design: .rounded))
                    .foregroundStyle(WordConnectStyle.tileText)
                    .monospaced()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 22)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .overlay(
            Capsule()
                .strokeBorder(feedback == true ? WordConnectStyle.tile : feedback == false ? Color.witsWarm : WordConnectStyle.paperEdge,
                              lineWidth: feedback == nil ? 1.5 : 2.5)
        )
        .shadow(color: currentWord.isEmpty ? Color.witsShadow.opacity(0.35) : WordConnectStyle.tileDeep.opacity(0.24),
                radius: currentWord.isEmpty ? 6 : 10,
                y: currentWord.isEmpty ? 3 : 5)
        .animation(.easeOut(duration: 0.14), value: feedback)
        .animation(.easeOut(duration: 0.14), value: currentWord)
    }

    private func bonusRow(height: CGFloat) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10.5, weight: .heavy))
                Text("+\(foundBonus.count)")
                    .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("bonus")
                    .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(WordConnectStyle.mutedInk)
            }
            .foregroundStyle(WordConnectStyle.amber)

            if let latest = foundBonus.last {
                Text(latest)
                    .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(WordConnectStyle.tileText)
                    .monospaced()
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                    .padding(.horizontal, 8)
                    .frame(height: height - 8)
                    .background(WordConnectStyle.tileGradient, in: Capsule())
                    .overlay(Capsule().strokeBorder(WordConnectStyle.paperTop.opacity(0.42), lineWidth: 1))
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: height)
        .background(WordConnectStyle.paperTop.opacity(0.72), in: Capsule())
        .overlay(Capsule().strokeBorder(WordConnectStyle.paperEdge, lineWidth: 1.2))
        .shadow(color: .witsShadow.opacity(0.45), radius: 5, y: 3)
        .opacity(foundBonus.isEmpty ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(foundBonus.isEmpty)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.16), value: foundBonus.count)
    }

    private func letterWheel(height: CGFloat) -> some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size * 0.32
            let hitRadius = max(34, min(42, size * 0.16))

            ZStack {
                Circle()
                    .fill(WordConnectStyle.paperGradient)
                    .overlay(Circle().strokeBorder(WordConnectStyle.paperEdge, lineWidth: 2))
                    .shadow(color: .witsShadow, radius: 18, y: 10)
                    .frame(width: size, height: size)
                    .position(center)

                Circle()
                    .strokeBorder(WordConnectStyle.sage.opacity(0.85), lineWidth: 1.2)
                    .frame(width: size * 0.85, height: size * 0.85)
                    .position(center)

                Image(systemName: "leaf.fill")
                    .font(.system(size: size * 0.17, weight: .regular))
                    .foregroundStyle(WordConnectStyle.tile.opacity(0.13))
                    .rotationEffect(.degrees(-8))
                    .position(center)

                Canvas { ctx, _ in
                    guard selectedIndices.count > 1 else { return }
                    var path = Path()
                    for (offset, index) in selectedIndices.enumerated() {
                        let point = Self.wheelPoint(index: index, count: letters.count, radius: radius, center: center)
                        if offset == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    ctx.stroke(
                        path,
                        with: .color(WordConnectStyle.tileDeep.opacity(0.20)),
                        style: StrokeStyle(lineWidth: 15, lineCap: .round, lineJoin: .round)
                    )
                    ctx.stroke(
                        path,
                        with: .color(WordConnectStyle.tile.opacity(0.90)),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                    )
                }

                ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                    letterNode(letter, selected: selectedIndices.contains(index), size: hitRadius * 2)
                        .position(Self.wheelPoint(index: index, count: letters.count, radius: radius, center: center))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
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
        .frame(height: height)
        .padding(.top, 2)
    }

    private func letterNode(_ letter: String, selected: Bool, size: CGFloat) -> some View {
        Text(letter)
            .font(.system(size: min(31, size * 0.43), weight: .heavy, design: .rounded))
            .foregroundStyle(WordConnectStyle.tileText)
            .monospaced()
            .frame(width: size, height: size)
            .background {
                if selected {
                    Circle().fill(WordConnectStyle.selectedTileGradient)
                } else {
                    Circle().fill(WordConnectStyle.tileGradient)
                }
            }
            .overlay(
                Circle()
                    .strokeBorder(selected ? WordConnectStyle.amber : WordConnectStyle.paperTop.opacity(0.62),
                                  lineWidth: selected ? 3 : 1.2)
            )
            .shadow(color: selected ? WordConnectStyle.amber.opacity(0.28) : WordConnectStyle.tileDeep.opacity(0.22),
                    radius: selected ? 12 : 6,
                    y: selected ? 5 : 3)
            .scaleEffect(selected ? 1.07 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: selected)
            .accessibilityLabel(letter)
    }

    private func actionRow(buttonSize: CGFloat) -> some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            iconButton("shuffle", systemName: "shuffle", size: buttonSize) {
                selectedIndices.removeAll()
                withAnimation(.easeOut(duration: 0.16)) { letters.shuffle() }
            }
            iconButton("clear", systemName: "delete.left.fill", size: buttonSize) {
                selectedIndices.removeAll()
            }
            hintButton(size: buttonSize)
            Spacer(minLength: 0)
        }
    }

    private func hintButton(size: CGFloat) -> some View {
        Button(action: useHint) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: size * 0.34, weight: .heavy))
                    .foregroundStyle(hintCandidateCells.isEmpty || hintsRemaining == 0 ? WordConnectStyle.mutedInk.opacity(0.45) : WordConnectStyle.amber)
                    .frame(width: size, height: size)
                if hintsRemaining > 0 {
                    Text("\(hintsRemaining)")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(WordConnectStyle.tileText)
                        .monospacedDigit()
                        .frame(width: 18, height: 18)
                        .background(WordConnectStyle.amber, in: Circle())
                        .offset(x: 2, y: -2)
                }
            }
            .background(WordConnectStyle.paperGradient, in: Circle())
            .overlay(Circle().strokeBorder(WordConnectStyle.paperEdge, lineWidth: 1.4))
            .shadow(color: .witsShadow, radius: 7, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(hintCandidateCells.isEmpty || hintsRemaining == 0)
        .accessibilityLabel("hint")
    }

    private func iconButton(_ label: String, systemName: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.34, weight: .heavy))
                .foregroundStyle(WordConnectStyle.ink)
                .frame(width: size, height: size)
                .background(WordConnectStyle.paperGradient, in: Circle())
                .overlay(Circle().strokeBorder(WordConnectStyle.paperEdge, lineWidth: 1.4))
                .shadow(color: .witsShadow, radius: 7, y: 4)
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

        if found.contains(word) || foundBonus.contains(word) {
            flash(false)
            selectedIndices.removeAll()
            return
        }

        attempts += 1
        if puzzle.required.contains(word) {
            correct += 1
            streak += 1
            bestStreak = max(bestStreak, streak)
            requiredWordsFoundTotal += 1
            found.insert(word)
            score += Self.requiredWordPoints * multiplier
            logGuess(word, kind: "required")
            cfg.report(.hit, points: Self.requiredWordPoints, combo: streak)
            flash(true)
            selectedIndices.removeAll()

            if foundRequiredCount >= puzzle.required.count {
                let completedBoards = boardsSolved + 1
                boardsSolved = completedBoards
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                    guard !finished else { return }
                    if cfg.isSurvival || completedBoards < Self.boardsPerRun {
                        nextPuzzle()
                    } else {
                        finish()
                    }
                }
            }
        } else if isBonusWord(word) {
            correct += 1
            streak += 1
            bestStreak = max(bestStreak, streak)
            bonusWordsFoundTotal += 1
            foundBonus.append(word)
            score += Self.bonusWordPoints
            logGuess(word, kind: "bonus")
            cfg.report(.hit, points: Self.bonusWordPoints, combo: streak)
            flash(true)
            selectedIndices.removeAll()
        } else {
            wrong += 1
            streak = 0
            logGuess(word, kind: "miss")
            cfg.report(.miss)
            flash(false)
            selectedIndices.removeAll()
        }
    }

    private var hintCandidateCells: [Cell] {
        puzzle.entries
            .filter { !found.contains($0.word) }
            .flatMap { $0.cells() }
            .filter { !hintedCells.contains($0) }
    }

    private func useHint() {
        guard !finished, hintsRemaining > 0, let cell = hintCandidateCells.randomElement() else { return }
        hintedCells.insert(cell)
        hintsUsed += 1
        boardHintsUsed += 1
        attempts += 1
        wrong += 1
        streak = 0
        score = max(0, score - Self.hintPenalty)
        cfg.report(.miss)
    }

    private func flash(_ ok: Bool) {
        feedback = ok
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            feedback = nil
        }
    }

    private func nextPuzzle() {
        let p = Self.makePuzzle(level: Double(currentLevel), avoiding: [puzzle.key] + recentPuzzleKeys)
        let updatedRecent = Self.recordRecentPuzzle(p.key, in: recentPuzzleKeys)
        withAnimation(.easeOut(duration: 0.18)) {
            puzzle = p
            letters = p.letters.shuffled()
            found.removeAll()
            foundBonus.removeAll()
            hintedCells.removeAll()
            boardHintsUsed = 0
            selectedIndices.removeAll()
            recentPuzzleKeys = updatedRecent
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        let accuracy = attempts > 0 ? Double(correct) / Double(attempts) : 0
        let unlocksNextLevel = boardsSolved >= Self.boardsPerRun && accuracy >= 0.85
        let nextLevel = unlocksNextLevel ? min(10, currentLevel + 1) : currentLevel
        var result = GameResult(game: .wordConnect, score: score, accuracy: accuracy)
        result.trials = attempts
        result.startedAt = startedAt
        result.durationMs = Int(cfg.activeElapsed(since: startedAt) * 1000)
        result.raw = [
            "bestStreak": Double(bestStreak),
            "wordsFound": Double(requiredWordsFoundTotal + bonusWordsFoundTotal),
            "requiredWordsFound": Double(requiredWordsFoundTotal),
            "bonusWordsFound": Double(bonusWordsFoundTotal),
            "boardsSolved": Double(boardsSolved),
            "wrong": Double(wrong),
            "hintsUsed": Double(hintsUsed),
            "levelStart": Double(currentLevel),
            "levelEnd": Double(nextLevel),
            "levelDelta": Double(nextLevel - currentLevel)
        ]
        result.text = ["guessedWords": guessedWords]
        onResult(result)
    }

    private func logGuess(_ word: String, kind: String) {
        guard !guessedWords.contains(where: { $0.hasPrefix("\(word)|") }) else { return }
        guessedWords.append("\(word)|\(kind)")
    }

    private func isBonusWord(_ word: String) -> Bool {
        word.count >= 3
            && !puzzle.required.contains(word)
            && !foundBonus.contains(word)
            && Self.canForm(word, from: letters)
            && Self.isDictionaryWord(word)
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

    private static func makePuzzle(level: Double, avoiding recent: [String] = []) -> Puzzle {
        let tier = puzzleTier(for: level)
        let pool = bank.filter { $0.difficulty == tier }
        let blocked = Set(recent)
        let eligible = pool.filter { !blocked.contains($0.key) }
        if let pick = eligible.randomElement() { return pick }

        let currentKey = recent.first
        return pool.filter { $0.key != currentKey }.randomElement()
            ?? pool.randomElement()
            ?? bank[0]
    }

    private static func puzzleTier(for level: Double) -> Int {
        let n = Int(floor(clampLevel(level)))
        if n <= 2 { return 1 }
        if n <= 5 { return 2 }
        if n <= 8 { return 3 }
        return 4
    }

    private static func clampLevel(_ level: Double) -> Double {
        min(10, max(1, level))
    }

    private static func levelNumber(_ level: Double) -> Int {
        min(10, max(1, Int(floor(clampLevel(level)))))
    }

    private static func canForm(_ word: String, from letters: [String]) -> Bool {
        var counts: [Character: Int] = [:]
        for letter in letters {
            guard let ch = letter.first else { continue }
            counts[ch, default: 0] += 1
        }
        for ch in word {
            guard let count = counts[ch], count > 0 else { return false }
            counts[ch] = count - 1
        }
        return true
    }

    private static func isDictionaryWord(_ word: String) -> Bool {
        let text = word.lowercased()
        let checker = UITextChecker()
        let range = NSRange(location: 0, length: text.utf16.count)
        let misspelled = checker.rangeOfMisspelledWord(
            in: text,
            range: range,
            startingAt: 0,
            wrap: false,
            language: "en_US"
        )
        return misspelled.location == NSNotFound
    }

    private static func loadRecentPuzzleKeys() -> [String] {
        UserDefaults.standard.stringArray(forKey: recentPuzzleDefaultsKey) ?? []
    }

    private static func recordRecentPuzzle(_ key: String, in recent: [String]) -> [String] {
        let updated = ([key] + recent.filter { $0 != key }).prefix(recentPuzzleLimit)
        let result = Array(updated)
        UserDefaults.standard.set(result, forKey: recentPuzzleDefaultsKey)
        return result
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
            letters: ["E", "A", "S", "T"],
            required: ["EAST", "SEAT", "EATS", "TEAS"],
            bonus: ["SEA", "SET", "EAT"],
            difficulty: 1
        ),
        Puzzle(
            letters: ["D", "E", "A", "L"],
            required: ["DEAL", "LEAD", "DALE"],
            bonus: ["LAD", "ALE"],
            difficulty: 1
        ),
        Puzzle(
            letters: ["S", "T", "A", "R"],
            required: ["STAR", "RATS", "TARS", "ART"],
            bonus: ["TAR", "SAT"],
            difficulty: 1
        ),
        Puzzle(
            letters: ["P", "O", "S", "T"],
            required: ["POST", "STOP", "POTS"],
            bonus: ["TOP", "POT"],
            difficulty: 1
        ),
        Puzzle(
            letters: ["M", "I", "L", "E"],
            required: ["MILE", "LIME", "ELM"],
            bonus: ["LIE"],
            difficulty: 1
        ),
        Puzzle(
            letters: ["N", "O", "T", "E"],
            required: ["NOTE", "TONE", "ONE"],
            bonus: ["TEN", "TOE"],
            difficulty: 1
        ),
        Puzzle(
            letters: ["F", "I", "R", "E"],
            required: ["FIRE", "RIFE", "IRE"],
            bonus: ["FIR"],
            difficulty: 1
        ),
        Puzzle(
            letters: ["S", "A", "I", "L"],
            required: ["SAIL", "AILS", "AIL"],
            bonus: ["SIL"],
            difficulty: 1
        ),
        Puzzle(
            letters: ["B", "E", "A", "R"],
            required: ["BEAR", "BARE", "BRAE", "EAR"],
            bonus: ["ARE", "BAR"],
            difficulty: 1
        ),
        Puzzle(
            letters: ["G", "A", "M", "E"],
            required: ["GAME", "MAGE", "MEGA"],
            bonus: ["AGE", "GEM"],
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
            letters: ["S", "M", "I", "L", "E"],
            required: ["SMILE", "MILES", "LIME", "SLIM"],
            bonus: ["MILE", "ELM"],
            difficulty: 2
        ),
        Puzzle(
            letters: ["H", "E", "A", "R", "T"],
            required: ["HEART", "EARTH", "HATER", "HEAR", "RATE"],
            bonus: ["TEAR", "HARE"],
            difficulty: 2
        ),
        Puzzle(
            letters: ["A", "N", "G", "L", "E"],
            required: ["ANGLE", "ANGEL", "GLEAN", "LANE"],
            bonus: ["LEAN", "GALE"],
            difficulty: 2
        ),
        Puzzle(
            letters: ["B", "R", "A", "V", "E"],
            required: ["BRAVE", "BEAR", "RAVE", "AVER"],
            bonus: ["BARE", "VERB"],
            difficulty: 2
        ),
        Puzzle(
            letters: ["S", "H", "I", "N", "E"],
            required: ["SHINE", "SINE", "SHIN", "HENS"],
            bonus: ["HIS", "SIN"],
            difficulty: 2
        ),
        Puzzle(
            letters: ["T", "R", "A", "C", "E"],
            required: ["TRACE", "REACT", "CATER", "RACE"],
            bonus: ["CARE", "TEAR"],
            difficulty: 2
        ),
        Puzzle(
            letters: ["P", "A", "I", "N", "T"],
            required: ["PAINT", "PINT", "PAIN", "ANTI"],
            bonus: ["TAP", "TIN"],
            difficulty: 2
        ),
        Puzzle(
            letters: ["D", "R", "E", "A", "M"],
            required: ["DREAM", "ARMED", "READ", "DARE"],
            bonus: ["MADE", "EAR"],
            difficulty: 2
        ),
        Puzzle(
            letters: ["F", "L", "O", "U", "R"],
            required: ["FLOUR", "FOUR", "FOUL", "OUR"],
            bonus: ["FUR"],
            difficulty: 2
        ),
        Puzzle(
            letters: ["C", "H", "A", "I", "R"],
            required: ["CHAIR", "RICH", "HAIR", "AIR"],
            bonus: ["CAR", "ARC"],
            difficulty: 2
        ),
        Puzzle(
            letters: ["G", "R", "A", "P", "E"],
            required: ["GRAPE", "PAGER", "PEAR", "RAGE"],
            bonus: ["GEAR", "APE"],
            difficulty: 2
        ),
        Puzzle(
            letters: ["W", "O", "R", "L", "D"],
            required: ["WORLD", "WORD", "LORD"],
            bonus: ["OLD", "ROW"],
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
            letters: ["C", "L", "O", "U", "D"],
            required: ["CLOUD", "COLD", "LOUD", "CLOD"],
            bonus: ["OLD", "COD"],
            difficulty: 3
        ),
        Puzzle(
            letters: ["B", "L", "E", "N", "D"],
            required: ["BLEND", "BEND", "LEND", "LED"],
            bonus: ["DEN", "END"],
            difficulty: 3
        ),
        Puzzle(
            letters: ["Q", "U", "I", "E", "T"],
            required: ["QUIET", "QUITE", "QUIT", "TIE"],
            bonus: ["UTE"],
            difficulty: 3
        ),
        Puzzle(
            letters: ["S", "T", "R", "E", "A", "M"],
            required: ["STREAM", "MASTER", "TAMERS", "TEAMS", "TERMS"],
            bonus: ["SMART", "EARS"],
            difficulty: 3
        ),
        Puzzle(
            letters: ["F", "R", "I", "E", "N", "D"],
            required: ["FRIEND", "FINDER", "FIRED", "DINER"],
            bonus: ["FIND", "RIND"],
            difficulty: 3
        ),
        Puzzle(
            letters: ["O", "R", "A", "N", "G", "E"],
            required: ["ORANGE", "ORGAN", "RANGE", "GROAN"],
            bonus: ["ANGER", "GEAR"],
            difficulty: 3
        ),
        Puzzle(
            letters: ["C", "A", "S", "T", "L", "E"],
            required: ["CASTLE", "CLEATS", "STEAL", "LACES"],
            bonus: ["TALES", "SEAL"],
            difficulty: 3
        ),
        Puzzle(
            letters: ["B", "R", "I", "D", "G", "E"],
            required: ["BRIDGE", "GIBED", "RIDGE", "BIRD"],
            bonus: ["DIRE", "GRID"],
            difficulty: 3
        ),
        Puzzle(
            letters: ["P", "O", "C", "K", "E", "T"],
            required: ["POCKET", "POET", "TOPE", "COKE"],
            bonus: ["POKE", "TOP"],
            difficulty: 3
        ),
        Puzzle(
            letters: ["G", "A", "R", "D", "E", "N"],
            required: ["GARDEN", "DANGER", "RANGE", "GRADE"],
            bonus: ["READ", "GEAR"],
            difficulty: 3
        ),
        Puzzle(
            letters: ["C", "A", "N", "D", "L", "E"],
            required: ["CANDLE", "DANCE", "CLEAN", "LEND"],
            bonus: ["LACE", "DEAL"],
            difficulty: 3
        ),
        Puzzle(
            letters: ["S", "P", "R", "I", "N", "G"],
            required: ["SPRING", "RINGS", "GRINS", "SIGN"],
            bonus: ["PING", "SPIN"],
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
        ),
        Puzzle(
            letters: ["T", "R", "A", "V", "E", "L"],
            required: ["TRAVEL", "LATER", "ALERT", "ALTER"],
            bonus: ["VALE", "TALE"],
            difficulty: 4
        ),
        Puzzle(
            letters: ["S", "I", "L", "V", "E", "R"],
            required: ["SILVER", "LIVERS", "LIVER", "VEIL"],
            bonus: ["RILE", "SIRE"],
            difficulty: 4
        ),
        Puzzle(
            letters: ["F", "O", "R", "E", "S", "T"],
            required: ["FOREST", "FROST", "STORE", "SOFT"],
            bonus: ["REST", "TORE"],
            difficulty: 4
        ),
        Puzzle(
            letters: ["A", "N", "C", "H", "O", "R"],
            required: ["ANCHOR", "ROACH", "RANCH", "CORN"],
            bonus: ["CHAR", "ARC"],
            difficulty: 4
        ),
        Puzzle(
            letters: ["C", "H", "A", "N", "G", "E"],
            required: ["CHANGE", "HANG", "ACHE", "EACH"],
            bonus: ["CAGE", "CAN"],
            difficulty: 4
        ),
        Puzzle(
            letters: ["M", "O", "D", "E", "R", "N"],
            required: ["MODERN", "DRONE", "DEMON", "MORE"],
            bonus: ["NODE", "NORM"],
            difficulty: 4
        ),
        Puzzle(
            letters: ["P", "R", "A", "I", "S", "E"],
            required: ["PRAISE", "RAISE", "ARISE", "SPEAR"],
            bonus: ["PAIR", "RISE"],
            difficulty: 4
        ),
        Puzzle(
            letters: ["C", "A", "M", "E", "R", "A"],
            required: ["CAMERA", "CREAM", "RACE", "ACRE"],
            bonus: ["MARE", "CARE"],
            difficulty: 4
        ),
        Puzzle(
            letters: ["F", "L", "A", "M", "E", "S"],
            required: ["FLAMES", "FLEAS", "MALES", "SEAL"],
            bonus: ["MEAL", "SAFE"],
            difficulty: 4
        ),
        Puzzle(
            letters: ["B", "A", "L", "A", "N", "C", "E"],
            required: ["BALANCE", "CABLE", "CANAL", "LANCE"],
            bonus: ["CLEAN", "LANE"],
            difficulty: 4
        ),
        Puzzle(
            letters: ["P", "I", "C", "T", "U", "R", "E"],
            required: ["PICTURE", "PRICE", "TRUCE", "CURE"],
            bonus: ["TIER", "RICE"],
            difficulty: 4
        ),
        Puzzle(
            letters: ["M", "U", "S", "I", "C", "A", "L"],
            required: ["MUSICAL", "CLAIM", "MAILS", "CALM"],
            bonus: ["SLIM", "SAIL"],
            difficulty: 4
        )
    ]
}
