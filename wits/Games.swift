//
//  Games.swift
//  wits
//
//  Binds each GameID to its playable view + adaptive policy, and gives the
//  workout host one entry point (`makeGameView`) to launch any game in a
//  difficulty-seeded, GameResult-emitting run.
//

import SwiftUI

enum ArrowStorm: Game {
    static let id = GameID.arrowStorm
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(FlankerScreen(cfg: config, onResult: onComplete))
    }
}

enum CrowdControl: Game {
    static let id = GameID.crowdControl
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(TrackerScreen(cfg: config, onResult: onComplete))
    }
}

enum EchoGrid: Game {
    static let id = GameID.echoGrid
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(SpanScreen(cfg: config, onResult: onComplete))
    }
}

/// Single dispatch the host uses to launch any game.
@MainActor
func makeGameView(_ id: GameID, config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
    switch id {
    case .arrowStorm:  ArrowStorm.makeView(config: config, onComplete: onComplete)
    case .crowdControl: CrowdControl.makeView(config: config, onComplete: onComplete)
    case .echoGrid:    EchoGrid.makeView(config: config, onComplete: onComplete)
    default:           AnyView(ComingSoonGame(id: id, onComplete: onComplete))
    }
}

func advanceDifficulty(for id: GameID, _ s: DifficultyState, accuracy: Double) -> DifficultyState {
    switch id {
    case .arrowStorm:  ArrowStorm.advance(s, accuracy: accuracy)
    case .crowdControl: CrowdControl.advance(s, accuracy: accuracy)
    case .echoGrid:    EchoGrid.advance(s, accuracy: accuracy)
    default:           Staircase.adjust(s, accuracy: accuracy)
    }
}

/// Placeholder for roadmap games (Spot Speed / Color Clash / …) so the library
/// and host stay total before those games ship.
struct ComingSoonGame: View {
    var id: GameID
    var onComplete: (GameResult) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: id.symbol)
                .font(.system(size: 44, weight: .heavy))
                .foregroundStyle(Color.witsAccent)
            Text(id.displayName)
                .font(.witsDisplay(28))
                .foregroundStyle(Color.witsInk)
            Text("this game is coming soon.")
                .font(.witsBody(16))
                .foregroundStyle(Color.witsMuted)
            Spacer()
            Cta(title: "skip for now") {
                onComplete(GameResult(game: id, score: 0, accuracy: 0))
            }
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }
}
