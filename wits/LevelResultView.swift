//
//  LevelResultView.swift
//  wits
//
//  A result screen rendered inside the game that produced it.
//

import SwiftUI

struct DifficultyLevelResultView: View {
    let game: GameID
    let difficulty: ChallengeDifficulty
    let level: Int
    let passed: Bool
    let quality: Double
    let improved: Bool
    let onRetry: () -> Void
    let onNext: () -> Void
    let onSelector: () -> Void

    private var world: GameWorld { game.world }
    private var difficultyColor: Color { world.difficultyColor(difficulty) }
    private var nextLevel: Int { level == Int.max ? Int.max : level + 1 }

    var body: some View {
        ZStack {
            GameWorldBackdrop(game: game)

            VStack(spacing: 0) {
                Spacer(minLength: 18)

                resultMark

                Text(difficulty.title.uppercased())
                    .font(.system(size: 11, weight: .black, design: world.bodyDesign))
                    .foregroundStyle(difficultyColor)
                    .padding(.top, 18)

                Text(passed ? "LEVEL \(level) CLEARED" : "LEVEL \(level)")
                    .font(.system(size: 31, weight: .black, design: world.titleDesign))
                    .foregroundStyle(world.ink)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.68)
                    .padding(.top, 5)

                Text(headline)
                    .font(.system(size: 15, weight: .semibold, design: world.bodyDesign))
                    .foregroundStyle(world.muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 9)

                Text(passed ? "PASSED" : "NOT YET")
                    .font(.system(size: 15, weight: .black, design: world.bodyDesign))
                    .foregroundStyle(passed ? world.background : world.muted)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(
                        passed ? AnyShapeStyle(world.accent) : AnyShapeStyle(world.surface),
                        in: Capsule()
                    )
                    .overlay {
                        if !passed {
                            Capsule().strokeBorder(world.muted.opacity(0.34), lineWidth: 1)
                        }
                    }
                    .padding(.top, 27)

                Text("\(Int((quality * 100).rounded()))%")
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .foregroundStyle(world.muted)
                    .monospacedDigit()
                    .padding(.top, 13)

                Spacer(minLength: 24)

                actions
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .frame(maxWidth: 560)
        }
        .overlay {
            if improved && passed { ConfettiBurst().ignoresSafeArea() }
        }
    }

    private var resultMark: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                switch game {
                case .crowdControl, .pegSolitaire:
                    Circle().fill(world.surface)
                case .arrowStorm, .blockEscape, .slidePuzzle:
                    Rectangle().fill(world.surface)
                default:
                    RoundedRectangle(cornerRadius: 7).fill(world.surface)
                }
            }
            .overlay {
                Image(systemName: passed ? "checkmark" : game.symbol)
                    .font(.system(size: 35, weight: .black))
                    .foregroundStyle(difficultyColor)
            }

            Image(systemName: difficulty.symbol)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(world.background)
                .frame(width: 27, height: 27)
                .background(difficultyColor, in: Circle())
                .offset(x: 7, y: 7)
        }
        .frame(width: 86, height: 86)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if passed {
                Button(action: onNext) {
                    HStack {
                        Text("LEVEL \(nextLevel)")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 17, weight: .black, design: world.titleDesign))
                    .foregroundStyle(world.background)
                    .padding(.horizontal, 19)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(difficultyColor,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(PressScale())
            }

            Button(action: onRetry) {
                Text(passed ? "REPLAY" : "TRY AGAIN")
                    .font(.system(size: 15, weight: .black, design: world.bodyDesign))
                    .foregroundStyle(world.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(world.surface,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(world.accent.opacity(0.42), lineWidth: 1)
                    )
            }
            .buttonStyle(PressScale())

            Button(action: onSelector) {
                Text("CHANGE DIFFICULTY")
                    .font(.system(size: 11.5, weight: .black, design: world.bodyDesign))
                    .foregroundStyle(world.muted)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }

    private var headline: String {
        switch (passed, improved) {
        case (false, _): "same challenge. another attempt."
        case (true, true): "new best. next level unlocked."
        case (true, false): "cleared. keep the track moving."
        }
    }
}

struct WeeklyChallengeResultView: View {
    let game: GameID
    let challenge: WeeklyChallenge
    let score: WeeklyChallengeScore
    let best: WeeklyChallengeBest?
    let improved: Bool
    let onRetry: () -> Void
    let onDone: () -> Void

    private var world: GameWorld { game.world }

    var body: some View {
        ZStack {
            GameWorldBackdrop(game: game)
            VStack(spacing: 0) {
                Spacer(minLength: 22)

                Image(systemName: improved ? "trophy.fill" : "calendar.badge.checkmark")
                    .font(.system(size: 38, weight: .black))
                    .foregroundStyle(world.background)
                    .frame(width: 88, height: 88)
                    .background(world.accent, in: Circle())
                    .overlay(Circle().strokeBorder(world.ink.opacity(0.18), lineWidth: 1))

                Text("WEEKLY CHALLENGE")
                    .font(.system(size: 11, weight: .black, design: world.bodyDesign))
                    .foregroundStyle(world.accent)
                    .padding(.top, 20)

                Text(improved ? "NEW WEEKLY BEST" : "RUN COMPLETE")
                    .font(.system(size: 30, weight: .black, design: world.titleDesign))
                    .foregroundStyle(world.ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, 5)

                Text(score.headline)
                    .font(.system(size: 44, weight: .black, design: world.titleDesign))
                    .foregroundStyle(world.accent)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                    .padding(.top, 28)

                Text(score.detail)
                    .font(.system(size: 14, weight: .bold, design: world.bodyDesign))
                    .foregroundStyle(world.muted)
                    .padding(.top, 7)

                if let best {
                    HStack {
                        Text("WEEK BEST")
                        Spacer()
                        Text(best.headline)
                    }
                    .font(.system(size: 12, weight: .black, design: world.bodyDesign))
                    .foregroundStyle(world.ink)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(world.surface,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(.top, 25)
                }

                Spacer(minLength: 28)

                Button(action: onRetry) {
                    HStack {
                        Text("RUN IT AGAIN")
                        Spacer()
                        Image(systemName: "arrow.clockwise")
                    }
                    .font(.system(size: 17, weight: .black, design: world.titleDesign))
                    .foregroundStyle(world.background)
                    .padding(.horizontal, 19)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(world.accent,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(PressScale())

                Button {
                    GameCenterManager.shared.presentDashboard()
                } label: {
                    Label("LEADERBOARD", systemImage: "trophy")
                        .font(.system(size: 14, weight: .black, design: world.bodyDesign))
                        .foregroundStyle(world.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(world.surface,
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(world.accent.opacity(0.42), lineWidth: 1)
                        )
                }
                .buttonStyle(PressScale())
                .padding(.top, 10)

                Button(action: onDone) {
                    Text("BACK TO MODES")
                        .font(.system(size: 11.5, weight: .black, design: world.bodyDesign))
                        .foregroundStyle(world.muted)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .frame(maxWidth: 560)
        }
        .overlay {
            if improved { ConfettiBurst().ignoresSafeArea() }
        }
    }
}
