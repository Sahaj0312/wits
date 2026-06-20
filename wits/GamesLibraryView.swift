//
//  GamesLibraryView.swift
//  wits
//
//  Free play: the full library. Live games launch a single-game session (which
//  still calibrates difficulty); roadmap games show as coming soon.
//

import SwiftUI

struct GamesLibraryView: View {
    @Environment(AppModel.self) private var app
    @State private var launch: GameID?
    @State private var showPaywall = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    WitsBrandMark()
                    Text("games")
                        .font(.witsDisplay(30))
                        .foregroundStyle(Color.witsInk)
                }
                .padding(.top, 8)
                Text("train any skill on its own. your daily workout mixes these for you.")
                    .font(.witsBody(15))
                    .foregroundStyle(Color.witsMuted)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(GameID.allCases) { g in
                        card(g)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, WitsMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .background(Color.witsBg.ignoresSafeArea())
        .fullScreenCover(item: $launch) { g in
            if g.isSurvivalOnly {
                SplitSurvivalScreen(
                    best: app.gameStats[g]?.survivalBest ?? 0,
                    onRunComplete: { level, depth, trials in
                        app.recordSplitRun(levelReached: level, depth: depth, trials: trials)
                    },
                    onQuit: { launch = nil }
                )
            } else {
                GameLauncher(game: g)
            }
        }
        .fullScreenCover(isPresented: $showPaywall) { PaywallView() }
    }

    private func card(_ g: GameID) -> some View {
        let stats = app.gameStats[g]
        return Button {
            guard g.isPlayable else { return }
            if app.entitlement.isExpired { showPaywall = true } else { launch = g }
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: g.symbol)
                        .font(.system(size: 21, weight: .heavy))
                        .foregroundStyle(g.isPlayable ? Color.witsAccent : Color.witsFaint)
                        .frame(width: 44, height: 44)
                        .background((g.isPlayable ? Color.witsAccent : Color.witsFaint).opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Spacer(minLength: 0)
                    Text(g.isSurvivalOnly ? "survival" : (g.isLive ? g.domain.label : "soon"))
                        .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(g.isPlayable ? Color.witsAccent : Color.witsFaint)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((g.isPlayable ? Color.witsAccent : Color.witsFaint).opacity(0.12), in: Capsule())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(g.displayName)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(g.tagline)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(g.isPlayable ? Color.witsMuted : Color.witsFaint)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    libraryMetric(value: bestValue(for: g, stats: stats), label: bestLabel(for: g))
                    if g.isLive {
                        libraryMetric(value: "lvl \(String(format: "%.1f", app.difficultyFor(g).level))", label: "start")
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 178, alignment: .topLeading)
            .padding(16)
            .cardSurface()
            .opacity(g.isPlayable ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!g.isPlayable)
    }

    private func bestValue(for game: GameID, stats: GameStats?) -> String {
        if game.isSurvivalOnly {
            let best = stats?.survivalBest ?? 0
            return best > 0 ? "lvl \(best)" : "—"
        }
        let best = stats?.bestScore ?? 0
        return best > 0 ? "\(best)" : "—"
    }

    private func bestLabel(for game: GameID) -> String {
        game.isSurvivalOnly ? "best" : "points"
    }

    private func libraryMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsInk)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.witsFaint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.witsTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Pre-game chooser: the card with Train vs Survival, then runs the chosen mode
/// in a single full-screen cover (no double card).
private struct GameLauncher: View {
    let game: GameID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .card
    @State private var lastResult: GameResult?
    @State private var lastNewBest = false
    @State private var attempt = 0   // bump to force a fresh game instance on replay

    private enum Phase { case card, train, survival, result }

    var body: some View {
        switch phase {
        case .card:
            GameCard(
                game: game,
                stats: app.gameStats[game],
                primaryTitle: "train",
                onPlay: { phase = .train },
                onBack: { dismiss() },
                onSurvival: { phase = .survival }
            )
            .overlay(alignment: .topLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.28), in: Circle())
                }
                .padding(.top, 44)
                .padding(.leading, 12)
            }
        case .train:
            ZStack {
                Color.witsBg.ignoresSafeArea()
                makeGameView(game, config: .standard(game, difficulty: app.difficultyFor(game), freePlay: true)) { r in
                    let previousBest = app.gameStats[game]?.bestScore ?? 0
                    app.recordGameResult(r, source: "free_play")
                    lastResult = r
                    lastNewBest = r.score > previousBest
                    withAnimation(.easeOut(duration: 0.2)) { phase = .result }
                }
                .id(attempt)
            }
            .overlay(alignment: .topLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Color.witsFaint)
                        .padding(12)
                }
                .padding(.top, 44)
            }
            .onAppear { GameFeel.shared.warmUp() }
            .onDisappear { GameFeel.shared.teardown() }
        case .result:
            GameResultView(
                game: game,
                result: lastResult,
                isNewBest: lastNewBest,
                onReplay: { attempt += 1; withAnimation(.easeOut(duration: 0.2)) { phase = .train } },
                onDone: { dismiss() }
            )
        case .survival:
            SurvivalHost(
                game: game,
                seedDifficulty: app.difficultyFor(game),
                stats: app.gameStats[game],
                onRunComplete: { score, trials in app.recordSurvivalRun(game: game, score: score, trials: trials) },
                onQuit: { dismiss() },
                startImmediately: true
            )
        }
    }
}

/// End-of-game screen for free play: score + accuracy, then replay or exit.
private struct GameResultView: View {
    let game: GameID
    let result: GameResult?
    var isNewBest: Bool
    var onReplay: () -> Void
    var onDone: () -> Void

    private var accuracyPct: Int? {
        guard let r = result, r.trials > 0 else { return nil }
        return Int((r.accuracy * 100).rounded())
    }
    private var bestStreak: Int? {
        guard let v = result?.raw["bestStreak"], v > 0 else { return nil }
        return Int(v)
    }
    private var bestStat: String? {
        guard game.statKey != "bestStreak" else { return nil }
        guard let v = result?.raw[game.statKey] else { return nil }
        return game.statLabel(v)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: game.symbol)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(Color.witsAccent)
                Text(game.displayName)
                    .font(.witsBody(15, weight: .semibold))
                    .foregroundStyle(Color.witsMuted)
                Text("\(result?.score ?? 0)")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                    .monospacedDigit()
                Text("points")
                    .font(.witsBody(13, weight: .semibold))
                    .foregroundStyle(Color.witsMuted)
                if isNewBest {
                    Text("NEW BEST")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .kerning(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.witsWarm, in: Capsule())
                }
                if accuracyPct != nil || bestStreak != nil || bestStat != nil {
                    HStack(spacing: 12) {
                        if let a = accuracyPct { stat("\(a)%", "accuracy") }
                        if let s = bestStreak { stat("\(s)", "best streak") }
                        if let bestStat { stat(bestStat, "best stat") }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .cardSurface()
            .rise()
            Spacer()
            Cta(title: "play again", action: onReplay)
                .rise(0.1)
            QuietButton(title: "back to games", action: onDone)
                .padding(.top, 6)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.witsBg.ignoresSafeArea())
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsAccent)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.witsMuted)
        }
    }
}
