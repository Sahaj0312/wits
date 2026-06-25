//
//  RuleFinder.swift
//  wits
//
//  Matrix reasoning: infer the rule across a 3x3 grid and pick the missing
//  figure. Difficulty now comes from rule templates, not just adding more
//  visible attributes to the same row/column pattern.
//

import SwiftUI

private struct Figure: Equatable, Hashable {
    var shape: Int     // index into shapes
    var count: Int     // 1...3
    var filled: Bool
    var tint: Int      // index into figureColors
    var size: Int      // 0...2
}

private enum FigureAttribute: CaseIterable, Hashable {
    case shape, count, fill, tint, size

    var domainCount: Int {
        switch self {
        case .shape, .tint: 4
        case .count, .size: 3
        case .fill: 2
        }
    }

    var latinDomainCount: Int { min(3, domainCount) }

    static var latinEligible: [FigureAttribute] {
        [.shape, .count, .tint, .size]
    }
}

private extension Figure {
    func value(for attr: FigureAttribute) -> Int {
        switch attr {
        case .shape: shape
        case .count: count - 1
        case .fill: filled ? 1 : 0
        case .tint: tint
        case .size: size
        }
    }

    mutating func setValue(_ value: Int, for attr: FigureAttribute) {
        let normalized = ((value % attr.domainCount) + attr.domainCount) % attr.domainCount
        switch attr {
        case .shape: shape = normalized
        case .count: count = normalized + 1
        case .fill: filled = normalized == 1
        case .tint: tint = normalized
        case .size: size = normalized
        }
    }
}

private enum AxisPattern: CaseIterable {
    case byRow, byCol, checker

    func step(row: Int, col: Int) -> Int {
        switch self {
        case .byRow: row
        case .byCol: col
        case .checker: row + col
        }
    }
}

private enum CombineDirection {
    case rows, columns
}

private struct AttributeRule {
    var attr: FigureAttribute
    var pattern: AxisPattern
    var offset: Int

    func value(row: Int, col: Int) -> Int {
        (offset + pattern.step(row: row, col: col)) % attr.domainCount
    }
}

private struct LatinRule {
    var attr: FigureAttribute
    var values: [Int]
    var offset: Int
    var slope: Int

    func value(row: Int, col: Int) -> Int {
        values[(offset + row + slope * col) % values.count]
    }
}

private struct PuzzleBuild {
    var grid: [Figure]
    var answerIndex: Int
    var tier: Int
    var template: String
    var focus: [FigureAttribute]
    var validator: ([Figure]) -> Bool
}

struct RuleFinderScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private static let shapes = ["circle", "square", "triangle", "diamond"]
    private static let figureColors: [Color] = [.witsInk, .witsAccent, .witsWarm, .witsMuted]
    private static let total = 8

    private let baseTier: Int
    @State private var grid: [Figure] = []
    @State private var options: [Figure] = []
    @State private var answer = Figure(shape: 0, count: 1, filled: true, tint: 0, size: 1)
    @State private var answerIndex = 8
    @State private var picked: Figure?
    @State private var puzzle = 1
    @State private var correct = 0
    @State private var streak = 0
    @State private var score = 0
    @State private var generation = 0
    @State private var started = false
    @State private var currentTier = 1
    @State private var maxTier = 1
    @State private var tierTotal = 0
    @State private var puzzleStartedAt = Date()
    @State private var runStartedAt = Date()
    @State private var responseTimesMs: [Double] = []
    @State private var templatesSeen: [String] = []

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        self.baseTier = max(1, min(5, Int(ceil(cfg.difficulty.level / 2.0))))
    }

    var body: some View {
        VStack(spacing: 12) {
            if !cfg.isSurvival {
                HStack(alignment: .firstTextBaseline) {
                    Text("puzzle \(Text("\(min(puzzle, Self.total))").foregroundStyle(Color.witsAccent)) of \(Self.total)")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                        .monospacedDigit()
                    Spacer()
                    Text("\(score) pts")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsMuted)
                        .monospacedDigit()
                }
                ProgressTrack(fraction: Double(puzzle - 1) / Double(Self.total), animated: true)
            }

            matrix
            Text("which figure completes the grid?")
                .font(.witsBody(13))
                .foregroundStyle(Color.witsFaint)
            optionGrid
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .onAppear {
            if !started {
                started = true
                runStartedAt = Date()
                newPuzzle()
            }
        }
    }

    private var matrix: some View {
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(0..<9, id: \.self) { i in
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.witsTint)
                    if i == answerIndex {
                        Image(systemName: "questionmark")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(Color.witsAccent)
                    } else if i < grid.count {
                        figureView(grid[i])
                    }
                }
                .aspectRatio(1, contentMode: .fit)
            }
        }
        .padding(14)
        .cardSurface()
    }

    private var optionGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                Button { pick(opt) } label: {
                    figureView(opt)
                        .frame(maxWidth: .infinity)
                        .frame(height: 76)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.witsCard)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(borderColor(opt), lineWidth: 2)
                        )
                        .shadow(color: .witsShadow, radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(picked != nil)
            }
        }
    }

    private func borderColor(_ opt: Figure) -> Color {
        guard let picked else { return .clear }
        if opt == answer { return .witsAccent }
        if opt == picked { return .witsWarm }
        return .clear
    }

    private func figureView(_ f: Figure) -> some View {
        let size = [14.0, 17.0, 20.0][max(0, min(2, f.size))]
        return HStack(spacing: 3) {
            ForEach(0..<f.count, id: \.self) { _ in
                Image(systemName: Self.shapes[f.shape] + (f.filled ? ".fill" : ""))
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(Self.figureColors[f.tint])
            }
        }
    }

    // MARK: Generation

    private func newPuzzle() {
        let tier = nextTier()
        var build = makePuzzle(tier: tier)
        var opts = makeOptions(for: build)
        var attempts = 0
        while opts.count < 4 && attempts < 80 {
            attempts += 1
            build = makePuzzle(tier: tier)
            opts = makeOptions(for: build)
        }

        grid = build.grid
        answerIndex = build.answerIndex
        answer = build.grid[build.answerIndex]
        options = opts
        currentTier = build.tier
        maxTier = max(maxTier, build.tier)
        tierTotal += build.tier
        templatesSeen.append(build.template)
        picked = nil
        puzzleStartedAt = Date()
    }

    private func nextTier() -> Int {
        let runBoost = cfg.isSurvival ? correct / 3 : correct / 5
        let ceiling = min(5, baseTier + runBoost)
        guard ceiling > 1, Bool.random() else { return ceiling }
        return Int.random(in: max(1, ceiling - 1)...ceiling)
    }

    private func makePuzzle(tier: Int) -> PuzzleBuild {
        switch tier {
        case 1:
            return makeAxisPuzzle(tier: tier, attrCount: 1, allowChecker: false)
        case 2:
            return Bool.random()
                ? makeAxisPuzzle(tier: tier, attrCount: 2, allowChecker: true)
                : makeLatinPuzzle(tier: tier, attrCount: 1)
        case 3:
            switch Int.random(in: 0..<3) {
            case 0: return makeAxisPuzzle(tier: tier, attrCount: 3, allowChecker: true)
            case 1: return makeLatinPuzzle(tier: tier, attrCount: 2)
            default: return makeCombinePuzzle(tier: tier, combineCount: 1, supportCount: 1)
            }
        case 4:
            return Bool.random()
                ? makeCombinePuzzle(tier: tier, combineCount: 1, supportCount: 2)
                : makeAxisPuzzle(tier: tier, attrCount: 4, allowChecker: true)
        default:
            return Bool.random()
                ? makeCombinePuzzle(tier: tier, combineCount: 2, supportCount: 2)
                : makeLatinPuzzle(tier: tier, attrCount: 3)
        }
    }

    private func makeAxisPuzzle(tier: Int, attrCount: Int, allowChecker: Bool) -> PuzzleBuild {
        let attrs = Array(FigureAttribute.allCases.shuffled().prefix(attrCount))
        let patterns = allowChecker ? AxisPattern.allCases : [.byRow, .byCol]
        let rules = attrs.map { attr in
            AttributeRule(attr: attr, pattern: patterns.randomElement()!, offset: Int.random(in: 0..<attr.domainCount))
        }
        let base = randomFigure()

        func figure(row: Int, col: Int) -> Figure {
            var f = base
            for rule in rules {
                f.setValue(rule.value(row: row, col: col), for: rule.attr)
            }
            return f
        }

        let built = buildGrid(figure)
        let validator: ([Figure]) -> Bool = { candidate in
            guard candidate.count == 9 else { return false }
            for index in 0..<9 where candidate[index] != figure(row: index / 3, col: index % 3) {
                return false
            }
            return true
        }

        return PuzzleBuild(
            grid: built,
            answerIndex: Int.random(in: 0..<9),
            tier: tier,
            template: "axis",
            focus: attrs,
            validator: validator
        )
    }

    private func makeLatinPuzzle(tier: Int, attrCount: Int) -> PuzzleBuild {
        let attrs = Array(FigureAttribute.latinEligible.shuffled().prefix(attrCount))
        let rules = attrs.map { attr in
            let values = Array(0..<attr.latinDomainCount).shuffled()
            return LatinRule(attr: attr, values: values, offset: Int.random(in: 0..<3), slope: Bool.random() ? 1 : 2)
        }
        let base = randomFigure()

        func figure(row: Int, col: Int) -> Figure {
            var f = base
            for rule in rules {
                f.setValue(rule.value(row: row, col: col), for: rule.attr)
            }
            return f
        }

        let built = buildGrid(figure)
        let validator: ([Figure]) -> Bool = { candidate in
            guard candidate.count == 9 else { return false }
            for index in 0..<9 where candidate[index] != figure(row: index / 3, col: index % 3) {
                return false
            }
            return true
        }

        return PuzzleBuild(
            grid: built,
            answerIndex: Int.random(in: 0..<9),
            tier: tier,
            template: "set",
            focus: attrs,
            validator: validator
        )
    }

    private func makeCombinePuzzle(tier: Int, combineCount: Int, supportCount: Int) -> PuzzleBuild {
        let direction: CombineDirection = Bool.random() ? .rows : .columns
        let combineAttrs = Array(FigureAttribute.allCases.shuffled().prefix(combineCount))
        let supportPool = FigureAttribute.allCases.filter { !combineAttrs.contains($0) }
        let supportRules = Array(supportPool.shuffled().prefix(supportCount)).map { attr in
            AttributeRule(attr: attr, pattern: Bool.random() ? .byRow : .byCol, offset: Int.random(in: 0..<attr.domainCount))
        }
        let base = randomFigure()
        var built = Array(repeating: base, count: 9)

        for r in 0..<3 {
            for c in 0..<3 {
                var f = built[r * 3 + c]
                for rule in supportRules {
                    f.setValue(rule.value(row: r, col: c), for: rule.attr)
                }
                built[r * 3 + c] = f
            }
        }

        for attr in combineAttrs {
            for line in 0..<3 {
                let domain = attr.latinDomainCount
                let first = Int.random(in: 0..<domain)
                let second = Int.random(in: 0..<domain)
                let third = combine(first, second, attr: attr)
                let values = [first, second, third]
                for slot in 0..<3 {
                    let index = direction == .rows ? line * 3 + slot : slot * 3 + line
                    built[index].setValue(values[slot], for: attr)
                }
            }
        }

        let validator: ([Figure]) -> Bool = { candidate in
            guard candidate.count == 9 else { return false }

            for attr in FigureAttribute.allCases where !combineAttrs.contains(attr) {
                if let rule = supportRules.first(where: { $0.attr == attr }) {
                    for index in 0..<9 {
                        let expected = rule.value(row: index / 3, col: index % 3)
                        if candidate[index].value(for: attr) != expected { return false }
                    }
                } else {
                    let expected = base.value(for: attr)
                    if candidate.contains(where: { $0.value(for: attr) != expected }) { return false }
                }
            }

            for attr in combineAttrs {
                for line in 0..<3 {
                    let firstIndex = direction == .rows ? line * 3 : line
                    let secondIndex = direction == .rows ? line * 3 + 1 : 3 + line
                    let thirdIndex = direction == .rows ? line * 3 + 2 : 6 + line
                    let first = candidate[firstIndex].value(for: attr)
                    let second = candidate[secondIndex].value(for: attr)
                    if candidate[thirdIndex].value(for: attr) != combine(first, second, attr: attr) {
                        return false
                    }
                }
            }

            return true
        }

        return PuzzleBuild(
            grid: built,
            answerIndex: Int.random(in: 0..<9),
            tier: tier,
            template: "combine",
            focus: Array(Set(combineAttrs + supportRules.map(\.attr))),
            validator: validator
        )
    }

    private func makeOptions(for puzzle: PuzzleBuild) -> [Figure] {
        let answer = puzzle.grid[puzzle.answerIndex]
        var seen: Set<Figure> = [answer]
        var distractors: [Figure] = []

        func satisfiesRule(_ candidate: Figure) -> Bool {
            var grid = puzzle.grid
            grid[puzzle.answerIndex] = candidate
            return puzzle.validator(grid)
        }

        func add(_ candidate: Figure) {
            guard distractors.count < 3 else { return }
            guard !seen.contains(candidate), !satisfiesRule(candidate) else { return }
            seen.insert(candidate)
            distractors.append(candidate)
        }

        let row = puzzle.answerIndex / 3
        let col = puzzle.answerIndex % 3
        let peerIndexes = (0..<9).filter { $0 != puzzle.answerIndex && ($0 / 3 == row || $0 % 3 == col) }.shuffled()
        let focus = puzzle.focus.isEmpty ? FigureAttribute.allCases : puzzle.focus

        for peer in peerIndexes {
            let peerFigure = puzzle.grid[peer]
            for attr in focus.shuffled() {
                var candidate = answer
                candidate.setValue(peerFigure.value(for: attr), for: attr)
                add(candidate)
            }

            var blended = answer
            for attr in focus.shuffled().prefix(min(2, focus.count)) {
                blended.setValue(peerFigure.value(for: attr), for: attr)
            }
            add(blended)
        }

        for peer in (0..<9).filter({ $0 != puzzle.answerIndex }).shuffled() {
            var candidate = puzzle.grid[peer]
            for attr in FigureAttribute.allCases.filter({ !focus.contains($0) }) {
                if Bool.random() { candidate.setValue(answer.value(for: attr), for: attr) }
            }
            add(candidate)
        }

        for attr in focus.shuffled() {
            for delta in 1..<attr.domainCount {
                var candidate = answer
                candidate.setValue(answer.value(for: attr) + delta, for: attr)
                add(candidate)
            }
        }

        var guardCount = 0
        while distractors.count < 3 && guardCount < 240 {
            guardCount += 1
            var candidate = answer
            let changedAttrs = FigureAttribute.allCases.shuffled().prefix(Int.random(in: 1...3))
            for attr in changedAttrs {
                candidate.setValue(Int.random(in: 0..<attr.domainCount), for: attr)
            }
            add(candidate)
        }

        return (distractors + [answer]).shuffled()
    }

    private func buildGrid(_ figure: (Int, Int) -> Figure) -> [Figure] {
        var built: [Figure] = []
        for r in 0..<3 {
            for c in 0..<3 {
                built.append(figure(r, c))
            }
        }
        return built
    }

    private func randomFigure() -> Figure {
        Figure(
            shape: Int.random(in: 0..<Self.shapes.count),
            count: Int.random(in: 1...3),
            filled: Bool.random(),
            tint: Int.random(in: 0..<Self.figureColors.count),
            size: Int.random(in: 0..<3)
        )
    }

    private func combine(_ first: Int, _ second: Int, attr: FigureAttribute) -> Int {
        let domain = attr.latinDomainCount
        return (first + second) % domain
    }

    // MARK: Scoring

    private func pick(_ opt: Figure) {
        guard picked == nil else { return }
        let elapsedMs = Date().timeIntervalSince(puzzleStartedAt) * 1_000
        responseTimesMs.append(elapsedMs)
        picked = opt

        if opt == answer {
            streak += 1
            correct += 1
            let points = pointsForCorrect(elapsedMs: elapsedMs, streak: streak)
            score += points
            cfg.report(.hit, points: points, combo: streak)
        } else {
            streak = 0
            cfg.report(.miss)
        }

        generation += 1
        let gen = generation
        Task {
            try? await Task.sleep(for: .milliseconds(cfg.isSurvival ? 500 : 800))
            guard gen == generation else { return }
            if !cfg.isSurvival && puzzle >= Self.total {
                finish()
            } else {
                puzzle += 1
                newPuzzle()
            }
        }
    }

    private func pointsForCorrect(elapsedMs: Double, streak: Int) -> Int {
        let base = 80 + currentTier * 45
        let parMs = [0.0, 6_000, 8_000, 10_500, 13_500, 16_500][currentTier]
        let speedMultiplier = max(0.55, min(1.35, parMs / max(1_000, elapsedMs)))
        let streakBonus = min(75, max(0, (streak - 1) * 10))
        let raw = Double(base) * speedMultiplier + Double(streakBonus)
        return max(25, Int((raw / 5).rounded()) * 5)
    }

    private func finish() {
        let acc = Double(correct) / Double(Self.total)
        let median = median(responseTimesMs).map { Int($0.rounded()) }
        var r = GameResult(game: .ruleFinder, score: score, accuracy: acc)
        r.trials = Self.total
        r.threshold = Double(maxTier)
        r.medianRTms = median
        r.startedAt = runStartedAt
        r.durationMs = Int(Date().timeIntervalSince(runStartedAt) * 1_000)
        r.raw = [
            "complexity": Double(maxTier),
            "avgTier": Double(tierTotal) / Double(max(1, Self.total)),
            "correct": Double(correct)
        ]
        if let median { r.raw["medianRTms"] = Double(median) }
        r.text = ["templates": templatesSeen]
        onResult(r)
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
