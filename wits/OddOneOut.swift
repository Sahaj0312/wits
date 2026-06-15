//
//  OddOneOut.swift
//  wits
//
//  Visual search. Find the one tile whose colour doesn't match the rest.
//  Adaptive: the grid grows and the colour difference shrinks with level.
//

import SwiftUI

struct OddOneOutScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private static let gameSeconds = 45.0
    private static let base = (r: 0.09, g: 0.70, b: 0.64)   // teal
    private static let warm = (r: 0.94, g: 0.47, b: 0.37)   // coral

    @State private var cols = 3
    @State private var oddIndex = 0
    @State private var delta = 0.5
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

    private var oddColor: Color {
        Color(red: Self.base.r + (Self.warm.r - Self.base.r) * delta,
              green: Self.base.g + (Self.warm.g - Self.base.g) * delta,
              blue: Self.base.b + (Self.warm.b - Self.base.b) * delta)
    }
    private var baseColor: Color { Color(red: Self.base.r, green: Self.base.g, blue: Self.base.b) }

    var body: some View {
        VStack(spacing: 12) {
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
            Spacer()
            GeometryReader { geo in
                let gap: CGFloat = 8
                let side = (min(geo.size.width, geo.size.height) - gap * CGFloat(cols - 1)) / CGFloat(cols)
                let grid = Array(repeating: GridItem(.fixed(side), spacing: gap), count: cols)
                LazyVGrid(columns: grid, spacing: gap) {
                    ForEach(0..<(cols * cols), id: \.self) { i in
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(i == oddIndex ? oddColor : baseColor)
                            .frame(width: side, height: side)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(wrongTap == i ? Color.witsWarm : .clear, lineWidth: 3)
                            )
                            .onTapGesture { tap(i) }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            }
            Text("tap the tile that's a different colour")
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
        cols = min(6, 3 + Int(level / 2) + Int.random(in: 0...1))
        delta = max(0.16, 0.55 - level * 0.035)
        oddIndex = Int.random(in: 0..<(cols * cols))
        wrongTap = nil
    }

    private func tap(_ i: Int) {
        guard !finished else { return }
        if i == oddIndex {
            right += 1; streak += 1; bestStreak = max(bestStreak, streak)
            score += 100 * min(5, 1 + streak / 3)
            newRound()
        } else {
            wrong += 1; streak = 0
            wrongTap = i
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { wrongTap = nil }
        }
    }

    private func run() async {
        let start = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(40))
            timeLeft = max(0, Self.gameSeconds - Date().timeIntervalSince(start))
            if timeLeft <= 0 {
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
