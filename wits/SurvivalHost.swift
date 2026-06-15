//
//  SurvivalHost.swift
//  wits
//
//  Endless arcade mode for one game: 3 lives, a combo you lose on any miss, a
//  single chase-able score, and instant tap-to-retry. Fair-but-brutal — every
//  loss is the player's own. Never touches the adaptive staircase: it persists a
//  survival best via AppModel.recordSurvivalRun.
//

import SwiftUI

struct SurvivalHost: View {
    let game: GameID
    let seedDifficulty: DifficultyState
    let stats: GameStats?
    /// (score, trials) → persist best + tagged session.
    let onRunComplete: (Int, Int) -> Void
    let onQuit: () -> Void

    init(game: GameID, seedDifficulty: DifficultyState, stats: GameStats?,
         onRunComplete: @escaping (Int, Int) -> Void, onQuit: @escaping () -> Void,
         startImmediately: Bool = false) {
        self.game = game
        self.seedDifficulty = seedDifficulty
        self.stats = stats
        self.onRunComplete = onRunComplete
        self.onQuit = onQuit
        _phase = State(initialValue: startImmediately ? .playing : .card)
    }

    private enum Phase: Equatable { case card, playing, gameOver }

    @State private var phase: Phase
    @State private var runID = 0
    @State private var lives = 3
    @State private var score = 0
    @State private var combo = 0
    @State private var trials = 0
    @State private var lastScore = 0
    @State private var newBest = false
    @State private var shakeTick = 0
    @State private var flashTick = 0

    private var multiplier: Int { min(8, 1 + combo / 3) }
    private var best: Int { stats?.survivalBest ?? 0 }

    var body: some View {
        ZStack {
            Color.witsBg.ignoresSafeArea()
            switch phase {
            case .card:
                GameCard(game: game, stats: stats, primaryTitle: "start survival",
                         onPlay: startRun, onBack: onQuit)
            case .playing:
                VStack(spacing: 10) {
                    ComboHUD(score: score, combo: combo, multiplier: multiplier,
                             lives: lives, maxLives: 3)
                        .padding(.top, 8)
                    makeGameView(game, config: .survival(game, difficulty: seedDifficulty,
                                                          onOutcome: handle)) { _ in }
                        .id(runID)
                }
                .witsShake(trigger: shakeTick)
                .witsFlash(.witsWarm, trigger: flashTick)
            case .gameOver:
                gameOver
            }
        }
        .overlay(alignment: .topLeading) {
            if phase == .playing {
                Button(action: onQuit) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Color.witsFaint)
                        .padding(12)
                }
                .padding(.top, 44)
            }
        }
        .onAppear { GameFeel.shared.warmUp() }
        .onDisappear { GameFeel.shared.teardown() }
    }

    // MARK: Outcome handling (host owns lives/combo/score)

    private func handle(_ o: TrialOutcome) {
        guard phase == .playing else { return }
        switch o.kind {
        case .hit:
            combo += 1
            trials += 1
            score += o.points * multiplier
            GameFeel.shared.play(.correct(combo: combo))
            if combo % 5 == 0 { GameFeel.shared.play(.comboMilestone(combo)) }
        case .nearMiss:
            GameFeel.shared.play(.nearMiss)
            flashTick += 1
            loseLife()
        case .miss:
            GameFeel.shared.play(.wrong)
            shakeTick += 1; flashTick += 1
            loseLife()
        case .timeout:
            GameFeel.shared.play(.timeout)
            shakeTick += 1
            loseLife()
        }
    }

    private func loseLife() {
        trials += 1
        combo = 0
        lives -= 1
        if lives > 0 { GameFeel.shared.play(.lifeLost(remaining: lives)) }
        if lives <= 0 { endRun() }
    }

    private func startRun() {
        lives = 3; score = 0; combo = 0; trials = 0
        runID += 1
        withAnimation(.easeOut(duration: 0.2)) { phase = .playing }
    }

    private func endRun() {
        lastScore = score
        newBest = score > best
        GameFeel.shared.play(newBest ? .newBest : .gameOver)
        onRunComplete(score, trials)
        withAnimation(.easeOut(duration: 0.25)) { phase = .gameOver }
    }

    // MARK: Game over

    private var gameOver: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: game.symbol)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(Color.witsAccent)
                Text(game.displayName)
                    .font(.witsBody(15, weight: .semibold))
                    .foregroundStyle(Color.witsMuted)
                if newBest {
                    Text("NEW BEST")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .kerning(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.witsWarm, in: Capsule())
                        .padding(.top, 2)
                }
                Text("\(lastScore)")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                    .monospacedDigit()
                Text("best \(max(best, lastScore))")
                    .font(.witsBody(15, weight: .semibold))
                    .foregroundStyle(Color.witsMuted)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .cardSurface()
            .rise()
            Spacer()
            Cta(title: "play again", action: startRun)
                .rise(0.1)
            QuietButton(title: "done", action: onQuit)
                .padding(.top, 6)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 16)
    }
}
