//
//  NumberRush.swift
//  wits
//
//  Running arithmetic under time pressure. Each round reveals a starting value
//  and then operations one by one; the player keeps the running total in mind
//  and types the final answer when prompted.
//

import SwiftUI

enum NumberRushTuning {
    struct Settings {
        let operationCount: Int
        let startRange: ClosedRange<Int>
        let addRange: ClosedRange<Int>
        let multiplyRange: ClosedRange<Int>
        let divideRange: ClosedRange<Int>
        let revealInterval: Double
        let answerWindow: Double
        let minimumAnswerWindow: Double
        let maximumAnswerWindow: Double
        let maxResult: Int
        let allowsMultiply: Bool
        let allowsDivide: Bool
    }

    static func settings(for level: Double) -> Settings {
        let clamped = min(10, max(1, level.isFinite ? level : 1))
        let lvl = Int(clamped.rounded(.down))
        let operationCount = operationCount(for: clamped)
        let answerWindow = max(3.1, 5.4 - clamped * 0.24)

        return Settings(
            operationCount: operationCount,
            startRange: 2...max(6, 8 + lvl * 3),
            addRange: 1...max(4, 5 + lvl * 2),
            multiplyRange: 2...max(2, min(7, 2 + lvl / 2)),
            divideRange: 2...max(2, min(9, 2 + lvl / 2)),
            revealInterval: max(0.62, 1.04 - clamped * 0.04),
            answerWindow: answerWindow,
            minimumAnswerWindow: max(2.2, answerWindow - 1.0),
            maximumAnswerWindow: answerWindow + 1.25,
            maxResult: 90 + lvl * 55,
            allowsMultiply: clamped >= 3,
            allowsDivide: clamped >= 6
        )
    }

    static func operationCount(for level: Double) -> Int {
        switch min(10, max(1, level.isFinite ? level : 1)) {
        case ..<2: 1
        case ..<4: 2
        case ..<6: 3
        case ..<8: 4
        case ..<10: 5
        default: 6
        }
    }

    static func targetCorrectPerSecond(for level: Double) -> Double {
        let settings = settings(for: level)
        let revealSeconds = Double(settings.operationCount + 1) * settings.revealInterval
        let solveSeconds = max(1.4, settings.answerWindow * 0.45)
        let expectedRoundSeconds = revealSeconds + solveSeconds
        return min(0.22, max(0.08, 0.78 / expectedRoundSeconds))
    }
}

struct NumberRushScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private static let gameSeconds = 45.0

    private enum Phase: String {
        case revealing
        case answering
    }

    private struct Operation: Identifiable {
        let id = UUID()
        let symbol: String
        let operand: Int
        let result: Int

        var text: String { "\(symbol) \(operand)" }
    }

    private struct Round: Identifiable {
        let id = UUID()
        let start: Int
        let operations: [Operation]
        let answer: Int
    }

    private struct Candidate {
        let symbol: String
        let operand: Int
        let result: Int
    }

    @State private var round: Round
    @State private var phase = Phase.revealing
    @State private var revealIndex = 0
    @State private var revealStartedAt = Date()
    @State private var entry = ""
    @State private var answerWindow: Double
    @State private var answerWindowFrac = 1.0
    @State private var answerStartedAt = Date()
    @State private var timeLeft = gameSeconds
    @State private var right = 0
    @State private var wrong = 0
    @State private var streak = 0
    @State private var bestStreak = 0
    @State private var bestOperations = 0
    @State private var score = 0
    @State private var feedback: Bool?
    @State private var finished = false
    private let startedAt = Date()
    private let level: Double
    private let tuning: NumberRushTuning.Settings

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        let tuning = NumberRushTuning.settings(for: cfg.difficulty.level)
        self.cfg = cfg
        self.onResult = onResult
        self.level = cfg.difficulty.level
        self.tuning = tuning
        _answerWindow = State(initialValue: tuning.answerWindow)
        _round = State(initialValue: Self.make(level: cfg.difficulty.level))
    }

    private var multiplier: Int { min(5, 1 + streak / 3) }

    private var currentPrompt: String {
        if phase == .answering { return entry.isEmpty ? "?" : entry }
        guard revealIndex > 0 else { return "\(round.start)" }
        return round.operations[min(revealIndex - 1, round.operations.count - 1)].text
    }

    private static func make(level: Double) -> Round {
        let settings = NumberRushTuning.settings(for: level)

        for _ in 0..<120 {
            let start = Int.random(in: settings.startRange)
            var current = start
            var operations: [Operation] = []
            var previousSymbol: String?

            for _ in 0..<settings.operationCount {
                guard let next = candidate(from: current, settings: settings, previousSymbol: previousSymbol) else {
                    break
                }
                operations.append(Operation(symbol: next.symbol, operand: next.operand, result: next.result))
                current = next.result
                previousSymbol = next.symbol
            }

            if operations.count == settings.operationCount, current > 0, current <= settings.maxResult {
                return Round(start: start, operations: operations, answer: current)
            }
        }

        return fallbackRound(settings: settings)
    }

    private static func candidate(from value: Int,
                                  settings: NumberRushTuning.Settings,
                                  previousSymbol: String?) -> Candidate? {
        var candidates: [Candidate] = []

        let addMax = min(settings.addRange.upperBound, settings.maxResult - value)
        if addMax >= settings.addRange.lowerBound {
            let amount = Int.random(in: settings.addRange.lowerBound...addMax)
            let plus = Candidate(symbol: "+", operand: amount, result: value + amount)
            candidates.append(plus)
            candidates.append(plus)
        }

        let subMax = min(settings.addRange.upperBound, value - 1)
        if subMax >= settings.addRange.lowerBound {
            let amount = Int.random(in: settings.addRange.lowerBound...subMax)
            let minus = Candidate(symbol: "−", operand: amount, result: value - amount)
            candidates.append(minus)
            if previousSymbol != "−" { candidates.append(minus) }
        }

        if settings.allowsMultiply {
            let factorMax = min(settings.multiplyRange.upperBound, settings.maxResult / max(1, value))
            if factorMax >= settings.multiplyRange.lowerBound {
                let factor = Int.random(in: settings.multiplyRange.lowerBound...factorMax)
                let multiply = Candidate(symbol: "×", operand: factor, result: value * factor)
                candidates.append(multiply)
                if settings.operationCount >= 4 { candidates.append(multiply) }
            }
        }

        if settings.allowsDivide {
            let divisors = settings.divideRange.filter { value % $0 == 0 && value / $0 > 0 }
            if let divisor = divisors.randomElement() {
                candidates.append(Candidate(symbol: "÷", operand: divisor, result: value / divisor))
            }
        }

        return candidates.randomElement()
    }

    private static func fallbackRound(settings: NumberRushTuning.Settings) -> Round {
        let start = Int.random(in: 3...9)
        var current = start
        var operations: [Operation] = []

        for _ in 0..<settings.operationCount {
            let amount = Int.random(in: 1...min(9, settings.addRange.upperBound))
            current += amount
            operations.append(Operation(symbol: "+", operand: amount, result: current))
        }

        return Round(start: start, operations: operations, answer: current)
    }

    var body: some View {
        VStack(spacing: 12) {
            if !cfg.isSurvival {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(score) pts")
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

            VStack(spacing: 14) {
                promptCard
                    .id("\(round.id)-\(phase.rawValue)-\(revealIndex)")
                    .transition(.scale(scale: 0.94).combined(with: .opacity))

                answerProgress
            }

            Spacer()

            keypad
                .opacity(phase == .answering ? 1 : 0.45)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 24).padding(.bottom, 12)
        .task { await run() }
    }

    private var promptCard: some View {
        HStack(spacing: phase == .answering ? 12 : 0) {
            if phase == .answering {
                Text("total =")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Text(currentPrompt)
                .font(.system(size: phase == .answering ? 44 : 52, weight: .heavy, design: .rounded))
                .foregroundStyle(entry.isEmpty && phase == .answering ? Color.witsFaint : Color.witsAccent)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 142)
        .cardSurface()
        .overlay(
            RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                .strokeBorder(feedback == true ? Color.witsAccent : feedback == false ? Color.witsWarm : .clear, lineWidth: 2.5)
                .padding(-14)
        )
    }

    private var answerProgress: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.witsLine)
            GeometryReader { geo in
                Capsule()
                    .fill(answerWindowFrac < 0.35 && phase == .answering ? Color.witsWarm : Color.witsMuted)
                    .frame(width: max(0, geo.size.width * (phase == .answering ? answerWindowFrac : 1)))
            }
        }
        .frame(width: 132, height: 4)
        .opacity(phase == .answering ? 1 : 0.24)
        .padding(.top, 4)
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
        let canAnswer = phase == .answering && !finished
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
            .background(isSubmit ? Color.witsAccent.opacity(canAnswer ? 1 : 0.45) : Color.witsTint,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canAnswer)
    }

    private func press(_ key: String) {
        guard !finished, phase == .answering else { return }
        switch key {
        case "⌫":
            if !entry.isEmpty { entry.removeLast() }
        case "✓":
            commit()
        default:
            guard entry.count < 5 else { return }
            entry += key
            if Int(entry) == round.answer { resolve(correct: true) }
        }
    }

    private func commit() {
        guard let value = Int(entry) else { return }
        resolve(correct: value == round.answer)
    }

    private func resolve(correct ok: Bool) {
        guard !finished, phase == .answering else { return }
        if ok {
            let points = 75 + round.operations.count * 25 + Int(max(0, answerWindowFrac) * 50)
            right += 1
            streak += 1
            bestStreak = max(bestStreak, streak)
            bestOperations = max(bestOperations, round.operations.count)
            score += points * multiplier
            answerWindow = max(tuning.minimumAnswerWindow, answerWindow - 0.06)
            cfg.report(.hit, points: points, combo: streak)
        } else {
            wrong += 1
            streak = 0
            answerWindow = min(tuning.maximumAnswerWindow, answerWindow + 0.35)
            cfg.report(.miss)
        }
        feedback = ok
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { feedback = nil }
        next()
    }

    private func timeout() {
        guard !finished, phase == .answering else { return }
        wrong += 1
        streak = 0
        answerWindow = min(tuning.maximumAnswerWindow, answerWindow + 0.35)
        feedback = false
        cfg.report(.timeout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { feedback = nil }
        next()
    }

    private func next() {
        entry = ""
        withAnimation(.easeOut(duration: 0.13)) {
            round = Self.make(level: level)
            phase = .revealing
            revealIndex = 0
        }
        revealStartedAt = Date()
        answerStartedAt = Date()
        answerWindowFrac = 1
    }

    private func advanceReveal() {
        guard phase == .revealing else { return }
        if revealIndex < round.operations.count {
            withAnimation(.easeOut(duration: 0.13)) { revealIndex += 1 }
            revealStartedAt = Date()
        } else {
            withAnimation(.easeOut(duration: 0.13)) { phase = .answering }
            entry = ""
            answerStartedAt = Date()
            answerWindowFrac = 1
        }
    }

    private func run() async {
        let start = Date()
        revealStartedAt = start

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(30))
            guard !finished else { return }

            timeLeft = max(0, Self.gameSeconds - cfg.activeElapsed(since: start))

            switch phase {
            case .revealing:
                let elapsed = cfg.activeElapsed(since: revealStartedAt)
                if elapsed >= tuning.revealInterval { advanceReveal() }
            case .answering:
                let elapsed = cfg.activeElapsed(since: answerStartedAt)
                answerWindowFrac = max(0, 1 - elapsed / answerWindow)
                if elapsed > answerWindow { timeout() }
            }

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
        let accuracy = total > 0 ? Double(right) / Double(total) : 0
        var result = GameResult(game: .numberRush, score: score, accuracy: accuracy)
        result.trials = total
        result.startedAt = startedAt
        result.durationMs = Int(Self.gameSeconds * 1000)
        result.raw = [
            "bestStreak": Double(bestStreak),
            "bestOperations": Double(bestOperations),
            "correct": Double(right),
            "wrong": Double(wrong),
            "operationsPerRound": Double(tuning.operationCount),
            "answerWindowMs": answerWindow * 1000,
            "timeOnTaskMs": Self.gameSeconds * 1000
        ]
        onResult(result)
    }
}
