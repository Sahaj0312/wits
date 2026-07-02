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
        switch game {
        case .wordConnect:
            WordConnectSafeAreaBackground()
        case .dotsConnect:
            DotsConnectSafeAreaBackground()
        case .oneLine:
            OneLineSafeAreaBackground()
        case .slidePuzzle:
            LinearGradient(colors: [Color(light: 0x4A3A22, dark: 0x33270F),
                                    Color(light: 0x392C18, dark: 0x261C0B)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        case .towerOfHanoi:
            LinearGradient(colors: [Color(light: 0x24536A, dark: 0x16384A),
                                    Color(light: 0x1A465D, dark: 0x102E41)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        default:
            Color.witsBg.ignoresSafeArea()
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let accessory {
                accessory
                    .padding(.bottom, 10)
            }
            GameTopTag(text: "first play tutorial")
                .padding(.bottom, 18)
            ZStack {
                GameHeroArt(game: game, patternOpacity: 0.45)
                GameTutorialHero(game: game)
            }
            .frame(height: 195)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: WitsMetrics.panelRadius, style: .continuous))
            .shadow(color: .witsShadow, radius: 10, y: 6)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("how to play \(game.displayName)")
                        .font(.witsDisplay(30))
                        .foregroundStyle(Color.witsInk)
                        .rise(0.08)
                    Text(game.cardHow)
                        .font(.witsBody(15.5))
                        .foregroundStyle(Color.witsMuted)
                        .rise(0.14)
                    VStack(spacing: 10) {
                        ForEach(game.tutorialSteps.indices, id: \.self) { index in
                            TutorialStepRow(number: index + 1,
                                            text: game.tutorialSteps[index],
                                            tint: game.domain.color)
                        }
                    }
                    .padding(.top, 2)
                    .rise(0.2)
                    TutorialHint(text: game.tutorialHint)
                        .rise(0.26)
                }
                .padding(.top, 22)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Cta(title: "start game", action: onStart)
                .rise(0.32)
                .padding(.top, 12)
            if let onBack {
                QuietButton(title: "back", action: onBack)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.witsBg.ignoresSafeArea())
    }
}

private struct GameTutorialHero: View {
    let game: GameID

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: game.symbol)
                .font(.system(size: 58, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 94, height: 94)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 1.5)
                )
            HStack(spacing: 8) {
                tutorialChip(game.domain.label)
                tutorialChip(game.subskill)
            }
        }
    }

    private func tutorialChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.78))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.10), in: Capsule())
    }
}

private struct TutorialStepRow: View {
    let number: Int
    let text: String
    var tint: Color = .witsAccent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: Circle())
            Text(text)
                .font(.witsBody(15, weight: .semibold))
                .foregroundStyle(Color.witsInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.witsCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.witsLine, lineWidth: 1)
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
                "watch the row of arrows.",
                "answer only the middle arrow's direction.",
                "go quickly, but wrong taps break your streak."
            ]
        case .crowdControl:
            [
                "memorize the glowing dots.",
                "track them while every dot moves.",
                "when they freeze, tap the original targets."
            ]
        case .echoGrid:
            [
                "watch the tiles light up in order.",
                "when the board goes dark, tap them backwards.",
                "perfect rounds make the path longer."
            ]
        case .spotSpeed:
            [
                "watch the centre and the edge at the same time.",
                "pick whether the centre showed a car or bus.",
                "then tap the ring position where the dot flashed."
            ]
        case .colorClash:
            [
                "look at the ink colour, not the word.",
                "tap the matching colour button.",
                "answer before the timer bar drains."
            ]
        case .matchBack:
            [
                "a new card enters the lane each beat.",
                "compare it with the card a few steps back.",
                "answer yes or no for the prompted feature."
            ]
        case .ruleFinder:
            [
                "study the figures already in the grid.",
                "find the rule running across the row or column.",
                "choose the missing figure that completes the pattern."
            ]
        case .numberRush:
            [
                "watch the start value.",
                "keep the running total as operations appear.",
                "submit with the checkmark before the timer bar drains."
            ]
        case .estimator:
            [
                "use the number tiles and operators to build the target.",
                "exact answers score best, but close answers still count.",
                "submit before time runs out."
            ]
        case .oddOneOut:
            [
                "scan the whole grid.",
                "tap the one shape that does not match the rest.",
                "later boards get denser and faster."
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
        case .pathKeeper:
            [
                "watch the token hop across the board.",
                "repeat the path in the same order.",
                "one wrong tap reveals the answer and starts a new path."
            ]
        case .wordConnect:
            [
                "connect letters to spell hidden words.",
                "fill the grid by finding every target word.",
                "clear two boards to unlock the next level."
            ]
        case .memoryLock:
            [
                "guess the hidden word in six tries.",
                "use the green, yellow, and gray clues.",
                "remember them quickly before the clues fade."
            ]
        case .dotsConnect:
            [
                "draw paths between matching dots.",
                "cover every square on the board.",
                "paths cannot cross each other."
            ]
        case .oneLine:
            [
                "choose a starting dot on the graph.",
                "move dot to dot along unused segments.",
                "solve the board when every segment has been used once."
            ]
        case .towerOfHanoi:
            [
                "move one top disk at a time.",
                "never place a bigger disk on a smaller disk.",
                "move the stack to the target tower in as few moves as you can."
            ]
        case .slidePuzzle:
            [
                "tap any tile in the same row or column as the gap to slide it.",
                "put the numbers back in order, reading left to right.",
                "fewer moves and a faster solve score higher."
            ]
        case .split:
            [
                "tap the left side to keep the flyer up.",
                "tap the right-side targets before they pass.",
                "avoid the look-alike; one mistake ends the run."
            ]
        }
    }
}
