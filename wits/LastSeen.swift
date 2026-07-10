//
//  LastSeen.swift
//  wits
//
//  Short-term memory. Tap each object once — never one you've already chosen.
//  The board reshuffles every pick and grows as you clear it. Adaptive: the
//  starting set size scales with level.
//

import SwiftUI

private let lastSeenPool = ["star.fill", "heart.fill", "bolt.fill", "leaf.fill", "flame.fill",
                            "drop.fill", "moon.fill", "sun.max.fill", "cloud.fill", "bell.fill",
                            "gift.fill", "crown.fill", "pawprint.fill", "camera.fill"]

struct LastSeenScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private static let gameSeconds = 45.0

    @State private var icons: [Int] = []        // symbol indices in play
    @State private var order: [Int] = []         // shuffled display order (indices into icons)
    @State private var tapped: Set<Int> = []     // symbol indices already chosen
    @State private var flash: (idx: Int, ok: Bool)?
    @State private var timeLeft = gameSeconds
    @State private var right = 0
    @State private var wrong = 0
    @State private var bestRemembered = 0
    @State private var score = 0
    @State private var finished = false
    private let startedAt = Date()
    private let level: Double
    private var world: GameWorld { GameID.lastSeen.world }

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        self.level = cfg.difficulty.level
    }

    var body: some View {
        VStack(spacing: 12) {
            if !cfg.isSurvival {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Text("\(score)").foregroundStyle(world.accent)) pts")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(world.ink).monospacedDigit()
                    Spacer()
                    Text("\(Int(ceil(timeLeft)))s")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(world.muted).monospacedDigit()
                }
                ProgressTrack(fraction: timeLeft / Self.gameSeconds, animated: false,
                              tint: world.accent, track: world.raised)
            }
            Spacer()
            let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(order.enumerated()), id: \.offset) { _, iconID in
                    let isFlash = flash?.idx == iconID
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isFlash ? (flash!.ok ? world.secondary.opacity(0.88) : world.accent.opacity(0.88)) : world.surface)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            Image(systemName: lastSeenPool[iconID])
                                .font(.system(size: 26, weight: .heavy))
                                .foregroundStyle(isFlash ? world.background : world.ink)
                        )
                        .shadow(color: world.ink.opacity(0.12), radius: 4, y: 2)
                        .onTapGesture { tap(iconID) }
                }
            }
            Text("tap one you haven't tapped yet")
                .font(.system(size: 12.5, weight: .semibold, design: world.bodyDesign))
                .foregroundStyle(world.muted)
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 24).padding(.bottom, 12)
        .onAppear { if icons.isEmpty { startSet(size: max(3, 3 + Int(level / 2))) } }
        .task { await run() }
    }

    private func startSet(size: Int) {
        let s = min(lastSeenPool.count, size)
        icons = Array(lastSeenPool.indices.shuffled().prefix(s))
        tapped = []
        reshuffle()
    }

    private func reshuffle() { order = icons.shuffled() }

    private func tap(_ iconID: Int) {
        guard !finished else { return }
        if tapped.contains(iconID) {
            wrong += 1
            flash = (iconID, false)
            cfg.report(.miss)
        } else {
            tapped.insert(iconID)
            right += 1
            score += 80
            bestRemembered = max(bestRemembered, tapped.count)
            flash = (iconID, true)
            cfg.report(.hit, points: 80, combo: tapped.count)
            if tapped.count == icons.count {
                // cleared the set — grow it
                score += 200
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    startSet(size: icons.count + 1)
                }
                return
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            flash = nil
            reshuffle()
        }
    }

    private func run() async {
        let start = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(40))
            timeLeft = max(0, Self.gameSeconds - cfg.activeElapsed(since: start))
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
        var r = GameResult(game: .lastSeen, score: score, accuracy: acc)
        r.trials = total
        r.startedAt = startedAt
        r.durationMs = Int(Self.gameSeconds * 1000)
        r.raw = [
            "remembered": Double(bestRemembered),
            "correct": Double(right),
            "wrong": Double(wrong),
            "timeOnTaskMs": Self.gameSeconds * 1000
        ]
        onResult(r)
    }
}
