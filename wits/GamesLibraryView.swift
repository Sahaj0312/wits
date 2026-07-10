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
        GameID.allCases.filter(\.isPlayable)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WITS")
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .foregroundStyle(Color(hexAny: 0xFF4E77))
                        Text("choose a game")
                            .font(.system(size: 29, weight: .black, design: .default))
                            .foregroundStyle(.white)
                    }
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
            }
            .padding(.horizontal, WitsMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .background(Color(hexAny: 0x09090B).ignoresSafeArea())
        .fullScreenCover(item: $launch) { g in
            GameLauncher(game: g)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear { GameCenterManager.shared.setAccessPointActive(true) }
        .onChange(of: launch) { _, value in
            GameCenterManager.shared.setAccessPointActive(value == nil && !showSettings)
        }
        .onChange(of: showSettings) { _, value in
            GameCenterManager.shared.setAccessPointActive(!value && launch == nil)
        }
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
            .overlay(alignment: .topTrailing) {
                if g.isStandalone {
                    survivalSticker.offset(x: 5, y: -5)
                }
            }
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
            let best = app.levels.marathonBest(for: g)?.depth ?? 0
            return best > 0 ? "best \(best)" : "no runs yet"
        }
        let difficulty = app.levels.selectedDifficulty(for: g)
        let level = app.levels.currentLevel(for: g, difficulty: difficulty)
        return "\(difficulty.title) · level \(level)"
    }

    /// Tilted sticker in the reference-app spirit — marks split as the one
    /// one-life survival mode on the shelf.
    private var survivalSticker: some View {
        Text("survival!")
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(hexAny: 0xE84545), in: Capsule())
            .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
            .rotationEffect(.degrees(7))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
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
    @State private var lastStars = 0
    @State private var lastQuality = 0.0
    @State private var lastImproved = false
    @State private var attempt = 0   // bump to force a fresh game instance
    @State private var pauseController = GamePauseController()

    private enum Phase { case selector, tutorial, playing, levelResult }

    var body: some View {
        switch phase {
        case .selector:
            if game == .split {
                // Split is survival-only: no selector to show, and its screen
                // carries its own intro/game-over chrome — go straight there.
                GameWorldBackdrop(game: .split)
                    .onAppear { startRun() }
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
            FirstPlayTutorial(
                game: game,
                onStart: {
                    GameTutorialStore.markSeen(game)
                    pauseController.reset()
                    withAnimation(.easeOut(duration: 0.2)) { phase = .playing }
                },
                onBack: {
                    pauseController.reset()
                    if game == .split {
                        dismiss()   // no map page behind split's tutorial
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) { phase = .selector }
                    }
                }
            )
        case .playing:
            if game == .split {
                SplitSurvivalScreen(
                    best: app.levels.marathonBest(for: .split)?.depth ?? splitBestLevel,
                    startsImmediately: false,
                    onRunComplete: { level, depth, trials in
                        let result = splitResult(level: level, depth: depth, trials: trials)
                        app.recordStandaloneGameResult(result)
                        app.recordMarathon(game: .split, depth: level, score: splitScore(level: level))
                    },
                    onQuit: { dismiss() }
                )
            } else {
                GeometryReader { _ in
                    ZStack {
                        // Full-bleed stage matching the game's surface, so no
                        // app-background band shows in the safe areas.
                        GameStageBackground(game: game)
                        makeGameView(game, config: .challenge(game,
                                                              difficulty: playDifficulty,
                                                              trackLevel: playLevel,
                                                              persisted: app.difficultyFor(game),
                                                              freePlay: true,
                                                              pauseController: pauseController)) { r in
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
                stars: lastStars,
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

    private func startRun() {
        pauseController.reset()
        attempt += 1
        let needsTutorial = GameTutorialStore.shouldShow(for: game, hasPlayed: app.hasPlayed(game))
        withAnimation(.easeOut(duration: 0.2)) { phase = needsTutorial ? .tutorial : .playing }
    }

    private func handle(_ result: GameResult) {
        pauseController.reset()
        // Snapshot before recording — recordGameResult merges this run in.
        let starsBefore = app.levels.stars(for: game,
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
        let stars = StarGrader.stars(quality: quality)

        lastStars = stars
        lastQuality = quality
        lastImproved = stars > starsBefore || (stars >= 1 && quality > qualityBefore)
        withAnimation(.easeOut(duration: 0.2)) { phase = .levelResult }
        AdManager.shared.gameCompleted()
        AdManager.shared.maybeShowInterstitial()
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
