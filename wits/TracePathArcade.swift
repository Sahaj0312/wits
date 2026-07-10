//
//  TracePathArcade.swift
//  wits
//
//  "Trace the Path" — nodes light up in sequence, then you tap them back in
//  order (forward = Path Keeper; reverse = Echo Grid). A single transposition
//  is the near-miss. Each map level is a frozen exam spec (board × span ×
//  flash speed) served for a fixed number of rounds — no wall clock, so an
//  idle run never ends and unplayed rounds can't inflate the grade.
//

import SwiftUI
import SpriteKit
import UIKit

@MainActor
final class TracePathArcade: ArcadeGame {
    let id: GameID
    let reverse: Bool
    let inputMode: ArcadeInputMode = .tap
    var howTo: String { reverse ? "watch the path, then tap it BACKWARDS" : "watch the path, then tap it in order" }
    private var world: GameWorld { id.world }

    private enum Phase { case show, awaitTrace, reveal }
    private var phase: Phase = .show
    private var placed = false
    private var seq: [Int] = []          // node ids in presentation order
    private var entered: [Int] = []      // node ids the player has tapped, in order
    private var litID: Int?
    private var phaseT = 0.0
    private var maxSpan = 0
    private var perfectRounds = 0
    private var roundsPlayed = 0
    private var complete = false
    private var rng: SeededRandomNumberGenerator

    // Frozen exam spec, fixed at seed() for the whole run.
    private var grid = 4
    private var span = 4
    private var showStep = 0.5
    private var roundsTotal = 6
    private var stepX = 0.24
    private var nodeRadius = 0.09
    private var tapRadius = 0.11

    init(id: GameID, reverse: Bool, seed: UInt64) {
        self.id = id
        self.reverse = reverse
        self.rng = SeededRandomNumberGenerator(seed: seed)
    }

    /// The exam spec for a map level. Bands overlap on purpose: a bigger board
    /// resets span, so each band opens with a sideways-then-up step instead of
    /// one unbroken ramp. Echo Grid runs one span lower — reverse recall is a
    /// notch harder at the same length.
    static func spec(for game: GameID, mapLevel: Int) -> (grid: Int, span: Int, step: Double, rounds: Int) {
        let n = min(max(mapLevel, 1), 40)
        let grid: Int
        var span: Int
        let step: Double
        switch n {
        case ...10:
            grid = 3; span = 3 + (n - 1) / 4; step = 0.60 - 0.010 * Double(n - 1)
        case ...22:
            grid = 4; span = 4 + (n - 11) / 3; step = 0.54 - 0.011 * Double(n - 11)
        case ...32:
            grid = 5; span = 5 + (n - 23) / 3; step = 0.46 - 0.011 * Double(n - 23)
        default:
            grid = 5; span = 8 + (n - 33) / 4; step = 0.36 - 0.008 * Double(n - 33)
        }
        if game == .echoGrid { span = max(2, span - 1) }
        return (grid, span, max(0.30, step), span >= 8 ? 5 : 6)
    }

    func seed(level: Double, survival: Bool) -> Spawner {
        let mapLevel = DifficultyScale.contentLevel(for: id, legacyDifficulty: level)
        let s = Self.spec(for: id, mapLevel: mapLevel)
        grid = s.grid; span = s.span; showStep = s.step; roundsTotal = s.rounds
        stepX = grid <= 3 ? 0.30 : grid == 4 ? 0.24 : 0.19
        nodeRadius = stepX * 0.375
        tapRadius = stepX * 0.45
        return Spawner(rate: 0, maxAlive: 99, speed: 0)   // round-based, no generic spawns
    }

    func spawn(into scene: ArcadeScene, params: Spawner) {}

    func preStep(scene: ArcadeScene, dt: Double) {
        if !placed { placeNodes(scene); startRound(scene); placed = true }
        phaseT += dt
        switch phase {
        case .show:
            let step = Int(phaseT / showStep)
            if step >= seq.count {
                litID = nil; phase = .awaitTrace; phaseT = 0
            } else {
                // light for 70% of each step
                let withinStep = phaseT - Double(step) * showStep
                litID = withinStep < showStep * 0.7 ? seq[step] : nil
            }
        case .awaitTrace:
            break
        case .reveal:
            if phaseT > 0.9 {
                if roundsPlayed >= roundsTotal { complete = true } else { startRound(scene) }
            }
        }
    }

    func postStep(scene: ArcadeScene, dt: Double) -> [Resolution] { [] }

    func roundProgress(scene: ArcadeScene) -> (done: Int, total: Int)? {
        (done: roundsPlayed, total: roundsTotal)
    }

    func isComplete(scene: ArcadeScene) -> Bool { complete }

    func resolve(_ action: ArcadeAction, scene: ArcadeScene) -> Resolution? {
        guard phase == .awaitTrace, case let .tap(p) = action else { return nil }
        guard let e = scene.nearest(to: p, maxDist: tapRadius, where: { $0.kind == 1 }),
              !entered.contains(e.id) else { return nil }

        entered.append(e.id)
        setMark(scene, e.id, 1)            // light the tile so taps visibly register

        // wait until the player has tapped the full sequence
        guard entered.count >= seq.count else { return nil }

        let expected = reverse ? Array(seq.reversed()) : seq
        phase = .reveal; phaseT = 0
        roundsPlayed += 1
        let correct = zip(entered, expected).reduce(0) { $0 + ($1.0 == $1.1 ? 1 : 0) }
        if correct == expected.count {
            perfectRounds += 1
            maxSpan = max(maxSpan, expected.count)
            return Resolution(kind: .hit, points: 60 * expected.count)
        }
        // one transposition leaves all-but-two correct
        if correct >= expected.count - 2 {
            return Resolution(kind: .nearMiss, points: 0)
        }
        return Resolution(kind: .miss, points: 0)
    }

    private func setMark(_ scene: ArcadeScene, _ id: Int, _ v: Int) {
        if let i = scene.entities.firstIndex(where: { $0.id == id }) { scene.entities[i].a = v }
    }

    func makeNode(_ e: ArcadeEntity, style: ArcadeStyle) -> SKNode {
        let r = e.radius * style.unit
        let n = SKShapeNode(rectOf: CGSize(width: r * 2, height: r * 2), cornerRadius: r * 0.55)
        n.strokeColor = .clear; n.zPosition = 1
        n.fillColor = UIColor(world.surface)
        n.addSoftShadow(radius: r, style: style, alpha: 0.10)
        return n
    }

    func refreshNode(_ node: SKNode, _ e: ArcadeEntity, style: ArcadeStyle) {
        let lit = e.id == litID
        let selected = e.a == 1
        let color: UIColor = lit ? UIColor(world.accent)
            : selected ? UIColor(world.secondary).withAlphaComponent(0.72)
            : UIColor(world.surface)
        (node as? SKShapeNode)?.fillColor = color
        node.setScale(lit || selected ? 1.14 : 1.0)
    }

    func draw(_ e: ArcadeEntity, into ctx: inout GraphicsContext, rect: CGRect, scene: ArcadeScene) {
        let lit = e.id == litID
        let path = Path(roundedRect: rect, cornerRadius: rect.width * 0.3)
        if lit {
            var g = ctx
            g.addFilter(.shadow(color: world.accent.opacity(0.9), radius: rect.width * 0.5))
            g.fill(path, with: .color(world.accent))
            ctx.fill(Path(ellipseIn: rect.insetBy(dx: rect.width * 0.3, dy: rect.height * 0.3)),
                     with: .color(.white.opacity(0.7)))
        } else {
            ctx.fill(path, with: .color(.white.opacity(0.12)))
            ctx.stroke(path, with: .color(.white.opacity(0.18)), lineWidth: 1)
        }
    }

    func overlay(scene: ArcadeScene) -> AnyView {
        AnyView(VStack {
            Spacer()
            Text(phase == .awaitTrace ? (reverse ? "tap it backwards" : "tap it in order")
                 : phase == .reveal ? "" : "watch")
                .font(.system(size: 13, weight: .semibold, design: world.bodyDesign))
                .foregroundStyle(world.muted)
                .padding(.bottom, 8)
        }.allowsHitTesting(false))
    }

    func resultMetrics(scene: ArcadeScene, hits: Int, misses: Int, nearMisses: Int) -> [String: Double] {
        [
            "maxSpan": Double(maxSpan),
            "perfectRounds": Double(perfectRounds),
            "span": Double(span),
            "gridSize": Double(grid),
            "rounds": Double(roundsPlayed)
        ]
    }

    // MARK: Round setup

    private func placeNodes(_ scene: ArcadeScene) {
        scene.reset()
        // Unit coords normalize x to width and y to height; on a tall field that
        // makes equal fractions look stretched vertically. Use the same *pixel* gap
        // for rows as columns (a true square grid), centered.
        let aspect = scene.bounds.height > 0 ? scene.bounds.width / scene.bounds.height : 390.0 / 700.0
        let stepY = stepX * aspect         // matching pixel gap between rows
        let startX = 0.5 - stepX * Double(grid - 1) / 2
        let startY = 0.5 - stepY * Double(grid - 1) / 2
        for r in 0..<grid {
            for c in 0..<grid {
                let x = startX + Double(c) * stepX
                let y = startY + Double(r) * stepY
                scene.add(ArcadeEntity(id: scene.newID(), pos: CGPoint(x: x, y: y), vel: .zero,
                                       radius: nodeRadius, kind: 1, b: r * grid + c))
            }
        }
    }

    private func startRound(_ scene: ArcadeScene) {
        let ids = scene.entities.filter { $0.kind == 1 }.map(\.id).shuffled(using: &rng)
        seq = Array(ids.prefix(span))
        entered = []
        for i in scene.entities.indices { scene.entities[i].a = 0 }   // clear prior selection
        phaseT = 0; litID = nil
        phase = .show
    }
}
