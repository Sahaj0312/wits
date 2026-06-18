//
//  OddOneOut.swift
//  wits
//
//  Visual search. Find the one tile that doesn't match — by a subtle COLOUR
//  shift on some rounds, by ROTATION (orientation) on others, so it can't just
//  "pop out". Adaptive: the grid grows, the difference shrinks, and the per-round
//  deadline tightens with level.
//

import SwiftUI

struct OddOneOutScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private static let gameSeconds = 45.0
    private static let base = (r: 0.09, g: 0.70, b: 0.64)   // teal
    private static let warm = (r: 0.94, g: 0.47, b: 0.37)   // coral

    private enum Mode { case color, rotation }

    @State private var cols = 4
    @State private var oddIndex = 0
    @State private var mode: Mode = .color
    @State private var delta = 0.4         // colour shift of the odd tile
    @State private var angle = 60.0        // rotation of the odd tile (degrees)
    @State private var window = 4.2        // per-round deadline (s)
    @State private var windowFrac = 1.0
    @State private var roundStart = Date()
    @State private var timeLeft = gameSeconds
    @State private var right = 0
    @State private var wrong = 0
    @State private var streak = 0
    @State private var bestStreak = 0
    @State private var score = 0
    @State private var wrongTap: Int?
    @State private var finished = false
    private let startedAt = Date()
    private let level: Double

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        self.level = cfg.difficulty.level
    }

    private var baseColor: Color { Color(red: Self.base.r, green: Self.base.g, blue: Self.base.b) }
    private var oddColor: Color {
        Color(red: Self.base.r + (Self.warm.r - Self.base.r) * delta,
              green: Self.base.g + (Self.warm.g - Self.base.g) * delta,
              blue: Self.base.b + (Self.warm.b - Self.base.b) * delta)
    }

    private func iconColor(_ isOdd: Bool) -> Color {
        mode == .color && isOdd ? oddColor : baseColor
    }
    private func iconAngle(_ isOdd: Bool) -> Double {
        mode == .rotation && isOdd ? angle : 0
    }

    var body: some View {
        VStack(spacing: 12) {
            if !cfg.isSurvival {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Text("\(score)").foregroundStyle(Color.witsAccent)) pts")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsInk).monospacedDigit()
                    Spacer()
                    Text("\(Int(ceil(timeLeft)))s")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsMuted).monospacedDigit()
                }
                ProgressTrack(fraction: timeLeft / Self.gameSeconds, animated: false)
            }
            Spacer()
            GeometryReader { geo in
                let gap: CGFloat = 8
                let side = (min(geo.size.width, geo.size.height) - gap * CGFloat(cols - 1)) / CGFloat(cols)
                let grid = Array(repeating: GridItem(.fixed(side), spacing: gap), count: cols)
                LazyVGrid(columns: grid, spacing: gap) {
                    ForEach(0..<(cols * cols), id: \.self) { i in
                        let isOdd = i == oddIndex
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.witsCard)
                            .frame(width: side, height: side)
                            .overlay(
                                Image(systemName: "arrowtriangle.up.fill")
                                    .font(.system(size: side * 0.5, weight: .heavy))
                                    .foregroundStyle(iconColor(isOdd))
                                    .rotationEffect(.degrees(iconAngle(isOdd)))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(wrongTap == i ? Color.witsWarm : .clear, lineWidth: 3)
                            )
                            .onTapGesture { tap(i) }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.witsLine)
                GeometryReader { geo in
                    Capsule().fill(windowFrac < 0.35 ? Color.witsWarm : Color.witsMuted)
                        .frame(width: max(0, geo.size.width * windowFrac))
                }
            }
            .frame(width: 130, height: 4)
            Text("tap the one that doesn't match")
                .font(.witsBody(12.5)).foregroundStyle(Color.witsFaint)
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 24).padding(.bottom, 12)
        .task { await run() }
        .onAppear { newRound() }
    }

    private func newRound() {
        cols = min(6, 4 + Int(level / 3))
        mode = Bool.random() ? .color : .rotation
        delta = max(0.14, 0.40 - level * 0.025)        // subtler colour with level
        angle = max(16, 65 - level * 5)                // smaller rotation with level
        window = max(2.0, 4.2 - level * 0.22)
        oddIndex = Int.random(in: 0..<(cols * cols))
        wrongTap = nil
        roundStart = Date(); windowFrac = 1
    }

    private func tap(_ i: Int) {
        guard !finished else { return }
        if i == oddIndex {
            right += 1; streak += 1; bestStreak = max(bestStreak, streak)
            score += 100 * min(5, 1 + streak / 3)
            cfg.report(.hit, points: 100, combo: streak)
            newRound()
        } else {
            wrong += 1; streak = 0
            wrongTap = i
            cfg.report(NearMiss.adjacent(i, oddIndex, cols: cols) ? .nearMiss : .miss)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { wrongTap = nil }
        }
    }

    private func roundTimeout() {
        guard !finished else { return }
        wrong += 1; streak = 0
        cfg.report(.timeout)
        newRound()
    }

    private func run() async {
        let start = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(40))
            timeLeft = max(0, Self.gameSeconds - Date().timeIntervalSince(start))
            let elapsed = Date().timeIntervalSince(roundStart)
            windowFrac = max(0, 1 - elapsed / window)
            if elapsed > window { roundTimeout() }
            if !cfg.isSurvival && timeLeft <= 0 {
                guard !finished else { return }
                finished = true
                try? await Task.sleep(for: .milliseconds(300))
                finish()
                return
            }
        }
    }

    private func finish() {
        let total = right + wrong
        let acc = total > 0 ? Double(right) / Double(total) : 0
        var r = GameResult(game: .oddOneOut, score: score, accuracy: acc)
        r.trials = total
        r.startedAt = startedAt
        r.durationMs = Int(Self.gameSeconds * 1000)
        r.raw = ["bestStreak": Double(bestStreak)]
        onResult(r)
    }
}
