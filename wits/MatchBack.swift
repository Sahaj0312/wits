//
//  MatchBack.swift
//  wits
//
//  Match-back — a working-memory task made approachable. Coloured symbols flow by
//  one at a time; tap MATCH when the current symbol is the same as the one a few
//  cards back. Starts at 1-back ("same as the one just before") so the rule is
//  obvious, then n rises with level. Per-card feedback teaches the rule.
//

import SwiftUI

struct MatchBackScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private static let symbols = ["star.fill", "heart.fill", "bolt.fill", "leaf.fill",
                                  "moon.fill", "drop.fill", "flame.fill", "bell.fill"]
    private static let colors: [Color] = [
        Color(red: 0.95, green: 0.74, blue: 0.16),   // star  — amber
        Color(red: 0.91, green: 0.30, blue: 0.42),   // heart — rose
        Color(red: 0.55, green: 0.45, blue: 0.95),   // bolt  — violet
        Color(red: 0.16, green: 0.70, blue: 0.46),   // leaf  — green
        Color(red: 0.20, green: 0.52, blue: 0.95),   // moon  — blue
        Color(red: 0.20, green: 0.74, blue: 0.86),   // drop  — cyan
        Color(red: 0.95, green: 0.45, blue: 0.27),   // flame — orange
        Color(red: 0.85, green: 0.36, blue: 0.78),   // bell  — magenta
    ]

    private let n: Int
    private let total: Int
    private let intervalMs: Int
    private let feedbackMs = 260

    @State private var seq: [Int] = []
    @State private var pos = -1
    @State private var current: Int?
    @State private var responded = false
    @State private var feedback: Bool?       // green = correct decision, red = wrong
    @State private var tapFlash = false
    @State private var hits = 0
    @State private var misses = 0
    @State private var falseAlarms = 0
    @State private var correctRej = 0
    @State private var score = 0
    @State private var streak = 0
    @State private var generation = 0
    @State private var started = false
    private let startedAt = Date()

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        let level = cfg.difficulty.level
        self.n = max(1, min(3, 1 + Int(level / 4)))
        self.total = 18 + n
        self.intervalMs = max(900, Int(1350 - level * 45))
    }

    private var decisions: Int { hits + misses + falseAlarms + correctRej }
    private var multiplier: Int { min(5, 1 + streak / 3) }

    private var instruction: String {
        n == 1 ? "tap MATCH when a symbol is the same as the one just before it"
               : "tap MATCH when a symbol is the same as the one \(n) cards back"
    }

    var body: some View {
        VStack(spacing: 14) {
            if !cfg.isSurvival {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(n)-back")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsAccent)
                    if multiplier > 1 {
                        Text("×\(multiplier)")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.witsAccent)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.witsAccent.opacity(0.14), in: Capsule())
                    }
                    Spacer()
                    Text("\(score) pts")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsMuted)
                        .monospacedDigit()
                }
                ProgressTrack(fraction: Double(max(0, pos)) / Double(total), animated: true)
            }

            Spacer()

            // One big card, one symbol at a time — clear focal point, never empty.
            ZStack {
                if let s = current, s < Self.symbols.count {
                    Image(systemName: Self.symbols[s])
                        .font(.system(size: 104, weight: .heavy))
                        .foregroundStyle(Self.colors[s])
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                        .id(pos)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 260)
            .cardSurface()
            .overlay(
                RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                    .strokeBorder(feedback == true ? Color.witsAccent
                                  : feedback == false ? Color.witsWarm : .clear, lineWidth: 3)
            )
            .animation(.easeOut(duration: 0.18), value: pos)

            Text(instruction)
                .font(.witsBody(13))
                .foregroundStyle(Color.witsFaint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Spacer()

            Button { tapMatch() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .heavy))
                    Text("match")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(tapFlash ? Color.witsAccent : Color.witsInk.opacity(0.88), in: Capsule())
                .animation(.easeOut(duration: 0.12), value: tapFlash)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .onAppear { if !started { started = true; run() } }
    }

    private func makeSequence() -> [Int] {
        var s: [Int] = []
        for i in 0..<total {
            if i >= n, Double.random(in: 0..<1) < 0.32 {
                s.append(s[i - n])                       // planned match
            } else if i >= n {
                let avoid = s[i - n]
                s.append((0..<Self.symbols.count).filter { $0 != avoid }.randomElement()!)
            } else {
                s.append(Int.random(in: 0..<Self.symbols.count))
            }
        }
        return s
    }

    private func run() {
        generation += 1
        let gen = generation
        Task {
            repeat {
                seq = makeSequence()
                for i in 0..<seq.count {
                    guard gen == generation else { return }
                    pos = i
                    responded = false
                    feedback = nil
                    withAnimation { current = seq[i] }
                    try? await Task.sleep(for: .milliseconds(intervalMs))
                    guard gen == generation else { return }
                    evaluate(i)
                    try? await Task.sleep(for: .milliseconds(feedbackMs))
                }
            } while cfg.isSurvival && !Task.isCancelled
            if !cfg.isSurvival { finish() }
        }
    }

    private func tapMatch() {
        guard started, pos >= 0, !responded else { return }
        responded = true
        tapFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { tapFlash = false }
    }

    private func evaluate(_ i: Int) {
        let isMatch = i >= n && seq[i] == seq[i - n]
        if responded {
            if isMatch { hits += 1; streak += 1; score += 120 * multiplier; cfg.report(.hit, points: 120, combo: streak) }
            else { falseAlarms += 1; streak = 0; cfg.report(.miss) }
        } else {
            if isMatch { misses += 1; streak = 0; cfg.report(.miss) }
            else { correctRej += 1; score += 20 }   // silent: a non-event every beat
        }
        feedback = (responded == isMatch)
    }

    private func finish() {
        let acc = decisions > 0 ? Double(hits + correctRej) / Double(decisions) : 0
        var r = GameResult(game: .matchBack, score: score, accuracy: acc)
        r.trials = total
        r.threshold = Double(n)
        r.startedAt = startedAt
        r.durationMs = total * (intervalMs + feedbackMs)
        r.raw = [
            "n": Double(n),
            "hits": Double(hits),
            "falseAlarms": Double(falseAlarms),
            "misses": Double(misses),
            "correctRejections": Double(correctRej),
            "timeOnTaskMs": Double(total * (intervalMs + feedbackMs))
        ]
        onResult(r)
    }
}
