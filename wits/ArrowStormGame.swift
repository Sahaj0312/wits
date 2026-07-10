//
//  ArrowStormGame.swift
//  wits
//
//  Arrow storm (Eriksen flanker task — interference control).
//  Five arrows flash. Only the middle one matters; the flankers usually
//  disagree. An adaptive response deadline tightens as you streak — too
//  slow counts as a miss. Based on the Eriksen flanker paradigm (1974).
//

import SwiftUI

private struct FlankerStats {
    var right = 0
    var wrong = 0
    var bestStreak = 0
    var score = 0
}

struct FlankerScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        _window = State(initialValue: Self.seededWindow(cfg.difficulty.level))
        _trial = State(initialValue: Self.makeTrial())
    }

    private static let gameSeconds = 45.0
    private static let maxWindow = 1.4
    private static let minWindow = 0.75

    /// Higher level → tighter starting deadline (harder).
    private static func seededWindow(_ level: Double) -> Double {
        max(minWindow, maxWindow - level * 0.08)
    }
    private var startedAt = Date()

    private struct Trial: Identifiable {
        let id = UUID()
        let right: Bool       // center arrow direction
        let congruent: Bool
        let yShift: CGFloat
    }

    private static func makeTrial() -> Trial {
        Trial(right: Bool.random(),
              congruent: Double.random(in: 0..<1) < 0.35,
              yShift: CGFloat.random(in: -34...34))
    }

    @State private var stats = FlankerStats()
    @State private var streak = 0
    @State private var trial: Trial?
    @State private var trialStart = Date()
    @State private var window = maxWindow
    @State private var windowFrac = 1.0
    @State private var timeLeft = gameSeconds
    @State private var feedback: Bool?
    @State private var finished = false

    private var multiplier: Int { min(5, 1 + streak / 3) }
    private var world: GameWorld { GameID.arrowStorm.world }

    var body: some View {
        VStack(spacing: 12) {
            if !cfg.isSurvival {
                HStack {
                    Spacer()
                    Text("\(Int(ceil(timeLeft)))s")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(world.muted)
                        .monospacedDigit()
                }
                ProgressTrack(fraction: timeLeft / Self.gameSeconds, animated: false,
                              tint: world.accent, track: world.surface)
            }
            Spacer()
            if let trial {
                trialCard(trial)
                    .id(trial.id)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(
                                feedback == true ? world.accent : feedback == false ? world.secondary : .clear,
                                lineWidth: 2.5
                            )
                            .padding(-14)
                    )
                // per-trial deadline
                ZStack(alignment: .leading) {
                    Capsule().fill(world.surface)
                    GeometryReader { geo in
                        Capsule()
                            .fill(windowFrac < 0.35 ? world.secondary : world.muted)
                            .frame(width: max(0, geo.size.width * windowFrac))
                    }
                }
                .frame(width: 130, height: 4)
                .padding(.top, 18)
            }
            Spacer()
            answerButtons { saysRight in
                answer(saysRight)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .task { await run() }
    }

    private func arrowRow(right: Bool, congruent: Bool, size: CGFloat = 32) -> some View {
        HStack(spacing: 12) {
            ForEach(0..<5, id: \.self) { i in
                let isCenter = i == 2
                let pointsRight = isCenter ? right : (congruent ? right : !right)
                Image(systemName: pointsRight ? "arrowtriangle.right.fill" : "arrowtriangle.left.fill")
                    .font(.system(size: size, weight: .heavy))
                    .foregroundStyle(world.ink)
            }
        }
    }

    private func trialCard(_ t: Trial) -> some View {
        VStack(spacing: 6) {
            arrowRow(right: t.right, congruent: t.congruent)
                .offset(y: t.yShift)
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .background(world.surface, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(world.ink.opacity(0.12), lineWidth: 1))
            Text("THE MIDDLE ONE")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(0.7)
                .foregroundStyle(world.muted)
        }
    }

    private func answerButtons(_ act: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 10) {
            Button { act(false) } label: {
                Image(systemName: "arrowtriangle.left.fill")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(world.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(world.surface, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            Button { act(true) } label: {
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(world.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(world.accent, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
        }
    }

    private func answer(_ saysRight: Bool) {
        guard let current = trial, !finished else { return }
        let ok = saysRight == current.right
        if ok {
            stats.right += 1
            streak += 1
            stats.bestStreak = max(stats.bestStreak, streak)
            stats.score += 100 * multiplier
            window = max(cfg.isSurvival ? 0.6 : Self.minWindow, window - (cfg.isSurvival ? 0.04 : 0.025))
            cfg.report(.hit, points: 100, combo: streak)
        } else {
            stats.wrong += 1
            streak = 0
            window = min(Self.maxWindow, window + 0.12)
            cfg.report(.miss)
        }
        feedback = ok
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { feedback = nil }
        nextTrial()
    }

    private func timeout() {
        guard !finished else { return }
        stats.wrong += 1
        streak = 0
        window = min(Self.maxWindow, window + 0.12)
        feedback = false
        cfg.report(.timeout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { feedback = nil }
        nextTrial()
    }

    private func nextTrial() {
        withAnimation(.easeOut(duration: 0.13)) {
            trial = Self.makeTrial()
        }
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
        let total = stats.right + stats.wrong
        let acc = total > 0 ? Double(stats.right) / Double(total) : 0
        var r = GameResult(game: .arrowStorm, score: stats.score, accuracy: acc)
        r.trials = total
        r.threshold = window
        r.startedAt = startedAt
        r.durationMs = Int(Self.gameSeconds * 1000)
        r.raw = [
            "bestStreak": Double(stats.bestStreak),
            "correct": Double(stats.right),
            "wrong": Double(stats.wrong),
            "timeOnTaskMs": Self.gameSeconds * 1000
        ]
        onResult(r)
    }
}
