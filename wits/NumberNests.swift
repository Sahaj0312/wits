//
//  NumberNests.swift
//  wits
//
//  Number Nests: an original arithmetic-region Latin-square puzzle. Each row
//  and column contains every number once, while the outlined "nests" combine
//  to their shown targets. Puzzles are generated locally from a seeded stream,
//  checked for a unique solution, and scale from friendly 3×3 boards to 6×6.
//

import SwiftUI

// MARK: - Puzzle model

nonisolated struct NumberNestPosition: Hashable, Codable, Sendable {
    let r: Int
    let c: Int
}

nonisolated enum NumberNestOperation: String, Codable, Sendable {
    case exact
    case add
    case subtract
    case multiply
    case divide

    var symbol: String {
        switch self {
        case .exact: ""
        case .add: "+"
        case .subtract: "−"
        case .multiply: "×"
        case .divide: "÷"
        }
    }
}

nonisolated struct NumberNestCage: Identifiable, Equatable, Sendable {
    let id: Int
    let cells: [NumberNestPosition]
    let target: Int
    let operation: NumberNestOperation

    var clue: String { "\(target)\(operation.symbol)" }
    var anchor: NumberNestPosition {
        cells.min { lhs, rhs in lhs.r == rhs.r ? lhs.c < rhs.c : lhs.r < rhs.r }
            ?? NumberNestPosition(r: 0, c: 0)
    }

    func accepts(_ values: [Int]) -> Bool {
        guard values.count == cells.count else { return false }
        switch operation {
        case .exact:
            return values.count == 1 && values[0] == target
        case .add:
            return values.reduce(0, +) == target
        case .subtract:
            return values.count == 2 && abs(values[0] - values[1]) == target
        case .multiply:
            return values.reduce(1, *) == target
        case .divide:
            guard values.count == 2,
                  let low = values.min(), let high = values.max(), low > 0 else { return false }
            return high.isMultiple(of: low) && high / low == target
        }
    }
}

nonisolated struct NumberNestsPuzzle: Equatable, Sendable {
    let size: Int
    let cages: [NumberNestCage]
    let solution: [[Int]]
    let parSeconds: Double

    func cageIndex(at position: NumberNestPosition) -> Int? {
        cages.firstIndex { $0.cells.contains(position) }
    }

    func cage(at position: NumberNestPosition) -> NumberNestCage? {
        cageIndex(at: position).map { cages[$0] }
    }

    func isValidSolution(_ grid: [[Int]]) -> Bool {
        guard grid.count == size, grid.allSatisfy({ $0.count == size }) else { return false }
        let expected = Set(1...size)
        for r in 0..<size where Set(grid[r]) != expected { return false }
        for c in 0..<size where Set((0..<size).map { grid[$0][c] }) != expected { return false }
        return cages.allSatisfy { cage in
            cage.accepts(cage.cells.map { grid[$0.r][$0.c] })
        }
    }
}

// MARK: - Generator and solver

nonisolated enum NumberNestsEngine {
    static func boardSize(mapLevel: Int) -> Int {
        switch max(1, mapLevel) {
        case ...5: 3
        case ...14: 4
        case ...25: 5
        default: 6
        }
    }

    static func generate(mapLevel: Int, seed: UInt64) -> NumberNestsPuzzle {
        let level = max(1, mapLevel)
        let size = boardSize(mapLevel: level)
        var rng = SeededRandomNumberGenerator(seed: seed)
        let solution = latinSquare(size: size, using: &rng)
        let groups = partition(size: size, level: level, using: &rng)
        var cages = groups.enumerated().map { index, cells in
            makeCage(id: index, cells: cells, solution: solution,
                     level: level, using: &rng)
        }
        var puzzle = makePuzzle(size: size, cages: cages, solution: solution, level: level)

        // Arithmetic regions can occasionally describe more than one Latin
        // square. Split a large ambiguous nest into givens until only the
        // intended grid survives. In the worst case every cell becomes a
        // given, so generation always terminates with a valid unique puzzle.
        var guardCount = size * size
        while solutionCount(for: puzzle, limit: 2) != 1, guardCount > 0 {
            guardCount -= 1
            guard let split = cages.indices
                .filter({ cages[$0].cells.count > 1 })
                .max(by: { cages[$0].cells.count < cages[$1].cells.count }) else { break }
            let cells = cages.remove(at: split).cells
            for cell in cells {
                cages.append(NumberNestCage(id: 0,
                                            cells: [cell],
                                            target: solution[cell.r][cell.c],
                                            operation: .exact))
            }
            cages = renumber(cages)
            puzzle = makePuzzle(size: size, cages: cages, solution: solution, level: level)
        }
        return puzzle
    }

    static func solutionCount(for puzzle: NumberNestsPuzzle, limit: Int = 2) -> Int {
        let n = puzzle.size
        let fullMask = (1 << n) - 1
        var grid = Array(repeating: 0, count: n * n)
        var rowMasks = Array(repeating: 0, count: n)
        var colMasks = Array(repeating: 0, count: n)
        var cageForCell = Array(repeating: 0, count: n * n)
        for (cageIndex, cage) in puzzle.cages.enumerated() {
            for cell in cage.cells { cageForCell[cell.r * n + cell.c] = cageIndex }
        }
        var found = 0

        func cageAllows(_ cage: NumberNestCage, assigning value: Int, at index: Int) -> Bool {
            var values: [Int] = []
            var missing = 0
            for cell in cage.cells {
                let cellIndex = cell.r * n + cell.c
                let current = cellIndex == index ? value : grid[cellIndex]
                if current == 0 { missing += 1 } else { values.append(current) }
            }
            if missing == 0 { return cage.accepts(values) }

            switch cage.operation {
            case .exact:
                return values.isEmpty || values[0] == cage.target
            case .add:
                let sum = values.reduce(0, +)
                return sum + missing <= cage.target && sum + missing * n >= cage.target
            case .multiply:
                let product = values.reduce(1, *)
                return product <= cage.target && cage.target.isMultiple(of: product)
            case .subtract:
                guard values.count <= 1 else { return false }
                if let first = values.first {
                    return (1...n).contains(where: { abs(first - $0) == cage.target })
                }
                return true
            case .divide:
                guard values.count <= 1 else { return false }
                if let first = values.first {
                    return (1...n).contains(where: { other in
                        let low = min(first, other), high = max(first, other)
                        return low > 0 && high.isMultiple(of: low) && high / low == cage.target
                    })
                }
                return true
            }
        }

        func candidates(for index: Int) -> [Int] {
            let r = index / n, c = index % n
            let unavailable = rowMasks[r] | colMasks[c]
            let cage = puzzle.cages[cageForCell[index]]
            return (1...n).filter { value in
                let bit = 1 << (value - 1)
                return unavailable & bit == 0 && cageAllows(cage, assigning: value, at: index)
            }
        }

        func search() {
            guard found < limit else { return }
            var bestIndex: Int?
            var bestCandidates: [Int] = []
            for index in grid.indices where grid[index] == 0 {
                let options = candidates(for: index)
                if options.isEmpty { return }
                if bestIndex == nil || options.count < bestCandidates.count {
                    bestIndex = index
                    bestCandidates = options
                    if options.count == 1 { break }
                }
            }
            guard let index = bestIndex else {
                found += 1
                return
            }

            let r = index / n, c = index % n
            for value in bestCandidates {
                let bit = 1 << (value - 1)
                grid[index] = value
                rowMasks[r] |= bit
                colMasks[c] |= bit
                search()
                rowMasks[r] &= fullMask ^ bit
                colMasks[c] &= fullMask ^ bit
                grid[index] = 0
                if found >= limit { return }
            }
        }

        search()
        return found
    }

    private static func latinSquare(size: Int,
                                    using rng: inout SeededRandomNumberGenerator) -> [[Int]] {
        var symbols = Array(1...size)
        var rows = Array(0..<size)
        var cols = Array(0..<size)
        symbols.shuffle(using: &rng)
        rows.shuffle(using: &rng)
        cols.shuffle(using: &rng)
        return rows.map { r in cols.map { c in symbols[(r + c) % size] } }
    }

    private static func partition(size: Int,
                                  level: Int,
                                  using rng: inout SeededRandomNumberGenerator) -> [[NumberNestPosition]] {
        var remaining = Array(0..<(size * size))
        var groups: [[NumberNestPosition]] = []
        let maximum = level < 10 ? 2 : (level < 24 ? 3 : 4)

        while !remaining.isEmpty {
            let startOffset = Int.random(in: 0..<remaining.count, using: &rng)
            let start = remaining.remove(at: startOffset)
            var group = [position(start, size: size)]
            let roll = Int.random(in: 0..<100, using: &rng)
            let desired = roll < 14 ? 1 : (roll < 72 ? 2 : maximum)

            while group.count < desired {
                let occupied = Set(group.map { $0.r * size + $0.c })
                let available = Set(remaining)
                let frontier = group
                    .flatMap { neighbours(of: $0, size: size) }
                    .map { $0.r * size + $0.c }
                    .filter { !occupied.contains($0) && available.contains($0) }
                    .sorted()
                let unique = Array(Set(frontier)).sorted()
                guard !unique.isEmpty else { break }
                let pick = unique[Int.random(in: 0..<unique.count, using: &rng)]
                remaining.removeAll { $0 == pick }
                group.append(position(pick, size: size))
            }
            groups.append(group.sorted { $0.r == $1.r ? $0.c < $1.c : $0.r < $1.r })
        }
        return groups
    }

    private static func makeCage(id: Int,
                                 cells: [NumberNestPosition],
                                 solution: [[Int]],
                                 level: Int,
                                 using rng: inout SeededRandomNumberGenerator) -> NumberNestCage {
        let values = cells.map { solution[$0.r][$0.c] }
        guard values.count > 1 else {
            return NumberNestCage(id: id, cells: cells, target: values[0], operation: .exact)
        }

        var operations: [NumberNestOperation] = [.add]
        if level >= 7 { operations.append(.multiply) }
        if values.count == 2 {
            operations.append(.subtract)
            if level >= 13, let low = values.min(), let high = values.max(), high.isMultiple(of: low) {
                operations.append(.divide)
            }
        }
        let operation = operations[Int.random(in: 0..<operations.count, using: &rng)]
        let target: Int
        switch operation {
        case .exact: target = values[0]
        case .add: target = values.reduce(0, +)
        case .subtract: target = abs(values[0] - values[1])
        case .multiply: target = values.reduce(1, *)
        case .divide:
            target = (values.max() ?? 1) / max(1, values.min() ?? 1)
        }
        return NumberNestCage(id: id, cells: cells, target: target, operation: operation)
    }

    private static func renumber(_ cages: [NumberNestCage]) -> [NumberNestCage] {
        cages.sorted { lhs, rhs in
            let a = lhs.anchor, b = rhs.anchor
            return a.r == b.r ? a.c < b.c : a.r < b.r
        }.enumerated().map { index, cage in
            NumberNestCage(id: index,
                           cells: cage.cells,
                           target: cage.target,
                           operation: cage.operation)
        }
    }

    private static func makePuzzle(size: Int,
                                   cages: [NumberNestCage],
                                   solution: [[Int]],
                                   level: Int) -> NumberNestsPuzzle {
        let secondsBySize = [3: 75.0, 4: 150.0, 5: 300.0, 6: 540.0]
        let par = (secondsBySize[size] ?? 180) + Double(max(0, level - 1)) * 2
        return NumberNestsPuzzle(size: size,
                                 cages: renumber(cages),
                                 solution: solution,
                                 parSeconds: par)
    }

    private static func position(_ index: Int, size: Int) -> NumberNestPosition {
        NumberNestPosition(r: index / size, c: index % size)
    }

    private static func neighbours(of position: NumberNestPosition,
                                   size: Int) -> [NumberNestPosition] {
        [(position.r - 1, position.c), (position.r + 1, position.c),
         (position.r, position.c - 1), (position.r, position.c + 1)]
            .filter { $0.0 >= 0 && $0.0 < size && $0.1 >= 0 && $0.1 < size }
            .map { NumberNestPosition(r: $0.0, c: $0.1) }
    }
}

// MARK: - Play screen

struct NumberNestsScreen: View {
    let cfg: GameConfig
    let onResult: (GameResult) -> Void

    @State private var puzzle: NumberNestsPuzzle?
    @State private var entries: [[Int?]] = []
    @State private var notes: [[Set<Int>]] = []
    @State private var selected: NumberNestPosition?
    @State private var revealed: Set<NumberNestPosition> = []
    @State private var wrongCells: Set<NumberNestPosition> = []
    @State private var noteMode = false
    @State private var hints = 0
    @State private var wrongChecks = 0
    @State private var elapsed = 0.0
    @State private var timerStartedAt = Date()
    @State private var message = ""
    @State private var finished = false
    @State private var shakeBoard = 0
    @State private var freeHintsRemaining = 2
    @State private var hintAdBusy = false
    @State private var ads = AdManager.shared

    private let startedAt = Date()
    private let level: Double
    private let mapLevel: Int
    private var world: GameWorld { GameID.numberNests.world }

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        self.level = cfg.difficulty.level
        self.mapLevel = cfg.mapLevel ?? DifficultyScale.contentLevel(for: .numberNests,
                                                                     legacyDifficulty: cfg.difficulty.level)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                GameStageBackground(game: .numberNests)
                if let puzzle {
                    VStack(spacing: 0) {
                        topBar
                            .padding(.top, 8)
                            .padding(.horizontal, WitsMetrics.screenPadding)

                        Spacer(minLength: 10)

                        board(puzzle, available: geo.size)
                            .modifier(NumberNestsShakeEffect(shakes: CGFloat(shakeBoard)))
                            .animation(.linear(duration: 0.3), value: shakeBoard)

                        nestGuide(puzzle)
                            .padding(.top, 12)

                        Spacer(minLength: 10)

                        keypad(puzzle)
                            .padding(.horizontal, WitsMetrics.screenPadding)
                            .padding(.bottom, 12)
                    }
                } else {
                    VStack(spacing: 14) {
                        ProgressView().tint(world.ink)
                        Text("building the nests…")
                            .font(.system(size: 14, weight: .semibold, design: world.bodyDesign))
                            .foregroundStyle(world.muted)
                    }
                }
            }
        }
        .task { await setUpAndRun() }
        .onAppear { ads.loadRewardedIfNeeded() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Number Nests")
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            Spacer().frame(width: 38)

            HStack(spacing: 6) {
                Image(systemName: "timer")
                Text(Self.clock(elapsed))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                Text(wrongChecks == 0 ? "clean" : "checks \(wrongChecks)")
                    .foregroundStyle(wrongChecks == 0 ? world.accent : world.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(world.ink)
            .padding(.horizontal, 8)
            .frame(height: 42)
            .background(world.surface.opacity(0.9), in: Capsule())

            Button(action: requestReveal) {
                LimitedHintButtonLabel(world: world,
                                       freeHintsRemaining: freeHintsRemaining,
                                       background: world.surface.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(finished || hintAdBusy ||
                      (freeHintsRemaining == 0 && !ads.rewardedReady))
            .opacity(hintAdBusy || (freeHintsRemaining == 0 && !ads.rewardedReady) ? 0.6 : 1)
            .accessibilityLabel(hintAccessibilityLabel)

            Button(action: showHelp) {
                Image(systemName: "questionmark")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(world.ink)
                    .frame(width: 42, height: 42)
                    .background(world.surface.opacity(0.9), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show rule reminder")
        }
    }

    private func board(_ puzzle: NumberNestsPuzzle, available: CGSize) -> some View {
        let side = min(available.width - WitsMetrics.screenPadding * 2, 440)
        let cell = side / CGFloat(puzzle.size)
        let conflicts = liveConflicts(puzzle)
        return VStack(spacing: 0) {
            ForEach(0..<puzzle.size, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<puzzle.size, id: \.self) { c in
                        nestCell(puzzle,
                                 position: NumberNestPosition(r: r, c: c),
                                 side: cell,
                                 conflicts: conflicts)
                    }
                }
            }
        }
        .frame(width: side, height: side)
        .background(world.surface)
        .overlay(Rectangle().strokeBorder(world.ink, lineWidth: 3))
        .shadow(color: world.ink.opacity(0.16), radius: 12, y: 6)
    }

    private func nestCell(_ puzzle: NumberNestsPuzzle,
                          position: NumberNestPosition,
                          side: CGFloat,
                          conflicts: Set<NumberNestPosition>) -> some View {
        let cage = puzzle.cage(at: position)
        let value = entries[position.r][position.c]
        let isSelected = selected == position
        let isWrong = wrongCells.contains(position) || conflicts.contains(position)
        let isGiven = revealed.contains(position)

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(isWrong ? world.secondary.opacity(0.20)
                      : isSelected ? world.accent.opacity(0.24)
                      : world.surface)
            Rectangle().strokeBorder(world.ink.opacity(0.14), lineWidth: 0.6)

            if let cage, cage.anchor == position {
                Text(cage.clue)
                    .font(.system(size: max(9, side * 0.20), weight: .black, design: .rounded))
                    .foregroundStyle(world.muted)
                    .padding(.top, 3)
                    .padding(.leading, 5)
            }

            if let value {
                Text("\(value)")
                    .font(.system(size: side * 0.47, weight: .black, design: world.titleDesign))
                    .foregroundStyle(isGiven ? world.accent : world.ink)
                    .frame(width: side, height: side)
                    .offset(y: side * 0.08)
            } else {
                notesView(notes[position.r][position.c], size: puzzle.size, side: side)
            }
        }
        .frame(width: side, height: side)
        .overlay { cageBorders(puzzle, at: position) }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !finished else { return }
            selected = position
            wrongCells.remove(position)
            GameFeel.shared.uiTick(0.45)
        }
        .accessibilityLabel(cellAccessibility(puzzle, position: position, value: value, cage: cage))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func notesView(_ values: Set<Int>, size: Int, side: CGFloat) -> some View {
        let columns = size <= 4 ? 2 : 3
        let rows = Int(ceil(Double(size) / Double(columns)))
        return VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<columns, id: \.self) { col in
                        let value = row * columns + col + 1
                        Text(value <= size && values.contains(value) ? "\(value)" : " ")
                            .font(.system(size: max(8, side * 0.14), weight: .bold, design: .rounded))
                            .foregroundStyle(world.muted)
                            .frame(width: side / CGFloat(columns),
                                   height: side * 0.50 / CGFloat(rows))
                    }
                }
            }
        }
        .frame(width: side, height: side * 0.50)
        .offset(y: side * 0.38)
    }

    private func cageBorders(_ puzzle: NumberNestsPuzzle,
                             at position: NumberNestPosition) -> some View {
        let id = puzzle.cageIndex(at: position)
        let topDiffers = position.r == 0 || puzzle.cageIndex(at: .init(r: position.r - 1, c: position.c)) != id
        let bottomDiffers = position.r == puzzle.size - 1 || puzzle.cageIndex(at: .init(r: position.r + 1, c: position.c)) != id
        let leftDiffers = position.c == 0 || puzzle.cageIndex(at: .init(r: position.r, c: position.c - 1)) != id
        let rightDiffers = position.c == puzzle.size - 1 || puzzle.cageIndex(at: .init(r: position.r, c: position.c + 1)) != id
        return ZStack {
            VStack(spacing: 0) {
                Rectangle().fill(topDiffers ? world.ink : .clear).frame(height: 2.4)
                Spacer(minLength: 0)
                Rectangle().fill(bottomDiffers ? world.ink : .clear).frame(height: 2.4)
            }
            HStack(spacing: 0) {
                Rectangle().fill(leftDiffers ? world.ink : .clear).frame(width: 2.4)
                Spacer(minLength: 0)
                Rectangle().fill(rightDiffers ? world.ink : .clear).frame(width: 2.4)
            }
        }
        .allowsHitTesting(false)
    }

    private func nestGuide(_ puzzle: NumberNestsPuzzle) -> some View {
        let cage = selected.flatMap { puzzle.cage(at: $0) }
        let text: String
        if !message.isEmpty {
            text = message
        } else if let cage {
            text = cage.operation == .exact
                ? "this nest is exactly \(cage.target)"
                : "make \(cage.target) using \(cage.operation.symbol)"
        } else {
            text = "each row and column uses 1–\(puzzle.size) once"
        }
        return Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(message.isEmpty ? world.muted : world.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.72)
            .frame(height: 34)
            .padding(.horizontal, WitsMetrics.screenPadding)
    }

    private func keypad(_ puzzle: NumberNestsPuzzle) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 7) {
                ForEach(1...puzzle.size, id: \.self) { value in
                    Button { enter(value, puzzle: puzzle) } label: {
                        Text("\(value)")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(world.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(world.surface, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(noteMode ? world.accent.opacity(0.45) : world.ink.opacity(0.14), lineWidth: 1))
                    }
                    .buttonStyle(PressScale())
                    .disabled(finished)
                }
            }

            HStack(spacing: 8) {
                Button {
                    noteMode.toggle()
                    GameFeel.shared.uiSelection()
                } label: {
                    Label("NOTES", systemImage: "pencil")
                        .foregroundStyle(noteMode ? world.background : world.ink)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(noteMode ? world.accent : world.surface,
                                    in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(PressScale())

                Button(action: erase) {
                    Image(systemName: "delete.left.fill")
                        .foregroundStyle(world.ink)
                        .frame(width: 58, height: 46)
                        .background(world.raised, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(PressScale())
                .accessibilityLabel("Erase selected square")

                Button { check(puzzle) } label: {
                    Text("CHECK")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(world.background)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(world.accent, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(PressScale())
                .disabled(finished || !isFull(puzzle))
                .opacity(isFull(puzzle) ? 1 : 0.48)
            }
            .font(.system(size: 13, weight: .black, design: .rounded))
        }
        .frame(maxWidth: 520)
    }

    private func enter(_ value: Int, puzzle: NumberNestsPuzzle) {
        guard !finished, let selected, !revealed.contains(selected) else { return }
        wrongCells.removeAll()
        message = ""
        if noteMode {
            if notes[selected.r][selected.c].contains(value) {
                notes[selected.r][selected.c].remove(value)
            } else {
                entries[selected.r][selected.c] = nil
                notes[selected.r][selected.c].insert(value)
            }
            GameFeel.shared.uiTick(0.45)
            return
        }

        let wasFull = isFull(puzzle)
        entries[selected.r][selected.c] = entries[selected.r][selected.c] == value ? nil : value
        notes[selected.r][selected.c].removeAll()
        if entries[selected.r][selected.c] != nil {
            for c in 0..<puzzle.size { notes[selected.r][c].remove(value) }
            for r in 0..<puzzle.size { notes[r][selected.c].remove(value) }
        }
        GameFeel.shared.play(.correct(combo: 1))
        if !wasFull, isFull(puzzle) { check(puzzle) }
    }

    private func erase() {
        guard !finished, let selected, !revealed.contains(selected) else { return }
        let hadContent = entries[selected.r][selected.c] != nil || !notes[selected.r][selected.c].isEmpty
        entries[selected.r][selected.c] = nil
        notes[selected.r][selected.c].removeAll()
        wrongCells.remove(selected)
        message = ""
        if hadContent { GameFeel.shared.uiTap() }
    }

    private func requestReveal() {
        guard !finished, !hintAdBusy else { return }
        if freeHintsRemaining > 0 {
            if reveal() { freeHintsRemaining -= 1 }
            return
        }
        guard ads.rewardedReady else {
            ads.loadRewardedIfNeeded()
            return
        }
        hintAdBusy = true
        cfg.pause()
        ads.showRewarded { earned in
            cfg.resume()
            hintAdBusy = false
            guard earned else { return }
            _ = reveal()
        }
    }

    @discardableResult
    private func reveal() -> Bool {
        guard let puzzle, !finished else { return false }
        let position = selected.flatMap { entries[$0.r][$0.c] == puzzle.solution[$0.r][$0.c] ? nil : $0 }
            ?? firstUnsolved(in: puzzle)
        guard let position else { return false }
        hints += 1
        selected = position
        entries[position.r][position.c] = puzzle.solution[position.r][position.c]
        notes[position.r][position.c].removeAll()
        revealed.insert(position)
        wrongCells.remove(position)
        message = "one square revealed"
        GameFeel.shared.play(.nearMiss)
        if isFull(puzzle), firstUnsolved(in: puzzle) == nil { check(puzzle) }
        return true
    }

    private var hintAccessibilityLabel: String {
        freeHintsRemaining > 0
            ? "Reveal one square, \(freeHintsRemaining) free hints remaining"
            : "Reveal one square with a rewarded ad"
    }

    private func check(_ puzzle: NumberNestsPuzzle) {
        guard !finished, isFull(puzzle) else { return }
        let wrong = Set((0..<puzzle.size).flatMap { r in
            (0..<puzzle.size).compactMap { c -> NumberNestPosition? in
                entries[r][c] == puzzle.solution[r][c] ? nil : NumberNestPosition(r: r, c: c)
            }
        })
        if wrong.isEmpty {
            finished = true
            message = "every nest fits"
            GameFeel.shared.play(.newBest)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { finish(puzzle) }
        } else {
            wrongChecks += 1
            wrongCells = wrong
            shakeBoard += 1
            message = wrong.count == 1 ? "one square needs another look" : "\(wrong.count) squares need another look"
            GameFeel.shared.play(.wrong)
        }
    }

    private func liveConflicts(_ puzzle: NumberNestsPuzzle) -> Set<NumberNestPosition> {
        var conflicts: Set<NumberNestPosition> = []
        for r in 0..<puzzle.size {
            for value in 1...puzzle.size {
                let matches = (0..<puzzle.size).filter { entries[r][$0] == value }
                if matches.count > 1 { matches.forEach { conflicts.insert(.init(r: r, c: $0)) } }
            }
        }
        for c in 0..<puzzle.size {
            for value in 1...puzzle.size {
                let matches = (0..<puzzle.size).filter { entries[$0][c] == value }
                if matches.count > 1 { matches.forEach { conflicts.insert(.init(r: $0, c: c)) } }
            }
        }
        for cage in puzzle.cages {
            let values = cage.cells.compactMap { entries[$0.r][$0.c] }
            if values.count == cage.cells.count, !cage.accepts(values) {
                conflicts.formUnion(cage.cells)
            }
        }
        return conflicts
    }

    private func isFull(_ puzzle: NumberNestsPuzzle) -> Bool {
        entries.count == puzzle.size && entries.allSatisfy { row in row.count == puzzle.size && row.allSatisfy { $0 != nil } }
    }

    private func firstUnsolved(in puzzle: NumberNestsPuzzle) -> NumberNestPosition? {
        for r in 0..<puzzle.size {
            for c in 0..<puzzle.size where entries[r][c] != puzzle.solution[r][c] {
                return NumberNestPosition(r: r, c: c)
            }
        }
        return nil
    }

    private func setUpAndRun() async {
        if puzzle == nil {
            let targetLevel = mapLevel
            let seed = cfg.resolvedRandomSeed()
            let task = Task.detached(priority: .userInitiated) {
                NumberNestsEngine.generate(mapLevel: targetLevel, seed: seed)
            }
            let generated = await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }
            guard !Task.isCancelled else { return }
            puzzle = generated
            entries = Array(repeating: Array(repeating: nil, count: generated.size), count: generated.size)
            notes = Array(repeating: Array(repeating: Set<Int>(), count: generated.size), count: generated.size)
            selected = NumberNestPosition(r: 0, c: 0)
            timerStartedAt = Date()
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            guard !finished else { return }
            elapsed = cfg.activeElapsed(since: timerStartedAt)
        }
    }

    private func finish(_ puzzle: NumberNestsPuzzle) {
        let seconds = max(1, elapsed)
        let cells = puzzle.size * puzzle.size
        let cleanness = max(0, 1 - Double(hints) * 0.13 - Double(wrongChecks) * 0.08)
        let timeEfficiency = min(1, puzzle.parSeconds / seconds)
        let accuracy = min(1, max(0, 0.25 + cleanness * 0.65 + timeEfficiency * 0.10))
        let score = max(0, Int((Double(cells * 55) + cleanness * 1_200
                               + timeEfficiency * 450 + Double(mapLevel * 15)).rounded()))

        var result = GameResult(game: .numberNests, score: score, accuracy: accuracy)
        result.trials = cells
        result.startedAt = startedAt
        result.durationMs = Int(seconds * 1_000)
        result.raw = [
            "efficiency": (cleanness * 100).rounded(),
            "correct": Double(cells),
            "cells": Double(cells),
            "size": Double(puzzle.size),
            "nests": Double(puzzle.cages.count),
            "reveals": Double(hints),
            "wrongChecks": Double(wrongChecks),
            "seconds": seconds.rounded(),
            "parSeconds": puzzle.parSeconds.rounded(),
            "numberNestsLevel": level
        ]
        onResult(result)
    }

    private func showHelp() {
        guard let puzzle else { return }
        GameFeel.shared.uiTap()
        message = "use 1–\(puzzle.size) once per row and column; every outlined nest must hit its target"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if !finished { message = "" }
        }
    }

    private func cellAccessibility(_ puzzle: NumberNestsPuzzle,
                                   position: NumberNestPosition,
                                   value: Int?,
                                   cage: NumberNestCage?) -> String {
        let entry = value.map(String.init) ?? "empty"
        let clue = cage?.anchor == position ? ", nest \(cage?.clue ?? "")" : ""
        return "Row \(position.r + 1), column \(position.c + 1), \(entry)\(clue)"
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct NumberNestsShakeEffect: GeometryEffect {
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(shakes * .pi * 4) * 7, y: 0))
    }
}
