//
//  LevelMapView.swift
//  wits
//
//  A game-owned difficulty selector. The launcher supplies progression; every
//  visual decision comes from the selected game's world.
//

import SwiftUI

struct DifficultySelectView: View {
    let game: GameID
    var onPlay: (ChallengeDifficulty, Int) -> Void
    var onWeekly: (WeeklyChallenge) -> Void
    var onClose: () -> Void

    @Environment(AppModel.self) private var app
    @State private var difficulty: ChallengeDifficulty = .easy
    @State private var showHelp = false

    private var world: GameWorld { game.world }
    private var level: Int { app.levels.currentLevel(for: game, difficulty: difficulty) }
    private var difficultyColor: Color { world.difficultyColor(difficulty) }

    var body: some View {
        ZStack {
            GameWorldBackdrop(game: game)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    navigation
                    identity
                    difficultyControl
                    playButton
                        .padding(.top, 28)
                    if GameCenterManager.isEnabled {
                        weeklyButton
                            .padding(.top, 11)
                    }
                }
                .padding(.bottom, 30)
                .padding(.horizontal, 22)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { difficulty = app.levels.selectedDifficulty(for: game) }
        .onChange(of: difficulty) { _, value in app.levels.select(value, for: game) }
        .sheet(isPresented: $showHelp) { GameHelpSheet(game: game) }
    }

    private var navigation: some View {
        HStack {
            worldIconButton(symbol: "chevron.left", label: "Close", action: onClose)
            Spacer()
            Text(game.subskill.uppercased())
                .font(.system(size: 10.5, weight: .black, design: world.bodyDesign))
                .foregroundStyle(world.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            worldIconButton(symbol: "questionmark", label: "How to play") { showHelp = true }
        }
        .padding(.top, 10)
    }

    private var identity: some View {
        VStack(spacing: 4) {
            GamePosterArt(game: game)
                .frame(height: 225)
                .frame(maxWidth: 430)

            Text(game.worldTitle())
                .font(.system(size: titleSize, weight: .black, design: world.titleDesign))
                .foregroundStyle(world.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.62)

            Text(game.tagline)
                .font(.system(size: 14.5, weight: .semibold, design: world.bodyDesign))
                .foregroundStyle(world.muted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 7)
        }
    }

    private var difficultyControl: some View {
        VStack(spacing: 0) {
            HStack(spacing: 15) {
                GameDifficultyToken(game: game, difficulty: difficulty)

                VStack(alignment: .leading, spacing: 2) {
                    Text(difficulty.title.uppercased())
                        .font(.system(size: 24, weight: .black, design: world.titleDesign))
                        .foregroundStyle(difficultyColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text("LEVEL \(level)")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundStyle(world.ink)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 27)

            DifficultySlider(game: game, selection: $difficulty)
                .padding(.top, 17)

            HStack(spacing: 0) {
                ForEach(ChallengeDifficulty.allCases) { option in
                    Text(option.shortTitle.uppercased())
                        .font(.system(size: 9.5, weight: .black, design: world.bodyDesign))
                        .foregroundStyle(option == difficulty
                                         ? world.difficultyColor(option)
                                         : world.muted.opacity(0.62))
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .padding(.horizontal, 1)
            .padding(.top, 4)
        }
    }

    private var playButton: some View {
        Button { onPlay(difficulty, level) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("PLAY")
                        .font(.system(size: 25, weight: .black, design: world.titleDesign))
                    Text("\(difficulty.title) · level \(level)")
                        .font(.system(size: 12.5, weight: .bold, design: world.bodyDesign))
                        .monospacedDigit()
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 23, weight: .black))
            }
            .foregroundStyle(world.background)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(difficultyColor,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(alignment: .bottom) {
                Rectangle().fill(world.secondary).frame(height: 4)
            }
        }
        .buttonStyle(PressScale())
        .shadow(color: difficultyColor.opacity(0.25), radius: 12, y: 6)
    }

    private var weeklyButton: some View {
        let challenge = WeeklyChallenge.current(for: game)
        let best = app.levels.weeklyBest(for: challenge)
        return Button { onWeekly(challenge) } label: {
            HStack(spacing: 13) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(world.accent)
                    .frame(width: 42, height: 42)
                    .background(world.accent.opacity(0.13), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("WEEKLY CHALLENGE")
                        .font(.system(size: 14, weight: .black, design: world.titleDesign))
                    Text(best.map { "best · \($0.headline)" } ?? challenge.shortWeekLabel.uppercased())
                        .font(.system(size: 11.5, weight: .bold, design: world.bodyDesign))
                        .foregroundStyle(world.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(world.muted)
            }
            .foregroundStyle(world.ink)
            .padding(.horizontal, 15)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(world.surface,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(world.accent.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(PressScale())
    }

    private var titleSize: CGFloat {
        switch game {
        case .crowdControl, .pegSolitaire: 34
        case .blockEscape, .slidePuzzle: 38
        default: 42
        }
    }

    private func worldIconButton(symbol: String,
                                 label: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(world.ink)
                .frame(width: 44, height: 44)
                .background(world.surface, in: Circle())
                .overlay(Circle().strokeBorder(world.accent.opacity(0.42), lineWidth: 1))
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(label)
    }
}

/// Mode selector for the standalone survival games (Split, Block Fit):
/// one endless mode plus the weekly challenge, no difficulty tracks.
struct StandaloneModeSelectView: View {
    let game: GameID
    var onSurvival: () -> Void
    var onWeekly: (WeeklyChallenge) -> Void
    var onClose: () -> Void

    @Environment(AppModel.self) private var app

    private var world: GameWorld { game.world }
    private var challenge: WeeklyChallenge { .current(for: game) }

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
                        Color.clear.frame(width: 44, height: 44)
                    }
                    .padding(.top, 10)

                    GamePosterArt(game: game)
                        .frame(height: 260)
                        .frame(maxWidth: 440)

                    Text(game.worldTitle())
                        .font(.system(size: 44, weight: .black, design: world.titleDesign))
                        .foregroundStyle(world.ink)
                    Text(game.tagline)
                        .font(.system(size: 14.5, weight: .semibold, design: world.bodyDesign))
                        .foregroundStyle(world.muted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 7)

                    modeButton(title: game == .split ? "SURVIVAL" : "ENDLESS",
                               subtitle: survivalSubtitle,
                               symbol: "infinity",
                               color: world.accent,
                               action: onSurvival)
                        .padding(.top, 30)

                    if GameCenterManager.isEnabled {
                        modeButton(title: "WEEKLY CHALLENGE",
                                   subtitle: weeklySubtitle,
                                   symbol: "calendar.badge.clock",
                                   color: world.secondary) {
                            onWeekly(challenge)
                        }
                        .padding(.top, 11)
                    }
                }
                .padding(.bottom, 30)
                .padding(.horizontal, 22)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var survivalSubtitle: String {
        guard let best = app.levels.marathonBest(for: game) else { return "all-time run" }
        return game == .split
            ? "all-time best · \(WeeklyChallengeScorer.splitLabel(rankValue: best.leaderboardScore))"
            : "all-time best · \(best.score) points"
    }

    private var weeklySubtitle: String {
        app.levels.weeklyBest(for: challenge).map { "best · \($0.headline)" }
            ?? challenge.shortWeekLabel.uppercased()
    }

    private func modeButton(title: String,
                            subtitle: String,
                            symbol: String,
                            color: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .black))
                    .frame(width: 45)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 18, weight: .black, design: world.titleDesign))
                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .bold, design: world.bodyDesign))
                        .opacity(0.72)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 19, weight: .black))
            }
            .foregroundStyle(world.background)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(PressScale())
    }

    private func iconButton(_ symbol: String,
                            label: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(world.ink)
                .frame(width: 44, height: 44)
                .background(world.surface, in: Circle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(label)
    }
}

private struct GameDifficultyToken: View {
    let game: GameID
    let difficulty: ChallengeDifficulty

    private var world: GameWorld { game.world }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                switch game {
                case .crowdControl, .pegSolitaire:
                    Circle().fill(world.surface)
                case .arrowStorm, .blockEscape, .slidePuzzle:
                    Rectangle().fill(world.surface)
                default:
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(world.surface)
                }
            }
            .overlay {
                Image(systemName: game.symbol)
                    .font(.system(size: 27, weight: .black))
                    .foregroundStyle(world.difficultyColor(difficulty))
            }
            .overlay {
                switch game {
                case .crowdControl, .pegSolitaire:
                    Circle().strokeBorder(world.ink.opacity(0.18), lineWidth: 1)
                default:
                    RoundedRectangle(cornerRadius: game == .arrowStorm || game == .blockEscape || game == .slidePuzzle ? 0 : 7)
                        .strokeBorder(world.ink.opacity(0.18), lineWidth: 1)
                }
            }

            Image(systemName: difficulty.symbol)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(world.background)
                .frame(width: 23, height: 23)
                .background(world.difficultyColor(difficulty), in: Circle())
                .offset(x: 6, y: 6)
        }
        .frame(width: 66, height: 66)
        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: difficulty)
        .accessibilityHidden(true)
    }
}

private struct DifficultySlider: View {
    let game: GameID
    @Binding var selection: ChallengeDifficulty

    private var world: GameWorld { game.world }

    var body: some View {
        GeometryReader { proxy in
            let thumb: CGFloat = 52
            let inset = thumb / 2
            let usable = max(1, proxy.size.width - thumb)
            let step = usable / CGFloat(max(1, ChallengeDifficulty.allCases.count - 1))
            let x = inset + CGFloat(selection.ordinal) * step

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: game == .arrowStorm || game == .slidePuzzle ? 0 : 7)
                    .fill(world.surface)
                    .frame(height: 24)

                HStack(spacing: 0) {
                    ForEach(ChallengeDifficulty.allCases) { option in
                        Rectangle()
                            .fill(world.difficultyColor(option))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 10)
                .padding(.horizontal, 7)
                .clipShape(RoundedRectangle(cornerRadius: 3))

                ForEach(ChallengeDifficulty.allCases) { option in
                    Circle()
                        .fill(world.background)
                        .frame(width: 5, height: 5)
                        .position(x: inset + CGFloat(option.ordinal) * step,
                                  y: proxy.size.height / 2)
                }

                Group {
                    if game == .arrowStorm || game == .blockEscape || game == .slidePuzzle {
                        Rectangle().fill(world.ink)
                    } else if game == .crowdControl || game == .pegSolitaire {
                        Circle().fill(world.ink)
                    } else {
                        RoundedRectangle(cornerRadius: 6).fill(world.ink)
                    }
                }
                .frame(width: thumb, height: thumb)
                .overlay {
                    Image(systemName: game.symbol)
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(world.difficultyColor(selection))
                }
                .shadow(color: .black.opacity(0.3), radius: 5, y: 3)
                .position(x: x, y: proxy.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let raw = (gesture.location.x - inset) / usable
                        let ordinal = Int((raw * CGFloat(ChallengeDifficulty.allCases.count - 1)).rounded())
                        let clamped = min(ChallengeDifficulty.allCases.count - 1, max(0, ordinal))
                        guard let next = ChallengeDifficulty(ordinal: clamped), next != selection else { return }
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) { selection = next }
                    }
            )
        }
        .frame(height: 60)
        .accessibilityElement()
        .accessibilityLabel("Difficulty")
        .accessibilityValue(selection.title)
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? 1 : -1
            let ordinal = min(ChallengeDifficulty.allCases.count - 1, max(0, selection.ordinal + delta))
            if let next = ChallengeDifficulty(ordinal: ordinal) { selection = next }
        }
    }
}

private struct GameHelpSheet: View {
    let game: GameID
    @Environment(\.dismiss) private var dismiss

    private var world: GameWorld { game.world }

    var body: some View {
        ZStack {
            GameWorldBackdrop(game: game, patternOpacity: 0.55)
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: game.symbol)
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(world.accent)
                        .frame(width: 48, height: 48)
                        .background(world.surface,
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Text(game.worldTitle("how to play"))
                        .font(.system(size: 25, weight: .black, design: world.titleDesign))
                        .foregroundStyle(world.ink)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(world.ink)
                            .frame(width: 40, height: 40)
                            .background(world.surface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }

                Rectangle().fill(world.accent).frame(height: 4)

                Text(game.cardHow)
                    .font(.system(size: 15.5, weight: .semibold, design: world.bodyDesign))
                    .foregroundStyle(world.ink)

                Text(game.cardAbout)
                    .font(.system(size: 14.5, weight: .regular, design: world.bodyDesign))
                    .foregroundStyle(world.muted)

                Spacer(minLength: 0)
            }
            .padding(22)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(world.background)
    }
}
