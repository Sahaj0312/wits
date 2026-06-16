//
//  ArcadeGame.swift
//  wits
//
//  The contract a concrete arcade game implements. The ArcadeGameView wrapper
//  owns the loop, HUD, scoring, cfg.report plumbing and end conditions — a game
//  only describes how to spawn, draw, escalate, and resolve a player action into
//  a hit / miss / near-miss. Keeps every game ~100 lines.
//

import SwiftUI

enum ArcadeInputMode { case tap, swipe, drag, trace }

enum ArcadeAction {
    case tap(CGPoint)                       // unit
    case swipe(SwipeDir, at: CGPoint)       // unit start point
    case drop(entityID: Int, at: CGPoint)   // unit drop point
    case trace([Int])                       // ordered entity ids entered
}

struct Resolution {
    var kind: TrialOutcome.Kind
    var points: Int = 100
    var entityID: Int? = nil
}

@MainActor
protocol ArcadeGame: AnyObject {
    var id: GameID { get }
    var inputMode: ArcadeInputMode { get }

    /// Baseline spawner from the persisted difficulty level (0…10).
    func seed(level: Double, survival: Bool) -> Spawner

    /// Emit one entity using the current (escalated) spawner params.
    func spawn(into scene: ArcadeScene, params: Spawner)

    /// Continuous per-frame rule (running totals, conveyor beats, light-up …).
    func preStep(scene: ArcadeScene, dt: Double)

    /// Resolve entities that left the field / expired → outcomes (e.g. floor = miss).
    /// Mark them dead here; return one Resolution per resolved entity.
    func postStep(scene: ArcadeScene, dt: Double) -> [Resolution]

    /// The player acted; classify against the rule (nil = no-op).
    func resolve(_ action: ArcadeAction, scene: ArcadeScene) -> Resolution?

    /// Draw one entity inside the field Canvas.
    func draw(_ e: ArcadeEntity, into ctx: inout GraphicsContext, rect: CGRect, scene: ArcadeScene)

    /// Fixed chrome (buckets, reticle, prompt) layered over the field.
    func overlay(scene: ArcadeScene) -> AnyView

    /// One-line how-to shown briefly at the start.
    var howTo: String { get }
}

extension ArcadeGame {
    func preStep(scene: ArcadeScene, dt: Double) {}
    func overlay(scene: ArcadeScene) -> AnyView { AnyView(EmptyView()) }
    func advance(_ s: DifficultyState, accuracy: Double) -> DifficultyState { Staircase.adjust(s, accuracy: accuracy) }
}
