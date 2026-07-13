//
//  HeroArt.swift
//  wits
//
//  Generative hero artwork for every game: a domain-derived gradient stage
//  plus a per-game geometric pattern drawn in Canvas. Replaces the old flat
//  hex-pair gradients so each game card has its own identity while the domain
//  color keeps the system coherent.
//

import SwiftUI

/// Full-bleed hero background for a game (card hero, tutorial stage).
struct GameHeroArt: View {
    let game: GameID
    var patternOpacity: Double = 1

    var body: some View {
        let domain = game.domain
        ZStack {
            LinearGradient(
                colors: [domain.heroTopColor, domain.deepColor],
                startPoint: .top, endPoint: .bottom
            )
            // soft light wash so the top-left text zone stays readable
            RadialGradient(
                colors: [.white.opacity(0.10), .clear],
                center: .topLeading, startRadius: 0, endRadius: 320
            )
            Canvas { ctx, size in
                HeroPattern.draw(game, in: &ctx, size: size)
            }
            .opacity(patternOpacity)
        }
        .clipped()
    }
}

/// The per-game pattern vocabulary. Everything is drawn in the hero's own
/// coordinate space with white/domain inks at low opacity, anchored to the
/// right side so the card's text column stays clean.
enum HeroPattern {

    static func draw(_ game: GameID, in ctx: inout GraphicsContext, size: CGSize) {
        let ink = GraphicsContext.Shading.color(.white.opacity(0.16))
        let inkSoft = GraphicsContext.Shading.color(.white.opacity(0.08))
        let glow = GraphicsContext.Shading.color(.white.opacity(0.30))

        switch game {
        case .arrowStorm:
            arrows(&ctx, size, ink: ink, soft: inkSoft, glow: glow)
        case .crowdControl, .split:
            crowd(&ctx, size, ink: ink, soft: inkSoft, glow: glow)
        case .echoGrid:
            grid(&ctx, size, litPath: true, ink: ink, soft: inkSoft, glow: glow)
        case .colorClash:
            rings(&ctx, size, ink: ink, soft: inkSoft, glow: glow)
        case .tileShift:
            shiftTiles(&ctx, size, ink: ink, soft: inkSoft, glow: glow)
        case .lastSeen:
            sparks(&ctx, size, ink: ink, soft: inkSoft, glow: glow)
        case .slidePuzzle, .fuse:
            slide(&ctx, size, ink: ink, soft: inkSoft, glow: glow)
        case .blockEscape, .blockFit:
            escape(&ctx, size, ink: ink, soft: inkSoft, glow: glow)
        case .pegSolitaire:
            pegs(&ctx, size, ink: ink, soft: inkSoft, glow: glow)
        case .waterSort:
            tubes(&ctx, size, ink: ink, soft: inkSoft, glow: glow)
        }
    }

    // MARK: pattern primitives

    /// Rows of right-pointing chevrons drifting off the right edge; one glows.
    private static func arrows(_ ctx: inout GraphicsContext, _ size: CGSize,
                               ink: GraphicsContext.Shading, soft: GraphicsContext.Shading,
                               glow: GraphicsContext.Shading) {
        let rows = 4, cols = 4
        let cell: CGFloat = 46
        let originX = size.width - CGFloat(cols) * cell - 8
        for r in 0..<rows {
            for c in 0..<cols {
                let x = originX + CGFloat(c) * cell + (r.isMultiple(of: 2) ? 0 : cell * 0.4)
                let y = size.height * 0.16 + CGFloat(r) * cell * 0.72
                var p = Path()
                p.move(to: CGPoint(x: x, y: y - 9))
                p.addLine(to: CGPoint(x: x + 14, y: y))
                p.addLine(to: CGPoint(x: x, y: y + 9))
                let isHero = r == 1 && c == 2
                ctx.stroke(p, with: isHero ? glow : (c.isMultiple(of: 2) ? ink : soft),
                           style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            }
        }
    }

    /// A scatter of dots; a handful glow (the tracked ones).
    private static func crowd(_ ctx: inout GraphicsContext, _ size: CGSize,
                              ink: GraphicsContext.Shading, soft: GraphicsContext.Shading,
                              glow: GraphicsContext.Shading) {
        // deterministic pseudo-random scatter
        var seed: UInt64 = 0x9E3779B9
        func rnd() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) % 1000) / 1000
        }
        for i in 0..<26 {
            let x = size.width * (0.38 + rnd() * 0.60)
            let y = size.height * (0.08 + rnd() * 0.84)
            let d: CGFloat = 7 + rnd() * 7
            let rect = CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)
            if i % 7 == 0 {
                ctx.fill(Path(ellipseIn: rect), with: glow)
                ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -5, dy: -5)), with: soft, lineWidth: 1.5)
            } else {
                ctx.fill(Path(ellipseIn: rect), with: i % 2 == 0 ? ink : soft)
            }
        }
    }

    /// A 3×3 tile grid; optionally a lit path snakes through it.
    private static func grid(_ ctx: inout GraphicsContext, _ size: CGSize, litPath: Bool,
                             ink: GraphicsContext.Shading, soft: GraphicsContext.Shading,
                             glow: GraphicsContext.Shading) {
        let cell: CGFloat = 52, gap: CGFloat = 10
        let side = cell * 3 + gap * 2
        let ox = size.width - side - 26
        let oy = (size.height - side) / 2
        let lit: Set<Int> = litPath ? [0, 1, 4, 7, 8] : [8]
        for i in 0..<9 {
            let r = i / 3, c = i % 3
            let rect = CGRect(x: ox + CGFloat(c) * (cell + gap),
                              y: oy + CGFloat(r) * (cell + gap),
                              width: cell, height: cell)
            let p = Path(roundedRect: rect, cornerRadius: 12)
            if lit.contains(i) {
                ctx.fill(p, with: litPath ? soft : glow)
                ctx.stroke(p, with: glow, lineWidth: 2)
            } else if litPath || i != 8 {
                ctx.stroke(p, with: i % 2 == 0 ? ink : soft, lineWidth: 2)
            } else {
                // ruleFinder: the missing cell — dashed outline
                ctx.stroke(p, with: glow, style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
            }
        }
    }


    /// Interlocking rings — color vs word tension.
    private static func rings(_ ctx: inout GraphicsContext, _ size: CGSize,
                              ink: GraphicsContext.Shading, soft: GraphicsContext.Shading,
                              glow: GraphicsContext.Shading) {
        let base = CGPoint(x: size.width * 0.72, y: size.height * 0.5)
        let offsets: [(CGFloat, CGFloat, CGFloat)] = [(-46, -34, 58), (46, -20, 74), (-8, 48, 64)]
        for (i, o) in offsets.enumerated() {
            let rect = CGRect(x: base.x + o.0 - o.2, y: base.y + o.1 - o.2,
                              width: o.2 * 2, height: o.2 * 2)
            ctx.stroke(Path(ellipseIn: rect),
                       with: i == 1 ? glow : (i == 0 ? ink : soft),
                       lineWidth: 12)
        }
    }




    /// Tiles mid-swap with rotation arrows.
    private static func shiftTiles(_ ctx: inout GraphicsContext, _ size: CGSize,
                                   ink: GraphicsContext.Shading, soft: GraphicsContext.Shading,
                                   glow: GraphicsContext.Shading) {
        let c = CGPoint(x: size.width * 0.74, y: size.height * 0.5)
        let r: CGFloat = 78
        for i in 0..<4 {
            let a = CGFloat(i) * .pi / 2 + .pi / 4
            let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            let rect = CGRect(x: p.x - 24, y: p.y - 24, width: 48, height: 48)
            let tile = Path(roundedRect: rect, cornerRadius: 12)
            if i == 0 { ctx.fill(tile, with: soft); ctx.stroke(tile, with: glow, lineWidth: 2) }
            else { ctx.stroke(tile, with: i % 2 == 0 ? ink : soft, lineWidth: 2) }
        }
        // circular swap arrow
        var arc = Path()
        arc.addArc(center: c, radius: r * 0.42, startAngle: .degrees(-40), endAngle: .degrees(200), clockwise: false)
        ctx.stroke(arc, with: glow, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        var head = Path()
        let tip = CGPoint(x: c.x + cos(-40 * .pi / 180) * r * 0.42, y: c.y + sin(-40 * .pi / 180) * r * 0.42)
        head.move(to: CGPoint(x: tip.x - 10, y: tip.y - 2))
        head.addLine(to: tip)
        head.addLine(to: CGPoint(x: tip.x - 1, y: tip.y + 11))
        ctx.stroke(head, with: glow, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
    }

    /// Sparkle marks, a few checked off.
    private static func sparks(_ ctx: inout GraphicsContext, _ size: CGSize,
                               ink: GraphicsContext.Shading, soft: GraphicsContext.Shading,
                               glow: GraphicsContext.Shading) {
        let spots: [(CGFloat, CGFloat, CGFloat, Bool)] = [
            (0.48, 0.20, 13, false), (0.66, 0.12, 9, true), (0.84, 0.24, 15, false),
            (0.56, 0.48, 10, false), (0.76, 0.52, 17, true), (0.92, 0.44, 9, false),
            (0.50, 0.78, 15, true), (0.68, 0.84, 9, false), (0.88, 0.74, 13, false),
        ]
        for s in spots {
            let c = CGPoint(x: size.width * s.0, y: size.height * s.1)
            var p = Path()
            p.move(to: CGPoint(x: c.x, y: c.y - s.2)); p.addLine(to: CGPoint(x: c.x, y: c.y + s.2))
            p.move(to: CGPoint(x: c.x - s.2, y: c.y)); p.addLine(to: CGPoint(x: c.x + s.2, y: c.y))
            ctx.stroke(p, with: s.3 ? glow : (s.2 > 12 ? ink : soft),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }




    /// Slide puzzle mid-move: numbered tiles, one gap, one tile slipping in.
    private static func slide(_ ctx: inout GraphicsContext, _ size: CGSize,
                              ink: GraphicsContext.Shading, soft: GraphicsContext.Shading,
                              glow: GraphicsContext.Shading) {
        let cell: CGFloat = 54, gap: CGFloat = 8
        let side = cell * 3 + gap * 2
        let ox = size.width - side - 28
        let oy = (size.height - side) / 2
        let labels = ["1", "2", "3", "4", "5", "", "7", "8", "6"]
        for i in 0..<9 {
            let r = i / 3, c = i % 3
            var rect = CGRect(x: ox + CGFloat(c) * (cell + gap),
                              y: oy + CGFloat(r) * (cell + gap),
                              width: cell, height: cell)
            if labels[i].isEmpty { continue }
            let sliding = i == 8
            if sliding { rect.origin.x -= cell * 0.55 }
            let p = Path(roundedRect: rect, cornerRadius: 12)
            if sliding { ctx.fill(p, with: glow) }
            else { ctx.fill(p, with: (r + c).isMultiple(of: 2) ? ink : soft) }
            ctx.draw(Text(labels[i]).font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(sliding ? 0.85 : 0.4)),
                     at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }
    }

    /// Block escape mid-solve: a jammed tray, the glowing 2×2 hero lined up
    /// over the exit notch in the bottom rail.
    private static func escape(_ ctx: inout GraphicsContext, _ size: CGSize,
                               ink: GraphicsContext.Shading, soft: GraphicsContext.Shading,
                               glow: GraphicsContext.Shading) {
        let cell: CGFloat = 26, gap: CGFloat = 5
        let cols = 4, rows = 5
        let trayW = CGFloat(cols) * cell + CGFloat(cols - 1) * gap
        let trayH = CGFloat(rows) * cell + CGFloat(rows - 1) * gap
        let ox = size.width - trayW - 44
        let oy = (size.height - trayH) / 2 - 12

        func block(_ c: Int, _ r: Int, _ w: Int, _ h: Int, _ shading: GraphicsContext.Shading) {
            let rect = CGRect(x: ox + CGFloat(c) * (cell + gap),
                              y: oy + CGFloat(r) * (cell + gap),
                              width: CGFloat(w) * cell + CGFloat(w - 1) * gap,
                              height: CGFloat(h) * cell + CGFloat(h - 1) * gap)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 9), with: shading)
        }

        block(0, 0, 1, 2, soft)     // vertical
        block(1, 0, 2, 1, ink)      // flat
        block(3, 0, 1, 2, soft)     // vertical
        block(0, 2, 1, 1, ink)      // single
        block(3, 2, 1, 1, soft)     // single
        block(1, 2, 2, 2, glow)     // the hero, two rows above the exit
        block(0, 4, 1, 1, soft)     // single by the door

        // bottom rail with the exit gap under the hero's columns
        let railY = oy + trayH + 10
        let exitL = ox + 1 * (cell + gap)
        let exitR = exitL + 2 * cell + gap
        var rail = Path()
        rail.move(to: CGPoint(x: ox - 8, y: railY))
        rail.addLine(to: CGPoint(x: exitL - 6, y: railY))
        rail.move(to: CGPoint(x: exitR + 6, y: railY))
        rail.addLine(to: CGPoint(x: ox + trayW + 8, y: railY))
        ctx.stroke(rail, with: ink, style: StrokeStyle(lineWidth: 4, lineCap: .round))

        // escape arrow through the gap
        var arrow = Path()
        let ax = (exitL + exitR) / 2
        arrow.move(to: CGPoint(x: ax, y: railY - 4))
        arrow.addLine(to: CGPoint(x: ax, y: railY + 12))
        arrow.move(to: CGPoint(x: ax - 7, y: railY + 6))
        arrow.addLine(to: CGPoint(x: ax, y: railY + 13))
        arrow.addLine(to: CGPoint(x: ax + 7, y: railY + 6))
        ctx.stroke(arrow, with: glow, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
    }

    /// Peg solitaire mid-jump: a diamond of holes, a few pegs, one arcing
    /// over its neighbour into the empty hole.
    /// Three standing tubes with fill lines; one top segment glows (the run
    /// about to pour) and a bubble drifts between them.
    private static func tubes(_ ctx: inout GraphicsContext, _ size: CGSize,
                              ink: GraphicsContext.Shading, soft: GraphicsContext.Shading,
                              glow: GraphicsContext.Shading) {
        let tubeW: CGFloat = 44
        let tubeH: CGFloat = 128
        let baseY = size.height / 2 - tubeH / 2 + 6
        for (index, x) in [size.width - 210, size.width - 148, size.width - 86].enumerated() {
            let rect = CGRect(x: x, y: baseY + CGFloat(index.isMultiple(of: 2) ? 0 : 14),
                              width: tubeW, height: tubeH)
            ctx.stroke(Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(topLeading: 8,
                                                                                 bottomLeading: tubeW / 2,
                                                                                 bottomTrailing: tubeW / 2,
                                                                                 topTrailing: 8)),
                       with: index == 1 ? ink : soft, lineWidth: 3)
            // fill lines: the tube's liquid levels
            for line in 1...3 {
                let y = rect.maxY - CGFloat(line) * tubeH / 4.6
                var path = Path()
                path.move(to: CGPoint(x: rect.minX + 6, y: y))
                path.addLine(to: CGPoint(x: rect.maxX - 6, y: y))
                ctx.stroke(path, with: index == 1 && line == 3 ? glow : soft, lineWidth: 2.5)
            }
        }
        // a rising bubble
        ctx.stroke(Path(ellipseIn: CGRect(x: size.width - 122, y: baseY - 26, width: 12, height: 12)),
                   with: glow, lineWidth: 2.5)
    }

    private static func pegs(_ ctx: inout GraphicsContext, _ size: CGSize,
                             ink: GraphicsContext.Shading, soft: GraphicsContext.Shading,
                             glow: GraphicsContext.Shading) {
        let cell: CGFloat = 38
        let cx = size.width - 118, cy = size.height / 2 + 8
        // diamond of holes (radius 2 in taxicab distance)
        for dy in -2...2 {
            for dx in -2...2 where abs(dx) + abs(dy) <= 2 {
                let p = CGPoint(x: cx + CGFloat(dx) * cell, y: cy + CGFloat(dy) * cell)
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)),
                           with: soft, lineWidth: 2.5)
            }
        }
        // resting pegs
        for (dx, dy) in [(-1, 1), (0, 1), (1, 0), (0, -1)] {
            let p = CGPoint(x: cx + CGFloat(dx) * cell, y: cy + CGFloat(dy) * cell)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20)), with: ink)
        }
        // the jumper, mid-arc from (-2,0) over (-1,0) into (0,0)
        let from = CGPoint(x: cx - 2 * cell, y: cy)
        let mid = CGPoint(x: cx - cell, y: cy)
        ctx.fill(Path(ellipseIn: CGRect(x: mid.x - 10, y: mid.y - 10, width: 20, height: 20)), with: soft)
        var arc = Path()
        arc.move(to: from)
        arc.addQuadCurve(to: CGPoint(x: cx, y: cy), control: CGPoint(x: cx - cell, y: cy - cell * 1.5))
        ctx.stroke(arc, with: glow, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [1, 7]))
        let jumper = CGPoint(x: cx - cell, y: cy - cell * 1.1)
        ctx.fill(Path(ellipseIn: CGRect(x: jumper.x - 11, y: jumper.y - 11, width: 22, height: 22)), with: glow)
    }
}

#Preview("hero art") {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(GameID.allCases) { g in
                GameHeroArt(game: g)
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(alignment: .bottomLeading) {
                        Text(g.displayName).font(.witsHeading()).foregroundStyle(.white).padding(12)
                    }
            }
        }
        .padding(16)
    }
}
