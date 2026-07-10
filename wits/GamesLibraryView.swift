//
//  GamesLibraryView.swift
//  wits
//
//  The home screen: every game as a card with its star progress, the daily
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
                        WitsBrandMark()
                        Text("games")
                            .font(.witsDisplay(30))
                            .foregroundStyle(Color.witsInk)
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
        .background(Color.witsBg.ignoresSafeArea())
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
                .foregroundStyle(Color.witsInk)
                .frame(width: 44, height: 44)
                .background(Color.witsCard, in: Circle())
                .overlay(Circle().strokeBorder(Color.witsLine, lineWidth: 1.5))
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
                .foregroundStyle(Color.witsInk)
                .frame(width: 44, height: 44)
                .background(Color.witsCard, in: Circle())
                .overlay(Circle().strokeBorder(Color.witsLine, lineWidth: 1.5))
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
                g.posterBackground
                GamePosterArt(game: g)
                VStack(alignment: .leading, spacing: 6) {
                    Text(g.displayName)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(g.posterAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Capsule()
                        .fill(g.posterAccent)
                        .frame(width: 32, height: 3.5)
                }
                .padding(.horizontal, 14)
                .padding(.top, 13)
            }
            .aspectRatio(0.74, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                progressPill(g).padding(9)
            }
            .padding(4)
            .background(Color.witsCard, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .strokeBorder(Color.witsLine, lineWidth: 1)
            )
            .shadow(color: .witsShadow, radius: 10, y: 5)
            .overlay(alignment: .topTrailing) {
                if g.isStandalone {
                    survivalSticker.offset(x: 5, y: -5)
                }
            }
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(Text("\(g.displayName). \(g.tagline)"))
    }

    /// One quiet line of progression per card: star total for map games,
    /// best level for split.
    private func progressPill(_ g: GameID) -> some View {
        HStack(spacing: 4) {
            Image(systemName: g.isStandalone ? "trophy.fill" : "star.fill")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Color.witsGold)
            Text(progressLabel(g))
                .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.black.opacity(0.35), in: Capsule())
    }

    private func progressLabel(_ g: GameID) -> String {
        if g.isStandalone {
            let best = app.levels.marathonBest(for: g)?.depth ?? 0
            return best > 0 ? "best \(best)" : "no runs yet"
        }
        return "\(app.levels.totalStars(for: g))/\(3 * LevelLadder.levelCount(for: g))"
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

/// Pre-game chooser: the star map, then exam or marathon runs in a
/// full-screen cover (design doc §1/§4).
private struct GameLauncher: View {
    let game: GameID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .map
    @State private var playLevel = 1
    @State private var marathonActive = false
    @State private var marathonDepth = 0     // last level cleared this run
    @State private var marathonScore = 0
    @State private var marathonNewBest = false
    @State private var lastStars = 0
    @State private var lastQuality = 0.0
    @State private var lastImproved = false
    @State private var attempt = 0   // bump to force a fresh game instance
    @State private var pauseController = GamePauseController()

    private enum Phase { case map, tutorial, playing, levelResult, marathonResult }

    var body: some View {
        switch phase {
        case .map:
            if game == .split {
                // Split is survival-only: no star map to show, and its screen
                // carries its own intro/game-over chrome — go straight there.
                Color.witsBg.ignoresSafeArea()
                    .onAppear { startRun() }
            } else {
                LevelMapView(
                    game: game,
                    onPlayLevel: { level in
                        marathonActive = false
                        playLevel = level
                        startRun()
                    },
                    onPlayMarathon: {
                        marathonActive = true
                        marathonDepth = 0
                        marathonScore = 0
                        playLevel = 1
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
                        withAnimation(.easeOut(duration: 0.2)) { phase = .map }
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
                        makeGameView(game, config: .level(game,
                                                          mapLevel: playLevel,
                                                          persisted: app.difficultyFor(game),
                                                          freePlay: true,
                                                          marathon: marathonActive,
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
                    .overlay(alignment: .top) {
                        if marathonActive {
                            marathonBanner
                        }
                    }
                    .overlay {
                        if !game.usesEmbeddedQuitControl, !pauseController.isPaused {
                            GamePauseButtonLayer {
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
                                                  if marathonActive, marathonDepth >= 1 {
                                                      endMarathon()
                                                  } else {
                                                      withAnimation { phase = .map }
                                                  }
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
            LevelResultView(
                game: game,
                level: playLevel,
                stars: lastStars,
                quality: lastQuality,
                improved: lastImproved,
                nextUnlocked: playLevel < LevelLadder.levelCount(for: game)
                    && app.levels.isUnlocked(game, level: playLevel + 1),
                onRetry: { startRun() },
                onNext: {
                    playLevel += 1
                    startRun()
                },
                onMap: { withAnimation(.easeOut(duration: 0.2)) { phase = .map } }
            )
        case .marathonResult:
            MarathonResultView(
                game: game,
                depth: marathonDepth,
                score: marathonScore,
                best: app.levels.marathonBest(for: game),
                isNewBest: marathonNewBest,
                onRunAgain: {
                    marathonDepth = 0
                    marathonScore = 0
                    playLevel = 1
                    startRun()
                },
                onMap: { withAnimation(.easeOut(duration: 0.2)) { phase = .map } }
            )
        }
    }

    /// A quiet strip so a marathon run always shows where the chain stands.
    private var marathonBanner: some View {
        Label("marathon · level \(playLevel)", systemImage: "infinity")
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .monospacedDigit()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.35), in: Capsule())
            .padding(.top, 6)
            .allowsHitTesting(false)
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
        let starsBefore = app.levels.stars(for: game, level: playLevel)
        let qualityBefore = app.levels.record(for: game, level: playLevel)?.bestQuality ?? 0
        var tagged = result
        tagged.raw["mapLevel"] = Double(playLevel)
        if marathonActive { tagged.raw["marathon"] = 1 }
        let scored = app.recordGameResult(tagged)
        let quality = scored.performanceQuality ?? scored.accuracy
        let stars = StarGrader.stars(quality: quality)

        if marathonActive {
            if stars >= 1 {
                marathonScore += MarathonMath.points(level: playLevel, quality: quality)
                marathonDepth = playLevel
                if playLevel >= LevelLadder.levelCount(for: game) {
                    endMarathon()   // cleared the whole map — go out on top
                } else {
                    playLevel += 1
                    attempt += 1    // next link, fresh instance
                }
            } else {
                endMarathon()
            }
            return
        }

        lastStars = stars
        lastQuality = quality
        lastImproved = stars > starsBefore || (stars >= 1 && quality > qualityBefore)
        withAnimation(.easeOut(duration: 0.2)) { phase = .levelResult }
        AdManager.shared.gameCompleted()
        AdManager.shared.maybeShowInterstitial()
    }

    private func endMarathon() {
        marathonNewBest = marathonDepth >= 1
            && app.recordMarathon(game: game, depth: marathonDepth, score: marathonScore)
        withAnimation(.easeOut(duration: 0.2)) { phase = .marathonResult }
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
