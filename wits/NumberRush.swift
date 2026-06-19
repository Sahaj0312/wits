//
//  NumberRush.swift
//  wits
//
//  Arithmetic under time pressure. Type each answer on the keypad before its
//  deadline — no multiple choice, so there's nothing to guess. Adaptive: the
//  per-question window tightens and operands grow with level.
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
    }

    @State private var problem: Problem
    @State private var entry = ""
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
        _window = State(initialValue: max(2.5, 6.0 - cfg.difficulty.level * 0.3))
        _problem = State(initialValue: Self.make(level: cfg.difficulty.level))
    }

    private var multiplier: Int { min(5, 1 + streak / 3) }

    private static func make(level: Double) -> Problem {
        let lvl = Int(level)

        // higher levels mix in two-operator expressions (with proper precedence)
        if level >= 5, Double.random(in: 0..<1) < 0.45 {
            let a = Int.random(in: 2...(4 + lvl))
            let b = Int.random(in: 2...(3 + lvl / 2))
            let c = Int.random(in: 2...(6 + lvl))
            return Bool.random()
                ? Problem(text: "\(a) × \(b) + \(c)", answer: a * b + c)
                : Problem(text: "\(c) + \(a) × \(b)", answer: c + a * b)
        }

        let ops = level < 2 ? ["+", "−"] : level < 5 ? ["+", "−", "×"] : ["+", "−", "×", "÷"]
        let op = ops.randomElement()!
        let cap = 8 + lvl * 3
        switch op {
        case "−":
            var a = Int.random(in: 2...cap), b = Int.random(in: 1...cap)
            if b > a { swap(&a, &b) }
            return Problem(text: "\(a) − \(b)", answer: a - b)
        case "×":
            let a = Int.random(in: 2...(4 + lvl)), b = Int.random(in: 2...(4 + lvl))
            return Problem(text: "\(a) × \(b)", answer: a * b)
        case "÷":
            let d = Int.random(in: 2...9), q = Int.random(in: 2...(3 + lvl))
            return Problem(text: "\(d * q) ÷ \(d)", answer: q)   // clean integer division
        default:
            let a = Int.random(in: 2...cap), b = Int.random(in: 2...cap)
            return Problem(text: "\(a) + \(b)", answer: a + b)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            if !cfg.isSurvival {
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
            }

            Spacer()

            VStack(spacing: 10) {
                // equation + the answer the player is typing, on one card
                HStack(spacing: 12) {
                    Text("\(problem.text) =")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                    Text(entry.isEmpty ? "?" : entry)
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(entry.isEmpty ? Color.witsFaint : Color.witsAccent)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity).frame(height: 130)
                .cardSurface()
                .id(problem.id)
                .transition(.scale(scale: 0.94).combined(with: .opacity))
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
                .frame(width: 130, height: 4).padding(.top, 6)
            }

            Spacer()

            keypad
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 24).padding(.bottom, 12)
        .task { await run() }
    }

    private var keypad: some View {
        let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["⌫", "0", "✓"]]
        return VStack(spacing: 10) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { key in keyButton(key) }
                }
            }
        }
    }

    private func keyButton(_ key: String) -> some View {
        let isSubmit = key == "✓"
        let isBack = key == "⌫"
        return Button { press(key) } label: {
            Group {
                if isSubmit {
                    Image(systemName: "checkmark").font(.system(size: 22, weight: .heavy))
                } else if isBack {
                    Image(systemName: "delete.left.fill").font(.system(size: 20, weight: .heavy))
                } else {
                    Text(key).font(.system(size: 26, weight: .heavy, design: .rounded))
                }
            }
            .foregroundStyle(isSubmit ? .white : Color.witsInk)
            .frame(maxWidth: .infinity).frame(height: 58)
            .background(isSubmit ? Color.witsAccent : Color.witsTint,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func press(_ key: String) {
        guard !finished else { return }
        switch key {
        case "⌫": if !entry.isEmpty { entry.removeLast() }
        case "✓": commit()
        default:
            guard entry.count < 4 else { return }
            entry += key
            // auto-advance the moment the typed value is correct
            if Int(entry) == problem.answer { resolve(correct: true) }
        }
    }

    private func commit() {
        guard let v = Int(entry) else { return }
        resolve(correct: v == problem.answer)
    }

    private func resolve(correct ok: Bool) {
        guard !finished else { return }
        if ok {
            right += 1; streak += 1; bestStreak = max(bestStreak, streak)
            score += 100 * multiplier
            window = max(cfg.isSurvival ? 1.6 : 2.0, window - (cfg.isSurvival ? 0.08 : 0.05))
            cfg.report(.hit, points: 100, combo: streak)
        } else {
            wrong += 1; streak = 0
            window = min(6.0, window + 0.3)
            cfg.report(.miss)
        }
        feedback = ok
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { feedback = nil }
        next()
    }

    private func timeout() {
        guard !finished else { return }
        wrong += 1; streak = 0
        window = min(6.0, window + 0.3)
        feedback = false
        cfg.report(.timeout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { feedback = nil }
        next()
    }

    private func next() {
        entry = ""
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
            if !cfg.isSurvival && timeLeft <= 0 {
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
