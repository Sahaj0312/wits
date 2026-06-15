//
//  Estimator.swift
//  wits  ("snap count")
//
//  Numerical estimation. Two groups of dots flash; pick the bigger before you
//  can count. Adaptive: the flash gets shorter and the two counts get closer.
//

import SwiftUI

struct EstimatorScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private static let totalTrials = 16
    private enum Step { case show, answer, feedback }

    @State private var step: Step = .show
    @State private var leftDots: [CGPoint] = []
    @State private var rightDots: [CGPoint] = []
    @State private var leftBigger = true
    @State private var trial = 1
    @State private var right = 0
    @State private var wrong = 0
    @State private var streak = 0
    @State private var bestStreak = 0
    @State private var score = 0
    @State private var lastCorrect: Bool?
    @State private var generation = 0
    @State private var started = false
    private let startedAt = Date()
    private let level: Double

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        self.level = cfg.difficulty.level
    }

    private var flashMs: Int { max(350, 1200 - Int(level * 70)) }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("round \(Text("\(min(trial, Self.totalTrials))").foregroundStyle(Color.witsAccent)) of \(Self.totalTrials)")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsInk).monospacedDigit()
                Spacer()
                Text("\(score) pts")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsMuted).monospacedDigit()
            }
            ProgressTrack(fraction: Double(trial - 1) / Double(Self.totalTrials), animated: true)
            Spacer()
            HStack(spacing: 12) {
                panel(dots: leftDots, side: false)
                panel(dots: rightDots, side: true)
            }
            Text(statusText)
                .font(.witsBody(13))
                .foregroundStyle(step == .feedback && lastCorrect == false ? Color.witsWarm : Color.witsFaint)
                .frame(maxWidth: .infinity).frame(height: 30)
            Spacer()
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 24).padding(.bottom, 12)
        .onAppear { if !started { started = true; newTrial() } }
    }

    private var statusText: String {
        switch step {
        case .show: "which side has more?"
        case .answer: "tap the side with more dots"
        case .feedback: lastCorrect == true ? "right!" : "not quite"
        }
    }

    private func panel(dots: [CGPoint], side: Bool) -> some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                    .fill(Color.witsCard)
                    .shadow(color: .witsShadow, radius: 8, y: 4)
                if step == .show {
                    ForEach(Array(dots.enumerated()), id: \.offset) { _, p in
                        Circle().fill(Color.witsAccent)
                            .frame(width: 12, height: 12)
                            .position(x: p.x * geo.size.width, y: p.y * geo.size.height)
                    }
                } else if step == .feedback {
                    let isBig = side == leftBigger
                    Image(systemName: isBig ? "checkmark" : "")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(Color.witsAccent)
                } else {
                    Image(systemName: "questionmark")
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(Color.witsFaint)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { pick(side) }
        }
    }

    private func newTrial() {
        generation += 1
        let gen = generation
        let big = Int.random(in: 12...(12 + Int(level * 3) + 6))
        let ratio = max(1.12, 1.7 - level * 0.06)
        let small = max(6, Int(Double(big) / ratio))
        leftBigger = Bool.random()
        let lCount = leftBigger ? big : small
        let rCount = leftBigger ? small : big
        leftDots = Self.scatter(lCount)
        rightDots = Self.scatter(rCount)
        step = .show
        lastCorrect = nil
        Task {
            try? await Task.sleep(for: .milliseconds(flashMs))
            guard gen == generation else { return }
            step = .answer
        }
    }

    private static func scatter(_ n: Int) -> [CGPoint] {
        (0..<n).map { _ in CGPoint(x: Double.random(in: 0.12...0.88), y: Double.random(in: 0.12...0.88)) }
    }

    private func pick(_ side: Bool) {
        guard step == .answer else { return }
        let ok = side == leftBigger
        lastCorrect = ok
        if ok { right += 1; streak += 1; bestStreak = max(bestStreak, streak); score += 100 * min(5, 1 + streak / 3) }
        else { wrong += 1; streak = 0 }
        step = .feedback
        let gen = generation
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard gen == generation else { return }
            if trial >= Self.totalTrials { finish() } else { trial += 1; newTrial() }
        }
    }

    private func finish() {
        let total = right + wrong
        let acc = total > 0 ? Double(right) / Double(total) : 0
        var r = GameResult(game: .estimator, score: score, accuracy: acc)
        r.trials = total
        r.startedAt = startedAt
        r.raw = ["bestStreak": Double(bestStreak)]
        onResult(r)
    }
}
