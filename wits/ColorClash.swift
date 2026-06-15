//
//  ColorClash.swift
//  wits
//
//  Stroop task — tap the colour the word is printed in, not the word itself.
//  Targets cognitive flexibility / interference control. Adaptive: the response
//  deadline tightens and the share of incongruent trials rises with level.
//

import SwiftUI

enum StroopColor: String, CaseIterable, Identifiable {
    case red, blue, green, yellow
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .red: Color(red: 0.91, green: 0.26, blue: 0.27)
        case .blue: Color(red: 0.20, green: 0.52, blue: 0.95)
        case .green: Color(red: 0.16, green: 0.70, blue: 0.46)
        case .yellow: Color(red: 0.95, green: 0.74, blue: 0.16)
        }
    }
}

struct ColorClashScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private static let gameSeconds = 45.0

    private struct Trial: Identifiable {
        let id = UUID()
        let word: StroopColor   // the text
        let ink: StroopColor    // the colour it's drawn in (the answer)
    }

    @State private var trial: Trial?
    @State private var trialStart = Date()
    @State private var window: Double
    @State private var windowFrac = 1.0
    @State private var timeLeft = gameSeconds
    @State private var right = 0
    @State private var wrong = 0
    @State private var streak = 0
    @State private var bestStreak = 0
    @State private var score = 0
    @State private var feedback: Bool?
    @State private var finished = false
    private let startedAt = Date()

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        _window = State(initialValue: max(0.7, 1.6 - cfg.difficulty.level * 0.09))
        _trial = State(initialValue: Self.makeTrial(pIncongruent: 0.5))
    }

    private var pIncongruent: Double { min(0.85, 0.4 + cfg.difficulty.level * 0.04) }
    private var multiplier: Int { min(5, 1 + streak / 3) }

    private static func makeTrial(pIncongruent: Double) -> Trial {
        let word = StroopColor.allCases.randomElement()!
        let incongruent = Double.random(in: 0..<1) < pIncongruent
        let ink = incongruent
            ? StroopColor.allCases.filter { $0 != word }.randomElement()!
            : word
        return Trial(word: word, ink: ink)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Text("\(score)").foregroundStyle(Color.witsAccent)) pts")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                    .monospacedDigit()
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
                    .foregroundStyle(Color.witsMuted)
                    .monospacedDigit()
            }
            ProgressTrack(fraction: timeLeft / Self.gameSeconds, animated: false)
            Spacer()
            if let trial {
                VStack(spacing: 6) {
                    Text(trial.word.rawValue)
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .foregroundStyle(trial.ink.color)
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .cardSurface()
                        .id(trial.id)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                        .overlay(
                            RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                                .strokeBorder(feedback == true ? Color.witsAccent : feedback == false ? Color.witsWarm : .clear, lineWidth: 2.5)
                                .padding(-14)
                        )
                    Text("TAP THE COLOUR, NOT THE WORD")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .kerning(0.7)
                        .foregroundStyle(Color.witsFaint)
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.witsLine)
                    GeometryReader { geo in
                        Capsule()
                            .fill(windowFrac < 0.35 ? Color.witsWarm : Color.witsMuted)
                            .frame(width: max(0, geo.size.width * windowFrac))
                    }
                }
                .frame(width: 130, height: 4)
                .padding(.top, 18)
            }
            Spacer()
            colorButtons
                .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .task { await run() }
    }

    private var colorButtons: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(StroopColor.allCases) { c in
                Button { answer(c) } label: {
                    Text(c.rawValue)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(c.color, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func answer(_ c: StroopColor) {
        guard let current = trial, !finished else { return }
        let ok = c == current.ink
        if ok {
            right += 1; streak += 1; bestStreak = max(bestStreak, streak)
            score += 100 * multiplier
            window = max(0.6, window - 0.02)
        } else {
            wrong += 1; streak = 0
            window = min(1.6, window + 0.1)
        }
        feedback = ok
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { feedback = nil }
        nextTrial()
    }

    private func timeout() {
        guard !finished else { return }
        wrong += 1; streak = 0
        window = min(1.6, window + 0.1)
        feedback = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { feedback = nil }
        nextTrial()
    }

    private func nextTrial() {
        withAnimation(.easeOut(duration: 0.13)) { trial = Self.makeTrial(pIncongruent: pIncongruent) }
        trialStart = Date()
        windowFrac = 1
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
        var r = GameResult(game: .colorClash, score: score, accuracy: acc)
        r.trials = total
        r.threshold = window
        r.startedAt = startedAt
        r.durationMs = Int(Self.gameSeconds * 1000)
        r.raw = ["bestStreak": Double(bestStreak)]
        onResult(r)
    }
}
