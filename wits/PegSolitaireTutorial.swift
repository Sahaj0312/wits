//
//  PegSolitaireTutorial.swift
//  wits
//
//  Animated how-to-play demos for Peg Solitaire on the mini diamond board:
//  tap a peg and the empty hole two spaces away to jump, the peg leapt over
//  pops off the board, and chaining jumps clears down to a single peg.
//  Rendering mirrors the real game, felt-green surface, cream pegs, the red
//  selection tint and dashed landing rings, so nothing needs relearning.
//

import SwiftUI

enum PegSolitaireTutorial {
    static let slides: [TutorialSlide] = [
        TutorialSlide(caption: "tap a peg, then tap the empty hole two spaces away to jump it") {
            PegSolitaireDemo(page: .jump)
        },
        TutorialSlide(caption: "the peg you jump over is removed. land and jump again to keep clearing") {
            PegSolitaireDemo(page: .chain)
        },
        TutorialSlide(caption: "clear the board down to a single peg") {
            PegSolitaireDemo(page: .clear)
        },
    ]
}

private struct PegSolitaireDemo: View {
    enum Page { case jump, chain, clear }
    let page: Page

    private static let cols = 5
    private static let jumpTime = 0.35
    /// diamond13, the shape the first levels use.
    private static let holes: [Int] = [2, 6, 7, 8, 10, 11, 12, 13, 14, 16, 17, 18, 22]

    private var world: GameWorld { GameID.pegSolitaire.world }

    var body: some View {
        DemoLoop(duration: script.duration) { t in
            Canvas { context, size in
                render(context, size: size, t: t)
            }
        }
    }

    // MARK: Script

    /// One scripted jump: `peg` is the moving peg's identity (its starting
    /// hole), `over` names the removed peg by its hole. Selection runs
    /// selectAt..<start, matching the tap that picks the peg up.
    private struct Jump {
        let peg: Int
        let from: Int
        let over: Int
        let to: Int
        let selectAt: Double
        let start: Double
    }

    private struct Script {
        let duration: Double
        let pegs: [Int]                       // starting holes, doubling as ids
        let jumps: [Jump]
        let taps: [(time: Double, hole: Int)]
        var clearedAt: Double? = nil          // last-peg celebration
    }

    private var script: Script {
        switch page {
        case .jump:
            // Middle row: 10 jumps over 11 into the empty 12; 7/17 dress the
            // board without adding extra legal destinations.
            return Script(
                duration: 4.8,
                pegs: [10, 11, 7, 17],
                jumps: [Jump(peg: 10, from: 10, over: 11, to: 12, selectAt: 1.2, start: 2.5)],
                taps: [(1.2, 10), (2.5, 12)])
        case .chain:
            // Same peg sweeps the middle row twice: 10→12 removing 11, then
            // 12→14 removing 13.
            return Script(
                duration: 5.8,
                pegs: [10, 11, 13, 6],
                jumps: [Jump(peg: 10, from: 10, over: 11, to: 12, selectAt: 1.0, start: 1.9),
                        Jump(peg: 10, from: 12, over: 13, to: 14, selectAt: 2.9, start: 3.8)],
                taps: [(1.0, 10), (1.9, 12), (2.9, 12), (3.8, 14)])
        case .clear:
            // Down the spine: 2 over 7 into the centre, then over 17 to the
            // bottom point, three pegs become one.
            return Script(
                duration: 6.0,
                pegs: [2, 7, 17],
                jumps: [Jump(peg: 2, from: 2, over: 7, to: 12, selectAt: 0.9, start: 1.7),
                        Jump(peg: 2, from: 12, over: 17, to: 22, selectAt: 2.6, start: 3.4)],
                taps: [(0.9, 2), (1.7, 12), (2.6, 12), (3.4, 22)],
                clearedAt: 3.95)
        }
    }

    // MARK: Geometry

    private struct Geo {
        let board: CGRect
        let cell: CGFloat
        let chipCenter: CGPoint
        let chipSize: CGSize

        init(size: CGSize) {
            let side = min(size.width * 0.94, size.height * 0.70)
            board = CGRect(x: (size.width - side) / 2,
                           y: size.height * 0.195,
                           width: side, height: side)
            let inset = side * 0.045
            cell = (side - inset * 2) / 5
            chipSize = CGSize(width: cell * 2.3, height: cell * 0.62)
            chipCenter = CGPoint(x: size.width / 2, y: size.height * 0.095)
        }

        func center(_ hole: Int) -> CGPoint {
            let inset = (board.width - cell * 5) / 2
            return CGPoint(x: board.minX + inset + (CGFloat(hole % 5) + 0.5) * cell,
                           y: board.minY + inset + (CGFloat(hole / 5) + 0.5) * cell)
        }
    }

    // MARK: Render

    private func render(_ context: GraphicsContext, size: CGSize, t: Double) {
        let geo = Geo(size: size)
        let script = script

        context.fill(Path(roundedRect: geo.board, cornerRadius: 7, style: .continuous),
                     with: .color(world.surface.opacity(0.90)))

        for hole in Self.holes {
            let d = geo.cell * 0.72
            let c = geo.center(hole)
            context.fill(Path(ellipseIn: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)),
                         with: .color(.black.opacity(0.32)))
        }

        // Dashed landing ring while the jumping peg is selected.
        for jump in script.jumps where t >= jump.selectAt + 0.12 && t < jump.start + 0.05 {
            let alpha = DemoEase.ramp(t, jump.selectAt + 0.12, jump.selectAt + 0.35)
            let d = geo.cell * 0.84
            let c = geo.center(jump.to)
            context.stroke(Path(ellipseIn: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)),
                           with: .color(.white.opacity(0.85 * alpha)),
                           style: StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
        }

        if page == .clear, let at = script.clearedAt {
            drawClearHalo(context, geo: geo, t: t, clearedAt: at)
        }

        drawPegs(context, geo: geo, script: script, t: t)
        drawChip(context, geo: geo, script: script, t: t)

        if page == .chain {
            for jump in script.jumps {
                drawMinusOne(context, geo: geo, jump: jump, t: t)
            }
        }

        for tap in script.taps {
            DemoEase.drawTapRipple(context, at: geo.center(tap.hole),
                                   start: tap.time, t: t,
                                   radius: geo.cell * 0.52, color: world.accent)
        }

        let hand = DemoEase.handAlongTaps(
            script.taps.map { DemoEase.Tap(time: $0.time, point: geo.center($0.hole)) }, t: t)
        DemoEase.drawHand(context, tip: CGPoint(x: hand.tip.x + geo.cell * 0.06,
                                                y: hand.tip.y + geo.cell * 0.10),
                          size: geo.cell * 0.98, pressed: hand.pressed, alpha: hand.alpha)

        if page == .clear, let at = script.clearedAt {
            drawClearBadge(context, geo: geo, t: t, clearedAt: at)
        }
    }

    private func drawPegs(_ context: GraphicsContext, geo: Geo, script: Script, t: Double) {
        for peg in script.pegs {
            var scale = 1.0
            // The peg being leapt over shrinks out just like the game's
            // vanishing scaleEffect.
            if let killer = script.jumps.first(where: { $0.over == peg }) {
                let gone = DemoEase.ramp(t, killer.start + 0.10, killer.start + 0.38)
                if gone >= 0.97 { continue }
                scale = 1 - gone
            }

            var center = geo.center(peg)
            for jump in script.jumps where jump.peg == peg {
                let u = DemoEase.ramp(t, jump.start, jump.start + Self.jumpTime)
                guard u > 0 else { break }   // chronological; later hops haven't begun
                center = DemoEase.lerp(geo.center(jump.from), geo.center(jump.to), u)
                if u < 1 {
                    center.y -= sin(.pi * u) * geo.cell * 0.38   // hop arc
                }
            }

            let selected = script.jumps.contains {
                $0.peg == peg && t >= $0.selectAt && t < $0.start
            }
            if selected { scale *= 1.12 }

            let d = geo.cell * 0.58 * scale
            let rect = CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.25), radius: 3, y: 2))
                layer.fill(Path(ellipseIn: rect),
                           with: .color(selected ? world.secondary : world.ink))
            }
        }
    }

    /// The real top bar's "pegs: N" capsule, ticking down as jumps land.
    private func drawChip(_ context: GraphicsContext, geo: Geo, script: Script, t: Double) {
        let count = script.pegs.count - script.jumps.filter { t >= $0.start + 0.18 }.count
        let rect = CGRect(x: geo.chipCenter.x - geo.chipSize.width / 2,
                          y: geo.chipCenter.y - geo.chipSize.height / 2,
                          width: geo.chipSize.width, height: geo.chipSize.height)
        context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2, style: .continuous),
                     with: .color(.black.opacity(0.35)))
        context.draw(Text("pegs: \(count)")
                        .font(.system(size: rect.height * 0.52, weight: .heavy, design: .rounded))
                        .foregroundColor(.white),
                     at: geo.chipCenter)
    }

    private func drawMinusOne(_ context: GraphicsContext, geo: Geo, jump: Jump, t: Double) {
        let u = DemoEase.ramp(t, jump.start + 0.20, jump.start + 1.05)
        guard u > 0, u < 1 else { return }
        let alpha = min(1, u * 6) * (1 - DemoEase.ramp(u, 0.60, 1))
        let start = geo.center(jump.over)
        // Starts above the hole so the gold text sits on felt, not the pit.
        let at = CGPoint(x: start.x, y: start.y - geo.cell * (0.55 + 0.85 * CGFloat(u)))
        context.drawLayer { layer in
            layer.opacity = alpha
            layer.addFilter(.shadow(color: .black.opacity(0.5), radius: 2, y: 1))
            layer.draw(Text("-1")
                        .font(.system(size: geo.cell * 0.52, weight: .black, design: world.titleDesign))
                        .foregroundColor(world.accent),
                       at: at)
        }
    }

    // MARK: Clear celebration

    private func drawClearHalo(_ context: GraphicsContext, geo: Geo, t: Double, clearedAt: Double) {
        let appear = DemoEase.ramp(t, clearedAt, clearedAt + 0.4)
        guard appear > 0 else { return }
        let final = geo.center(22)

        // Soft pulsing glow under the survivor.
        let pulse = 1 + 0.10 * sin((t - clearedAt) * 4)
        let r = geo.cell * 0.52 * CGFloat(pulse)
        context.fill(Path(ellipseIn: CGRect(x: final.x - r, y: final.y - r, width: r * 2, height: r * 2)),
                     with: .color(world.accent.opacity(0.32 * appear)))

        // Two staggered rings ripple outward once.
        for k in 0..<2 {
            let delay = clearedAt + 0.15 + Double(k) * 0.45
            let u = DemoEase.ramp(t, delay, delay + 0.85)
            guard u > 0, u < 1 else { continue }
            let ringR = geo.cell * (0.45 + 1.25 * CGFloat(u))
            context.stroke(Path(ellipseIn: CGRect(x: final.x - ringR, y: final.y - ringR,
                                                  width: ringR * 2, height: ringR * 2)),
                           with: .color(world.accent.opacity(0.85 * (1 - u))),
                           lineWidth: 3)
        }
    }

    private func drawClearBadge(_ context: GraphicsContext, geo: Geo, t: Double, clearedAt: Double) {
        let u = DemoEase.ramp(t, clearedAt + 0.35, clearedAt + 0.75)
        guard u > 0 else { return }
        let badge = CGRect(x: geo.board.midX - geo.cell * 1.6,
                           y: geo.board.midY - geo.cell * 0.45,
                           width: geo.cell * 3.2, height: geo.cell * 0.9)
        context.drawLayer { layer in
            layer.opacity = u
            layer.addFilter(.shadow(color: .black.opacity(0.45), radius: 8, y: 5))
            layer.fill(Path(roundedRect: badge, cornerRadius: badge.height / 2, style: .continuous),
                       with: .color(world.background.opacity(0.95)))
            layer.stroke(Path(roundedRect: badge, cornerRadius: badge.height / 2, style: .continuous),
                         with: .color(world.accent.opacity(0.9)), lineWidth: 2)
            layer.draw(Text("cleared!")
                        .font(.system(size: geo.cell * 0.44, weight: .black, design: world.titleDesign))
                        .foregroundColor(world.ink),
                       at: CGPoint(x: badge.midX, y: badge.midY))
        }
    }
}
