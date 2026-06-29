//
//  TileShift.swift
//  wits
//
//  Task switching. Match the target by the rule on screen — colour or shape —
//  and the rule keeps flipping. Adaptive: faster deadline + more frequent
//  switches with level.
//

import SwiftUI

private let tileShapes = ["circle.fill", "square.fill", "triangle.fill"]
private let tileColors: [Color] = [
    Color(red: 0.09, green: 0.70, blue: 0.64),
    Color(red: 0.94, green: 0.47, blue: 0.37),
    Color(red: 0.95, green: 0.74, blue: 0.16),
]

struct TileShiftScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private static let gameSeconds = 45.0

    private struct Tile: Equatable { var shape: Int; var color: Int }
    private struct Round: Identifiable {
        let id = UUID()
        let byColor: Bool
        let target: Tile
        let options: [Tile]
        let correct: Int
    }

    @State private var round: Round
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
        _window = State(initialValue: max(1.0, 2.2 - cfg.difficulty.level * 0.1))
        _round = State(initialValue: Self.make(byColor: Bool.random()))
    }

    private var multiplier: Int { min(5, 1 + streak / 3) }

    private static func make(byColor: Bool) -> Round {
        let target = Tile(shape: .random(in: 0..<3), color: .random(in: 0..<3))
        // correct matches target on the active dimension, differs on the other
        var correct = target
        if byColor { correct.shape = (target.shape + Int.random(in: 1...2)) % 3 }
        else { correct.color = (target.color + Int.random(in: 1...2)) % 3 }
        // distractor differs on the active dimension
        var distractor = target
        if byColor {
            distractor.color = (target.color + Int.random(in: 1...2)) % 3
            distractor.shape = .random(in: 0..<3)
        } else {
            distractor.shape = (target.shape + Int.random(in: 1...2)) % 3
            distractor.color = .random(in: 0..<3)
        }
        let correctFirst = Bool.random()
        let options = correctFirst ? [correct, distractor] : [distractor, correct]
        return Round(byColor: byColor, target: target, options: options, correct: correctFirst ? 0 : 1)
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

            Text(round.byColor ? "MATCH THE COLOUR" : "MATCH THE SHAPE")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .kerning(1)
                .foregroundStyle(round.byColor ? Color.witsAccent : Color.witsWarm)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background((round.byColor ? Color.witsAccent : Color.witsWarm).opacity(0.14), in: Capsule())
                .padding(.top, 6)

            Spacer()
            tileView(round.target)
                .frame(width: 120, height: 120)
                .cardSurface()
                .id(round.id)
                .overlay(
                    RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                        .strokeBorder(feedback == true ? Color.witsAccent : feedback == false ? Color.witsWarm : .clear, lineWidth: 2.5)
                        .padding(-10)
                )
            ZStack(alignment: .leading) {
                Capsule().fill(Color.witsLine)
                GeometryReader { geo in
                    Capsule().fill(windowFrac < 0.35 ? Color.witsWarm : Color.witsMuted)
                        .frame(width: max(0, geo.size.width * windowFrac))
                }
            }
            .frame(width: 130, height: 4).padding(.top, 14)
            Spacer()
            HStack(spacing: 12) {
                ForEach(0..<2, id: \.self) { i in
                    Button { answer(i) } label: {
                        tileView(round.options[i])
                            .frame(maxWidth: .infinity).frame(height: 110)
                            .background(Color.witsTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    private func tileView(_ t: Tile) -> some View {
        Image(systemName: tileShapes[t.shape])
            .font(.system(size: 46, weight: .heavy))
            .foregroundStyle(tileColors[t.color])
    }

    private func answer(_ i: Int) {
        guard !finished else { return }
        let ok = i == round.correct
        if ok {
            right += 1; streak += 1; bestStreak = max(bestStreak, streak)
            score += 100 * multiplier
            window = max(cfg.isSurvival ? 0.65 : 0.8, window - (cfg.isSurvival ? 0.05 : 0.03))
            cfg.report(.hit, points: 100, combo: streak)
        } else {
            wrong += 1; streak = 0
            window = min(2.4, window + 0.2)
            cfg.report(.miss)
        }
        feedback = ok
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { feedback = nil }
        next()
    }

    private func timeout() {
        guard !finished else { return }
        wrong += 1; streak = 0
        feedback = false
        cfg.report(.timeout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { feedback = nil }
        next()
    }

    private func next() {
        let pSwitch = min(0.7, 0.3 + level * 0.04)
        let nextByColor = Double.random(in: 0..<1) < pSwitch ? !round.byColor : round.byColor
        withAnimation(.easeOut(duration: 0.12)) { round = Self.make(byColor: nextByColor) }
        trialStart = Date(); windowFrac = 1
    }

    private func run() async {
        let start = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(30))
            timeLeft = max(0, Self.gameSeconds - cfg.activeElapsed(since: start))
            let elapsed = cfg.activeElapsed(since: trialStart)
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
        var r = GameResult(game: .tileShift, score: score, accuracy: acc)
        r.trials = total
        r.startedAt = startedAt
        r.durationMs = Int(Self.gameSeconds * 1000)
        r.raw = [
            "bestStreak": Double(bestStreak),
            "correct": Double(right),
            "wrong": Double(wrong),
            "timeOnTaskMs": Self.gameSeconds * 1000
        ]
        onResult(r)
    }
}
