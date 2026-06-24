//
//  GamesLibraryView.swift
//  wits
//
//  Free play: the full library. Live games launch a single-game session (which
//  still calibrates difficulty); roadmap games show as coming soon.
//

import SwiftUI
import UIKit

struct GamesLibraryView: View {
    @Environment(AppModel.self) private var app
    @State private var launch: GameID?
    @State private var showPaywall = false
    @State private var filter: CognitiveDomain?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var filteredGames: [GameID] {
        GameID.allCases.filter { filter == nil || $0.domain == filter }
    }

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

                filterBar

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filteredGames) { g in
                        card(g)
                    }
                }
                .padding(.top, 4)
                .animation(.easeOut(duration: 0.2), value: filter)
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

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "all", selected: filter == nil) { filter = nil }
                ForEach(CognitiveDomain.allCases) { d in
                    FilterChip(label: d.label, selected: filter == d) { filter = d }
                }
            }
            .padding(.horizontal, WitsMetrics.screenPadding)
        }
        .padding(.horizontal, -WitsMetrics.screenPadding)
    }

    private func card(_ g: GameID) -> some View {
        Button {
            guard g.isPlayable else { return }
            if app.entitlement.isExpired { showPaywall = true } else { launch = g }
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        gameIcon(g)
                        Spacer(minLength: 0)
                        gameBadge(g)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        gameIcon(g)
                        gameBadge(g)
                    }
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
            }
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .padding(16)
            .cardSurface()
            .opacity(g.isPlayable ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!g.isPlayable)
    }

    private func gameIcon(_ g: GameID) -> some View {
        Image(systemName: g.symbol)
            .font(.system(size: 21, weight: .heavy))
            .foregroundStyle(g.isPlayable ? Color.witsAccent : Color.witsFaint)
            .frame(width: 44, height: 44)
            .background((g.isPlayable ? Color.witsAccent : Color.witsFaint).opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func gameBadge(_ g: GameID) -> some View {
        Text(gameBadgeLabel(g))
            .font(.system(size: 10.5, weight: .heavy, design: .rounded))
            .foregroundStyle(g.isPlayable ? Color.witsAccent : Color.witsFaint)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((g.isPlayable ? Color.witsAccent : Color.witsFaint).opacity(0.12), in: Capsule())
    }

    private func gameBadgeLabel(_ g: GameID) -> String {
        if g.isSurvivalOnly { return "survival" }
        guard g.isLive else { return "soon" }
        return g.domain == .multitasking ? "multitask" : g.domain.label
    }
}

/// Single-select pill used to filter the library by cognitive focus.
private struct FilterChip: View {
    var label: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                .foregroundStyle(selected ? Color.witsBg : Color.witsInk)
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .background(selected ? Color.witsAccent : Color.witsCard, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? .clear : Color.witsLine, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: selected)
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
            GeometryReader { geo in
                ZStack {
                    if game == .wordConnect {
                        WordConnectSafeAreaBackground()
                    } else if game == .dotsConnect {
                        DotsConnectSafeAreaBackground()
                    } else {
                        Color.witsBg.ignoresSafeArea()
                    }
                    makeGameView(game, config: .standard(game, difficulty: app.difficultyFor(game), freePlay: true)) { r in
                        let previousBest = app.gameStats[game]?.bestScore ?? 0
                        app.recordGameResult(r, source: "free_play")
                        lastResult = r
                        lastNewBest = r.score > previousBest
                        withAnimation(.easeOut(duration: 0.2)) { phase = .result }
                    }
                    .id(attempt)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, game.ownsSafeAreaSurface ? 0 : max(geo.safeAreaInsets.top, 8))
                    .padding(.bottom, game.ownsSafeAreaSurface ? 0 : max(geo.safeAreaInsets.bottom, 8))
                    .clipped()
                }
                .overlay(alignment: .topLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(Color.witsFaint)
                            .padding(12)
                    }
                    .padding(.leading, 8)
                    .padding(.top, max(geo.safeAreaInsets.top, 8))
                }
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
        guard game != .wordConnect else { return nil }
        guard let r = result, r.trials > 0 else { return nil }
        return Int((r.accuracy * 100).rounded())
    }
    private var bestStreak: Int? {
        guard let v = result?.raw["bestStreak"], v > 0 else { return nil }
        return Int(v)
    }
    private var bestStat: String? {
        guard game != .wordConnect else { return nil }
        guard game.statKey != "bestStreak" else { return nil }
        guard let v = result?.raw[game.statKey] else { return nil }
        return game.statLabel(v)
    }
    private var wordAccuracy: Double {
        guard game == .wordConnect else { return 0 }
        return result?.accuracy ?? 0
    }
    private var wordAccuracyPct: Int {
        Int((wordAccuracy * 100).rounded())
    }
    private var wordLevelStart: Int {
        let level = result?.raw["levelStart"] ?? result?.raw["levelEnd"] ?? 1
        return min(10, max(1, Int(floor(level))))
    }
    private var wordLevelEnd: Double? {
        guard game == .wordConnect else { return nil }
        return result?.raw["levelEnd"]
    }
    private var wordLevelProgress: Double {
        guard game == .wordConnect else { return 0 }
        guard (result?.raw["levelDelta"] ?? 0) <= 0 else { return 1 }
        return max(0, min(0.98, wordAccuracy / 0.85))
    }
    private var wordLevelText: String? {
        guard game == .wordConnect else { return nil }
        if (result?.raw["levelDelta"] ?? 0) > 0, let level = wordLevelEnd {
            let label = "level \(min(10, max(1, Int(floor(level)))))"
            return "\(label) unlocked"
        }
        guard wordLevelStart < 10 else { return "level 10 held" }
        return "level \(wordLevelStart + 1) locked"
    }
    private var wordLevelDetail: String? {
        guard game == .wordConnect else { return nil }
        if (result?.raw["levelDelta"] ?? 0) > 0 {
            return "next board set is ready"
        }
        if wordLevelStart >= 10 {
            return "85% accuracy needed to clear level 10"
        }
        return "85% accuracy needed to unlock level \(wordLevelStart + 1)"
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
                if game == .wordConnect, let wordLevelText {
                    VStack(spacing: 6) {
                        HStack {
                            Text(wordLevelText)
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.witsInk)
                            Spacer()
                            Text("\(wordAccuracyPct)%")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle((result?.raw["levelDelta"] ?? 0) > 0 ? Color.witsAccent : Color.witsWarm)
                                .monospacedDigit()
                        }
                        ProgressTrack(fraction: wordLevelProgress, animated: false)
                        if let wordLevelDetail {
                            HStack {
                                Text(wordLevelDetail)
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.witsMuted)
                                Spacer()
                                Text((result?.raw["levelDelta"] ?? 0) > 0 ? "passed" : "target 85%")
                                    .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color.witsFaint)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                if game == .wordConnect {
                    wordConnectStats
                        .padding(.top, 8)
                } else if accuracyPct != nil || bestStreak != nil || bestStat != nil {
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
            Cta(title: replayTitle, action: onReplay)
                .rise(0.1)
            QuietButton(title: "back to games", action: onDone)
                .padding(.top, 6)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.witsBg.ignoresSafeArea())
    }

    private var replayTitle: String {
        guard game == .wordConnect else { return "play again" }
        guard (result?.raw["levelDelta"] ?? 0) > 0 else { return "play again" }
        return "play next level"
    }

    private var wordConnectStats: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            stat("\(wordAccuracyPct)%", "accuracy")
            if let words = result?.raw["wordsFound"] {
                stat("\(Int(words))", "words")
            }
            if let boards = result?.raw["boardsSolved"] {
                stat("\(Int(boards))/2", "boards")
            }
            if let hints = result?.raw["hintsUsed"] {
                stat("\(Int(hints))", "hints")
            }
        }
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
