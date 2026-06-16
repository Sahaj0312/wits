//
//  StroopArcade.swift
//  wits
//
//  "Ink Buckets" — colour words rain down; drag each into the bucket matching
//  its INK colour, not the word it spells. Dropping into the word's-meaning
//  bucket is the trap (near-miss). The Stroop interference IS the game.
//

import SwiftUI

@MainActor
final class StroopArcade: ArcadeGame {
    let id = GameID.colorClash
    let inputMode: ArcadeInputMode = .drag
    let howTo = "drag each word into the bucket matching its COLOUR — not the word"

    private let palette = StroopColor.allCases   // [red, blue, green, yellow] → columns 0…3

    func seed(level: Double, survival: Bool) -> Spawner {
        Spawner(
            rate: 0.45 + level * 0.04,
            maxAlive: 2 + Int(level / 3),
            speed: 0.13 + level * 0.018,
            distractorRatio: min(0.85, 0.4 + level * 0.04),   // = P(incongruent)
            targetRadius: 0.10
        )
    }

    func spawn(into scene: ArcadeScene, params: Spawner) {
        let text = Int.random(in: 0..<palette.count)
        let incong = Double.random(in: 0..<1) < params.distractorRatio
        let ink = incong ? (text + Int.random(in: 1..<palette.count)) % palette.count : text
        scene.add(ArcadeEntity(
            id: scene.newID(),
            pos: CGPoint(x: .random(in: 0.16...0.84), y: -0.08),
            vel: CGVector(dx: 0, dy: params.speed),
            radius: params.targetRadius,
            kind: 0, a: ink, b: text,
            birth: scene.runTime
        ))
    }

    func postStep(scene: ArcadeScene, dt: Double) -> [Resolution] {
        var out: [Resolution] = []
        for e in scene.entities where !e.dead && e.pos.y > 1.08 {
            scene.markDead(e.id)
            out.append(Resolution(kind: .timeout, points: 0, entityID: e.id))   // fell past the buckets
        }
        return out
    }

    func resolve(_ action: ArcadeAction, scene: ArcadeScene) -> Resolution? {
        guard case let .drop(id, at) = action, let e = scene.entity(id) else { return nil }
        // Only count drops in the bucket zone; otherwise release it to keep falling.
        guard at.y > 0.74 else { scene.setDragging(id, false); return nil }
        let col = min(palette.count - 1, max(0, Int(at.x * CGFloat(palette.count))))
        scene.markDead(id)
        if col == e.a { return Resolution(kind: .hit, points: 100, entityID: id) }
        if col == e.b { return Resolution(kind: .nearMiss, points: 0, entityID: id) } // the word's-meaning trap
        return Resolution(kind: .miss, points: 0, entityID: id)
    }

    func draw(_ e: ArcadeEntity, into ctx: inout GraphicsContext, rect: CGRect, scene: ArcadeScene) {
        guard e.b < palette.count, e.a < palette.count else { return }
        let text = Text(palette[e.b].rawValue)
            .font(.system(size: rect.width * 0.46, weight: .heavy, design: .rounded))
            .foregroundStyle(palette[e.a].color)
        ctx.draw(text, at: CGPoint(x: rect.midX, y: rect.midY))
    }

    func overlay(scene: ArcadeScene) -> AnyView { AnyView(InkBucketsBar(palette: palette)) }
}

private struct InkBucketsBar: View {
    let palette: [StroopColor]
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 6) {
                ForEach(Array(palette.enumerated()), id: \.offset) { _, c in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(c.color.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .overlay(
                            Image(systemName: "tray.fill")
                                .font(.system(size: 18, weight: .heavy))
                                .foregroundStyle(.white.opacity(0.85))
                        )
                }
            }
            .padding(6)
        }
        .allowsHitTesting(false)
    }
}
