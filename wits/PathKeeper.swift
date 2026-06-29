//
//  PathKeeper.swift
//  wits
//
//  Working memory. A token hops a path across the grid; repeat it in the same
//  order. Perfect rounds lengthen the path; a slip shortens it. (Forward recall,
//  unlike Echo Grid's reverse span.)
//

import SwiftUI

struct PathKeeperScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private static let totalTrials = 8
    private static let rows = 4
    private static let cols = 4

    private enum Phase { case show, recall, reveal }

    @State private var phase: Phase = .show
    @State private var seq: [Int] = []
    @State private var litIndex: Int?
    @State private var tapIndex = 0
    @State private var rightTaps: Set<Int> = []
    @State private var wrongTap: Int?
    @State private var len: Int
    @State private var trial = 1
    @State private var correctTaps = 0
    @State private var totalTaps = 0
    @State private var perfect = 0
    @State private var maxLen = 0
    @State private var score = 0
    @State private var failed = false
    @State private var generation = 0
    @State private var started = false
    private let startedAt = Date()

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        _len = State(initialValue: max(2, 2 + Int(cfg.difficulty.level / 2)))
    }

    private var cells: Int { Self.rows * Self.cols }

    var body: some View {
        VStack(spacing: 12) {
            if !cfg.isSurvival {
                HStack(alignment: .firstTextBaseline) {
                    Text("hop \(Text("\(min(trial, Self.totalTrials))").foregroundStyle(Color.witsAccent)) of \(Self.totalTrials)")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsInk).monospacedDigit()
                    Spacer()
                    Text("\(score) pts")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsMuted).monospacedDigit()
                }
                ProgressTrack(fraction: Double(trial - 1) / Double(Self.totalTrials), animated: true)
            }
            Spacer()
            GeometryReader { geo in
                let gap: CGFloat = 10
                let side = (min(geo.size.width, geo.size.height) - gap * CGFloat(Self.cols - 1)) / CGFloat(Self.cols)
                let grid = Array(repeating: GridItem(.fixed(side), spacing: gap), count: Self.cols)
                LazyVGrid(columns: grid, spacing: gap) {
                    ForEach(0..<cells, id: \.self) { i in
                        cell(i, side: side)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            }
            Text(statusText)
                .font(.witsBody(12.5)).foregroundStyle(Color.witsFaint)
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 24).padding(.bottom, 12)
        .onAppear { if !started { started = true; startTrial() } }
    }

    private var statusText: String {
        switch phase {
        case .show: "watch the path"
        case .recall: "repeat it — \(seq.count - tapIndex) to go"
        case .reveal: failed ? "not quite — path shrinks" : "perfect — path grows"
        }
    }

    private func cell(_ i: Int, side: CGFloat) -> some View {
        let isLit = phase == .show && litIndex.map { seq[$0] == i } ?? false
        let isRight = rightTaps.contains(i)
        let isWrong = wrongTap == i
        let order = phase == .reveal && failed ? seq.firstIndex(of: i).map { $0 + 1 } : nil
        let fill: Color = isLit ? .witsAccent
            : isRight ? Color.witsAccent.opacity(0.85)
            : isWrong ? Color.witsWarm.opacity(0.75)
            : order != nil ? Color.witsAccent.opacity(0.3)
            : .witsTint
        return RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(fill)
            .frame(width: side, height: side)
            .overlay {
                if let order {
                    Text("\(order)").font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Color.witsInk)
                }
            }
            .animation(.easeOut(duration: 0.12), value: isLit)
            .animation(.easeOut(duration: 0.12), value: isRight)
            .onTapGesture { tap(i) }
    }

    private func startTrial() {
        generation += 1
        let gen = generation
        var cellsSet: [Int] = []
        var last = Int.random(in: 0..<cells)
        cellsSet.append(last)
        // build a path of distinct cells, preferring nearby hops
        while cellsSet.count < len {
            let next = Int.random(in: 0..<cells)
            if !cellsSet.contains(next) { cellsSet.append(next); last = next }
            if cellsSet.count > cells { break }
        }
        seq = cellsSet
        litIndex = nil; tapIndex = 0; rightTaps = []; wrongTap = nil; failed = false
        phase = .show
        Task {
            await cfg.sleepActive(milliseconds: 500)
            for i in seq.indices {
                guard gen == generation else { return }
                litIndex = i
                await cfg.sleepActive(milliseconds: 520)
                guard gen == generation else { return }
                litIndex = nil
                await cfg.sleepActive(milliseconds: 150)
            }
            guard gen == generation else { return }
            phase = .recall
        }
    }

    private func tap(_ i: Int) {
        guard phase == .recall else { return }
        let expected = seq[tapIndex]
        if i == expected {
            rightTaps.insert(i)
            tapIndex += 1
            correctTaps += 1; score += 110
            cfg.report(.hit, points: 110, combo: tapIndex)
            if tapIndex == seq.count { endTrial(perfect: true) }
        } else {
            wrongTap = i
            cfg.report(.miss)
            endTrial(perfect: false)
        }
    }

    private func endTrial(perfect ok: Bool) {
        failed = !ok
        totalTaps += seq.count
        if ok { perfect += 1; maxLen = max(maxLen, seq.count); score += 250 }
        phase = .reveal
        let gen = generation
        Task {
            await cfg.sleepActive(milliseconds: ok ? 800 : 1500)
            guard gen == generation else { return }
            len = ok ? min(9, len + 1) : max(2, len - 1)
            if !cfg.isSurvival && trial >= Self.totalTrials { finish() } else { trial += 1; startTrial() }
        }
    }

    private func finish() {
        let acc = totalTaps > 0 ? Double(correctTaps) / Double(totalTaps) : 0
        var r = GameResult(game: .pathKeeper, score: score, accuracy: acc)
        r.trials = Self.totalTrials
        r.startedAt = startedAt
        r.durationMs = Int(cfg.activeElapsed(since: startedAt) * 1000)
        r.raw = [
            "maxLen": Double(maxLen),
            "perfect": Double(perfect),
            "correct": Double(correctTaps),
            "wrong": Double(max(0, totalTaps - correctTaps)),
            "timeOnTaskMs": Double(r.durationMs)
        ]
        onResult(r)
    }
}
