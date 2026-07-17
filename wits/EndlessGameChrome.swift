//
//  EndlessGameChrome.swift
//  wits
//
//  Shared chrome for the endless hearts-and-continue games (arrow storm,
//  crowd control, color clash, tile shift): the snake-style mode select, the
//  in-run HUD (quit / mode + all-time chips / pause), and the hearts row.
//  Extracted once the third copy appeared; each game keeps its own trial
//  flow and run lifecycle.
//

import SwiftUI

enum EndlessMetrics {
    /// Horizontal inset for run content (trial cards, answer buttons, boards).
    /// Wider than WitsMetrics.screenPadding on purpose, full-bleed cards on a
    /// phone read as "too wide" (user feedback 2026-07-14).
    static let sidePadding: CGFloat = 34
}

// MARK: - Mode select

/// Pre-game screen for endless games: no levels, just the three modes with
/// their own bests and the all-time best underneath.
struct EndlessModeSelectView: View {
    let game: GameID
    var onPlay: (ChallengeDifficulty) -> Void
    var onClose: () -> Void
    var onHelp: (() -> Void)? = nil

    @Environment(AppModel.self) private var app

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
                        if let onHelp {
                            iconButton("questionmark", label: "How to play", action: onHelp)
                        } else {
                            Color.clear.frame(width: 44, height: 44)
                        }
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
        .buttonStyle(TactilePressScale(feedback: .primary))
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
        .buttonStyle(TactilePressScale())
        .accessibilityLabel(label)
    }
}

// MARK: - Run HUD

/// Top bar during an endless run: quit, mode-score + all-time chips, pause.
struct EndlessRunHUD: View {
    let game: GameID
    let difficulty: ChallengeDifficulty
    let score: Int
    let allTimeBest: Int
    let onQuit: () -> Void
    let onPause: () -> Void

    private var world: GameWorld { game.world }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onQuit) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(world.ink)
                    .frame(width: 44, height: 44)
                    .background(world.surface.opacity(0.9), in: Circle())
            }
            .buttonStyle(TactilePressScale())
            .accessibilityLabel("quit run")

            chip(title: "\(difficulty.shortTitle.uppercased()) MODE",
                 value: score,
                 tint: world.ink,
                 crowned: false)
            chip(title: "ALL TIME",
                 value: max(allTimeBest, score),
                 tint: world.accent,
                 crowned: true)

            Button(action: onPause) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(world.ink)
                    .frame(width: 44, height: 44)
                    .background(world.surface.opacity(0.9), in: Circle())
            }
            .buttonStyle(TactilePressScale())
            .accessibilityLabel("pause game")
        }
    }

    private func chip(title: String, value: Int, tint: Color, crowned: Bool) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 10.5, weight: .black, design: world.bodyDesign))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(String(value))
                .font(.system(size: 21, weight: .black, design: world.titleDesign))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: value)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
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
}

// MARK: - Hearts

/// The lives row. After a rewarded continue every heart shows grey, the
/// player is running on their last life.
struct EndlessHeartsRow: View {
    let game: GameID
    let lives: Int
    let maxLives: Int
    let usedContinue: Bool

    private static let heartColor = Color(hexAny: 0xEF476F)

    var body: some View {
        HStack(spacing: 9) {
            ForEach(0..<maxLives, id: \.self) { i in
                Image(systemName: i < lives ? "heart.fill" : "heart")
                    .font(.system(size: 21, weight: .black))
                    .foregroundStyle(i < lives ? Self.heartColor : game.world.muted.opacity(0.45))
                    .scaleEffect(i < lives ? 1 : 0.88)
                    .animation(.snappy(duration: 0.25), value: lives)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(usedContinue ? "last life" : "\(lives) of \(maxLives) lives left")
    }
}
