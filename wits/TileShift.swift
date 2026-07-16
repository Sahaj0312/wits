//
//  TileShift.swift
//  wits
//
//  Task switching, played as an endless run. Match the target by the rule on
//  screen — colour or shape — and the rule keeps flipping. Pick a mode, then
//  answer trial after trial against a deadline that tightens as you score.
//  Three hearts: a wrong tap or a timeout costs one. Out of hearts, a
//  rewarded ad buys one last life — the hearts stay grey, and the next slip
//  ends the run for good.
//

import SwiftUI

private let tileShapes = ["circle.fill", "square.fill", "triangle.fill"]
private let tileColors: [Color] = [
    Color(red: 0.09, green: 0.70, blue: 0.64),
    Color(red: 0.94, green: 0.47, blue: 0.37),
    Color(red: 0.95, green: 0.74, blue: 0.16),
]

struct TileShiftScreen: View {
    let difficulty: ChallengeDifficulty
    let modeBest: Int
    let allTimeBest: Int
    var todayBest: Int = 0
    var weekBest: Int = 0
    /// (score, best streak, misses) → persist.
    let onRunComplete: (Int, Int, Int) -> Void
    let onQuit: () -> Void

    private static let maxLives = 3

    private struct Tuning {
        let startWindow: Double   // seconds to answer, at the start of a run
        let minWindow: Double     // the deadline never tightens past this
        let shrink: Double        // deadline lost per correct answer
        let easeBack: Double      // breather given back after a miss
        let pSwitch: Double       // chance the rule flips between trials
    }

    private static func tuning(for difficulty: ChallengeDifficulty) -> Tuning {
        switch difficulty {
        case .easy: Tuning(startWindow: 2.1, minWindow: 1.1, shrink: 0.02, easeBack: 0.2, pSwitch: 0.35)
        case .medium: Tuning(startWindow: 1.8, minWindow: 0.9, shrink: 0.025, easeBack: 0.16, pSwitch: 0.5)
        default: Tuning(startWindow: 1.5, minWindow: 0.75, shrink: 0.03, easeBack: 0.12, pSwitch: 0.65)
        }
    }

    private var tuning: Tuning { Self.tuning(for: difficulty) }

    private struct Tile: Equatable { var shape: Int; var color: Int }
    private struct Round: Identifiable {
        let id = UUID()
        let byColor: Bool
        let target: Tile
        let options: [Tile]
        let correct: Int
    }

    private static func make<R: RandomNumberGenerator>(byColor: Bool, using rng: inout R) -> Round {
        let target = Tile(shape: .random(in: 0..<3, using: &rng),
                          color: .random(in: 0..<3, using: &rng))
        // correct matches target on the active dimension, differs on the other
        var correct = target
        if byColor { correct.shape = (target.shape + Int.random(in: 1...2, using: &rng)) % 3 }
        else { correct.color = (target.color + Int.random(in: 1...2, using: &rng)) % 3 }
        // distractor differs on the active dimension
        var distractor = target
        if byColor {
            distractor.color = (target.color + Int.random(in: 1...2, using: &rng)) % 3
            distractor.shape = .random(in: 0..<3, using: &rng)
        } else {
            distractor.shape = (target.shape + Int.random(in: 1...2, using: &rng)) % 3
            distractor.color = .random(in: 0..<3, using: &rng)
        }
        let correctFirst = Bool.random(using: &rng)
        let options = correctFirst ? [correct, distractor] : [distractor, correct]
        return Round(byColor: byColor, target: target, options: options, correct: correctFirst ? 0 : 1)
    }

    init(difficulty: ChallengeDifficulty,
         modeBest: Int,
         allTimeBest: Int,
         todayBest: Int = 0,
         weekBest: Int = 0,
         onRunComplete: @escaping (Int, Int, Int) -> Void,
         onQuit: @escaping () -> Void) {
        self.difficulty = difficulty
        self.modeBest = modeBest
        self.allTimeBest = allTimeBest
        self.todayBest = todayBest
        self.weekBest = weekBest
        self.onRunComplete = onRunComplete
        self.onQuit = onQuit
        let t = Self.tuning(for: difficulty)
        var rng = SystemRandomNumberGenerator()
        _round = State(initialValue: Self.make(byColor: Bool.random(using: &rng), using: &rng))
        _window = State(initialValue: t.startWindow)
        _trialRemaining = State(initialValue: t.startWindow)
    }

    @State private var rng = SystemRandomNumberGenerator()
    @State private var phase: Phase = .playing
    @State private var pauseController = GamePauseController()

    @State private var round: Round
    @State private var window: Double
    @State private var trialRemaining: Double
    @State private var windowFrac = 1.0
    @State private var feedback: Bool?

    @State private var score = 0
    @State private var streak = 0
    @State private var bestStreak = 0
    @State private var misses = 0
    @State private var lives = maxLives

    /// One rewarded continue per run: hearts stay empty afterwards, and the
    /// next mistake ends the run with no second offer.
    @State private var usedContinue = false
    @State private var canContinue = false
    @State private var adBusy = false
    /// The run isn't recorded while a continue offer is on the table.
    @State private var runRecorded = true

    @State private var newAllTimeBest = false
    /// Best across every run since this screen opened, so the bests rows stay
    /// honest through PLAY AGAIN loops.
    @State private var sessionBest = 0
    /// Bumped on PLAY AGAIN so the run loop restarts fresh.
    @State private var runID = 0

    private enum Phase { case playing, over }

    private var world: GameWorld { GameID.tileShift.world }

    var body: some View {
        ZStack {
            GameWorldBackdrop(game: .tileShift, patternOpacity: 0.35)
            // The playing view stays mounted behind the game-over card so the
            // final trial sits dimmed under the scrim.
            playing
            if phase == .over {
                if canContinue {
                    RewardedReviveOffer(game: .tileShift,
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
                GamePausedOverlay(game: .tileShift,
                                  controller: pauseController,
                                  onQuit: {
                                      pauseController.reset()
                                      onQuit()
                                  })
            }
        }
        .onAppear { GameFeel.shared.warmUp() }
        .onDisappear {
            pauseController.reset()
            GameFeel.shared.teardown()
        }
    }

    // MARK: Playing

    private var playing: some View {
        VStack(spacing: 0) {
            EndlessRunHUD(game: .tileShift,
                          difficulty: difficulty,
                          score: score,
                          allTimeBest: allTimeBest,
                          onQuit: onQuit,
                          onPause: { pauseController.pause() })
                .padding(.horizontal, 16)
                .padding(.top, 10)

            EndlessHeartsRow(game: .tileShift,
                             lives: lives,
                             maxLives: Self.maxLives,
                             usedContinue: usedContinue)
                .padding(.top, 14)

            Text(round.byColor ? "MATCH THE COLOUR" : "MATCH THE SHAPE")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .kerning(1)
                .foregroundStyle(round.byColor ? world.accent : world.secondary)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background((round.byColor ? world.accent : world.secondary).opacity(0.14), in: Capsule())
                .padding(.top, 18)

            Spacer()

            tileView(round.target)
                .frame(width: 120, height: 120)
                .background(world.surface, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(world.ink.opacity(0.12), lineWidth: 1))
                .id(round.id)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(feedback == true ? world.accent : feedback == false ? world.secondary : .clear, lineWidth: 2.5)
                        .padding(-10)
                )

            // per-trial deadline
            ZStack(alignment: .leading) {
                Capsule().fill(world.surface)
                GeometryReader { geo in
                    Capsule().fill(windowFrac < 0.35 ? world.secondary : world.muted)
                        .frame(width: max(0, geo.size.width * windowFrac))
                }
            }
            .frame(width: 130, height: 4)
            .padding(.top, 14)

            Spacer()

            HStack(spacing: 12) {
                ForEach(0..<2, id: \.self) { i in
                    Button { answer(i) } label: {
                        tileView(round.options[i])
                            .frame(maxWidth: .infinity).frame(height: 110)
                            .background(world.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, EndlessMetrics.sidePadding)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .allowsHitTesting(phase == .playing && !pauseController.isPaused)
        .task(id: runID) { await runLoop() }
    }

    private func tileView(_ t: Tile) -> some View {
        Image(systemName: tileShapes[t.shape])
            .font(.system(size: 46, weight: .heavy))
            .foregroundStyle(tileColors[t.color])
    }

    // MARK: Trial flow

    private func answer(_ i: Int) {
        guard phase == .playing else { return }
        if i == round.correct {
            score += 1
            streak += 1
            bestStreak = max(bestStreak, streak)
            window = max(tuning.minWindow, window - tuning.shrink)
            feedback = true
            GameFeel.shared.play(.correct(combo: streak))
            if !newAllTimeBest, score > allTimeBest, allTimeBest > 0 {
                newAllTimeBest = true
                GameFeel.shared.play(.newBest)
            }
            clearFeedbackSoon()
            next()
        } else {
            mistake()
        }
    }

    private func timeout() {
        guard phase == .playing else { return }
        mistake()
    }

    private func mistake() {
        misses += 1
        streak = 0
        window = min(tuning.startWindow, window + tuning.easeBack)
        feedback = false
        clearFeedbackSoon()
        if lives > 0 { lives -= 1 }
        if lives == 0 {
            GameFeel.shared.play(.lifeLost(remaining: 0))
            endRun()
        } else {
            GameFeel.shared.play(.lifeLost(remaining: lives))
            next()
        }
    }

    private func clearFeedbackSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { feedback = nil }
    }

    private func next() {
        let nextByColor = Double.random(in: 0..<1, using: &rng) < tuning.pSwitch
            ? !round.byColor : round.byColor
        withAnimation(.easeOut(duration: 0.12)) {
            round = Self.make(byColor: nextByColor, using: &rng)
        }
        trialRemaining = window
        windowFrac = 1
    }

    private func runLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(30))
            guard phase == .playing, !pauseController.isPaused else { continue }
            trialRemaining -= 0.03
            windowFrac = max(0, trialRemaining / window)
            if trialRemaining <= 0 { timeout() }
        }
    }

    // MARK: Run lifecycle

    private func endRun() {
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
        onRunComplete(score, bestStreak, misses)
    }

    private var runOver: some View {
        GameRunOverView(game: .tileShift,
                               contextTitle: "\(difficulty.shortTitle) mode",
                               badgeSymbol: difficulty.symbol,
                               score: score,
                               caption: "best streak \(bestStreak)",
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
            feedback = nil
            window = min(tuning.startWindow, window + tuning.easeBack)
            pauseController.reset()
            next()
            withAnimation(.easeOut(duration: 0.2)) { phase = .playing }
            // Count the player back in — the trial clock stays frozen until
            // the 3…2…1 finishes.
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
        streak = 0
        bestStreak = 0
        misses = 0
        lives = Self.maxLives
        usedContinue = false
        canContinue = false
        newAllTimeBest = false
        feedback = nil
        window = tuning.startWindow
        pauseController.reset()
        next()
        runID += 1
        withAnimation(.easeOut(duration: 0.2)) { phase = .playing }
    }
}
