//
//  ArrowStormGame.swift
//  wits
//
//  Arrow storm (Eriksen flanker task — interference control), played as an
//  endless run. Five arrows flash; only the middle one matters and the
//  flankers usually disagree. Pick a speed mode, then answer trial after
//  trial against a deadline that tightens as you score. Three hearts: a
//  wrong tap or a timeout costs one. Out of hearts, a rewarded ad buys one
//  last life — the hearts stay grey, and the next slip ends the run for good.
//

import SwiftUI

// MARK: - Mode select

/// Arrow storm's pre-game screen: no levels, just the three speed modes with
/// their own bests and the all-time best underneath.
struct ArrowStormModeSelectView: View {
    var onPlay: (ChallengeDifficulty) -> Void
    var onClose: () -> Void

    @Environment(AppModel.self) private var app

    private let game = GameID.arrowStorm
    private var world: GameWorld { game.world }
    private let modes: [ChallengeDifficulty] = [.easy, .medium, .hard]

    var body: some View {
        ZStack {
            GameWorldBackdrop(game: game)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack {
                        iconButton("chevron.left", label: "Close", action: onClose)
                        Spacer()
                        Text(game.subskill.uppercased())
                            .font(.system(size: 10.5, weight: .black, design: world.bodyDesign))
                            .foregroundStyle(world.muted)
                        Spacer()
                        Color.clear.frame(width: 44, height: 44)
                    }
                    .padding(.top, 10)

                    GamePosterArt(game: game)
                        .frame(height: 250)
                        .frame(maxWidth: 440)

                    Text(game.worldTitle())
                        .font(.system(size: 44, weight: .black, design: world.titleDesign))
                        .foregroundStyle(world.ink)
                    Text(game.tagline)
                        .font(.system(size: 14.5, weight: .semibold, design: world.bodyDesign))
                        .foregroundStyle(world.muted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 7)

                    VStack(spacing: 11) {
                        ForEach(modes) { mode in
                            modeButton(mode)
                        }
                    }
                    .padding(.top, 28)

                    if allTimeBest > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 11, weight: .black))
                                .foregroundStyle(world.accent)
                            Text("ALL TIME BEST · \(allTimeBest)")
                                .font(.system(size: 12, weight: .black, design: world.bodyDesign))
                                .foregroundStyle(world.ink)
                                .monospacedDigit()
                        }
                        .padding(.top, 18)
                    }
                }
                .padding(.bottom, 30)
                .padding(.horizontal, 22)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var allTimeBest: Int {
        app.levels.marathonBest(for: game)?.score ?? 0
    }

    private func modeButton(_ mode: ChallengeDifficulty) -> some View {
        let color = world.difficultyColor(mode)
        let best = app.levels.modeBest(for: game, difficulty: mode)
        return Button { onPlay(mode) } label: {
            HStack(spacing: 14) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 24, weight: .black))
                    .frame(width: 45)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(mode.shortTitle.uppercased()) MODE")
                        .font(.system(size: 18, weight: .black, design: world.titleDesign))
                    Text(best > 0 ? "best · \(best)" : "no runs yet")
                        .font(.system(size: 11.5, weight: .bold, design: world.bodyDesign))
                        .opacity(0.72)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .black))
                    .opacity(0.7)
            }
            .foregroundStyle(world.background)
            .padding(.horizontal, 17)
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(PressScale())
        .shadow(color: color.opacity(0.22), radius: 10, y: 5)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(world.ink)
                .frame(width: 44, height: 44)
                .background(world.surface, in: Circle())
                .overlay(Circle().strokeBorder(world.accent.opacity(0.42), lineWidth: 1))
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(label)
    }
}

// MARK: - Screen

struct ArrowStormScreen: View {
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
    }

    private static func tuning(for difficulty: ChallengeDifficulty) -> Tuning {
        switch difficulty {
        case .easy: Tuning(startWindow: 1.5, minWindow: 0.9, shrink: 0.015, easeBack: 0.12)
        case .medium: Tuning(startWindow: 1.2, minWindow: 0.72, shrink: 0.02, easeBack: 0.1)
        default: Tuning(startWindow: 1.0, minWindow: 0.58, shrink: 0.025, easeBack: 0.08)
        }
    }

    private var tuning: Tuning { Self.tuning(for: difficulty) }

    private struct Trial: Identifiable {
        let id = UUID()
        let right: Bool       // center arrow direction
        let congruent: Bool
        let yShift: CGFloat
    }

    private static func makeTrial<R: RandomNumberGenerator>(using rng: inout R) -> Trial {
        Trial(right: Bool.random(using: &rng),
              congruent: Double.random(in: 0..<1, using: &rng) < 0.35,
              yShift: CGFloat.random(in: -34...34, using: &rng))
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
        var rng = SystemRandomNumberGenerator()
        _trial = State(initialValue: Self.makeTrial(using: &rng))
        let start = Self.tuning(for: difficulty).startWindow
        _window = State(initialValue: start)
        _trialRemaining = State(initialValue: start)
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

    private var world: GameWorld { GameID.arrowStorm.world }

    var body: some View {
        ZStack {
            GameWorldBackdrop(game: .arrowStorm, patternOpacity: 0.35)
            // The playing view stays mounted behind the game-over card so the
            // final trial sits dimmed under the scrim.
            playing
            if phase == .over { runOver }
        }
        .overlay {
            if phase == .playing, pauseController.isPaused {
                GamePausedOverlay(game: .arrowStorm,
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
            hud
                .padding(.horizontal, 16)
                .padding(.top, 10)

            heartsRow
                .padding(.top, 14)

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
                    .padding(.horizontal, WitsMetrics.screenPadding)
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
            .padding(.horizontal, WitsMetrics.screenPadding)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .allowsHitTesting(phase == .playing && !pauseController.isPaused)
        .task(id: runID) { await runLoop() }
    }

    private var hud: some View {
        HStack(spacing: 10) {
            Button(action: onQuit) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(world.ink)
                    .frame(width: 44, height: 44)
                    .background(world.surface.opacity(0.9), in: Circle())
            }
            .buttonStyle(PressScale())
            .accessibilityLabel("quit run")

            Spacer(minLength: 0)

            hudChip(title: "\(difficulty.shortTitle.uppercased()) MODE",
                    value: score,
                    tint: world.ink,
                    crowned: false)
            hudChip(title: "ALL TIME",
                    value: max(allTimeBest, score),
                    tint: world.accent,
                    crowned: true)

            Spacer(minLength: 0)

            Button { pauseController.pause() } label: {
                Image(systemName: "pause.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(world.ink)
                    .frame(width: 44, height: 44)
                    .background(world.surface.opacity(0.9), in: Circle())
            }
            .buttonStyle(PressScale())
            .accessibilityLabel("pause game")
        }
    }

    private func hudChip(title: String, value: Int, tint: Color, crowned: Bool) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 10.5, weight: .black, design: world.bodyDesign))
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(String(value))
                .font(.system(size: 21, weight: .black, design: world.titleDesign))
                .foregroundStyle(tint)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: value)
        }
        .frame(minWidth: 108)
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .background(world.surface.opacity(0.9),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(alignment: .top) {
            if crowned {
                Image(systemName: "crown.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(world.accent)
                    .offset(y: -12)
            }
        }
    }

    private static let heartColor = Color(hexAny: 0xEF476F)

    /// After a rewarded continue every heart shows grey — the player is
    /// running on their last life.
    private var heartsRow: some View {
        HStack(spacing: 9) {
            ForEach(0..<Self.maxLives, id: \.self) { i in
                Image(systemName: i < lives ? "heart.fill" : "heart")
                    .font(.system(size: 21, weight: .black))
                    .foregroundStyle(i < lives ? Self.heartColor : world.muted.opacity(0.45))
                    .scaleEffect(i < lives ? 1 : 0.88)
                    .animation(.snappy(duration: 0.25), value: lives)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(usedContinue ? "last life" : "\(lives) of \(Self.maxLives) lives left")
    }

    // MARK: Trial card

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

    // MARK: Trial flow

    private func answer(_ saysRight: Bool) {
        guard phase == .playing, let current = trial else { return }
        if saysRight == current.right {
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
            trial = Self.makeTrial(using: &rng)
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
        var continueAction: (() -> Void)?
        if canContinue { continueAction = { continueRun() } }
        return GameRunOverView(game: .arrowStorm,
                        contextTitle: "\(difficulty.shortTitle) mode",
                        badgeSymbol: difficulty.symbol,
                        score: score,
                        caption: "best streak \(bestStreak)",
                        bests: RunBestLine.standard(today: max(todayBest, sessionBest),
                                                    week: max(weekBest, sessionBest),
                                                    allTime: max(allTimeBest, sessionBest)),
                        celebrate: newAllTimeBest && !canContinue,
                        onContinue: continueAction,
                        continueBusy: adBusy,
                        onHome: {
                            finalizeRun()
                            onQuit()
                        },
                        onPlayAgain: playAgain)
    }

    private func continueRun() {
        guard !adBusy else { return }
        adBusy = true
        AdManager.shared.showRewarded { earned in
            adBusy = false
            guard earned else { return }   // closed early — offer stays on the table
            usedContinue = true
            canContinue = false
            feedback = nil
            window = min(tuning.startWindow, window + tuning.easeBack)
            pauseController.reset()
            nextTrial()
            withAnimation(.easeOut(duration: 0.2)) { phase = .playing }
            // Count the player back in — the trial clock stays frozen until
            // the 3…2…1 finishes.
            pauseController.pause()
            pauseController.beginResumeCountdown()
        }
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
