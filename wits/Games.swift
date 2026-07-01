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
        AnyView(ArcadeSpriteHost(cfg: config, game: TracePathArcade(id: .echoGrid, reverse: true), onResult: onComplete))
    }
}

enum ColorClash: Game {
    static let id = GameID.colorClash
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(ColorClashScreen(cfg: config, onResult: onComplete))
    }
}

enum SpotSpeed: Game {
    static let id = GameID.spotSpeed
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(SpotSpeedScreen(cfg: config, onResult: onComplete))
    }
}

enum MatchBack: Game {
    static let id = GameID.matchBack
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(MatchBackScreen(cfg: config, onResult: onComplete))
    }
}

enum RuleFinder: Game {
    static let id = GameID.ruleFinder
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(RuleFinderScreen(cfg: config, onResult: onComplete))
    }
}

enum NumberRush: Game {
    static let id = GameID.numberRush
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(NumberRushScreen(cfg: config, onResult: onComplete))
    }
}

enum Estimator: Game {
    static let id = GameID.estimator
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(TargetForgeScreen(cfg: config, onResult: onComplete))
    }
}

enum OddOneOut: Game {
    static let id = GameID.oddOneOut
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(OddOneOutScreen(cfg: config, onResult: onComplete))
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

enum PathKeeper: Game {
    static let id = GameID.pathKeeper
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(ArcadeSpriteHost(cfg: config, game: TracePathArcade(id: .pathKeeper, reverse: false), onResult: onComplete))
    }
}

enum WordConnect: Game {
    static let id = GameID.wordConnect
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(WordConnectScreen(cfg: config, onResult: onComplete))
    }
}

enum MemoryLock: Game {
    static let id = GameID.memoryLock
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(MemoryLockScreen(cfg: config, onResult: onComplete))
    }
}

enum DotsConnect: Game {
    static let id = GameID.dotsConnect
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(DotsConnectScreen(cfg: config, onResult: onComplete))
    }
}

enum OneLine: Game {
    static let id = GameID.oneLine
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(OneLineScreen(cfg: config, onResult: onComplete))
    }
}

enum TowerOfHanoi: Game {
    static let id = GameID.towerOfHanoi
    static func makeView(config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
        AnyView(TowerOfHanoiScreen(cfg: config, onResult: onComplete))
    }
}

/// Single dispatch the host uses to launch any game.
@MainActor
func makeGameView(_ id: GameID, config: GameConfig, onComplete: @escaping (GameResult) -> Void) -> AnyView {
    switch id {
    case .arrowStorm:  ArrowStorm.makeView(config: config, onComplete: onComplete)
    case .crowdControl: CrowdControl.makeView(config: config, onComplete: onComplete)
    case .echoGrid:    EchoGrid.makeView(config: config, onComplete: onComplete)
    case .colorClash:  ColorClash.makeView(config: config, onComplete: onComplete)
    case .spotSpeed:   SpotSpeed.makeView(config: config, onComplete: onComplete)
    case .matchBack:   MatchBack.makeView(config: config, onComplete: onComplete)
    case .ruleFinder:  RuleFinder.makeView(config: config, onComplete: onComplete)
    case .numberRush:  NumberRush.makeView(config: config, onComplete: onComplete)
    case .estimator:   Estimator.makeView(config: config, onComplete: onComplete)
    case .oddOneOut:   OddOneOut.makeView(config: config, onComplete: onComplete)
    case .tileShift:   TileShift.makeView(config: config, onComplete: onComplete)
    case .lastSeen:    LastSeen.makeView(config: config, onComplete: onComplete)
    case .pathKeeper:  PathKeeper.makeView(config: config, onComplete: onComplete)
    case .wordConnect: WordConnect.makeView(config: config, onComplete: onComplete)
    case .memoryLock:  MemoryLock.makeView(config: config, onComplete: onComplete)
    case .dotsConnect: DotsConnect.makeView(config: config, onComplete: onComplete)
    case .oneLine:     OneLine.makeView(config: config, onComplete: onComplete)
    case .towerOfHanoi: TowerOfHanoi.makeView(config: config, onComplete: onComplete)
    case .split:       AnyView(EmptyView())
    }
}

func advanceDifficulty(for id: GameID, _ s: DifficultyState, accuracy: Double) -> DifficultyState {
    switch id {
    case .arrowStorm:  return ArrowStorm.advance(s, accuracy: accuracy)
    case .crowdControl: return CrowdControl.advance(s, accuracy: accuracy)
    case .echoGrid:    return EchoGrid.advance(s, accuracy: accuracy)
    case .colorClash:  return ColorClash.advance(s, accuracy: accuracy)
    default:           return MasteryLadder.adjust(s, accuracy: accuracy)
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
