//
//  RuleFinder.swift
//  wits
//
//  Matrix reasoning (Raven's-style) — find the rule across the grid and pick the
//  missing cell. Targets fluid reasoning. Adaptive: complexity = how many
//  attributes vary at once (shape / count / fill). Untimed per puzzle.
//
//  Framed as a fun puzzle, not an IQ test: matrix reasoning is a *measure* of
//  reasoning, so we never claim solving these raises intelligence.
//

import SwiftUI

private struct Figure: Equatable {
    var shape: Int     // index into shapes
    var count: Int     // 1...3
    var filled: Bool
}

private enum Axis { case constant, byRow, byCol }

struct RuleFinderScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private static let shapes = ["circle", "square", "triangle", "diamond"]
    private static let total = 8

    private let complexity: Int
    @State private var grid: [Figure] = []      // 9 cells, [8] is the answer (hidden)
    @State private var options: [Figure] = []
    @State private var answer = Figure(shape: 0, count: 1, filled: true)
    @State private var picked: Figure?
    @State private var puzzle = 1
    @State private var correct = 0
    @State private var score = 0
    @State private var generation = 0
    @State private var started = false
    private let startedAt = Date()

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        self.complexity = max(1, min(3, 1 + Int(cfg.difficulty.level / 3.5)))
    }

    var body: some View {
        VStack(spacing: 12) {
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

            matrix
            Text("which figure completes the grid?")
                .font(.witsBody(13))
                .foregroundStyle(Color.witsFaint)
            optionGrid
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .onAppear { if !started { started = true; newPuzzle() } }
    }

    private var matrix: some View {
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(0..<9, id: \.self) { i in
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.witsTint)
                    if i == 8 {
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
        HStack(spacing: 3) {
            ForEach(0..<f.count, id: \.self) { _ in
                Image(systemName: Self.shapes[f.shape] + (f.filled ? ".fill" : ""))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.witsInk)
            }
        }
    }

    // MARK: Generation

    private func newPuzzle() {
        // choose which attributes vary (complexity of them), each on a random axis
        var axes: [String: Axis] = ["shape": .constant, "count": .constant, "fill": .constant]
        let varying = ["shape", "count", "fill"].shuffled().prefix(complexity)
        for key in varying { axes[key] = Bool.random() ? .byRow : .byCol }

        let baseShape = Int.random(in: 0..<Self.shapes.count)
        let baseCount = Int.random(in: 1...3)
        let baseFill = Bool.random()

        func cell(_ r: Int, _ c: Int) -> Figure {
            let shape: Int
            switch axes["shape"]! {
            case .byRow: shape = (baseShape + r) % Self.shapes.count
            case .byCol: shape = (baseShape + c) % Self.shapes.count
            case .constant: shape = baseShape
            }
            let count: Int
            switch axes["count"]! {
            case .byRow: count = 1 + r
            case .byCol: count = 1 + c
            case .constant: count = baseCount
            }
            let filled: Bool
            switch axes["fill"]! {
            case .byRow: filled = r % 2 == 0
            case .byCol: filled = c % 2 == 0
            case .constant: filled = baseFill
            }
            return Figure(shape: shape, count: count, filled: filled)
        }

        var g: [Figure] = []
        for r in 0..<3 { for c in 0..<3 { g.append(cell(r, c)) } }
        grid = g
        answer = g[8]

        // distractors: mutate one attribute at a time, keep unique
        var opts: Set<[Int]> = [encode(answer)]
        var distractors: [Figure] = []
        var guard0 = 0
        while distractors.count < 3 && guard0 < 50 {
            guard0 += 1
            var d = answer
            switch Int.random(in: 0..<3) {
            case 0: d.shape = (d.shape + Int.random(in: 1..<Self.shapes.count)) % Self.shapes.count
            case 1: d.count = max(1, min(3, d.count + (Bool.random() ? 1 : -1)))
            default: d.filled.toggle()
            }
            if !opts.contains(encode(d)) {
                opts.insert(encode(d))
                distractors.append(d)
            }
        }
        // pad if needed (rare)
        while distractors.count < 3 {
            var d = answer; d.count = max(1, min(3, (d.count % 3) + 1))
            if !opts.contains(encode(d)) { opts.insert(encode(d)); distractors.append(d) }
            else { d.filled.toggle(); distractors.append(d) }
        }
        options = (distractors + [answer]).shuffled()
        picked = nil
    }

    private func encode(_ f: Figure) -> [Int] { [f.shape, f.count, f.filled ? 1 : 0] }

    private func pick(_ opt: Figure) {
        guard picked == nil else { return }
        picked = opt
        if opt == answer { correct += 1; score += 150 }
        generation += 1
        let gen = generation
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard gen == generation else { return }
            if puzzle >= Self.total {
                finish()
            } else {
                puzzle += 1
                newPuzzle()
            }
        }
    }

    private func finish() {
        let acc = Double(correct) / Double(Self.total)
        var r = GameResult(game: .ruleFinder, score: score, accuracy: acc)
        r.trials = Self.total
        r.threshold = Double(complexity)
        r.startedAt = startedAt
        r.raw = ["complexity": Double(complexity)]
        onResult(r)
    }
}
