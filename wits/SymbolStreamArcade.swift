//
//  SymbolStreamArcade.swift
//  wits
//
//  "Symbol Stream" — symbols ride a conveyor left→right; tap the current
//  (front-most) symbol when it matches the one N steps back. Lures (matches at
//  n±1) are the near-miss trap. n grows with level.
//

import SwiftUI
import SpriteKit
import UIKit

@MainActor
final class SymbolStreamArcade: ArcadeGame {
    let id = GameID.matchBack
    let inputMode: ArcadeInputMode = .tap
    let howTo = "tap the front symbol when it matches the one N steps back"

    private static let glyphs = ["star.fill", "heart.fill", "bolt.fill", "leaf.fill",
                                 "moon.fill", "drop.fill", "flame.fill", "bell.fill"]
    private var n = 1
    private var recent: [Int] = []     // history of symbol ids, most-recent last
    private var beat = 0.0
    private var beatInterval = 1.0
    private var laneY = 0.5
    private var resolvedFront = false  // guard one decision per front symbol
    private var frontID: Int?

    func seed(level: Double, survival: Bool) -> Spawner {
        n = max(1, min(3, 1 + Int(level / 3.5)))
        beatInterval = max(0.6, 1.1 - level * 0.05)
        return Spawner(rate: 0, maxAlive: 99, speed: 0, targetRadius: 0.1)  // we spawn on the beat
    }

    // Symbols are emitted on the beat in preStep, not via the generic spawner.
    func spawn(into scene: ArcadeScene, params: Spawner) {}

    func preStep(scene: ArcadeScene, dt: Double) {
        // drive symbols rightward at a steady speed tied to the beat
        let v = (0.34) / beatInterval   // cross ~1/3 width per beat
        for i in scene.entities.indices where !scene.entities[i].dead {
            scene.entities[i].pos.x += v * dt
        }
        beat += dt
        if beat >= beatInterval {
            beat -= beatInterval
            emitSymbol(into: scene)
        }
        frontID = scene.entities.filter { !$0.dead }.max(by: { $0.pos.x < $1.pos.x })?.id
    }

    private func emitSymbol(into scene: ArcadeScene) {
        // ~32% planned matches; otherwise avoid an accidental n-back match
        let isMatch = recent.count >= n && Double.random(in: 0..<1) < 0.32
        let sym: Int
        if isMatch {
            sym = recent[recent.count - n]
        } else {
            let avoid = recent.count >= n ? recent[recent.count - n] : -1
            sym = (0..<Self.glyphs.count).filter { $0 != avoid }.randomElement() ?? 0
        }
        recent.append(sym)
        scene.add(ArcadeEntity(
            id: scene.newID(),
            pos: CGPoint(x: -0.05, y: laneY),
            vel: .zero, radius: 0.1,
            kind: 0, a: sym, b: recent.count - 1, flag: isMatch
        ))
        resolvedFront = false
    }

    func postStep(scene: ArcadeScene, dt: Double) -> [Resolution] {
        var out: [Resolution] = []
        for e in scene.entities where !e.dead && e.pos.x > 1.05 {
            scene.markDead(e.id)
            // a true match that left unanswered is a miss; a non-match correctly ignored is fine
            if e.flag { out.append(Resolution(kind: .miss, points: 0, entityID: e.id)) }
        }
        return out
    }

    func resolve(_ action: ArcadeAction, scene: ArcadeScene) -> Resolution? {
        guard case let .tap(p) = action else { return nil }
        guard let e = scene.nearest(to: p, maxDist: 0.12) else { return nil }
        scene.markDead(e.id)
        if e.flag { return Resolution(kind: .hit, points: 120, entityID: e.id) }
        // lure: matches at n-1 or n+1 back → near-miss
        let idx = e.b
        let lure = [n - 1, n + 1].contains { k in k >= 1 && idx - k >= 0 && recent[idx - k] == e.a }
        return Resolution(kind: lure ? .nearMiss : .miss, points: 0, entityID: e.id)
    }

    func makeNode(_ e: ArcadeEntity, style: ArcadeStyle) -> SKNode {
        let s = style.unit * 0.2
        let chip = SKShapeNode(rectOf: CGSize(width: s, height: s), cornerRadius: s * 0.26)
        chip.strokeColor = .clear; chip.zPosition = 1
        chip.fillColor = UIColor(white: 0.96, alpha: 1)
        chip.addSoftShadow(radius: s * 0.6, style: style, alpha: 0.14)
        if e.a < Self.glyphs.count,
           let img = UIImage(systemName: Self.glyphs[e.a])?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            let sprite = SKSpriteNode(texture: SKTexture(image: img))
            sprite.size = CGSize(width: s * 0.62, height: s * 0.62)
            sprite.color = UIColor(white: 0.2, alpha: 1); sprite.colorBlendFactor = 1
            sprite.name = "glyph"; sprite.zPosition = 2
            chip.addChild(sprite)
        }
        return chip
    }

    func refreshNode(_ node: SKNode, _ e: ArcadeEntity, style: ArcadeStyle) {
        let front = e.id == frontID
        (node as? SKShapeNode)?.fillColor = front ? UIColor(Color.witsAccent) : UIColor(white: 0.96, alpha: 1)
        if let g = node.childNode(withName: "glyph") as? SKSpriteNode {
            g.color = front ? .white : UIColor(white: 0.2, alpha: 1)
        }
        node.zPosition = front ? 3 : 1
    }

    func setupScene(_ scene: SKScene, style: ArcadeStyle) {
        let badge = SKLabelNode()
        badge.attributedText = NSAttributedString(string: "\(n)-BACK", attributes: [
            .font: roundedUIFont(14), .foregroundColor: UIColor(Color.witsAccent)])
        badge.horizontalAlignmentMode = .left
        badge.verticalAlignmentMode = .center
        badge.position = CGPoint(x: 24, y: style.size.height - 104)
        badge.zPosition = 40
        scene.addChild(badge)
    }

    func draw(_ e: ArcadeEntity, into ctx: inout GraphicsContext, rect: CGRect, scene: ArcadeScene) {
        guard e.a < Self.glyphs.count else { return }
        let front = scene.entities.filter { !$0.dead }.max(by: { $0.pos.x < $1.pos.x })?.id == e.id
        let box = rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.06)
        if front {
            ctx.chip(box, fill: .witsAccent, corner: box.width * 0.24, glow: .witsAccent)
            ctx.symbol(Self.glyphs[e.a], in: box, size: rect.width * 0.42, color: .white)
        } else {
            ctx.chip(box, fill: Color(white: 0.92), corner: box.width * 0.24)
            ctx.symbol(Self.glyphs[e.a], in: box, size: rect.width * 0.42, color: Color(white: 0.2))
        }
    }

    func overlay(scene: ArcadeScene) -> AnyView {
        AnyView(
            VStack {
                HStack {
                    Text("\(n)-BACK")
                        .font(.system(size: 13, weight: .heavy, design: .rounded)).kerning(1)
                        .foregroundStyle(Color.witsAccent)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.witsAccent.opacity(0.14), in: Capsule())
                    Spacer()
                }
                Spacer()
            }
            .padding(12)
            .allowsHitTesting(false)
        )
    }
}
