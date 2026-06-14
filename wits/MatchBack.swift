//
//  MatchBack.swift
//  wits
//
//  N-back — a working-memory classic. A cell lights up each beat; tap MATCH when
//  the current cell is the same as the one n steps back. Adaptive: n rises with
//  level (1-back → 2-back → 3-back).
//

import SwiftUI

struct MatchBackScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private static let cells = 9          // 3x3
    private let n: Int
    private let total: Int
    private let stimMs = 750
    private let gapMs = 450

    @State private var seq: [Int] = []
    @State private var pos = -1
    @State private var lit: Int?
    @State private var responded = false
    @State private var tapFlash = false
    @State private var hits = 0
    @State private var misses = 0
    @State private var falseAlarms = 0
    @State private var correctRej = 0
    @State private var score = 0
    @State private var streak = 0
    @State private var generation = 0
    @State private var started = false
    private let startedAt = Date()

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        let level = cfg.difficulty.level
        self.n = max(1, min(3, 1 + Int(level / 3.5)))
        self.total = 18 + n
    }

    private var decisions: Int { hits + misses + falseAlarms + correctRej }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Text("\(n)-back").foregroundStyle(Color.witsAccent))")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                Spacer()
                Text("\(score) pts")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsMuted)
                    .monospacedDigit()
            }
            ProgressTrack(fraction: Double(max(0, pos)) / Double(total), animated: true)

            GeometryReader { geo in
                let gap: CGFloat = 10
                let s = (min(geo.size.width, geo.size.height) - gap * 2) / 3
                VStack(spacing: gap) {
                    ForEach(0..<3, id: \.self) { r in
                        HStack(spacing: gap) {
                            ForEach(0..<3, id: \.self) { c in
                                let idx = r * 3 + c
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(lit == idx ? Color.witsAccent : Color.witsTint)
                                    .frame(width: s, height: s)
                                    .animation(.easeOut(duration: 0.1), value: lit)
                            }
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .cardSurface()
            }

            Button { tapMatch() } label: {
                Text("match")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(tapFlash ? Color.witsAccent : Color.witsInk.opacity(0.85), in: Capsule())
                    .animation(.easeOut(duration: 0.12), value: tapFlash)
            }
            .buttonStyle(.plain)

            Text("tap when the square matches the one \(n) step\(n > 1 ? "s" : "") ago")
                .font(.witsBody(12.5))
                .foregroundStyle(Color.witsFaint)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .onAppear { if !started { started = true; run() } }
    }

    private func makeSequence() -> [Int] {
        var s: [Int] = []
        for i in 0..<total {
            if i >= n, Double.random(in: 0..<1) < 0.32 {
                s.append(s[i - n])                       // planned match
            } else if i >= n {
                let avoid = s[i - n]
                s.append((0..<Self.cells).filter { $0 != avoid }.randomElement()!)
            } else {
                s.append(Int.random(in: 0..<Self.cells))
            }
        }
        return s
    }

    private func run() {
        seq = makeSequence()
        generation += 1
        let gen = generation
        Task {
            for i in 0..<seq.count {
                guard gen == generation else { return }
                pos = i
                responded = false
                lit = seq[i]
                try? await Task.sleep(for: .milliseconds(stimMs))
                guard gen == generation else { return }
                lit = nil
                try? await Task.sleep(for: .milliseconds(gapMs))
                guard gen == generation else { return }
                evaluate(i)
            }
            finish()
        }
    }

    private func tapMatch() {
        guard started, pos >= 0, !responded else { return }
        responded = true
        tapFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { tapFlash = false }
    }

    private func evaluate(_ i: Int) {
        let isMatch = i >= n && seq[i] == seq[i - n]
        if responded {
            if isMatch { hits += 1; streak += 1; score += 120 * min(5, 1 + streak / 3) }
            else { falseAlarms += 1; streak = 0 }
        } else {
            if isMatch { misses += 1; streak = 0 }
            else { correctRej += 1; score += 20 }
        }
    }

    private func finish() {
        let acc = decisions > 0 ? Double(hits + correctRej) / Double(decisions) : 0
        var r = GameResult(game: .matchBack, score: score, accuracy: acc)
        r.trials = total
        r.threshold = Double(n)
        r.startedAt = startedAt
        r.raw = ["n": Double(n), "hits": Double(hits), "falseAlarms": Double(falseAlarms), "misses": Double(misses)]
        onResult(r)
    }
}
