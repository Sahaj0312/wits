//
//  ArrowVolleyArcade.swift
//  wits
//
//  "Arrow Volley" — 5-arrow clusters fly up the screen; swipe the direction the
//  CENTER arrow points before the cluster escapes off the top. The flankers lie
//  on incongruent trials — swiping their way is the near-miss.
//

import SwiftUI

@MainActor
final class ArrowVolleyArcade: ArcadeGame {
    let id = GameID.arrowStorm
    let inputMode: ArcadeInputMode = .swipe
    let howTo = "swipe the way the MIDDLE arrow points — ignore the rest"

    func seed(level: Double, survival: Bool) -> Spawner {
        Spawner(
            rate: 0.42 + level * 0.03,
            maxAlive: 1 + Int(level / 4),
            speed: 0.16 + level * 0.02,
            distractorRatio: min(0.85, 0.45 + level * 0.04),  // P(incongruent)
            targetRadius: 0.13
        )
    }

    func spawn(into scene: ArcadeScene, params: Spawner) {
        let congruent = Double.random(in: 0..<1) >= params.distractorRatio
        scene.add(ArcadeEntity(
            id: scene.newID(),
            pos: CGPoint(x: .random(in: 0.3...0.7), y: 1.12),
            vel: CGVector(dx: 0, dy: -params.speed),
            radius: params.targetRadius,
            kind: 0,
            a: Bool.random() ? 1 : 0,   // center points right?
            flag: congruent
        ))
    }

    func postStep(scene: ArcadeScene, dt: Double) -> [Resolution] {
        var out: [Resolution] = []
        for e in scene.entities where !e.dead && e.pos.y < -0.1 {
            scene.markDead(e.id)
            out.append(Resolution(kind: .timeout, points: 0, entityID: e.id))
        }
        return out
    }

    func resolve(_ action: ArcadeAction, scene: ArcadeScene) -> Resolution? {
        guard case let .swipe(dir, _) = action, dir == .left || dir == .right else { return nil }
        // resolve the most urgent cluster (closest to the top edge)
        guard let e = scene.entities.filter({ !$0.dead }).min(by: { $0.pos.y < $1.pos.y }) else { return nil }
        scene.markDead(e.id)
        let centerRight = e.a == 1
        if (dir == .right) == centerRight { return Resolution(kind: .hit, points: 100, entityID: e.id) }
        // wrong: on incongruent the flankers point opposite the centre — that's the trap
        if !e.flag { return Resolution(kind: .nearMiss, points: 0, entityID: e.id) }
        return Resolution(kind: .miss, points: 0, entityID: e.id)
    }

    func draw(_ e: ArcadeEntity, into ctx: inout GraphicsContext, rect: CGRect, scene: ArcadeScene) {
        let n = 5
        let band = CGRect(x: rect.midX - rect.width * 1.25, y: rect.midY - rect.height * 0.35,
                          width: rect.width * 2.5, height: rect.height * 0.7)
        let cellW = band.width / CGFloat(n)
        let centerRight = e.a == 1
        for i in 0..<n {
            let isCenter = i == 2
            let pointsRight = isCenter ? centerRight : (e.flag ? centerRight : !centerRight)
            let cell = CGRect(x: band.minX + CGFloat(i) * cellW, y: band.minY, width: cellW, height: band.height)
                .insetBy(dx: cellW * 0.16, dy: band.height * 0.12)
            var p = Path()
            if pointsRight {
                p.move(to: CGPoint(x: cell.minX, y: cell.minY))
                p.addLine(to: CGPoint(x: cell.maxX, y: cell.midY))
                p.addLine(to: CGPoint(x: cell.minX, y: cell.maxY))
            } else {
                p.move(to: CGPoint(x: cell.maxX, y: cell.minY))
                p.addLine(to: CGPoint(x: cell.minX, y: cell.midY))
                p.addLine(to: CGPoint(x: cell.maxX, y: cell.maxY))
            }
            p.closeSubpath()
            if isCenter {
                var g = ctx
                g.addFilter(.shadow(color: Color.witsAccent.opacity(0.9), radius: cell.width * 0.5))
                g.fill(p, with: .color(.witsAccent))
            } else {
                ctx.fill(p, with: .color(.white.opacity(0.34)))
            }
        }
    }
}
