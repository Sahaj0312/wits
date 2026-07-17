//
//  ArcadeField.swift
//  wits
//
//  The real-time substrate every arcade game runs on. Entities live in
//  resolution-independent unit space [0,1]; a scene holds them and advances on a
//  display-synced loop (driven by ArcadeGameView). Difficulty is a spawner that
//  ramps speed / rate / clutter, the flow-channel knob, not a shrinking timer.
//

import SwiftUI

// MARK: - Entity (game-agnostic; games interpret a/b/flag)

struct ArcadeEntity: Identifiable {
    let id: Int
    var pos: CGPoint           // unit space 0…1
    var vel: CGVector          // unit / sec
    var radius: CGFloat = 0.07 // unit (of min dimension)
    var kind: Int = 0          // game-defined role
    var a: Int = 0             // game-defined (colour idx / symbol id / number …)
    var b: Int = 0             // game-defined (text idx / shape …)
    var flag: Bool = false     // game-defined (correct / odd / congruent …)
    var birth: Double = 0
    var dead = false
    var dragging = false       // follows the finger; skips integration
}

// MARK: - Spawner / escalation

struct Spawner {
    var rate: Double = 0.8           // spawns / sec
    var acc: Double = 0              // accumulator
    var maxAlive: Int = 6
    var speed: Double = 0.28         // unit / sec baseline
    var distractorRatio: Double = 0.5
    var targetRadius: CGFloat = 0.08
}

enum Escalation {
    /// Ramp the spawner from a baseline by elapsed time + combo. Gentle over a
    /// 45s workout; steep and endless in survival.
    static func apply(_ sp: inout Spawner, base: Spawner, runTime: Double, combo: Int, survival: Bool) {
        let t = survival ? min(runTime / 110, 1) : min(runTime / 45, 1)
        let comboBoost = survival ? Double(min(combo, 30)) * 0.02 : 0
        let k = t * (survival ? 1.0 : 0.45) + comboBoost
        sp.rate = base.rate * (1 + k * 1.4)
        sp.speed = base.speed * (1 + k * 1.1)
        sp.maxAlive = base.maxAlive + Int(k * 5)
        sp.targetRadius = max(0.04, base.targetRadius * (1 - k * 0.35))
        sp.distractorRatio = min(0.85, base.distractorRatio + k * 0.3)
    }
}

enum SwipeDir: Equatable { case up, down, left, right }

// MARK: - Scene

@Observable
@MainActor
final class ArcadeScene {
    var entities: [ArcadeEntity] = []
    var bounds: CGSize = .zero
    private(set) var runTime: Double = 0
    var spawner = Spawner()

    private var nextID = 0
    func newID() -> Int { nextID += 1; return nextID }

    var aliveCount: Int { entities.reduce(0) { $0 + ($1.dead ? 0 : 1) } }

    func add(_ e: ArcadeEntity) { entities.append(e) }

    func entity(_ id: Int) -> ArcadeEntity? { entities.first { $0.id == id } }

    func markDead(_ id: Int) {
        if let i = entities.firstIndex(where: { $0.id == id }) { entities[i].dead = true }
    }

    func setPos(_ id: Int, _ unit: CGPoint) {
        if let i = entities.firstIndex(where: { $0.id == id }) { entities[i].pos = unit }
    }

    func setDragging(_ id: Int, _ on: Bool) {
        if let i = entities.firstIndex(where: { $0.id == id }) { entities[i].dragging = on }
    }

    /// Nearest live entity within `maxDist` (unit space).
    func nearest(to unit: CGPoint, maxDist: CGFloat, where pred: (ArcadeEntity) -> Bool = { _ in true }) -> ArcadeEntity? {
        var best: ArcadeEntity?
        var bestD = maxDist
        for e in entities where !e.dead && pred(e) {
            let d = hypot(e.pos.x - unit.x, e.pos.y - unit.y)
            if d <= bestD { bestD = d; best = e }
        }
        return best
    }

    /// Advance positions (skips dragged entities). Caller clamps dt.
    func integrate(_ dt: Double) {
        runTime += dt
        for i in entities.indices where !entities[i].dragging && !entities[i].dead {
            entities[i].pos.x += entities[i].vel.dx * dt
            entities[i].pos.y += entities[i].vel.dy * dt
        }
    }

    func reset() {
        entities.removeAll()
        runTime = 0
        nextID = 0
    }
}
