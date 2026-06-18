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

    private enum Stage: Equatable { case playing, bonus, interstitial, summary }

    @Environment(AppModel.self) private var app
    @State private var index = 0
    @State private var stage: Stage = .interstitial
    @State private var results: [GameResult] = []
    @State private var bonusValue: Int?

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
        ZStack {
            Color.witsBg.ignoresSafeArea()
            content
                .id(stageKey)
                .transition(.opacity)
        }
        .animation(.easeOut(duration: 0.25), value: stageKey)
        .onAppear { GameFeel.shared.warmUp() }
        .onDisappear { GameFeel.shared.teardown() }
        .overlay(alignment: .topLeading) {
            if stage == .playing {
                Button(action: onQuit) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Color.witsFaint)
                        .padding(12)
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private var stageKey: String {
        switch stage {
        case .playing: "play-\(index)"
        case .bonus: "bonus-\(index)"
        case .interstitial: "inter-\(index)"
        case .summary: "summary"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .playing:
            if let game = currentGame {
                VStack(spacing: 0) {
                    progressDots
                        .padding(.top, 8)
                    makeGameView(game,
                                 config: GameConfig.standard(game, difficulty: difficultyFor(game))) { result in
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
                primaryTitle: index == 0 ? "start" : "play",
                onPlay: { withAnimation { stage = .playing } },
                onBack: onQuit,
                accessory: AnyView(progressDots)
            )
        } else {
            Color.clear.onAppear { stage = .summary }
        }
    }

    private func handle(_ result: GameResult) {
        var r = result
        let bonus = RewardEngine.bonus(seed: daySeed, index: index)
        if let bonus { r.score *= bonus }
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
    let results: [GameResult]
    let onDone: () -> Void

    private var totalScore: Int { results.reduce(0) { $0 + $1.score } }
    private var avgAccuracy: Int {
        guard !results.isEmpty else { return 0 }
        return Int((results.reduce(0) { $0 + $1.accuracy } / Double(results.count) * 100).rounded())
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
                            Text(r.game.domain.label)
                                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.witsMuted)
                        }
                        Spacer()
                        Text("\(Int((r.accuracy * 100).rounded()))%")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.witsMuted)
                            .monospacedDigit()
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
}
