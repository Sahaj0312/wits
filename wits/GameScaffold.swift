//
//  GameScaffold.swift
//  wits
//
//  Shared chrome for every game (onboarding fit test + the main-app library):
//  the phase machine, the top tag, the pre-game hero/explainer, the "you've got
//  it" interstitial, and the tutorial hint. Extracted from OnboardingGames so
//  the new adaptive games reuse exactly the same look and feel.
//

import SwiftUI

enum GamePhase {
    case intro, tutorial, ready, playing
}

/// Full-bleed stage painted behind a running game. Hosts draw this edge-to-edge
/// (through both safe areas) so a game's surface color never bands at the top
/// or bottom of the screen, no matter how the playfield itself is inset.
struct GameStageBackground: View {
    let game: GameID

    var body: some View {
        GameWorldBackdrop(game: game, patternOpacity: 0.48)
    }
}

struct GameTopTag: View {
    var text: String
    var body: some View {
        HStack {
            Wordmark()
            Spacer()
            Text(text)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.witsFaint)
        }
    }
}

/// Hero panel for the pre-game explainer: fixed navy stage with soft accent
/// glows, so the teal illustration reads the same in light and dark mode.
struct HeroPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(light: 0x243155, dark: 0x232E55), Color(light: 0x161F3A, dark: 0x141B33)],
                startPoint: .top, endPoint: .bottom
            )
            Circle()
                .fill(Color.witsAccent.opacity(0.10))
                .frame(width: 220, height: 220)
                .offset(x: -110, y: -80)
            Circle()
                .fill(Color.witsAccent.opacity(0.08))
                .frame(width: 180, height: 180)
                .offset(x: 130, y: 90)
            content
        }
        .frame(height: 195)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous))
        .shadow(color: .witsShadow, radius: 10, y: 6)
    }
}

/// Pre-game explainer card: hero illustration, "X tests your Y" headline,
/// how it plays, and what it measures.
struct GameExplainer<Hero: View>: View {
    var tag: String
    var title: String
    var skill: String
    var how: String
    var why: String
    var ctaTitle: String = "start tutorial"
    var onStart: () -> Void
    @ViewBuilder var hero: Hero

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GameTopTag(text: tag)
                .padding(.bottom, 18)
            HeroPanel { hero }
                .rise()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(title) tests your \(Text(skill).foregroundStyle(Color.witsAccent)).")
                        .font(.witsDisplay(27))
                        .foregroundStyle(Color.witsInk)
                        .rise(0.08)
                    Text(how)
                        .font(.witsBody(15.5))
                        .foregroundStyle(Color.witsMuted)
                        .rise(0.16)
                    Text(why)
                        .font(.witsBody(15.5))
                        .foregroundStyle(Color.witsMuted)
                        .rise(0.22)
                }
                .padding(.top, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Cta(title: ctaTitle, action: onStart)
                .rise(0.3)
                .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }
}

/// "Nice work" interstitial between tutorial and the scored run.
struct GameReady: View {
    var onPlay: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                Text("you've got it")
                    .font(.witsDisplay(28))
                    .foregroundStyle(Color.witsInk)
                Text("now it counts. respond as quickly as possible while avoiding mistakes.")
                    .font(.witsBody(16))
                    .foregroundStyle(Color.witsMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .cardSurface()
            .rise()
            Spacer()
            Cta(title: "let's play", action: onPlay)
                .rise(0.15)
                .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }
}

struct TutorialHint: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.witsBody(14, weight: .semibold))
            .foregroundStyle(Color.witsMuted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.witsTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

enum GameTutorialStore {
    static let onboardingGames: [GameID] = [.arrowStorm, .crowdControl, .echoGrid]

    private static let keyPrefix = "wits.gameTutorialSeen."

    static func shouldShow(for game: GameID, hasPlayed: Bool) -> Bool {
        game.isPlayable && !hasPlayed && !hasSeen(game)
    }

    static func hasSeen(_ game: GameID) -> Bool {
        UserDefaults.standard.bool(forKey: key(for: game))
    }

    static func markSeen(_ game: GameID) {
        UserDefaults.standard.set(true, forKey: key(for: game))
    }

    static func markSeen(_ games: [GameID]) {
        for game in games { markSeen(game) }
    }

    private static func key(for game: GameID) -> String {
        keyPrefix + game.rawValue
    }
}

struct FirstPlayTutorial: View {
    let game: GameID
    var accessory: AnyView? = nil
    var onStart: () -> Void
    var onBack: (() -> Void)? = nil

    private var world: GameWorld { game.world }

    var body: some View {
        ZStack {
            GameWorldBackdrop(game: game)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        if let onBack {
                            Button(action: onBack) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 17, weight: .black))
                                    .foregroundStyle(world.ink)
                                    .frame(width: 44, height: 44)
                                    .background(world.surface, in: Circle())
                            }
                            .buttonStyle(PressScale())
                            .accessibilityLabel("Back")
                        }
                        Spacer()
                        Text("FIRST PLAY")
                            .font(.system(size: 10.5, weight: .black, design: .monospaced))
                            .foregroundStyle(world.muted)
                    }

                    if let accessory {
                        accessory.padding(.top, 10)
                    }

                    GamePosterArt(game: game)
                        .frame(height: 190)
                        .frame(maxWidth: 430)
                        .frame(maxWidth: .infinity)

                    Text(game.worldTitle("how to play"))
                        .font(.system(size: 31, weight: .black, design: world.titleDesign))
                        .foregroundStyle(world.ink)
                        .padding(.top, 2)

                    Text(game.cardHow)
                        .font(.system(size: 15, weight: .semibold, design: world.bodyDesign))
                        .foregroundStyle(world.muted)
                        .padding(.top, 10)

                    VStack(spacing: 9) {
                        ForEach(game.tutorialSteps.indices, id: \.self) { index in
                            TutorialStepRow(game: game,
                                            number: index + 1,
                                            text: game.tutorialSteps[index])
                        }
                    }
                    .padding(.top, 20)

                    Text(game.tutorialHint)
                        .font(.system(size: 12.5, weight: .bold, design: world.bodyDesign))
                        .foregroundStyle(world.ink)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(world.raised,
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .padding(.top, 10)

                    Button(action: onStart) {
                        HStack {
                            Text("START GAME")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 17, weight: .black, design: world.titleDesign))
                        .foregroundStyle(world.background)
                        .padding(.horizontal, 19)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(world.accent,
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(PressScale())
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct TutorialStepRow: View {
    let game: GameID
    let number: Int
    let text: String

    private var world: GameWorld { game.world }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(world.background)
                .frame(width: 28, height: 28)
                .background(world.accent, in: Circle())
            Text(text)
                .font(.system(size: 14.5, weight: .semibold, design: world.bodyDesign))
                .foregroundStyle(world.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(world.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(world.ink.opacity(0.12), lineWidth: 1)
        )
    }
}

extension GameID {
    var tutorialHint: String {
        "the next screen is scored. \(tagline)"
    }

    var tutorialSteps: [String] {
        switch self {
        case .arrowStorm:
            [
                "watch the row of arrows — answer only the middle one's direction.",
                "beat the shrinking deadline: too slow counts as a miss.",
                "you have three hearts. every miss costs one — lose them all and the run ends."
            ]
        case .crowdControl:
            [
                "memorize the glowing dots, then track them while every dot moves.",
                "when they freeze, tap the ones you were tracking — each one you catch is a point.",
                "you have three hearts. every target you lose costs one — lose them all and the run ends."
            ]
        case .echoGrid:
            [
                "watch the tiles light up in order.",
                "when the board goes dark, tap them backwards.",
                "you get a fixed set of rounds — clear enough of them to pass."
            ]
        case .colorClash:
            [
                "look at the ink colour, not the word.",
                "tap the matching colour button.",
                "answer before the timer bar drains."
            ]
        case .tileShift:
            [
                "read the current rule.",
                "tap the tile that matches by that rule.",
                "adapt quickly when the rule changes."
            ]
        case .lastSeen:
            [
                "tap an object you have not chosen yet.",
                "keep the earlier picks in mind.",
                "never tap the same object twice."
            ]
        case .slidePuzzle:
            [
                "tap any tile in the same row or column as the gap to slide it.",
                "put the numbers back in order, reading left to right.",
                "fewer moves and a faster solve score higher."
            ]
        case .blockEscape:
            [
                "drag blocks along rows and columns — they can't jump or turn.",
                "clear a path for the big red block.",
                "walk it out the bottom exit in as few moves as you can."
            ]
        case .pegSolitaire:
            [
                "tap a peg, then the empty hole two spaces away.",
                "the peg you jumped over is removed.",
                "clear the board down to a single peg."
            ]
        case .waterSort:
            [
                "tap a tube to pick it up, tap another to pour.",
                "a pour lands only on a matching colour or an empty tube.",
                "sort every colour into its own tube in as few pours as you can."
            ]
        case .mahjong:
            [
                "tap a free tile — one with an open side and nothing on top — to lift it into the rack.",
                "when its twin lands in the rack, the pair vanishes.",
                "clear every tile before the rack fills with singles. undo rewinds a risky pick."
            ]
        case .crossword:
            [
                "tap a square, then type — tap the square again to flip between across and down.",
                "every answer crosses others, so each letter you land is a free hint elsewhere.",
                "stuck? the bulb reveals the selected square, but clean solves grade higher."
            ]
        case .split:
            [
                "tap the left side to keep the flyer up.",
                "tap the right-side targets before they pass.",
                "avoid the look-alike; one mistake ends the run."
            ]
        case .blockFit:
            [
                "drag pieces from the tray onto the board.",
                "fill a full row or column to clear it.",
                "pieces never rotate — use the NEXT row to plan ahead; the run ends when nothing fits."
            ]
        case .fuse:
            [
                "swipe in any direction — every cell slides as far as it can.",
                "matching numbers fuse into one and double.",
                "keep the board open and build the biggest cell you can — the run ends when nothing can move."
            ]
        case .snake:
            [
                "swipe to steer — the snake never stops moving.",
                "eat the apples: every one adds a segment and speeds you up.",
                "don't hit the walls or your own body — one clip ends the run."
            ]
        case .tower:
            [
                "tap to drop the sliding block onto the stack.",
                "the overhang is sliced off — what's left is your new top.",
                "land dead-center to keep the block whole; miss the stack entirely and the run ends."
            ]
        }
    }
}
