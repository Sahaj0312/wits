//
//  TracePathArcade.swift
//  wits
//
//  "Trace the Path" — nodes light up in sequence, then you drag one continuous
//  stroke through them in order (forward = Path Keeper; reverse = Echo Grid).
//  A single transposition is the near-miss. Round-based; span grows on success.
//

import SwiftUI

@MainActor
final class TracePathArcade: ArcadeGame {
    let id: GameID
    let reverse: Bool
    let inputMode: ArcadeInputMode = .trace
    var howTo: String { reverse ? "watch the path, then trace it BACKWARDS" : "watch the path, then trace it in order" }

    private enum Phase { case show, awaitTrace, reveal }
    private var phase: Phase = .show
    private var placed = false
    private var seq: [Int] = []          // node ids in presentation order
    private var litID: Int?
    private var litCursor = 0
    private var phaseT = 0.0
    private var span = 3
    private var showStep = 0.6

    init(id: GameID, reverse: Bool) { self.id = id; self.reverse = reverse }

    func seed(level: Double, survival: Bool) -> Spawner {
        span = max(2, 2 + Int(level / 2))
        showStep = max(0.32, 0.62 - level * 0.03)
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
                litCursor = step
            }
        case .awaitTrace:
            break
        case .reveal:
            if phaseT > 0.9 { startRound(scene) }
        }
    }

    func postStep(scene: ArcadeScene, dt: Double) -> [Resolution] { [] }

    func resolve(_ action: ArcadeAction, scene: ArcadeScene) -> Resolution? {
        guard phase == .awaitTrace, case let .trace(ids) = action else { return nil }
        let expected = reverse ? Array(seq.reversed()) : seq
        phase = .reveal; phaseT = 0
        let correct = zip(ids, expected).reduce(0) { $0 + ($1.0 == $1.1 ? 1 : 0) }
        if ids.count == expected.count && correct == expected.count {
            span = min(8, span + 1)
            return Resolution(kind: .hit, points: 60 * expected.count)
        }
        span = max(2, span - 1)
        // one transposition leaves all-but-two correct
        if ids.count == expected.count && correct >= expected.count - 2 {
            return Resolution(kind: .nearMiss, points: 0)
        }
        return Resolution(kind: .miss, points: 0)
    }

    func draw(_ e: ArcadeEntity, into ctx: inout GraphicsContext, rect: CGRect, scene: ArcadeScene) {
        let lit = e.id == litID
        let path = Path(roundedRect: rect, cornerRadius: rect.width * 0.3)
        if lit {
            var g = ctx
            g.addFilter(.shadow(color: Color.witsAccent.opacity(0.9), radius: rect.width * 0.5))
            g.fill(path, with: .color(.witsAccent))
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
            Text(phase == .awaitTrace ? (reverse ? "trace it backwards" : "trace it in order")
                 : phase == .reveal ? "" : "watch")
                .font(.witsBody(13, weight: .semibold))
                .foregroundStyle(Color.witsFaint)
                .padding(.bottom, 8)
        }.allowsHitTesting(false))
    }

    // MARK: Round setup

    private func placeNodes(_ scene: ArcadeScene) {
        scene.reset()
        let cols = 4, rows = 4
        for r in 0..<rows {
            for c in 0..<cols {
                let x = 0.2 + Double(c) / Double(cols - 1) * 0.6
                let y = 0.18 + Double(r) / Double(rows - 1) * 0.64
                scene.add(ArcadeEntity(id: scene.newID(), pos: CGPoint(x: x, y: y), vel: .zero,
                                       radius: 0.075, kind: 1, b: r * cols + c))
            }
        }
    }

    private func startRound(_ scene: ArcadeScene) {
        let ids = scene.entities.filter { $0.kind == 1 }.map(\.id).shuffled()
        seq = Array(ids.prefix(span))
        litCursor = 0; phaseT = 0; litID = nil
        phase = .show
    }
}
