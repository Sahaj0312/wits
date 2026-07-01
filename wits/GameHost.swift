//
//  GameHost.swift
//  wits
//
//  Drives a daily workout: launches each game at its persisted difficulty,
//  collects GameResults, shows a short between-games beat, then a summary. It is
//  the single place that decides a session "counts" — it hands each result back
//  to AppModel to persist, advance difficulty, and tick the streak.
//

import SwiftUI

struct GameHost: View {
    let workout: DailyWorkout
    /// Current persisted difficulty for a game (seed if never played).
    let difficultyFor: (GameID) -> DifficultyState
    /// Called as each game finishes (persist + advance difficulty live).
    let onGameResult: (GameResult) -> Void
    /// Called once with all results when the workout completes.
    let onWorkoutDone: ([GameResult]) -> Void
    /// Dismiss without finishing (user backs out).
    let onQuit: () -> Void

    private enum Stage: Equatable { case tutorial, playing, bonus, interstitial, summary }

    @Environment(AppModel.self) private var app
    @State private var index = 0
    @State private var stage: Stage = .interstitial
    @State private var results: [GameResult] = []
    @State private var bonusValue: Int?
    @State private var pauseController = GamePauseController()

    init(workout: DailyWorkout,
         difficultyFor: @escaping (GameID) -> DifficultyState,
         onGameResult: @escaping (GameResult) -> Void,
         onWorkoutDone: @escaping ([GameResult]) -> Void,
         onQuit: @escaping () -> Void) {
        self.workout = workout
        self.difficultyFor = difficultyFor
        self.onGameResult = onGameResult
        self.onWorkoutDone = onWorkoutDone
        self.onQuit = onQuit
        // resume: pick up after any games already completed today
        _index = State(initialValue: min(workout.results.count, workout.games.count))
        _results = State(initialValue: workout.results)
    }

    private var currentGame: GameID? {
        index < workout.games.count ? workout.games[index] : nil
    }

    private var daySeed: UInt64 { RewardEngine.daySeed(workout.day) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.witsBg.ignoresSafeArea()
                content
                    .id(stageKey)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, stage == .playing && currentGame?.ownsSafeAreaSurface != true ? max(geo.safeAreaInsets.top, 8) : 0)
                    .padding(.bottom, stage == .playing && currentGame?.ownsSafeAreaSurface != true ? max(geo.safeAreaInsets.bottom, 8) : 0)
                    .allowsHitTesting(!pauseController.isPaused)
                    .clipped()
            }
            .overlay {
                if stage == .playing, currentGame?.usesEmbeddedQuitControl != true, !pauseController.isPaused {
                    GamePauseButtonLayer {
                        pauseController.pause()
                    }
                }
            }
            .overlay {
                if stage == .playing, pauseController.isPaused {
                    GamePausedOverlay(game: currentGame,
                                      quitTitle: "quit workout",
                                      onResume: { pauseController.resume() },
                                      onQuit: {
                                          pauseController.reset()
                                          onQuit()
                                      })
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: stageKey)
        .onAppear { GameFeel.shared.warmUp() }
        .onChange(of: stage) { _, newStage in
            if newStage != .playing {
                pauseController.reset()
            }
        }
        .onDisappear {
            pauseController.reset()
            GameFeel.shared.teardown()
        }
    }

    private var stageKey: String {
        switch stage {
        case .tutorial:
            "tutorial-\(index)"
        case .playing: "play-\(index)"
        case .bonus: "bonus-\(index)"
        case .interstitial: "inter-\(index)"
        case .summary: "summary"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .tutorial:
            if let game = currentGame {
                FirstPlayTutorial(
                    game: game,
                    accessory: AnyView(progressDots),
                    onStart: {
                        GameTutorialStore.markSeen(game)
                        pauseController.reset()
                        withAnimation { stage = .playing }
                    },
                    onBack: {
                        pauseController.reset()
                        withAnimation { stage = .interstitial }
                    }
                )
            } else {
                Color.clear.onAppear { stage = .summary }
            }
        case .playing:
            if let game = currentGame {
                VStack(spacing: 0) {
                    progressDots
                        .padding(.top, 8)
                    makeGameView(game,
                                 config: GameConfig.standard(game, difficulty: difficultyFor(game), pauseController: pauseController)) { result in
                        handle(result)
                    }
                }
            } else {
                Color.clear.onAppear { stage = .summary }
            }
        case .bonus:
            bonusView
        case .interstitial:
            interstitial
        case .summary:
            WorkoutSummary(results: results) {
                onWorkoutDone(results)
            }
        }
    }

    private var bonusView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundStyle(Color.witsWarm)
                Text("surprise ×\(bonusValue ?? 2)")
                    .font(.witsDisplay(32))
                    .foregroundStyle(Color.witsInk)
                Text("lucky round — your score for that game just got multiplied.")
                    .font(.witsBody(15.5))
                    .foregroundStyle(Color.witsMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .cardSurface()
            .rise()
            Spacer()
            Cta(title: "nice") { withAnimation { proceed() } }
                .rise(0.12)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }

    /// Endowed-progress dots: completed games already filled when this game starts.
    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<workout.games.count, id: \.self) { i in
                Capsule()
                    .fill(i < index ? Color.witsAccent : i == index ? Color.witsAccent.opacity(0.5) : Color.witsLine)
                    .frame(width: i == index ? 22 : 14, height: 5)
            }
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
    }

    @ViewBuilder
    private var interstitial: some View {
        if let game = currentGame {
            GameCard(
                game: game,
                stats: app.gameStats[game],
                difficulty: app.difficultyFor(game),
                primaryTitle: index == 0 ? "start" : "play",
                onPlay: {
                    pauseController.reset()
                    withAnimation { beginCurrentGame() }
                },
                onBack: onQuit,
                accessory: AnyView(progressDots)
            )
        } else {
            Color.clear.onAppear { stage = .summary }
        }
    }

    private func beginCurrentGame() {
        guard let game = currentGame else {
            stage = .summary
            return
        }
        stage = GameTutorialStore.shouldShow(for: game, hasPlayed: app.hasPlayed(game)) ? .tutorial : .playing
    }

    private func handle(_ result: GameResult) {
        var r = result
        let base = result.baseScore ?? result.score
        r.baseScore = base
        let bonus = RewardEngine.bonus(seed: daySeed, index: index)
        if let bonus {
            r.bonusMultiplier = bonus
            r.score = base * bonus
        } else {
            r.bonusMultiplier = 1
            r.score = base
        }
        results.append(r)
        onGameResult(r)
        if let bonus {
            bonusValue = bonus
            withAnimation { stage = .bonus }
        } else {
            withAnimation { proceed() }
        }
    }

    /// Advance to the next game's lead-in, or the summary.
    private func proceed() {
        bonusValue = nil
        if index + 1 < workout.games.count {
            index += 1
            stage = .interstitial
        } else {
            stage = .summary
        }
    }
}

// MARK: - Summary

private struct WorkoutSummary: View {
    @Environment(AppModel.self) private var app
    let results: [GameResult]
    let onDone: () -> Void

    private var totalScore: Int { results.reduce(0) { $0 + $1.score } }
    private var avgAccuracy: Int {
        guard !results.isEmpty else { return 0 }
        return Int((results.reduce(0) { $0 + $1.accuracy } / Double(results.count) * 100).rounded())
    }
    private var bestRound: GameResult? {
        results.max { lhs, rhs in lhs.accuracy == rhs.accuracy ? lhs.score < rhs.score : lhs.accuracy < rhs.accuracy }
    }
    private var trainedDomains: [CognitiveDomain] {
        Array(Set(results.map(\.domain))).sorted { $0.label < $1.label }
    }
    private var bestStreak: Int? {
        let values = results.compactMap { $0.raw["bestStreak"] }.filter { $0 > 0 }
        guard let best = values.max() else { return nil }
        return Int(best)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
                .padding(.bottom, 24)
            Text("workout complete")
                .font(.witsDisplay(32))
                .foregroundStyle(Color.witsInk)
                .rise()
            Text("you showed up. that's the whole game.")
                .font(.witsBody(16))
                .foregroundStyle(Color.witsMuted)
                .padding(.top, 10)
                .rise(0.08)

            HStack(spacing: 12) {
                statCard(value: "\(totalScore)", label: "points")
                statCard(value: "\(avgAccuracy)%", label: "accuracy")
            }
            .padding(.top, 22)
            .rise(0.16)

            progressMoment
                .padding(.top, 12)
                .rise(0.2)

            VStack(spacing: 10) {
                ForEach(Array(results.enumerated()), id: \.offset) { i, r in
                    HStack {
                        Image(systemName: r.game.symbol)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(Color.witsAccent)
                            .frame(width: 34, height: 34)
                            .background(Color.witsAccent.opacity(0.14), in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.game.displayName)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.witsInk)
                            if let lb = app.leaderboards[r.game], let rank = lb.rank {
                                Text("global #\(rank) of \(lb.total)")
                                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.witsAccent)
                                    .monospacedDigit()
                            } else {
                                Text(r.game.domain.label)
                                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.witsMuted)
                            }
                        }
                        Spacer()
                        if r.bonusMultiplier > 1 {
                            Text("×\(r.bonusMultiplier)")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.witsWarm)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.witsWarm.opacity(0.14), in: Capsule())
                        }
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(Int((r.accuracy * 100).rounded()))%")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.witsMuted)
                                .monospacedDigit()
                            if let levelLine = levelLine(r) {
                                Text(levelLine.text)
                                    .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                                    .foregroundStyle(levelLine.moved ? Color.witsAccent : Color.witsFaint)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(14)
                    .cardSurface()
                    .rise(0.22 + Double(i) * 0.06)
                }
            }
            .padding(.top, 18)

            Spacer()
            Cta(title: "done", action: onDone)
                .rise(0.4)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 16)
    }

    /// "lvl 3 → 4" when the whole-number level moved this run, else "lvl 4".
    private func levelLine(_ r: GameResult) -> (text: String, moved: Bool)? {
        guard r.game.usesAdaptiveLevelDisplay, let next = r.newDifficulty?.level else { return nil }
        let after = Int(DifficultyState.clamp(next).rounded(.down))
        let before = Int(DifficultyState.clamp(r.previousDifficulty?.level ?? next).rounded(.down))
        return before != after ? ("lvl \(before) → \(after)", true) : ("lvl \(after)", false)
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsAccent)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.witsMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .cardSurface()
    }

    private var progressMoment: some View {
        HStack(spacing: 10) {
            momentPill(icon: "sparkles", value: "\(trainedDomains.count)", label: trainedDomains.count == 1 ? "skill trained" : "skills trained")
            if let bestRound {
                momentPill(icon: bestRound.game.symbol,
                           value: "\(Int((bestRound.accuracy * 100).rounded()))%",
                           label: "best round")
            }
            if let bestStreak {
                momentPill(icon: "flame.fill", value: "\(bestStreak)", label: "best streak")
            }
        }
    }

    private func momentPill(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Color.witsAccent)
                .frame(width: 26, height: 26)
                .background(Color.witsAccent.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(label)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.witsMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.witsTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
