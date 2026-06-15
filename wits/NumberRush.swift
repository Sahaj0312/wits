//
//  NumberRush.swift
//  wits
//
//  Arithmetic under time pressure. Solve each equation before its deadline.
//  Adaptive: the per-question window tightens and operands grow with level.
//

import SwiftUI

struct NumberRushScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private static let gameSeconds = 45.0

    private struct Problem: Identifiable {
        let id = UUID()
        let text: String
        let answer: Int
        let options: [Int]
    }

    @State private var problem: Problem
    @State private var window: Double
    @State private var windowFrac = 1.0
    @State private var trialStart = Date()
    @State private var timeLeft = gameSeconds
    @State private var right = 0
    @State private var wrong = 0
    @State private var streak = 0
    @State private var bestStreak = 0
    @State private var score = 0
    @State private var feedback: Bool?
    @State private var finished = false
    private let startedAt = Date()
    private let level: Double

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        self.level = cfg.difficulty.level
        _window = State(initialValue: max(2.0, 5.0 - cfg.difficulty.level * 0.3))
        _problem = State(initialValue: Self.make(level: cfg.difficulty.level))
    }

    private var multiplier: Int { min(5, 1 + streak / 3) }

    private static func make(level: Double) -> Problem {
        let cap = 6 + Int(level * 2)
        let ops = level < 3 ? ["+", "−"] : ["+", "−", "×"]
        let op = ops.randomElement()!
        var a = Int.random(in: 1...cap), b = Int.random(in: 1...cap)
        let answer: Int
        switch op {
        case "−": if b > a { swap(&a, &b) }; answer = a - b
        case "×": a = Int.random(in: 2...(3 + Int(level))); b = Int.random(in: 2...(3 + Int(level))); answer = a * b
        default: answer = a + b
        }
        var opts = Set<Int>()
        while opts.count < 3 {
            let d = answer + Int.random(in: -6...6)
            if d >= 0 && d != answer { opts.insert(d) }
        }
        opts.insert(answer)
        return Problem(text: "\(a) \(op) \(b)", answer: answer, options: Array(opts).shuffled())
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Text("\(score)").foregroundStyle(Color.witsAccent)) pts")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsInk).monospacedDigit()
                if multiplier > 1 {
                    Text("×\(multiplier)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsAccent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.witsAccent.opacity(0.14), in: Capsule())
                }
                Spacer()
                Text("\(Int(ceil(timeLeft)))s")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsMuted).monospacedDigit()
            }
            ProgressTrack(fraction: timeLeft / Self.gameSeconds, animated: false)
            Spacer()
            VStack(spacing: 6) {
                Text(problem.text)
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                    .frame(maxWidth: .infinity).frame(height: 140)
                    .cardSurface()
                    .id(problem.id)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                            .strokeBorder(feedback == true ? Color.witsAccent : feedback == false ? Color.witsWarm : .clear, lineWidth: 2.5)
                            .padding(-14)
                    )
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.witsLine)
                    GeometryReader { geo in
                        Capsule().fill(windowFrac < 0.35 ? Color.witsWarm : Color.witsMuted)
                            .frame(width: max(0, geo.size.width * windowFrac))
                    }
                }
                .frame(width: 130, height: 4).padding(.top, 14)
            }
            Spacer()
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(problem.options, id: \.self) { opt in
                    Button { answer(opt) } label: {
                        Text("\(opt)")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.witsInk)
                            .frame(maxWidth: .infinity).padding(.vertical, 18)
                            .background(Color.witsTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 24).padding(.bottom, 12)
        .task { await run() }
    }

    private func answer(_ choice: Int) {
        guard !finished else { return }
        let ok = choice == problem.answer
        if ok {
            right += 1; streak += 1; bestStreak = max(bestStreak, streak)
            score += 100 * multiplier
            window = max(1.6, window - 0.05)
        } else {
            wrong += 1; streak = 0
            window = min(5.0, window + 0.3)
        }
        feedback = ok
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { feedback = nil }
        next()
    }

    private func timeout() {
        guard !finished else { return }
        wrong += 1; streak = 0
        window = min(5.0, window + 0.3)
        feedback = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { feedback = nil }
        next()
    }

    private func next() {
        withAnimation(.easeOut(duration: 0.13)) { problem = Self.make(level: level) }
        trialStart = Date(); windowFrac = 1
    }

    private func run() async {
        let start = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(30))
            timeLeft = max(0, Self.gameSeconds - Date().timeIntervalSince(start))
            let elapsed = Date().timeIntervalSince(trialStart)
            windowFrac = max(0, 1 - elapsed / window)
            if elapsed > window { timeout() }
            if timeLeft <= 0 {
                guard !finished else { return }
                finished = true
                try? await Task.sleep(for: .milliseconds(350))
                finish()
                return
            }
        }
    }

    private func finish() {
        let total = right + wrong
        let acc = total > 0 ? Double(right) / Double(total) : 0
        var r = GameResult(game: .numberRush, score: score, accuracy: acc)
        r.trials = total
        r.startedAt = startedAt
        r.durationMs = Int(Self.gameSeconds * 1000)
        r.raw = ["bestStreak": Double(bestStreak)]
        onResult(r)
    }
}
