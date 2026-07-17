//
//  GamesLibraryView.swift
//  wits
//
//  The home screen: every game as a card with its selected difficulty progress, the daily
//  streak flame, and the settings sheet.
//

import SwiftUI
import UIKit

struct GamesLibraryView: View {
    @Environment(AppModel.self) private var app
    @State private var launch: GameID?
    @State private var showSettings = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var games: [GameID] {
        GameID.libraryOrder.filter(\.isPlayable)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 10) {
                    Text("games")
                        .font(.system(size: 29, weight: .black, design: .default))
                        .foregroundStyle(.white)
                    Spacer()
                    StreakPill(count: app.streak.current)
                    shuffleButton
                    settingsButton
                }
                .padding(.top, 8)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(games) { g in
                        card(g)
                    }
                }
                .padding(.top, 4)

                communityRow
                    .padding(.top, 4)
            }
            .padding(.horizontal, WitsMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .background(Color(hexAny: 0x09090B).ignoresSafeArea())
        .fullScreenCover(item: $launch) { g in
            GameLauncher(game: g)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    /// Opens a random game's level map — a "surprise me" for the library.
    private var shuffleButton: some View {
        Button {
            guard let pick = games.randomElement() else { return }
            launch = pick
        } label: {
            Image(systemName: "shuffle")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color(hexAny: 0x1B1B20), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("Open a random game")
    }

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color(hexAny: 0x1B1B20), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("Settings")
    }

    /// Poster card: a per-game color world with an illustrated gameplay
    /// vignette, framed in a thin card-colored border like a tiny game poster.
    private func card(_ g: GameID) -> some View {
        Button {
            launch = g
        } label: {
            ZStack(alignment: .topLeading) {
                GameWorldBackdrop(game: g, patternOpacity: 0.85)
                GamePosterArt(game: g)
                VStack(alignment: .leading, spacing: 6) {
                    Text(g.worldTitle())
                        .font(.system(size: 17, weight: .black, design: g.world.titleDesign))
                        .foregroundStyle(g.world.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)
                    Rectangle()
                        .fill(g.world.accent)
                        .frame(width: 30, height: 4)
                }
                .padding(.horizontal, 14)
                .padding(.top, 13)
            }
            .aspectRatio(0.74, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                progressPill(g).padding(9)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(g.world.accent.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: g.world.accent.opacity(0.16), radius: 12, y: 6)
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(Text("\(g.displayName). \(g.tagline)"))
    }

    /// One quiet line of progression per card: selected track for regular games,
    /// best level for split.
    private func progressPill(_ g: GameID) -> some View {
        HStack(spacing: 4) {
            Image(systemName: g.isStandalone ? "trophy.fill" : "flag.fill")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(g.world.accent)
            Text(progressLabel(g))
                .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                .foregroundStyle(g.world.ink)
                .monospacedDigit()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(g.world.surface.opacity(0.92), in: Capsule())
        .overlay(Capsule().strokeBorder(g.world.ink.opacity(0.12), lineWidth: 1))
    }

    private func progressLabel(_ g: GameID) -> String {
        if g.isStandalone {
            guard let best = app.levels.marathonBest(for: g) else { return "no runs yet" }
            return g == .split
                ? "best \(SplitProgress.label(level: best.depth, depth: best.depthFraction ?? 0))"
                : "best \(best.score)"
        }
        let difficulty = app.levels.selectedDifficulty(for: g)
        let level = app.levels.currentLevel(for: g, difficulty: difficulty)
        return "\(difficulty.title) · level \(level)"
    }

    /// A small community footer after the game grid. It deliberately uses the
    /// Wits visual language instead of pretending these are playable games.
    private var communityRow: some View {
        HStack(alignment: .top, spacing: 12) {
            ShareLink(item: shareMessage) {
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [Color(hexAny: 0x6657F5), Color(hexAny: 0x35C8B5)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)

                    Circle()
                        .fill(.white.opacity(0.13))
                        .frame(width: 112, height: 112)
                        .offset(x: 78, y: -32)

                    VStack(alignment: .leading, spacing: 0) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 25, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(.black.opacity(0.17), in: Circle())

                        Spacer(minLength: 12)

                        Text("PASS IT ON")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)

                        Text("invite a friend to play")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.82))
                            .padding(.top, 5)

                        HStack(spacing: 5) {
                            Text("SHARE WITS")
                            Image(systemName: "arrow.up.forward")
                        }
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.top, 13)
                    }
                    .padding(15)
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(0.88, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: Color(hexAny: 0x6657F5).opacity(0.22), radius: 12, y: 6)
            }
            .buttonStyle(PressScale())
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Share Wits with a friend")

            ZStack {
                Color(hexAny: 0x17171C)

                Circle()
                    .strokeBorder(Color(hexAny: 0xF2C94C).opacity(0.17),
                                  style: StrokeStyle(lineWidth: 2, dash: [5, 7]))
                    .frame(width: 126, height: 126)
                    .offset(x: 48, y: -45)

                VStack(spacing: 0) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hexAny: 0x25252D))
                            .frame(width: 58, height: 58)
                        Image(systemName: "sparkles")
                            .font(.system(size: 25, weight: .black))
                            .foregroundStyle(Color(hexAny: 0xF2C94C))
                    }

                    Spacer(minLength: 12)

                    Text("MORE WITS")
                        .font(.system(size: 21, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("ON THE WAY")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(Color(hexAny: 0xF2C94C))
                        .padding(.top, 5)

                    Text("fresh games are in the works")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
                .padding(15)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(0.88, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("More Wits games are on the way")
        }
    }

    private var shareMessage: String {
        "I’ve been playing Wits — quick brain games for memory, logic, words, maths, and focus. Give it a try!"
    }

}

/// Pre-game difficulty selector followed by one unbounded track level.
private struct GameLauncher: View {
    let game: GameID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .selector
    @State private var playDifficulty: ChallengeDifficulty = .easy
    @State private var playLevel = 1
    @State private var lastPassed = false
    @State private var lastQuality = 0.0
    @State private var lastImproved = false
    @State private var attempt = 0   // bump to force a fresh game instance
    @State private var pauseController = GamePauseController()
    @State private var pendingReviveResult: GameResult?
    @State private var reviveUsed = false
    @State private var reviveBusy = false

    private enum Phase { case selector, tutorial, reviewTutorial, playing, levelResult }

    var body: some View {
        ZStack {
            content

            if pendingReviveResult != nil {
                RewardedReviveOffer(game: game,
                                    busy: reviveBusy,
                                    onDecline: declineRevive,
                                    onSave: redeemRevive)
            }
        }
        .onChange(of: phase) { oldPhase, newPhase in
            // Endless runs have no dedicated result phase in this host —
            // the selector is the first static screen after a run, so the
            // interstitial slot (counted in each onRunComplete) is here.
            // Backing out of a tutorial isn't a run, so it never counts.
            guard newPhase == .selector,
                  oldPhase == .playing || oldPhase == .levelResult else { return }
            AdManager.shared.maybeShowInterstitial()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .selector:
            if game == .snake {
                SnakeModeSelectView(
                    onPlay: { difficulty in
                        playDifficulty = difficulty
                        startRun()
                    },
                    onClose: { dismiss() },
                    onHelp: showTutorialReview
                )
            } else if game == .tower {
                TowerModeSelectView(
                    onPlay: { difficulty in
                        playDifficulty = difficulty
                        startRun()
                    },
                    onClose: { dismiss() },
                    onHelp: showTutorialReview
                )
            } else if [.arrowStorm, .crowdControl, .colorClash, .tileShift, .lastSeen].contains(game) {
                EndlessModeSelectView(
                    game: game,
                    onPlay: { difficulty in
                        playDifficulty = difficulty
                        startRun()
                    },
                    onClose: { dismiss() },
                    onHelp: showTutorialReview
                )
            } else if game.isStandalone {
                StandaloneModeSelectView(
                    game: game,
                    onSurvival: {
                        startRun()
                    },
                    onClose: { dismiss() },
                    onHelp: showTutorialReview
                )
            } else {
                DifficultySelectView(
                    game: game,
                    onPlay: { difficulty, level in
                        playDifficulty = difficulty
                        playLevel = level
                        startRun()
                    },
                    onClose: { dismiss() }
                )
            }
        case .tutorial:
            if let slides = game.animatedTutorialSlides {
                AnimatedHowToPlay(
                    game: game,
                    slides: slides,
                    onStart: startFromTutorial,
                    onBack: backFromTutorial
                )
            } else {
                FirstPlayTutorial(
                    game: game,
                    onStart: startFromTutorial,
                    onBack: backFromTutorial
                )
            }
        case .reviewTutorial:
            // Re-opened from the selector's "?" — finishing returns there.
            if let slides = game.animatedTutorialSlides {
                AnimatedHowToPlay(
                    game: game,
                    slides: slides,
                    doneTitle: "got it",
                    onStart: backFromTutorial,
                    onBack: backFromTutorial
                )
            } else {
                FirstPlayTutorial(
                    game: game,
                    ctaTitle: "GOT IT",
                    onStart: backFromTutorial,
                    onBack: backFromTutorial
                )
            }
        case .playing:
            if game == .blockFit {
                let runBests = app.levels.runBests(for: .blockFit, difficulty: nil)
                BlockFitScreen(
                    best: app.levels.marathonBest(for: .blockFit)?.score ?? 0,
                    todayBest: runBests.today,
                    weekBest: runBests.week,
                    onRunComplete: { score, lines, pieces in
                        let result = blockFitResult(score: score, lines: lines, pieces: pieces)
                        AdManager.shared.gameCompleted()
                        app.recordStandaloneGameResult(result)
                        app.recordMarathon(game: .blockFit, depth: score, score: score)
                        app.recordRunBests(game: .blockFit, score: score)
                    },
                    onQuit: { withAnimation { phase = .selector } }
                )
            } else if game == .fuse {
                let runBests = app.levels.runBests(for: .fuse, difficulty: nil)
                FuseScreen(
                    best: app.levels.marathonBest(for: .fuse)?.score ?? 0,
                    todayBest: runBests.today,
                    weekBest: runBests.week,
                    onRunComplete: { score, bestTile, moves in
                        let result = fuseResult(score: score, bestTile: bestTile, moves: moves)
                        AdManager.shared.gameCompleted()
                        app.recordStandaloneGameResult(result)
                        app.recordMarathon(game: .fuse, depth: score, score: score)
                        app.recordRunBests(game: .fuse, score: score)
                    },
                    onQuit: { withAnimation { phase = .selector } }
                )
            } else if game == .snake {
                let runBests = app.levels.runBests(for: .snake, difficulty: playDifficulty)
                SnakeScreen(
                    difficulty: playDifficulty,
                    modeBest: app.levels.modeBest(for: .snake, difficulty: playDifficulty),
                    allTimeBest: app.levels.marathonBest(for: .snake)?.score ?? 0,
                    todayBest: runBests.today,
                    weekBest: runBests.week,
                    onRunComplete: { score, length in
                        let result = snakeResult(score: score, length: length)
                        AdManager.shared.gameCompleted()
                        app.recordStandaloneGameResult(result)
                        app.recordModeBest(game: .snake,
                                           difficulty: playDifficulty,
                                           score: score)
                        app.recordMarathon(game: .snake, depth: score, score: score)
                        app.recordRunBests(game: .snake, difficulty: playDifficulty, score: score)
                    },
                    onQuit: { withAnimation { phase = .selector } }
                )
            } else if game == .tower {
                let runBests = app.levels.runBests(for: .tower, difficulty: playDifficulty)
                TowerScreen(
                    difficulty: playDifficulty,
                    modeBest: app.levels.modeBest(for: .tower, difficulty: playDifficulty),
                    allTimeBest: app.levels.marathonBest(for: .tower)?.score ?? 0,
                    todayBest: runBests.today,
                    weekBest: runBests.week,
                    onRunComplete: { score, perfects, bestStreak in
                        let result = towerResult(score: score, perfects: perfects, bestStreak: bestStreak)
                        AdManager.shared.gameCompleted()
                        app.recordStandaloneGameResult(result)
                        app.recordModeBest(game: .tower,
                                           difficulty: playDifficulty,
                                           score: score)
                        app.recordMarathon(game: .tower, depth: score, score: score)
                        app.recordRunBests(game: .tower, difficulty: playDifficulty, score: score)
                    },
                    onQuit: { withAnimation { phase = .selector } }
                )
            } else if game == .arrowStorm {
                let runBests = app.levels.runBests(for: .arrowStorm, difficulty: playDifficulty)
                ArrowStormScreen(
                    difficulty: playDifficulty,
                    modeBest: app.levels.modeBest(for: .arrowStorm, difficulty: playDifficulty),
                    allTimeBest: app.levels.marathonBest(for: .arrowStorm)?.score ?? 0,
                    todayBest: runBests.today,
                    weekBest: runBests.week,
                    onRunComplete: { score, bestStreak, misses in
                        let result = arrowStormResult(score: score, bestStreak: bestStreak, misses: misses)
                        AdManager.shared.gameCompleted()
                        app.recordStandaloneGameResult(result)
                        app.recordModeBest(game: .arrowStorm,
                                           difficulty: playDifficulty,
                                           score: score)
                        app.recordMarathon(game: .arrowStorm, depth: score, score: score)
                        app.recordRunBests(game: .arrowStorm, difficulty: playDifficulty, score: score)
                    },
                    onQuit: { withAnimation { phase = .selector } }
                )
            } else if game == .crowdControl {
                let runBests = app.levels.runBests(for: .crowdControl, difficulty: playDifficulty)
                CrowdControlScreen(
                    difficulty: playDifficulty,
                    modeBest: app.levels.modeBest(for: .crowdControl, difficulty: playDifficulty),
                    allTimeBest: app.levels.marathonBest(for: .crowdControl)?.score ?? 0,
                    todayBest: runBests.today,
                    weekBest: runBests.week,
                    onRunComplete: { score, totalTargets, rounds, perfectRounds in
                        let result = crowdControlResult(score: score,
                                                        totalTargets: totalTargets,
                                                        rounds: rounds,
                                                        perfectRounds: perfectRounds)
                        AdManager.shared.gameCompleted()
                        app.recordStandaloneGameResult(result)
                        app.recordModeBest(game: .crowdControl,
                                           difficulty: playDifficulty,
                                           score: score)
                        app.recordMarathon(game: .crowdControl, depth: score, score: score)
                        app.recordRunBests(game: .crowdControl, difficulty: playDifficulty, score: score)
                    },
                    onQuit: { withAnimation { phase = .selector } }
                )
            } else if game == .colorClash {
                let runBests = app.levels.runBests(for: .colorClash, difficulty: playDifficulty)
                ColorClashScreen(
                    difficulty: playDifficulty,
                    modeBest: app.levels.modeBest(for: .colorClash, difficulty: playDifficulty),
                    allTimeBest: app.levels.marathonBest(for: .colorClash)?.score ?? 0,
                    todayBest: runBests.today,
                    weekBest: runBests.week,
                    onRunComplete: { score, bestStreak, misses in
                        let result = colorClashResult(score: score, bestStreak: bestStreak, misses: misses)
                        AdManager.shared.gameCompleted()
                        app.recordStandaloneGameResult(result)
                        app.recordModeBest(game: .colorClash,
                                           difficulty: playDifficulty,
                                           score: score)
                        app.recordMarathon(game: .colorClash, depth: score, score: score)
                        app.recordRunBests(game: .colorClash, difficulty: playDifficulty, score: score)
                    },
                    onQuit: { withAnimation { phase = .selector } }
                )
            } else if game == .tileShift {
                let runBests = app.levels.runBests(for: .tileShift, difficulty: playDifficulty)
                TileShiftScreen(
                    difficulty: playDifficulty,
                    modeBest: app.levels.modeBest(for: .tileShift, difficulty: playDifficulty),
                    allTimeBest: app.levels.marathonBest(for: .tileShift)?.score ?? 0,
                    todayBest: runBests.today,
                    weekBest: runBests.week,
                    onRunComplete: { score, bestStreak, misses in
                        let result = tileShiftResult(score: score, bestStreak: bestStreak, misses: misses)
                        AdManager.shared.gameCompleted()
                        app.recordStandaloneGameResult(result)
                        app.recordModeBest(game: .tileShift,
                                           difficulty: playDifficulty,
                                           score: score)
                        app.recordMarathon(game: .tileShift, depth: score, score: score)
                        app.recordRunBests(game: .tileShift, difficulty: playDifficulty, score: score)
                    },
                    onQuit: { withAnimation { phase = .selector } }
                )
            } else if game == .lastSeen {
                let runBests = app.levels.runBests(for: .lastSeen, difficulty: playDifficulty)
                LastSeenScreen(
                    difficulty: playDifficulty,
                    modeBest: app.levels.modeBest(for: .lastSeen, difficulty: playDifficulty),
                    allTimeBest: app.levels.marathonBest(for: .lastSeen)?.score ?? 0,
                    todayBest: runBests.today,
                    weekBest: runBests.week,
                    onRunComplete: { score, remembered, misses in
                        let result = lastSeenResult(score: score, remembered: remembered, misses: misses)
                        AdManager.shared.gameCompleted()
                        app.recordStandaloneGameResult(result)
                        app.recordModeBest(game: .lastSeen,
                                           difficulty: playDifficulty,
                                           score: score)
                        app.recordMarathon(game: .lastSeen, depth: score, score: score)
                        app.recordRunBests(game: .lastSeen, difficulty: playDifficulty, score: score)
                    },
                    onQuit: { withAnimation { phase = .selector } }
                )
            } else if game == .split {
                let survivalBest = app.levels.marathonBest(for: .split)
                let runBests = app.levels.runBests(for: .split, difficulty: nil)
                SplitSurvivalScreen(
                    best: survivalBest?.depth ?? splitBestLevel,
                    bestDepthFraction: survivalBest?.depthFraction ?? 0,
                    todayBest: runBests.today,
                    weekBest: runBests.week,
                    onRunComplete: { level, depth, trials in
                        let result = splitResult(level: level, depth: depth, trials: trials)
                        app.recordStandaloneGameResult(result)
                        app.recordMarathon(game: .split,
                                           depth: level,
                                           depthFraction: depth,
                                           score: splitScore(level: level))
                        app.recordRunBests(game: .split, score: level)
                    },
                    onQuit: { withAnimation { phase = .selector } }
                )
            } else {
                GeometryReader { _ in
                    ZStack {
                        // Full-bleed stage matching the game's surface, so no
                        // app-background band shows in the safe areas.
                        GameStageBackground(game: game)
                        makeGameView(game, config: activeConfig) { r in
                            handle(r)
                        }
                        .id(attempt)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // Content already sits inside the safe area; the top
                        // padding is a strip for the floating pause button,
                        // not another safe-area inset.
                        .padding(.top, game.ownsSafeAreaSurface ? 0 : 36)
                        .padding(.bottom, game.ownsSafeAreaSurface ? 0 : 8)
                        .allowsHitTesting(!pauseController.isPaused)
                        .clipped()
                    }
                    .overlay {
                        if !game.usesEmbeddedQuitControl, !pauseController.isPaused {
                            GamePauseButtonLayer(game: game) {
                                pauseController.pause()
                            }
                        }
                    }
                    .overlay {
                        if pauseController.isPaused {
                            GamePausedOverlay(game: game,
                                              controller: pauseController,
                                              onQuit: {
                                                  pauseController.reset()
                                                  withAnimation { phase = .selector }
                                              })
                        }
                    }
                }
                .onAppear { GameFeel.shared.warmUp() }
                .onDisappear {
                    pauseController.reset()
                    GameFeel.shared.teardown()
                }
            }
        case .levelResult:
            DifficultyLevelResultView(
                game: game,
                difficulty: playDifficulty,
                level: playLevel,
                passed: lastPassed,
                quality: lastQuality,
                improved: lastImproved,
                onRetry: { startRun() },
                onNext: {
                    playLevel = app.levels.currentLevel(for: game, difficulty: playDifficulty)
                    startRun()
                },
                onSelector: { withAnimation(.easeOut(duration: 0.2)) { phase = .selector } }
            )
        }
    }

    private var activeConfig: GameConfig {
        .challenge(game,
                   difficulty: playDifficulty,
                   trackLevel: playLevel,
                   persisted: app.difficultyState(for: game, difficulty: playDifficulty),
                   freePlay: true,
                   pauseController: pauseController)
    }

    private func startRun() {
        pauseController.reset()
        pendingReviveResult = nil
        reviveUsed = false
        reviveBusy = false
        attempt += 1
        let needsTutorial = GameTutorialStore.shouldShow(for: game, hasPlayed: app.hasPlayed(game))
        withAnimation(.easeOut(duration: 0.2)) { phase = needsTutorial ? .tutorial : .playing }
    }

    private func startFromTutorial() {
        GameTutorialStore.markSeen(game)
        pauseController.reset()
        withAnimation(.easeOut(duration: 0.2)) { phase = .playing }
    }

    private func backFromTutorial() {
        pauseController.reset()
        withAnimation(.easeOut(duration: 0.2)) { phase = .selector }
    }

    private func showTutorialReview() {
        withAnimation(.easeOut(duration: 0.2)) { phase = .reviewTutorial }
    }

    private func handle(_ result: GameResult) {
        pauseController.reset()
        let previous = app.difficultyState(for: game, difficulty: playDifficulty)
        if RewardedReviveEligibility.shouldOffer(for: result,
                                                 previous: previous,
                                                 alreadyUsed: reviveUsed) {
            withAnimation(.easeOut(duration: 0.2)) {
                pendingReviveResult = result
            }
            return
        }
        finish(result)
    }

    private func declineRevive() {
        guard let result = pendingReviveResult else { return }
        pendingReviveResult = nil
        finish(result)
    }

    private func redeemRevive() {
        guard pendingReviveResult != nil, !reviveBusy else { return }
        reviveBusy = true
        AdManager.shared.showRewarded { earned in
            reviveBusy = false
            guard earned else { return }
            reviveUsed = true
            pendingReviveResult = nil
            pauseController.reset()
            attempt += 1
        }
    }

    private func finish(_ result: GameResult) {
        // Snapshot before recording — recordGameResult merges this run in.
        let passedBefore = app.levels.hasPassed(game: game,
                                                difficulty: playDifficulty,
                                                level: playLevel)
        let qualityBefore = app.levels.record(for: game,
                                              difficulty: playDifficulty,
                                              level: playLevel)?.bestQuality ?? 0
        var tagged = result
        tagged.raw["trackLevel"] = Double(playLevel)
        tagged.raw["difficultyTrack"] = Double(playDifficulty.ordinal)
        let scored = app.recordGameResult(tagged)
        let quality = scored.performanceQuality ?? scored.accuracy
        let passed = LevelGrader.passed(quality: quality)

        lastPassed = passed
        lastQuality = quality
        lastImproved = passed && (!passedBefore || quality > qualityBefore)
        withAnimation(.easeOut(duration: 0.2)) { phase = .levelResult }
        AdManager.shared.gameCompleted()
        AdManager.shared.maybeShowInterstitial()
    }

    private func blockFitResult(score: Int, lines: Int, pieces: Int) -> GameResult {
        var result = GameResult(game: .blockFit,
                                score: score,
                                baseScore: score,
                                accuracy: 0,
                                trials: max(1, pieces))
        result.raw = [
            "score": Double(score),
            "lines": Double(lines),
            "pieces": Double(pieces)
        ]
        return result
    }

    private func fuseResult(score: Int, bestTile: Int, moves: Int) -> GameResult {
        var result = GameResult(game: .fuse,
                                score: score,
                                baseScore: score,
                                accuracy: 0,
                                trials: max(1, moves))
        result.raw = [
            "score": Double(score),
            "bestTile": Double(bestTile),
            "moves": Double(moves)
        ]
        return result
    }

    private func arrowStormResult(score: Int, bestStreak: Int, misses: Int) -> GameResult {
        let trials = score + misses
        var result = GameResult(game: .arrowStorm,
                                score: score,
                                baseScore: score,
                                accuracy: trials > 0 ? Double(score) / Double(trials) : 0,
                                trials: max(1, trials))
        result.raw = [
            "score": Double(score),
            "correct": Double(score),
            "wrong": Double(misses),
            "bestStreak": Double(bestStreak)
        ]
        return result
    }

    private func colorClashResult(score: Int, bestStreak: Int, misses: Int) -> GameResult {
        let trials = score + misses
        var result = GameResult(game: .colorClash,
                                score: score,
                                baseScore: score,
                                accuracy: trials > 0 ? Double(score) / Double(trials) : 0,
                                trials: max(1, trials))
        result.raw = [
            "score": Double(score),
            "correct": Double(score),
            "wrong": Double(misses),
            "bestStreak": Double(bestStreak)
        ]
        return result
    }

    private func lastSeenResult(score: Int, remembered: Int, misses: Int) -> GameResult {
        let trials = score + misses
        var result = GameResult(game: .lastSeen,
                                score: score,
                                baseScore: score,
                                accuracy: trials > 0 ? Double(score) / Double(trials) : 0,
                                trials: max(1, trials))
        result.raw = [
            "score": Double(score),
            "correct": Double(score),
            "wrong": Double(misses),
            "remembered": Double(remembered)
        ]
        return result
    }

    private func tileShiftResult(score: Int, bestStreak: Int, misses: Int) -> GameResult {
        let trials = score + misses
        var result = GameResult(game: .tileShift,
                                score: score,
                                baseScore: score,
                                accuracy: trials > 0 ? Double(score) / Double(trials) : 0,
                                trials: max(1, trials))
        result.raw = [
            "score": Double(score),
            "correct": Double(score),
            "wrong": Double(misses),
            "bestStreak": Double(bestStreak)
        ]
        return result
    }

    private func crowdControlResult(score: Int, totalTargets: Int, rounds: Int, perfectRounds: Int) -> GameResult {
        var result = GameResult(game: .crowdControl,
                                score: score,
                                baseScore: score,
                                accuracy: totalTargets > 0 ? Double(score) / Double(totalTargets) : 0,
                                trials: max(1, rounds))
        result.raw = [
            "score": Double(score),
            "correctPicks": Double(score),
            "totalTargets": Double(totalTargets),
            "rounds": Double(rounds),
            "perfectRounds": Double(perfectRounds),
            "correct": Double(score),
            "wrong": Double(max(0, totalTargets - score))
        ]
        return result
    }

    private func snakeResult(score: Int, length: Int) -> GameResult {
        var result = GameResult(game: .snake,
                                score: score,
                                baseScore: score,
                                accuracy: 0,
                                trials: max(1, score))
        result.raw = [
            "score": Double(score),
            "apples": Double(score),
            "length": Double(length)
        ]
        return result
    }

    private func towerResult(score: Int, perfects: Int, bestStreak: Int) -> GameResult {
        var result = GameResult(game: .tower,
                                score: score,
                                baseScore: score,
                                accuracy: 0,
                                trials: max(1, score))
        result.raw = [
            "score": Double(score),
            "blocks": Double(score),
            "perfects": Double(perfects),
            "bestStreak": Double(bestStreak)
        ]
        return result
    }

    private func splitResult(level: Int, depth: Double, trials: Int) -> GameResult {
        var result = GameResult(game: .split, score: level, baseScore: level, accuracy: 0, trials: max(1, trials))
        result.raw = [
            "survival": 1,
            "maxLevel": Double(level),
            "levelDepth": max(0, min(1, depth)),
            "picks": Double(trials)
        ]
        return result
    }

    /// Marathon-equivalent score for split's native endless run: the universal
    /// per-level payout summed over every level survived.
    private func splitScore(level: Int) -> Int {
        (1...max(1, level)).reduce(0) { $0 + MarathonMath.points(level: $1, quality: 1.0) }
    }

    private var splitBestLevel: Int {
        let stats = app.gameStats[.split]
        return max(stats?.bestScore ?? 0, Int(stats?.bestStat ?? 0))
    }
}
