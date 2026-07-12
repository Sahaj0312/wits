//
//  Games.swift
//  wits
//
//  Binds each GameID to its playable view and gives the launcher one entry
//  point (`makeGameView`) to launch any game in a difficulty-seeded,
//  GameResult-emitting run.
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
        AnyView(ArcadeSpriteHost(cfg: config,
                                 game: TracePathArcade(id: .echoGrid,
                                                       reverse: true,
                                                       seed: config.resolvedRandomSeed()),
                                 onResult: onComplete))
    }
}

enum ColorClash: Game {
    static let id = GameID.colorClash
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(ColorClashScreen(cfg: config, onResult: onComplete))
    }
}

enum TileShift: Game {
    static let id = GameID.tileShift
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(TileShiftScreen(cfg: config, onResult: onComplete))
    }
}

enum LastSeen: Game {
    static let id = GameID.lastSeen
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(LastSeenScreen(cfg: config, onResult: onComplete))
    }
}

enum SlidePuzzle: Game {
    static let id = GameID.slidePuzzle
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(SlidePuzzleScreen(cfg: config, onResult: onComplete))
    }
}

enum BlockEscape: Game {
    static let id = GameID.blockEscape
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(BlockEscapeScreen(cfg: config, onResult: onComplete))
    }
}

enum PegSolitaire: Game {
    static let id = GameID.pegSolitaire
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(PegSolitaireScreen(cfg: config, onResult: onComplete))
    }
}

/// Single dispatch the launcher uses to open any game.
@MainActor
func makeGameView(_ id: GameID, config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
    switch id {
    case .arrowStorm:  ArrowStorm.makeView(config: config, onComplete: onComplete)
    case .crowdControl: CrowdControl.makeView(config: config, onComplete: onComplete)
    case .echoGrid:    EchoGrid.makeView(config: config, onComplete: onComplete)
    case .colorClash:  ColorClash.makeView(config: config, onComplete: onComplete)
    case .tileShift:   TileShift.makeView(config: config, onComplete: onComplete)
    case .lastSeen:    LastSeen.makeView(config: config, onComplete: onComplete)
    case .slidePuzzle: SlidePuzzle.makeView(config: config, onComplete: onComplete)
    case .blockEscape: BlockEscape.makeView(config: config, onComplete: onComplete)
    case .pegSolitaire: PegSolitaire.makeView(config: config, onComplete: onComplete)
    // Standalone survival modes are hosted directly by the launcher.
    case .split, .blockFit: AnyView(EmptyView())
    }
}
