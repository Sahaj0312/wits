//
//  Games.swift
//  wits
//
//  Binds each GameID to its playable view and gives the launcher one entry
//  point (`makeGameView`) to launch any game in a difficulty-seeded,
//  GameResult-emitting run.
//

import SwiftUI

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

enum WaterSort: Game {
    static let id = GameID.waterSort
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(WaterSortScreen(cfg: config, onResult: onComplete))
    }
}

enum Mahjong: Game {
    static let id = GameID.mahjong
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(MahjongScreen(cfg: config, onResult: onComplete))
    }
}

enum Crossword: Game {
    static let id = GameID.crossword
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(CrosswordScreen(cfg: config, onResult: onComplete))
    }
}

/// Single dispatch the launcher uses to open any game.
@MainActor
func makeGameView(_ id: GameID, config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
    switch id {
    case .echoGrid:    EchoGrid.makeView(config: config, onComplete: onComplete)
    case .slidePuzzle: SlidePuzzle.makeView(config: config, onComplete: onComplete)
    case .blockEscape: BlockEscape.makeView(config: config, onComplete: onComplete)
    case .pegSolitaire: PegSolitaire.makeView(config: config, onComplete: onComplete)
    case .waterSort:   WaterSort.makeView(config: config, onComplete: onComplete)
    case .mahjong:     Mahjong.makeView(config: config, onComplete: onComplete)
    case .crossword:   Crossword.makeView(config: config, onComplete: onComplete)
    // Standalone survival modes are hosted directly by the launcher.
    case .arrowStorm, .crowdControl, .colorClash, .tileShift, .lastSeen,
         .split, .blockFit, .fuse, .snake, .tower: AnyView(EmptyView())
    }
}
