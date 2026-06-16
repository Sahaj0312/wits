//
//  ScrollHuntArcade.swift
//  wits
//
//  "Scroll Hunt" — a field of shapes drifts down; tap the odd-coloured ones
//  before they escape off the bottom. The colour difference shrinks with level
//  (feature search → hard discrimination). Tapping a neighbour is the near-miss.
//

import SwiftUI

@MainActor
final class ScrollHuntArcade: ArcadeGame {
    let id = GameID.oddOneOut
    let inputMode: ArcadeInputMode = .tap
    let howTo = "tap the odd-coloured dots before they fall off"

    private static let base = (r: 0.10, g: 0.70, b: 0.64)   // teal
    private static let warm = (r: 0.94, g: 0.47, b: 0.37)   // coral
    private var delta = 0.5

    func seed(level: Double, survival: Bool) -> Spawner {
        delta = max(0.16, 0.55 - level * 0.035)
        return Spawner(
            rate: 1.0 + level * 0.08,
            maxAlive: 8 + Int(level),
            speed: 0.11 + level * 0.015,
            distractorRatio: 0.5,
            targetRadius: 0.05
        )
    }

    func spawn(into scene: ArcadeScene, params: Spawner) {
        let odd = Double.random(in: 0..<1) < 0.22
        scene.add(ArcadeEntity(
            id: scene.newID(),
            pos: CGPoint(x: .random(in: 0.1...0.9), y: -0.06),
            vel: CGVector(dx: 0, dy: params.speed),
            radius: params.targetRadius,
            kind: 0, flag: odd, birth: scene.runTime
        ))
    }

    func postStep(scene: ArcadeScene, dt: Double) -> [Resolution] {
        var out: [Resolution] = []
        for e in scene.entities where !e.dead && e.pos.y > 1.06 {
            scene.markDead(e.id)
            if e.flag { out.append(Resolution(kind: .timeout, points: 0, entityID: e.id)) } // odd escaped
        }
        return out
    }

    func resolve(_ action: ArcadeAction, scene: ArcadeScene) -> Resolution? {
        guard case let .tap(p) = action else { return nil }
        guard let e = scene.nearest(to: p, maxDist: 0.08) else { return nil }
        if e.flag {
            scene.markDead(e.id)
            return Resolution(kind: .hit, points: 100, entityID: e.id)
        }
        // tapped a distractor — near-miss if an odd one is right next to the tap
        if scene.nearest(to: p, maxDist: 0.13, where: { $0.flag }) != nil {
            return Resolution(kind: .nearMiss, points: 0)
        }
        return Resolution(kind: .miss, points: 0)
    }

    func draw(_ e: ArcadeEntity, into ctx: inout GraphicsContext, rect: CGRect, scene: ArcadeScene) {
        let c: Color
        if e.flag {
            c = Color(red: Self.base.r + (Self.warm.r - Self.base.r) * delta,
                      green: Self.base.g + (Self.warm.g - Self.base.g) * delta,
                      blue: Self.base.b + (Self.warm.b - Self.base.b) * delta)
        } else {
            c = Color(red: Self.base.r, green: Self.base.g, blue: Self.base.b)
        }
        ctx.fill(Path(ellipseIn: rect), with: .color(c))
    }
}
