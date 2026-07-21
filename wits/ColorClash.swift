//
//  ColorClash.swift
//  wits
//
//  Stroop task, tap the colour the word is printed in, not the word itself.
//  Targets cognitive flexibility / interference control, played as an endless
//  run. Pick a speed mode, then answer trial after trial against a deadline
//  that tightens as you score. Three hearts: a wrong tap or a timeout costs
//  one. Out of hearts, a rewarded ad buys one last life, the hearts stay
//  grey, and the next slip ends the run for good.
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

// MARK: - Screen

struct ColorClashScreen: View {
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
        let pIncongruent: Double  // share of trials where word and ink disagree
    }

    private static func tuning(for difficulty: ChallengeDifficulty) -> Tuning {
        switch difficulty {
        case .easy: Tuning(startWindow: 1.6, minWindow: 0.95, shrink: 0.015, easeBack: 0.12, pIncongruent: 0.5)
        case .medium: Tuning(startWindow: 1.3, minWindow: 0.75, shrink: 0.02, easeBack: 0.1, pIncongruent: 0.65)
        default: Tuning(startWindow: 1.05, minWindow: 0.6, shrink: 0.025, easeBack: 0.08, pIncongruent: 0.8)
        }
    }

    private var tuning: Tuning { Self.tuning(for: difficulty) }

    private struct Trial: Identifiable {
        let id = UUID()
        let word: StroopColor   // the text
        let ink: StroopColor    // the colour it's drawn in (the answer)
    }

    private static func makeTrial<R: RandomNumberGenerator>(pIncongruent: Double,
                                                            using rng: inout R) -> Trial {
        let word = StroopColor.allCases.randomElement(using: &rng)!
        let incongruent = Double.random(in: 0..<1, using: &rng) < pIncongruent
        let ink = incongruent
            ? StroopColor.allCases.filter { $0 != word }.randomElement(using: &rng)!
            : word
        return Trial(word: word, ink: ink)
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
        _trial = State(initialValue: Self.makeTrial(pIncongruent: t.pIncongruent, using: &rng))
        _window = State(initialValue: t.startWindow)
        _trialRemaining = State(initialValue: t.startWindow)
    }

    @State private var rng = SystemRandomNumberGenerator()
    @State private var phase: Phase = .playing
    @State private var pauseController = GamePauseController()

    @State private var trial: Trial?
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

    private var world: GameWorld { GameID.colorClash.world }

    var body: some View {
        ZStack {
            GameWorldBackdrop(game: .colorClash, patternOpacity: 0.35)
            // The playing view stays mounted behind the game-over card so the
            // final trial sits dimmed under the scrim.
            playing
            if phase == .over {
                if canContinue {
                    RewardedReviveOffer(game: .colorClash,
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
                GamePausedOverlay(game: .colorClash,
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
            EndlessRunHUD(game: .colorClash,
                          difficulty: difficulty,
                          score: score,
                          allTimeBest: allTimeBest,
                          onQuit: onQuit,
                          onPause: { pauseController.pause() })
                .padding(.horizontal, 16)
                .padding(.top, 10)

            EndlessHeartsRow(game: .colorClash,
                             lives: lives,
                             maxLives: Self.maxLives,
                             usedContinue: usedContinue)
                .padding(.top, 14)

            Spacer()

            if let trial {
                trialCard(trial)
                    .id(trial.id)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(
                                feedback == true ? world.secondary : feedback == false ? world.accent : .clear,
                                lineWidth: 2.5
                            )
                            .padding(-14)
                    )
                    .padding(.horizontal, EndlessMetrics.sidePadding)
                // per-trial deadline
                ZStack(alignment: .leading) {
                    Capsule().fill(world.raised)
                    GeometryReader { geo in
                        Capsule()
                            .fill(windowFrac < 0.35 ? world.accent : world.muted)
                            .frame(width: max(0, geo.size.width * windowFrac))
                    }
                }
                .frame(width: 130, height: 4)
                .padding(.top, 18)
            }

            Spacer()

            colorButtons
                .padding(.horizontal, EndlessMetrics.sidePadding)
                .padding(.top, 16)
                .padding(.bottom, 12)
        }
        .allowsHitTesting(phase == .playing && !pauseController.isPaused)
        .task(id: runID) { await runLoop() }
    }

    // MARK: Trial card

    private func trialCard(_ t: Trial) -> some View {
        VStack(spacing: 6) {
            Text(t.word.rawValue)
                .font(.system(size: 52, weight: .heavy, design: .rounded))
                .foregroundStyle(t.ink.color)
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .background(world.surface, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(world.ink.opacity(0.12), lineWidth: 1))
            Text("TAP THE COLOUR, NOT THE WORD")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(0.7)
                .foregroundStyle(world.muted)
        }
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
                        .background(c.color, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Trial flow

    private func answer(_ c: StroopColor) {
        guard phase == .playing, let current = trial else { return }
        if c == current.ink {
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
            nextTrial()
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
            nextTrial()
        }
    }

    private func clearFeedbackSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { feedback = nil }
    }

    private func nextTrial() {
        withAnimation(.easeOut(duration: 0.13)) {
            trial = Self.makeTrial(pIncongruent: tuning.pIncongruent, using: &rng)
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
        // A continue offer defers recording, the run isn't over until the
        // player passes on it. No offer → record right away.
        canContinue = !usedContinue && AdManager.shared.rewardedReady
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
        GameRunOverView(game: .colorClash,
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
            guard earned else { return }   // closed early, offer stays on the table
            usedContinue = true
            canContinue = false
            feedback = nil
            window = min(tuning.startWindow, window + tuning.easeBack)
            pauseController.reset()
            nextTrial()
            withAnimation(.easeOut(duration: 0.2)) { phase = .playing }
            // Count the player back in, the trial clock stays frozen until
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
        nextTrial()
        runID += 1
        withAnimation(.easeOut(duration: 0.2)) { phase = .playing }
    }
}
