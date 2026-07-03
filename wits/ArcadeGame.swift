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
import SpriteKit

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

    /// Baseline spawner from the persisted mastery level (1...10).
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

    // MARK: SpriteKit rendering (the live path)

    /// Build the SKNode for a newly-spawned entity (positioned by the scene).
    func makeNode(_ e: ArcadeEntity, style: ArcadeStyle) -> SKNode

    /// Per-frame appearance refresh for an existing node (recolour, highlight…).
    func refreshNode(_ node: SKNode, _ e: ArcadeEntity, style: ArcadeStyle)

    /// Add fixed chrome (buckets, lanes, prompts) once when the scene loads.
    func setupScene(_ scene: SKScene, style: ArcadeStyle)

    /// Extra game-specific metrics to merge into GameResult.raw at finish.
    func resultMetrics(scene: ArcadeScene, hits: Int, misses: Int, nearMisses: Int) -> [String: Double]

    /// Round-based games end after a fixed round count instead of the host's
    /// countdown; non-nil replaces the timer HUD with "n of total" progress.
    func roundProgress(scene: ArcadeScene) -> (done: Int, total: Int)?

    /// A round-based run has served every round (host scores and finishes).
    func isComplete(scene: ArcadeScene) -> Bool
}

extension ArcadeGame {
    func preStep(scene: ArcadeScene, dt: Double) {}
    func roundProgress(scene: ArcadeScene) -> (done: Int, total: Int)? { nil }
    func isComplete(scene: ArcadeScene) -> Bool { false }
    func overlay(scene: ArcadeScene) -> AnyView { AnyView(EmptyView()) }
    func advance(_ s: DifficultyState, accuracy: Double) -> DifficultyState { MasteryLadder.adjust(s, accuracy: accuracy) }

    // default SK rendering: a clean soft-shadowed dot (overridden per game)
    func makeNode(_ e: ArcadeEntity, style: ArcadeStyle) -> SKNode {
        let r = e.radius * style.unit
        let n = SKShapeNode(circleOfRadius: r)
        n.fillColor = UIColor(Color.witsAccent)
        n.strokeColor = .clear
        n.zPosition = 1
        n.addSoftShadow(radius: r, style: style)
        return n
    }
    func refreshNode(_ node: SKNode, _ e: ArcadeEntity, style: ArcadeStyle) {}
    func setupScene(_ scene: SKScene, style: ArcadeStyle) {}
    func resultMetrics(scene: ArcadeScene, hits: Int, misses: Int, nearMisses: Int) -> [String: Double] { [:] }
}
