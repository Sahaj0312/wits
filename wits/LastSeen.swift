//
//  LastSeen.swift
//  wits
//
//  Short-term memory, played as an endless run. Tap each object once — never
//  one you've already chosen. The board reshuffles every pick and grows as
//  you clear it. Pick a mode (starting set size), then keep going: every new
//  object is a point. Three hearts: tapping something you already chose costs
//  one. Out of hearts, a rewarded ad buys one last life — the hearts stay
//  grey, and the next repeat ends the run for good.
//
//  No clock, deliberately: stalling earns nothing in an endless run, so the
//  pressure is pure memory load.
//

import SwiftUI

private let lastSeenPool = ["star.fill", "heart.fill", "bolt.fill", "leaf.fill", "flame.fill",
                            "drop.fill", "moon.fill", "sun.max.fill", "cloud.fill", "bell.fill",
                            "gift.fill", "crown.fill", "pawprint.fill", "camera.fill"]

struct LastSeenScreen: View {
    let difficulty: ChallengeDifficulty
    let modeBest: Int
    let allTimeBest: Int
    var todayBest: Int = 0
    var weekBest: Int = 0
    /// (score, best set remembered, misses) → persist.
    let onRunComplete: (Int, Int, Int) -> Void
    let onQuit: () -> Void

    private static let maxLives = 3

    /// Mode sets the opening memory load; every cleared set grows by one
    /// toward the full pool.
    private static func startSize(for difficulty: ChallengeDifficulty) -> Int {
        switch difficulty {
        case .easy: 3
        case .medium: 5
        default: 7
        }
    }

    @State private var rng = SystemRandomNumberGenerator()
    @State private var phase: Phase = .playing
    @State private var pauseController = GamePauseController()

    @State private var icons: [Int] = []         // symbol indices in play
    @State private var order: [Int] = []         // shuffled display order
    @State private var tapped: Set<Int> = []     // symbol indices already chosen
    @State private var flash: (idx: Int, ok: Bool)?

    @State private var score = 0
    @State private var bestRemembered = 0
    @State private var misses = 0
    @State private var lives = maxLives

    /// One rewarded continue per run: hearts stay empty afterwards, and the
    /// next repeat ends the run with no second offer.
    @State private var usedContinue = false
    @State private var canContinue = false
    @State private var adBusy = false
    /// The run isn't recorded while a continue offer is on the table.
    @State private var runRecorded = true

    @State private var newAllTimeBest = false
    /// Best across every run since this screen opened, so the bests rows stay
    /// honest through PLAY AGAIN loops.
    @State private var sessionBest = 0

    private enum Phase { case playing, over }

    private var world: GameWorld { GameID.lastSeen.world }

    var body: some View {
        ZStack {
            GameWorldBackdrop(game: .lastSeen, patternOpacity: 0.35)
            // The playing view stays mounted behind the game-over card so the
            // final board sits dimmed under the scrim.
            playing
            if phase == .over {
                if canContinue {
                    RewardedReviveOffer(game: .lastSeen,
                                        busy: adBusy,
                                        onDecline: declineContinue,
                                        onSave: continueRun)
                } else {
                    runOver
                }
            }
        }
        .overlay {
            if phase == .playing, pauseController.isPaused {
                GamePausedOverlay(game: .lastSeen,
                                  controller: pauseController,
                                  onQuit: {
                                      pauseController.reset()
                                      onQuit()
                                  })
            }
        }
        .onAppear {
            GameFeel.shared.warmUp()
            if icons.isEmpty { startSet(size: Self.startSize(for: difficulty)) }
        }
        .onDisappear {
            pauseController.reset()
            GameFeel.shared.teardown()
        }
    }

    // MARK: Playing

    private var playing: some View {
        VStack(spacing: 0) {
            EndlessRunHUD(game: .lastSeen,
                          difficulty: difficulty,
                          score: score,
                          allTimeBest: allTimeBest,
                          onQuit: onQuit,
                          onPause: { pauseController.pause() })
                .padding(.horizontal, 16)
                .padding(.top, 10)

            EndlessHeartsRow(game: .lastSeen,
                             lives: lives,
                             maxLives: Self.maxLives,
                             usedContinue: usedContinue)
                .padding(.top, 14)

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
            .padding(.horizontal, EndlessMetrics.sidePadding)

            Text("tap one you haven't tapped yet · \(tapped.count) of \(icons.count) found")
                .font(.system(size: 12.5, weight: .semibold, design: world.bodyDesign))
                .foregroundStyle(world.muted)
                .frame(maxWidth: .infinity)
                .monospacedDigit()
                .padding(.top, 12)

            Spacer()
        }
        .allowsHitTesting(phase == .playing && !pauseController.isPaused)
    }

    // MARK: Set flow

    private func startSet(size: Int) {
        let s = min(lastSeenPool.count, size)
        icons = Array(lastSeenPool.indices.shuffled(using: &rng).prefix(s))
        tapped = []
        reshuffle()
    }

    private func reshuffle() { order = icons.shuffled(using: &rng) }

    private func tap(_ iconID: Int) {
        guard phase == .playing else { return }
        if tapped.contains(iconID) {
            mistake(on: iconID)
            return
        }
        tapped.insert(iconID)
        score += 1
        bestRemembered = max(bestRemembered, tapped.count)
        flash = (iconID, true)
        GameFeel.shared.play(.correct(combo: tapped.count))
        if !newAllTimeBest, score > allTimeBest, allTimeBest > 0 {
            newAllTimeBest = true
            GameFeel.shared.play(.newBest)
        }
        if tapped.count == icons.count {
            // cleared the set — grow it
            let nextSize = icons.count + 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard phase == .playing else { return }
                flash = nil
                startSet(size: nextSize)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            flash = nil
            reshuffle()
        }
    }

    private func mistake(on iconID: Int) {
        misses += 1
        flash = (iconID, false)
        if lives > 0 { lives -= 1 }
        if lives == 0 {
            GameFeel.shared.play(.lifeLost(remaining: 0))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                flash = nil
                endRun()
            }
        } else {
            GameFeel.shared.play(.lifeLost(remaining: lives))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                flash = nil
                reshuffle()
            }
        }
    }

    // MARK: Run lifecycle

    private func endRun() {
        guard phase == .playing else { return }
        pauseController.reset()
        if score > 0, allTimeBest == 0 || score > allTimeBest {
            newAllTimeBest = true
        }
        sessionBest = max(sessionBest, score)
        // A continue offer defers recording — the run isn't over until the
        // player passes on it. No offer → record right away.
        canContinue = !usedContinue
        runRecorded = false
        if !canContinue { finalizeRun() }
        GameFeel.shared.play(.gameOver)
        withAnimation(.easeOut(duration: 0.3)) { phase = .over }
    }

    private func finalizeRun() {
        guard !runRecorded else { return }
        runRecorded = true
        onRunComplete(score, bestRemembered, misses)
    }

    private var runOver: some View {
        GameRunOverView(game: .lastSeen,
                               score: score,
                               caption: "best set \(bestRemembered)",
                               bests: RunBestLine.standard(today: max(todayBest, sessionBest),
                                                           week: max(weekBest, sessionBest),
                                                           allTime: max(allTimeBest, sessionBest)),
                               celebrate: newAllTimeBest,
                               onHome: {
                                   finalizeRun()
                                   onQuit()
                               },
                               onPlayAgain: playAgain)
    }

    private func continueRun() {
        guard !adBusy, canContinue else { return }
        adBusy = true
        AdManager.shared.showRewarded { earned in
            adBusy = false
            guard earned else { return }   // closed early — offer stays on the table
            usedContinue = true
            canContinue = false
            flash = nil
            pauseController.reset()
            // Resume the same set right where it died — the reshuffle keeps
            // the next pick honest.
            reshuffle()
            withAnimation(.easeOut(duration: 0.2)) { phase = .playing }
            // Count the player back in before input unlocks.
            pauseController.pause()
            pauseController.beginResumeCountdown()
        }
    }

    private func declineContinue() {
        withAnimation(.easeOut(duration: 0.2)) { canContinue = false }
        finalizeRun()
    }

    private func playAgain() {
        finalizeRun()
        score = 0
        bestRemembered = 0
        misses = 0
        lives = Self.maxLives
        usedContinue = false
        canContinue = false
        newAllTimeBest = false
        flash = nil
        pauseController.reset()
        startSet(size: Self.startSize(for: difficulty))
        withAnimation(.easeOut(duration: 0.2)) { phase = .playing }
    }
}
