//
//  MatchBack.swift
//  wits
//
//  Memory Lane — an active working-memory game. Cards move through a short lane;
//  each scored beat asks whether the current card matches the card n steps back
//  by symbol, colour, or the full pair. Unlike a plain n-back, every prompt needs
//  an answer, and higher levels add lures that share the wrong feature.
//

import SwiftUI

private enum MemoryLaneDimension: CaseIterable {
    case symbol, color, pair

    var label: String {
        switch self {
        case .symbol: "symbol"
        case .color: "colour"
        case .pair: "both"
        }
    }

    var prompt: String {
        switch self {
        case .symbol: "same symbol?"
        case .color: "same colour?"
        case .pair: "same symbol and colour?"
        }
    }
}

private struct MemoryLaneCard: Equatable, Identifiable {
    let id = UUID()
    var symbol: Int
    var color: Int
}

private struct MemoryLaneDisplayItem: Identifiable {
    var offset: Int
    var card: MemoryLaneCard?
    var hidden: Bool
    var opacity: Double
    var id: Int { offset }
}

private struct MemoryLaneTuning {
    let level: Double
    let distance: Int
    let totalScored: Int
    let intervalMs: Int
    let visibleHistory: Int
    let matchRate: Double
    let lureRate: Double
    let dimensions: [MemoryLaneDimension]

    init(level: Double, survival: Bool) {
        let clamped = min(10, max(1, level.isFinite ? level : 1))
        self.level = clamped
        self.distance = clamped < 3 ? 1 : clamped < 6 ? 2 : 3
        self.totalScored = survival ? 24 : 22 + Int(clamped.rounded(.down))
        self.intervalMs = max(760, Int(1_850 - clamped * 105))
        self.visibleHistory = clamped < 4 ? 4 : clamped < 7 ? 3 : clamped < 9 ? 2 : 1
        self.matchRate = 0.46
        self.lureRate = min(0.70, 0.16 + clamped * 0.055)
        if clamped < 3 {
            self.dimensions = [.symbol]
        } else if clamped < 6 {
            self.dimensions = [.symbol, .color]
        } else {
            self.dimensions = [.symbol, .color, .pair]
        }
    }
}

struct MatchBackScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private static let symbols = ["star.fill", "heart.fill", "bolt.fill", "leaf.fill",
                                  "moon.fill", "drop.fill", "flame.fill", "bell.fill"]
    private static let colors: [Color] = [
        Color(red: 0.95, green: 0.74, blue: 0.16),
        Color(red: 0.91, green: 0.30, blue: 0.42),
        Color(red: 0.55, green: 0.45, blue: 0.95),
        Color(red: 0.16, green: 0.70, blue: 0.46),
        Color(red: 0.20, green: 0.52, blue: 0.95),
        Color(red: 0.20, green: 0.74, blue: 0.86),
        Color(red: 0.95, green: 0.45, blue: 0.27),
        Color(red: 0.85, green: 0.36, blue: 0.78),
    ]

    private let tuning: MemoryLaneTuning
    private let feedbackMs = 240

    @State private var cards: [MemoryLaneCard] = []
    @State private var dimensions: [MemoryLaneDimension] = []
    @State private var pos = -1
    @State private var current: MemoryLaneCard?
    @State private var resolved = false
    @State private var chosenSame: Bool?
    @State private var feedback: Bool?
    @State private var windowFrac = 1.0
    @State private var hits = 0
    @State private var misses = 0
    @State private var falseAlarms = 0
    @State private var correctRej = 0
    @State private var timeouts = 0
    @State private var lures = 0
    @State private var score = 0
    @State private var streak = 0
    @State private var generation = 0
    @State private var started = false
    private let startedAt = Date()

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        self.tuning = MemoryLaneTuning(level: cfg.difficulty.level, survival: cfg.isSurvival)
    }

    private var scoredIndex: Int { max(0, pos - tuning.distance + 1) }
    private var decisions: Int { hits + misses + falseAlarms + correctRej }
    private var multiplier: Int { min(5, 1 + streak / 4) }
    private var isPromptActive: Bool { pos >= tuning.distance && current != nil }
    private var dimension: MemoryLaneDimension { dimensions.indices.contains(pos) ? dimensions[pos] : .symbol }
    private var isMatch: Bool {
        guard isPromptActive, cards.indices.contains(pos), cards.indices.contains(pos - tuning.distance) else { return false }
        return Self.matches(cards[pos], cards[pos - tuning.distance], by: dimension)
    }

    var body: some View {
        VStack(spacing: 12) {
            if !cfg.isSurvival {
                header
                ProgressTrack(fraction: Double(scoredIndex) / Double(tuning.totalScored), animated: true)
            }

            Spacer(minLength: 8)

            VStack(spacing: 14) {
                laneView
                promptView
                timerBar
            }

            Spacer(minLength: 8)

            answerButtons
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .onAppear { if !started { started = true; run() } }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(tuning.distance)-back")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsAccent)
            Text(dimension.label)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.witsTint, in: Capsule())
            if multiplier > 1 {
                Text("x\(multiplier)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.witsAccent.opacity(0.14), in: Capsule())
            }
            Spacer()
            Text("\(score) pts")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsMuted)
                .monospacedDigit()
        }
    }

    private var laneView: some View {
        GeometryReader { geo in
            let cardCount = max(3, tuning.visibleHistory + 1)
            let spacing: CGFloat = 9
            let width = min(82, (geo.size.width - spacing * CGFloat(cardCount - 1)) / CGFloat(cardCount))
            HStack(spacing: spacing) {
                ForEach(laneCards(count: cardCount)) { item in
                    let isCurrent = item.offset == pos
                    MemoryLaneCardView(card: item.card,
                                       symbolNames: Self.symbols,
                                       colors: Self.colors,
                                       isCurrent: isCurrent,
                                       isHidden: item.hidden,
                                       feedback: isCurrent ? feedback : nil)
                        .frame(width: width, height: isCurrent ? 118 : 96)
                        .opacity(item.opacity)
                        .scaleEffect(isCurrent ? 1.0 : 0.88)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 150)
        .cardSurface()
        .animation(.easeOut(duration: 0.18), value: pos)
    }

    private var promptView: some View {
        VStack(spacing: 6) {
            Text(isPromptActive ? dimension.prompt : "watch the lane")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsInk)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
            Text(isPromptActive ? "compare to \(tuning.distance) back" : "loading memory")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsFaint)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 66)
    }

    private var timerBar: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.witsLine)
            GeometryReader { geo in
                Capsule()
                    .fill(windowFrac < 0.28 ? Color.witsWarm : Color.witsMuted)
                    .frame(width: max(0, geo.size.width * windowFrac))
            }
        }
        .frame(width: 150, height: 4)
        .opacity(isPromptActive && !resolved ? 1 : 0.35)
    }

    private var answerButtons: some View {
        HStack(spacing: 10) {
            answerButton(title: "new", icon: "xmark.circle.fill", saysSame: false)
            answerButton(title: "same", icon: "checkmark.circle.fill", saysSame: true)
        }
    }

    private func answerButton(title: String, icon: String, saysSame: Bool) -> some View {
        Button { resolve(saysSame) } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .heavy))
                Text(title)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(buttonColor(saysSame: saysSame), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isPromptActive || resolved)
        .opacity(isPromptActive ? 1 : 0.45)
    }

    private func buttonColor(saysSame: Bool) -> Color {
        guard chosenSame == saysSame else { return saysSame ? Color.witsAccent : Color.witsInk.opacity(0.88) }
        if feedback == true { return Color.witsAccent }
        if feedback == false { return Color.witsWarm }
        return saysSame ? Color.witsAccent : Color.witsInk.opacity(0.88)
    }

    private func laneCards(count: Int) -> [MemoryLaneDisplayItem] {
        let start = max(0, pos - count + 1)
        let realItems = (start...max(start, pos)).compactMap { index -> (Int, MemoryLaneCard?, Bool, Double)? in
            guard cards.indices.contains(index) else { return nil }
            let age = max(0, pos - index)
            let hidden = age > tuning.visibleHistory
            let opacity = hidden ? 0.24 : max(0.34, 1.0 - Double(age) * 0.18)
            return (index, cards[index], hidden, opacity)
        }
        let missing = max(0, count - realItems.count)
        let placeholders = (0..<missing).map { idx in
            MemoryLaneDisplayItem(offset: -missing + idx, card: nil, hidden: true, opacity: 0.22)
        }
        return placeholders + realItems.map {
            MemoryLaneDisplayItem(offset: $0.0, card: $0.1, hidden: $0.2, opacity: $0.3)
        }
    }

    private func run() {
        generation += 1
        let gen = generation
        Task {
            repeat {
                let round = Self.makeRound(tuning: tuning)
                cards = round.cards
                dimensions = round.dimensions
                lures += round.lures
                for i in cards.indices {
                    guard gen == generation else { return }
                    pos = i
                    current = cards[i]
                    resolved = false
                    chosenSame = nil
                    feedback = nil
                    windowFrac = 1
                    if i < tuning.distance {
                        await cfg.sleepActive(milliseconds: max(520, tuning.intervalMs - 240))
                        continue
                    }
                    let trialStart = Date()
                    while !Task.isCancelled && !resolved {
                        let elapsed = cfg.activeElapsed(since: trialStart)
                        windowFrac = max(0, 1 - elapsed / (Double(tuning.intervalMs) / 1000.0))
                        if elapsed * 1000 >= Double(tuning.intervalMs) {
                            resolve(nil)
                            break
                        }
                        await cfg.sleepActive(milliseconds: 25)
                    }
                    await cfg.sleepActive(milliseconds: feedbackMs)
                }
            } while cfg.isSurvival && !Task.isCancelled
            if !cfg.isSurvival { finish() }
        }
    }

    private func resolve(_ saysSame: Bool?) {
        guard isPromptActive, !resolved else { return }
        resolved = true
        chosenSame = saysSame
        let correct = saysSame == isMatch
        feedback = correct

        switch (isMatch, saysSame) {
        case (true, true):
            hits += 1
            streak += 1
            score += 120 * multiplier
            cfg.report(.hit, points: 120, combo: streak)
        case (false, false):
            correctRej += 1
            streak += 1
            score += 80 * multiplier
            cfg.report(.hit, points: 80, combo: streak)
        case (true, _):
            misses += 1
            streak = 0
            if saysSame == nil { timeouts += 1; cfg.report(.timeout) } else { cfg.report(.miss) }
        case (false, _):
            falseAlarms += 1
            streak = 0
            if saysSame == nil { timeouts += 1; cfg.report(.timeout) } else { cfg.report(.miss) }
        }
    }

    private func finish() {
        let acc = decisions > 0 ? Double(hits + correctRej) / Double(decisions) : 0
        let elapsedMs = (tuning.distance + tuning.totalScored) * (tuning.intervalMs + feedbackMs)
        var r = GameResult(game: .matchBack, score: score, accuracy: acc)
        r.trials = decisions
        r.threshold = Double(tuning.distance)
        r.startedAt = startedAt
        r.durationMs = elapsedMs
        r.raw = [
            "n": Double(tuning.distance),
            "hits": Double(hits),
            "falseAlarms": Double(falseAlarms),
            "misses": Double(misses),
            "correctRejections": Double(correctRej),
            "timeouts": Double(timeouts),
            "lures": Double(lures),
            "intervalMs": Double(tuning.intervalMs),
            "timeOnTaskMs": Double(elapsedMs)
        ]
        onResult(r)
    }

    private static func makeRound(tuning: MemoryLaneTuning) -> (cards: [MemoryLaneCard], dimensions: [MemoryLaneDimension], lures: Int) {
        let total = tuning.distance + tuning.totalScored
        var cards: [MemoryLaneCard] = []
        var dimensions: [MemoryLaneDimension] = []
        var lures = 0
        for i in 0..<total {
            let dimension = tuning.dimensions.randomElement() ?? .symbol
            dimensions.append(dimension)
            guard i >= tuning.distance else {
                cards.append(randomCard())
                continue
            }
            let reference = cards[i - tuning.distance]
            let shouldMatch = Double.random(in: 0..<1) < tuning.matchRate
            let shouldLure = !shouldMatch && Double.random(in: 0..<1) < tuning.lureRate
            if shouldLure { lures += 1 }
            cards.append(makeCard(reference: reference, dimension: dimension, shouldMatch: shouldMatch, shouldLure: shouldLure))
        }
        return (cards, dimensions, lures)
    }

    private static func randomCard() -> MemoryLaneCard {
        MemoryLaneCard(symbol: Int.random(in: 0..<symbols.count), color: Int.random(in: 0..<colors.count))
    }

    private static func makeCard(reference: MemoryLaneCard,
                                 dimension: MemoryLaneDimension,
                                 shouldMatch: Bool,
                                 shouldLure: Bool) -> MemoryLaneCard {
        if shouldMatch {
            switch dimension {
            case .symbol:
                return MemoryLaneCard(symbol: reference.symbol, color: randomIndex(excluding: nil, count: colors.count))
            case .color:
                return MemoryLaneCard(symbol: randomIndex(excluding: nil, count: symbols.count), color: reference.color)
            case .pair:
                return reference
            }
        }

        switch dimension {
        case .symbol:
            return MemoryLaneCard(symbol: randomIndex(excluding: reference.symbol, count: symbols.count),
                                  color: shouldLure ? reference.color : randomIndex(excluding: nil, count: colors.count))
        case .color:
            return MemoryLaneCard(symbol: shouldLure ? reference.symbol : randomIndex(excluding: nil, count: symbols.count),
                                  color: randomIndex(excluding: reference.color, count: colors.count))
        case .pair:
            if shouldLure && Bool.random() {
                return MemoryLaneCard(symbol: reference.symbol, color: randomIndex(excluding: reference.color, count: colors.count))
            }
            if shouldLure {
                return MemoryLaneCard(symbol: randomIndex(excluding: reference.symbol, count: symbols.count), color: reference.color)
            }
            return MemoryLaneCard(symbol: randomIndex(excluding: reference.symbol, count: symbols.count),
                                  color: randomIndex(excluding: reference.color, count: colors.count))
        }
    }

    private static func randomIndex(excluding excluded: Int?, count: Int) -> Int {
        let pool = (0..<count).filter { $0 != excluded }
        return pool.randomElement() ?? 0
    }

    private static func matches(_ lhs: MemoryLaneCard, _ rhs: MemoryLaneCard, by dimension: MemoryLaneDimension) -> Bool {
        switch dimension {
        case .symbol: lhs.symbol == rhs.symbol
        case .color: lhs.color == rhs.color
        case .pair: lhs.symbol == rhs.symbol && lhs.color == rhs.color
        }
    }
}

private struct MemoryLaneCardView: View {
    var card: MemoryLaneCard?
    var symbolNames: [String]
    var colors: [Color]
    var isCurrent: Bool
    var isHidden: Bool
    var feedback: Bool?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isCurrent ? Color.witsTint : Color.witsBg.opacity(0.70))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isCurrent ? 3 : 1.5)
            if let card, !isHidden {
                Image(systemName: symbolNames[card.symbol])
                    .font(.system(size: isCurrent ? 48 : 34, weight: .heavy))
                    .foregroundStyle(colors[card.color])
                    .shadow(color: colors[card.color].opacity(isCurrent ? 0.28 : 0.12), radius: isCurrent ? 8 : 3)
            } else {
                Image(systemName: "circle.grid.cross.fill")
                    .font(.system(size: isCurrent ? 34 : 26, weight: .heavy))
                    .foregroundStyle(Color.witsLine)
            }
        }
    }

    private var borderColor: Color {
        if feedback == true { return Color.witsAccent }
        if feedback == false { return Color.witsWarm }
        return isCurrent ? Color.witsAccent.opacity(0.45) : Color.witsLine
    }
}
