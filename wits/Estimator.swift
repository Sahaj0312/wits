//
//  Estimator.swift
//  wits  ("target forge")
//
//  Flexible arithmetic. Build an expression from one-use number tiles to hit a
//  target exactly, or get close under time pressure.
//

import SwiftUI

struct TargetForgeScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private static let gameSeconds = 45.0

    private enum ForgeOperator: String, CaseIterable, Hashable {
        case add = "+"
        case subtract = "-"
        case multiply = "x"
        case divide = "/"

        var display: String {
            switch self {
            case .add: "+"
            case .subtract: "−"
            case .multiply: "×"
            case .divide: "÷"
            }
        }
    }

    private struct NumberTile: Identifiable, Hashable {
        let id: Int
        let value: Int
    }

    private enum ExpressionToken: Equatable {
        case number(id: Int, value: Int)
        case op(ForgeOperator)
    }

    private struct ForgeRound: Identifiable {
        let id = UUID()
        let target: Int
        let tiles: [NumberTile]
        let allowedOps: [ForgeOperator]
        let minimumTerms: Int
        let solution: String
    }

    private enum Grade: Equatable {
        case exact
        case close
        case near
        case miss
    }

    private struct Feedback: Equatable {
        let grade: Grade
        let value: Double?
        let error: Double?

        var text: String {
            switch grade {
            case .exact:
                "exact"
            case .close:
                "close"
            case .near:
                "near"
            case .miss:
                if let value {
                    "miss: \(TargetForgeScreen.format(value))"
                } else {
                    "time"
                }
            }
        }

        var color: Color {
            switch grade {
            case .exact, .close: .witsAccent
            case .near, .miss: .witsWarm
            }
        }
    }

    @State private var round: ForgeRound
    @State private var tokens: [ExpressionToken] = []
    @State private var usedTileIDs: Set<Int> = []
    @State private var roundWindow: Double
    @State private var windowFrac = 1.0
    @State private var roundStart = Date()
    @State private var timeLeft = gameSeconds
    @State private var exact = 0
    @State private var close = 0
    @State private var near = 0
    @State private var wrong = 0
    @State private var streak = 0
    @State private var bestStreak = 0
    @State private var score = 0
    @State private var totalError = 0.0
    @State private var valuedAttempts = 0
    @State private var feedback: Feedback?
    @State private var resolving = false
    @State private var finished = false
    private let startedAt = Date()
    private let level: Double

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        self.level = cfg.difficulty.level
        _round = State(initialValue: Self.makeRound(level: cfg.difficulty.level))
        _roundWindow = State(initialValue: Self.initialWindow(level: cfg.difficulty.level))
    }

    private var multiplier: Int { min(5, 1 + streak / 3) }
    private var expressionValue: Double? { Self.evaluate(tokens) }
    private var selectedTermCount: Int {
        tokens.reduce(0) { count, token in
            if case .number = token { return count + 1 }
            return count
        }
    }
    private var needsNumber: Bool {
        guard let last = tokens.last else { return true }
        if case .op = last { return true }
        return false
    }
    private var canSubmit: Bool {
        guard !resolving, selectedTermCount >= round.minimumTerms else { return false }
        guard let last = tokens.last, case .number = last else { return false }
        return expressionValue != nil
    }

    var body: some View {
        VStack(spacing: 12) {
            if !cfg.isSurvival {
                header
                ProgressTrack(fraction: timeLeft / Self.gameSeconds, animated: false)
            }

            Spacer(minLength: 10)

            challengeCard
                .id(round.id)

            windowBar

            Text(statusText)
                .font(.witsBody(13, weight: .semibold))
                .foregroundStyle(feedback?.color ?? Color.witsFaint)
                .frame(maxWidth: .infinity)
                .frame(height: 24)

            Spacer(minLength: 8)

            tileGrid
            operatorBar
            actionBar
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .task { await run() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(Text("\(score)").foregroundStyle(Color.witsAccent)) pts")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsInk)
                .monospacedDigit()
            if multiplier > 1 {
                Text("×\(multiplier)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.witsAccent.opacity(0.14), in: Capsule())
            }
            Spacer()
            Text("\(Int(ceil(timeLeft)))s")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsMuted)
                .monospacedDigit()
        }
    }

    private var challengeCard: some View {
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text("target")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsFaint)
                    .textCase(.uppercase)
                Text("\(round.target)")
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                    .monospacedDigit()
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
            }

            expressionStrip

            HStack(spacing: 8) {
                Text("current")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsFaint)
                    .textCase(.uppercase)
                Text(expressionValue.map(Self.format) ?? "-")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundStyle(expressionValue == nil ? Color.witsFaint : Color.witsAccent)
                    .monospacedDigit()
                Spacer(minLength: 0)
                Text("\(selectedTermCount)/\(round.minimumTerms)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(selectedTermCount >= round.minimumTerms ? Color.witsAccent : Color.witsFaint)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.witsTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .cardSurface()
        .overlay(
            RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                .strokeBorder(feedback?.color ?? .clear, lineWidth: 2.5)
                .padding(-10)
        )
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private var expressionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                if tokens.isEmpty {
                    Text("build expression")
                        .font(.witsBody(18, weight: .heavy))
                        .foregroundStyle(Color.witsFaint)
                        .frame(height: 42)
                } else {
                    ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                        tokenCell(token)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 4)
        }
        .frame(height: 46)
    }

    @ViewBuilder
    private func tokenCell(_ token: ExpressionToken) -> some View {
        switch token {
        case .number(_, let value):
            Text("\(value)")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsInk)
                .monospacedDigit()
                .frame(minWidth: 42, minHeight: 38)
                .background(Color.witsCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.witsLine, lineWidth: 1.5)
                )
        case .op(let op):
            Text(op.display)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsAccent)
                .frame(width: 32, height: 38)
        }
    }

    private var windowBar: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.witsLine)
            GeometryReader { geo in
                Capsule()
                    .fill(windowFrac < 0.28 ? Color.witsWarm : Color.witsMuted)
                    .frame(width: max(0, geo.size.width * windowFrac))
            }
        }
        .frame(width: 132, height: 4)
        .padding(.top, 2)
    }

    private var statusText: String {
        if let feedback { return feedback.text }
        if tokens.isEmpty { return "forge \(round.target)" }
        if needsNumber { return "pick a number" }
        return canSubmit ? "submit or keep building" : "add an operator"
    }

    private var tileGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(round.tiles) { tile in
                tileButton(tile)
            }
        }
    }

    private func tileButton(_ tile: NumberTile) -> some View {
        let used = usedTileIDs.contains(tile.id)
        return Button { choose(tile) } label: {
            Text("\(tile.value)")
                .font(.system(size: 23, weight: .heavy, design: .rounded))
                .foregroundStyle(used ? Color.witsFaint : Color.witsInk)
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(used ? Color.witsLine : Color.witsTint,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(used ? Color.clear : Color.witsLine, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(used || !needsNumber || resolving || finished)
        .opacity((used || !needsNumber) ? 0.55 : 1)
    }

    private var operatorBar: some View {
        HStack(spacing: 10) {
            ForEach(round.allowedOps, id: \.self) { op in
                Button { choose(op) } label: {
                    Text(op.display)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(needsNumber ? Color.witsFaint : Color.witsAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.witsCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.witsLine, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .disabled(needsNumber || resolving || finished)
                .opacity(needsNumber ? 0.5 : 1)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            iconButton("arrow.uturn.backward", enabled: !tokens.isEmpty) { undo() }
            iconButton("trash.fill", enabled: !tokens.isEmpty) { clearExpression() }
            Button { submit() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .heavy))
                    Text("submit")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(canSubmit ? Color.witsAccent : Color.witsLine,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
    }

    private func iconButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(enabled ? Color.witsInk : Color.witsFaint)
                .frame(width: 54, height: 54)
                .background(Color.witsTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled || resolving || finished)
    }

    private func choose(_ tile: NumberTile) {
        guard !finished, !resolving, needsNumber, !usedTileIDs.contains(tile.id) else { return }
        tokens.append(.number(id: tile.id, value: tile.value))
        usedTileIDs.insert(tile.id)
    }

    private func choose(_ op: ForgeOperator) {
        guard !finished, !resolving else { return }
        guard let last = tokens.last else { return }
        if case .number = last {
            tokens.append(.op(op))
        }
    }

    private func undo() {
        guard !finished, !resolving, let last = tokens.popLast() else { return }
        if case .number(let id, _) = last {
            usedTileIDs.remove(id)
        }
    }

    private func clearExpression() {
        guard !finished, !resolving else { return }
        tokens.removeAll()
        usedTileIDs.removeAll()
    }

    private func submit() {
        guard canSubmit, let value = expressionValue else { return }
        let error = abs(value - Double(round.target))
        valuedAttempts += 1
        totalError += error
        resolve(grade: grade(for: error), value: value, error: error)
    }

    private func timeout() {
        guard !finished, !resolving else { return }
        resolving = true
        wrong += 1
        streak = 0
        roundWindow = min(Self.maximumWindow(level: level), roundWindow + 0.45)
        cfg.report(.timeout)
        resolveFeedback(Feedback(grade: .miss, value: nil, error: nil), delay: 0.52)
    }

    private func resolve(grade: Grade, value: Double, error: Double) {
        guard !finished, !resolving else { return }
        resolving = true
        switch grade {
        case .exact:
            exact += 1
            streak += 1
            bestStreak = max(bestStreak, streak)
            score += 150 * multiplier
            roundWindow = max(Self.minimumWindow(level: level), roundWindow - 0.08)
            cfg.report(.hit, points: 150, combo: streak)
        case .close:
            close += 1
            streak += 1
            bestStreak = max(bestStreak, streak)
            score += 80 * multiplier
            roundWindow = max(Self.minimumWindow(level: level), roundWindow - 0.04)
            cfg.report(.hit, points: 80, combo: streak)
        case .near:
            near += 1
            streak = 0
            score += 40
            roundWindow = min(Self.maximumWindow(level: level), roundWindow + 0.18)
            cfg.report(.nearMiss)
        case .miss:
            wrong += 1
            streak = 0
            roundWindow = min(Self.maximumWindow(level: level), roundWindow + 0.45)
            cfg.report(.miss)
        }
        resolveFeedback(Feedback(grade: grade, value: value, error: error), delay: grade == .miss ? 0.62 : 0.42)
    }

    private func resolveFeedback(_ nextFeedback: Feedback, delay: Double) {
        feedback = nextFeedback
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard !finished else { return }
            nextRound()
        }
    }

    private func nextRound() {
        tokens.removeAll()
        usedTileIDs.removeAll()
        feedback = nil
        withAnimation(.easeOut(duration: 0.13)) {
            round = Self.makeRound(level: level)
        }
        roundStart = Date()
        windowFrac = 1
        resolving = false
    }

    private func run() async {
        let start = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(30))
            guard !finished else { return }
            timeLeft = max(0, Self.gameSeconds - cfg.activeElapsed(since: start))
            if !resolving {
                let elapsed = cfg.activeElapsed(since: roundStart)
                windowFrac = max(0, 1 - elapsed / roundWindow)
                if elapsed > roundWindow { timeout() }
            }
            if !cfg.isSurvival && timeLeft <= 0 {
                finished = true
                try? await Task.sleep(for: .milliseconds(350))
                finish()
                return
            }
        }
    }

    private func finish() {
        let total = exact + close + near + wrong
        let quality = total > 0 ? (Double(exact) + Double(close) * 0.65 + Double(near) * 0.30) / Double(total) : 0
        var r = GameResult(game: .estimator, score: score, accuracy: quality)
        r.trials = total
        r.startedAt = startedAt
        r.durationMs = Int(Self.gameSeconds * 1000)
        r.raw = [
            "bestStreak": Double(bestStreak),
            "exact": Double(exact),
            "close": Double(close),
            "near": Double(near),
            "correct": Double(exact + close),
            "wrong": Double(wrong),
            "forgeQuality": quality,
            "avgError": valuedAttempts > 0 ? totalError / Double(valuedAttempts) : 0,
            "timeOnTaskMs": Self.gameSeconds * 1000
        ]
        onResult(r)
    }

    private func grade(for error: Double) -> Grade {
        if error < 0.0001 { return .exact }
        let target = Double(round.target)
        let closeLimit = max(2, min(8, target * 0.04))
        let nearLimit = max(5, min(18, target * 0.10))
        if error <= closeLimit { return .close }
        if error <= nearLimit { return .near }
        return .miss
    }

    private static func initialWindow(level: Double) -> Double {
        max(7.0, 13.5 - level * 0.55)
    }

    private static func minimumWindow(level: Double) -> Double {
        max(4.8, 7.6 - level * 0.22)
    }

    private static func maximumWindow(level: Double) -> Double {
        max(8.0, 14.5 - level * 0.35)
    }

    private static func makeRound(level: Double) -> ForgeRound {
        let allowedOps = operators(for: level)
        let tileCount = numberOfTiles(level: level)
        let minTerms = level >= 5 ? 3 : 2
        let maxTerms = level < 3 ? 2 : level < 7 ? 3 : 4
        let targetCap = level < 3 ? 70 : level < 7 ? 160 : 260

        for _ in 0..<600 {
            let termCount = Int.random(in: minTerms...maxTerms)
            let numbers = uniqueTerms(count: termCount, level: level)
            let ops = (0..<(termCount - 1)).map { _ in allowedOps.randomElement() ?? .add }
            guard let value = evaluate(numbers: numbers.map(Double.init), ops: ops) else { continue }
            let rounded = value.rounded()
            guard abs(value - rounded) < 0.0001 else { continue }
            let target = Int(rounded)
            guard target >= 8, target <= targetCap else { continue }

            var values = numbers
            while values.count < tileCount {
                let candidate = distractor(level: level, target: target)
                if !values.contains(candidate) {
                    values.append(candidate)
                }
            }

            let tiles = values.shuffled().enumerated().map { NumberTile(id: $0.offset, value: $0.element) }
            return ForgeRound(
                target: target,
                tiles: tiles,
                allowedOps: allowedOps,
                minimumTerms: minTerms,
                solution: solutionText(numbers: numbers, ops: ops)
            )
        }

        let a = Int.random(in: 6...18)
        let b = Int.random(in: 2...12)
        var values = [a, b]
        while values.count < tileCount {
            let candidate = Int.random(in: 2...28)
            if !values.contains(candidate) { values.append(candidate) }
        }
        let tiles = values.shuffled().enumerated().map { NumberTile(id: $0.offset, value: $0.element) }
        return ForgeRound(
            target: a + b,
            tiles: tiles,
            allowedOps: operators(for: level),
            minimumTerms: 2,
            solution: "\(a) + \(b)"
        )
    }

    private static func operators(for level: Double) -> [ForgeOperator] {
        if level < 3 { return [.add, .subtract] }
        if level < 7 { return [.add, .subtract, .multiply] }
        return [.add, .subtract, .multiply, .divide]
    }

    private static func numberOfTiles(level: Double) -> Int {
        if level < 3 { return 5 }
        if level < 7 { return 6 }
        return 7
    }

    private static func uniqueTerms(count: Int, level: Double) -> [Int] {
        var values: [Int] = []
        while values.count < count {
            let value = term(level: level)
            if !values.contains(value) {
                values.append(value)
            }
        }
        return values
    }

    private static func term(level: Double) -> Int {
        if level < 3 { return Int.random(in: 2...20) }
        if level < 7 { return Int.random(in: 2...30) }
        return Int.random(in: 2...42)
    }

    private static func distractor(level: Double, target: Int) -> Int {
        if Double.random(in: 0..<1) < 0.45 {
            return max(1, target + Int.random(in: -12...12))
        }
        return term(level: level)
    }

    private static func evaluate(_ tokens: [ExpressionToken]) -> Double? {
        var numbers: [Double] = []
        var ops: [ForgeOperator] = []

        for token in tokens {
            switch token {
            case .number(_, let value):
                numbers.append(Double(value))
            case .op(let op):
                ops.append(op)
            }
        }

        guard numbers.count == ops.count + 1 else { return nil }
        return evaluate(numbers: numbers, ops: ops)
    }

    private static func evaluate(numbers: [Double], ops: [ForgeOperator]) -> Double? {
        guard let first = numbers.first, numbers.count == ops.count + 1 else { return nil }

        var collapsedNumbers = [first]
        var collapsedOps: [ForgeOperator] = []

        for (index, op) in ops.enumerated() {
            let next = numbers[index + 1]
            switch op {
            case .multiply:
                collapsedNumbers[collapsedNumbers.count - 1] *= next
            case .divide:
                guard abs(next) > 0.0001 else { return nil }
                collapsedNumbers[collapsedNumbers.count - 1] /= next
            case .add, .subtract:
                collapsedOps.append(op)
                collapsedNumbers.append(next)
            }
        }

        var result = collapsedNumbers[0]
        for (index, op) in collapsedOps.enumerated() {
            let next = collapsedNumbers[index + 1]
            switch op {
            case .add:
                result += next
            case .subtract:
                result -= next
            case .multiply, .divide:
                break
            }
        }

        return result.isFinite ? result : nil
    }

    private static func solutionText(numbers: [Int], ops: [ForgeOperator]) -> String {
        guard let first = numbers.first else { return "" }
        var pieces = ["\(first)"]
        for (index, op) in ops.enumerated() {
            pieces.append(op.display)
            pieces.append("\(numbers[index + 1])")
        }
        return pieces.joined(separator: " ")
    }

    nonisolated private static func format(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.0001 {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", value)
    }
}
