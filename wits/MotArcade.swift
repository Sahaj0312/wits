//
//  MotArcade.swift
//  wits
//
//  "Crowd Control" on the arcade field — a few dots glow, then everything goes
//  identical and drifts/bounces; when it freezes, tap the ones you tracked.
//  Multiple-object tracking with continuous motion. Round-based.
//

import SwiftUI
import SpriteKit
import UIKit

@MainActor
final class MotArcade: ArcadeGame {
    let id = GameID.crowdControl
    let inputMode: ArcadeInputMode = .tap
    let howTo = "remember the glowing dots, track them, then tap them when they stop"

    private enum Phase { case mark, move, pick, reveal, regroup }
    private var phase: Phase = .mark
    private var placed = false
    private var phaseT = 0.0
    private var targets = 3
    private var dots = 9
    private var speed = 0.2
    private var picked: Set<Int> = []
    private let markDur = 1.4
    private var moveDur = 5.0
    private let revealDur = 1.4
    private let regroupDur = 0.45   // empty beat so old dots fade out before new ones appear
    private let margin = 0.07

    func seed(level: Double, survival: Bool) -> Spawner {
        targets = min(6, 3 + Int(level / 3))
        dots = 9 + Int(level / 4)
        speed = 0.16 + level * 0.03
        moveDur = 4.5 + (survival ? 1.5 : 0)
        return Spawner(rate: 0, maxAlive: 99, speed: 0)
    }

    func spawn(into scene: ArcadeScene, params: Spawner) {}

    func preStep(scene: ArcadeScene, dt: Double) {
        if !placed { startRound(scene); placed = true }
        phaseT += dt
        switch phase {
        case .mark:
            if phaseT >= markDur { setMoving(scene, true); phase = .move; phaseT = 0 }
        case .move:
            bounce(scene)
            if phaseT >= moveDur { setMoving(scene, false); phase = .pick; phaseT = 0 }
        case .pick:
            break
        case .reveal:
            // clear the field first; the renderer fades the old dots out gracefully.
            if phaseT >= revealDur { scene.reset(); phase = .regroup; phaseT = 0 }
        case .regroup:
            // brief empty beat, then the new round's dots pop in cleanly.
            if phaseT >= regroupDur { spawnDots(scene) }
        }
    }

    func postStep(scene: ArcadeScene, dt: Double) -> [Resolution] { [] }

    func resolve(_ action: ArcadeAction, scene: ArcadeScene) -> Resolution? {
        guard phase == .pick, case let .tap(p) = action else { return nil }
        guard let e = scene.nearest(to: p, maxDist: 0.07), !picked.contains(e.id) else { return nil }
        picked.insert(e.id)
        let hit = e.flag
        setMark(scene, e.id, hit ? 1 : 2)   // a: 1=correct pick, 2=wrong pick
        if picked.count >= targets { phase = .reveal; phaseT = 0 }
        return Resolution(kind: hit ? .hit : .miss, points: 120, entityID: e.id)
    }

    private func uiColor(for e: ArcadeEntity) -> UIColor {
        let showTarget = (phase == .mark || phase == .reveal) && e.flag
        if e.a == 1 { return UIColor(Color.witsAccent) }
        if e.a == 2 { return UIColor(Color.witsWarm) }
        if showTarget { return UIColor(Color.witsAccent) }
        return UIColor(white: 0.72, alpha: 1)
    }

    func makeNode(_ e: ArcadeEntity, style: ArcadeStyle) -> SKNode {
        let r = e.radius * style.unit
        let n = SKShapeNode(circleOfRadius: r)
        n.strokeColor = .clear; n.zPosition = 1
        n.fillColor = uiColor(for: e)
        n.addSoftShadow(radius: r, style: style, alpha: 0.12)
        return n
    }

    func refreshNode(_ node: SKNode, _ e: ArcadeEntity, style: ArcadeStyle) {
        (node as? SKShapeNode)?.fillColor = uiColor(for: e)
    }

    func draw(_ e: ArcadeEntity, into ctx: inout GraphicsContext, rect: CGRect, scene: ArcadeScene) {
        let showTarget = (phase == .mark || phase == .reveal) && e.flag
        let glow = showTarget || e.a == 1 || e.a == 2
        let fill: Color
        if e.a == 1 { fill = .witsAccent }
        else if e.a == 2 { fill = .witsWarm }
        else if showTarget { fill = .witsAccent }
        else { fill = Color(white: 0.78) }
        ctx.orb(rect, color: fill, glow: glow ? 0.85 : 0.0)
        if phase == .reveal && e.flag && e.a == 0 {   // missed target → ring
            ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(.witsAccent), lineWidth: 2.5)
        }
    }

    // MARK: Round

    private func startRound(_ scene: ArcadeScene) {
        scene.reset()
        spawnDots(scene)
    }

    /// Lay out a fresh set of dots and enter the mark phase. Assumes the field is
    /// already clear (first round, or after the regroup beat).
    private func spawnDots(_ scene: ArcadeScene) {
        picked = []
        var rng = SystemRandomNumberGenerator()
        for i in 0..<dots {
            var pos = CGPoint.zero
            var ok = false
            var tries = 0
            while !ok && tries < 40 {
                pos = CGPoint(x: .random(in: margin...(1 - margin), using: &rng),
                              y: .random(in: margin...(1 - margin), using: &rng))
                ok = !scene.entities.contains { hypot($0.pos.x - pos.x, $0.pos.y - pos.y) < 0.14 }
                tries += 1
            }
            scene.add(ArcadeEntity(id: scene.newID(), pos: pos, vel: .zero,
                                   radius: 0.05, kind: 0, a: 0, flag: i < targets))
        }
        phase = .mark; phaseT = 0
    }

    private func setMoving(_ scene: ArcadeScene, _ on: Bool) {
        for i in scene.entities.indices {
            if on {
                let ang = Double.random(in: 0..<(2 * .pi))
                scene.entities[i].vel = CGVector(dx: cos(ang) * speed, dy: sin(ang) * speed)
            } else {
                scene.entities[i].vel = .zero
            }
        }
    }

    private func bounce(_ scene: ArcadeScene) {
        for i in scene.entities.indices {
            if scene.entities[i].pos.x < margin { scene.entities[i].pos.x = margin; scene.entities[i].vel.dx = abs(scene.entities[i].vel.dx) }
            if scene.entities[i].pos.x > 1 - margin { scene.entities[i].pos.x = 1 - margin; scene.entities[i].vel.dx = -abs(scene.entities[i].vel.dx) }
            if scene.entities[i].pos.y < margin { scene.entities[i].pos.y = margin; scene.entities[i].vel.dy = abs(scene.entities[i].vel.dy) }
            if scene.entities[i].pos.y > 1 - margin { scene.entities[i].pos.y = 1 - margin; scene.entities[i].vel.dy = -abs(scene.entities[i].vel.dy) }
        }
    }

    private func setMark(_ scene: ArcadeScene, _ id: Int, _ v: Int) {
        if let i = scene.entities.firstIndex(where: { $0.id == id }) { scene.entities[i].a = v }
    }
}
