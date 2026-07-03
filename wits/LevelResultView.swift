//
//  LevelResultView.swift
//  wits
//
//  Post-run surfaces for the star-map system (design doc §4): self-comparison
//  only. Exam runs show stars earned; marathon deaths show depth vs personal
//  best with near-miss framing. No percentiles, no leaderboards here.
//

import SwiftUI

struct LevelResultView: View {
    let game: GameID
    let level: Int
    let stars: Int
    let quality: Double
    let improved: Bool
    let nextUnlocked: Bool
    let onRetry: () -> Void
    let onNext: () -> Void
    let onMap: () -> Void

    private var passed: Bool { stars >= 1 }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text(passed ? "level \(level) cleared" : "level \(level)")
                .font(.witsDisplay(30))
                .foregroundStyle(Color.witsInk)
                .rise()

            Text(headline)
                .font(.witsBody(15.5))
                .foregroundStyle(Color.witsMuted)
                .padding(.top, 8)
                .rise(0.06)

            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: i < stars ? "star.fill" : "star")
                        .font(.system(size: 44, weight: .heavy))
                        .foregroundStyle(i < stars ? Color.witsWarm : Color.witsFaint)
                        .rise(0.12 + Double(i) * 0.1)
                }
            }
            .padding(.top, 26)

            Text("\(Int((quality * 100).rounded()))%")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsMuted)
                .monospacedDigit()
                .padding(.top, 14)
                .rise(0.3)

            Spacer()

            VStack(spacing: 11) {
                if passed && nextUnlocked {
                    Cta(title: "next level", action: onNext)
                }
                Button(action: onRetry) {
                    Text(passed ? (stars < 3 ? "replay for \(stars + 1)★" : "replay") : "try again")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.witsCard, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.witsLine, lineWidth: 1.5))
                }
                .buttonStyle(PressScale())
                Button(action: onMap) {
                    Text("back to map")
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.witsMuted)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .rise(0.36)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.witsBg.ignoresSafeArea())
        .overlay {
            if improved && passed {
                ConfettiBurst().ignoresSafeArea()
            }
        }
    }

    private var headline: String {
        switch (passed, stars, improved) {
        case (false, _, _): "not this time — the level isn't going anywhere."
        case (true, 3, true): "flawless. that's the whole star line."
        case (true, _, true): "new best on this level."
        case (true, 3, false): "still perfect."
        default: "cleared — stars to spare up there."
        }
    }
}

// MARK: - Marathon death

struct MarathonResultView: View {
    let game: GameID
    let depth: Int          // last level cleared this run
    let score: Int
    let startLevel: Int
    let best: MarathonBest?
    let isNewBest: Bool
    let onRunAgain: () -> Void
    let onMap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Label("marathon", systemImage: "infinity")
                .font(.witsLabel(13))
                .foregroundStyle(game.domain.color)
                .rise()

            Text(depth >= startLevel ? "level \(depth)" : "level \(startLevel)")
                .font(.witsDisplay(46))
                .foregroundStyle(Color.witsInk)
                .monospacedDigit()
                .padding(.top, 6)
                .rise(0.06)

            Text(framing)
                .font(.witsBody(15.5))
                .foregroundStyle(isNewBest ? Color.witsAccent : Color.witsMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .rise(0.12)

            HStack(spacing: 12) {
                statTile(value: "\(score)", label: "score")
                if let best {
                    statTile(value: "\(max(best.depth, depth))", label: "best level")
                }
            }
            .padding(.top, 24)
            .rise(0.2)

            Spacer()

            VStack(spacing: 11) {
                Cta(title: "run it back", action: onRunAgain)
                Button(action: onMap) {
                    Text("back to map")
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.witsMuted)
                }
                .buttonStyle(.plain)
            }
            .rise(0.3)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.witsBg.ignoresSafeArea())
        .overlay {
            if isNewBest {
                ConfettiBurst().ignoresSafeArea()
            }
        }
    }

    private var framing: String {
        if isNewBest { return "new personal best." }
        guard let best, best.depth > depth else {
            return "the ramp always wins eventually."
        }
        let gap = best.depth - depth
        return gap <= 3
            ? "\(gap) \(gap == 1 ? "level" : "levels") short of your best."
            : "your best is level \(best.depth). it's waiting."
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsInk)
                .monospacedDigit()
            Text(label)
                .font(.witsLabel(12))
                .foregroundStyle(Color.witsMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .cardSurface()
    }
}
