//
//  StroopArcade.swift
//  wits
//
//  "Ink Buckets" — colour words rain down; drag each into the bucket matching
//  its INK colour, not the word it spells. Dropping into the word's-meaning
//  bucket is the trap (near-miss). The Stroop interference IS the game.
//

import SwiftUI
import SpriteKit
import UIKit

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
        // a dark glossy chip carries the word, with a glow in its ink colour
        let chip = CGRect(x: rect.midX - rect.width * 1.05, y: rect.midY - rect.height * 0.5,
                          width: rect.width * 2.1, height: rect.height)
        ctx.chip(chip, fill: Color(white: 0.12), corner: chip.height * 0.32, glow: palette[e.a].color)
        let text = Text(palette[e.b].rawValue)
            .font(.system(size: rect.height * 0.5, weight: .heavy, design: .rounded))
            .foregroundStyle(palette[e.a].color)
        ctx.draw(text, at: CGPoint(x: chip.midX, y: chip.midY))
    }

    func overlay(scene: ArcadeScene) -> AnyView { AnyView(InkBucketsBar(palette: palette)) }

    // MARK: SpriteKit look (clean minimal premium)

    func makeNode(_ e: ArcadeEntity, style: ArcadeStyle) -> SKNode {
        guard e.b < palette.count, e.a < palette.count else { return SKNode() }
        let w = style.unit * 0.5, h = style.unit * 0.18
        let container = SKNode()
        container.zPosition = 1

        let shadow = SKSpriteNode(texture: style.dab)
        shadow.size = CGSize(width: w * 1.25, height: h * 2.4)
        shadow.color = UIColor(white: 0.1, alpha: 1); shadow.colorBlendFactor = 1
        shadow.alpha = 0.16; shadow.position = CGPoint(x: 0, y: -h * 0.32); shadow.zPosition = -1
        container.addChild(shadow)

        let chip = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: h * 0.36)
        chip.fillColor = .white; chip.strokeColor = .clear
        container.addChild(chip)

        let label = SKLabelNode()
        label.attributedText = NSAttributedString(string: palette[e.b].rawValue, attributes: [
            .font: roundedUIFont(h * 0.62), .foregroundColor: UIColor(palette[e.a].color)])
        label.verticalAlignmentMode = .center; label.horizontalAlignmentMode = .center
        chip.addChild(label)
        return container
    }

    func setupScene(_ scene: SKScene, style: ArcadeStyle) {
        let n = palette.count
        let w = style.size.width / CGFloat(n)
        let h: CGFloat = 66
        for i in 0..<n {
            let bucket = SKShapeNode(rectOf: CGSize(width: w - 8, height: h), cornerRadius: 16)
            bucket.fillColor = UIColor(palette[i].color)
            bucket.strokeColor = UIColor.white.withAlphaComponent(0.55); bucket.lineWidth = 1.5
            bucket.position = CGPoint(x: w * (CGFloat(i) + 0.5), y: h / 2 + 10)
            bucket.zPosition = 5
            // top sheen
            let sheen = SKShapeNode(rectOf: CGSize(width: w - 16, height: h * 0.4), cornerRadius: 10)
            sheen.fillColor = UIColor.white.withAlphaComponent(0.18); sheen.strokeColor = .clear
            sheen.position = CGPoint(x: 0, y: h * 0.22)
            bucket.addChild(sheen)
            scene.addChild(bucket)
        }
    }
}

private struct InkBucketsBar: View {
    let palette: [StroopColor]
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 8) {
                ForEach(Array(palette.enumerated()), id: \.offset) { _, c in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(colors: [c.color, c.color.opacity(0.78)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .overlay(alignment: .top) {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.white.opacity(0.18))
                                .frame(height: 22)
                                .padding(3)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(.white.opacity(0.5), lineWidth: 1.5)
                        )
                        .shadow(color: c.color.opacity(0.6), radius: 10, y: 0)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .allowsHitTesting(false)
    }
}
