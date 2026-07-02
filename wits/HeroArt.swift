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
        case .echoGrid, .ruleFinder:
            grid(&ctx, size, litPath: game == .echoGrid, ink: ink, soft: inkSoft, glow: glow)
        case .spotSpeed:
            radar(&ctx, size, ink: ink, soft: inkSoft, glow: glow)
        case .colorClash:
            rings(&ctx, size, ink: ink, soft: inkSoft, glow: glow)
        case .matchBack:
            lane(&ctx, size, ink: ink, soft: inkSoft, glow: glow)
        case .numberRush, .estimator:
            numerals(&ctx, size, forge: game == .estimator, soft: inkSoft, glow: glow)
        case .oddOneOut:
            oddOne(&ctx, size, ink: ink, soft: inkSoft, glow: glow)
        case .tileShift:
            shiftTiles(&ctx, size, ink: ink, soft: inkSoft, glow: glow)
        case .lastSeen:
            sparks(&ctx, size, ink: ink, soft: inkSoft, glow: glow)
        case .pathKeeper, .dotsConnect, .oneLine:
            path(&ctx, size, closed: game == .oneLine, ink: ink, soft: inkSoft, glow: glow)
        case .wordConnect, .memoryLock:
            letters(&ctx, size, wheel: game == .wordConnect, ink: ink, soft: inkSoft, glow: glow)
        case .towerOfHanoi:
            tower(&ctx, size, ink: ink, soft: inkSoft, glow: glow)
        case .slidePuzzle:
            slide(&ctx, size, ink: ink, soft: inkSoft, glow: glow)
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

    /// Concentric field-of-view rings with a flash at the periphery.
    private static func radar(_ ctx: inout GraphicsContext, _ size: CGSize,
                              ink: GraphicsContext.Shading, soft: GraphicsContext.Shading,
                              glow: GraphicsContext.Shading) {
        let c = CGPoint(x: size.width * 0.74, y: size.height * 0.5)
        for (i, r) in [36, 74, 112, 150].enumerated() {
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - CGFloat(r), y: c.y - CGFloat(r),
                                              width: CGFloat(r) * 2, height: CGFloat(r) * 2)),
                       with: i % 2 == 0 ? ink : soft, lineWidth: 2)
        }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)), with: glow)
        // the peripheral flash
        let f = CGPoint(x: c.x + 96, y: c.y - 82)
        ctx.fill(Path(ellipseIn: CGRect(x: f.x - 9, y: f.y - 9, width: 18, height: 18)), with: glow)
        ctx.stroke(Path(ellipseIn: CGRect(x: f.x - 17, y: f.y - 17, width: 34, height: 34)),
                   with: soft, lineWidth: 2)
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

    /// A receding lane of stacked cards.
    private static func lane(_ ctx: inout GraphicsContext, _ size: CGSize,
                             ink: GraphicsContext.Shading, soft: GraphicsContext.Shading,
                             glow: GraphicsContext.Shading) {
        for i in 0..<5 {
            let t = CGFloat(i)
            let w = 120 - t * 14, h = 156 - t * 18
            let x = size.width - 60 - w / 2 - t * 44
            let y = size.height / 2 - h / 2 + t * 4
            let p = Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: 16)
            if i == 0 {
                ctx.fill(p, with: soft)
                ctx.stroke(p, with: glow, lineWidth: 2.5)
            } else {
                ctx.stroke(p, with: i < 2 ? ink : soft, lineWidth: 2)
            }
        }
    }

    /// Drifting numerals and operators; estimator adds the target ring.
    private static func numerals(_ ctx: inout GraphicsContext, _ size: CGSize, forge: Bool,
                                 soft: GraphicsContext.Shading,
                                 glow: GraphicsContext.Shading) {
        let glyphs = forge ? ["7", "×", "3", "+", "42", "−", "9"] : ["8", "+", "5", "−", "12", "÷", "3"]
        let spots: [(CGFloat, CGFloat, CGFloat)] = [
            (0.46, 0.16, 30), (0.62, 0.36, 46), (0.82, 0.14, 34),
            (0.90, 0.44, 30), (0.56, 0.66, 34), (0.76, 0.78, 52), (0.92, 0.72, 30),
        ]
        for (i, g) in glyphs.enumerated() {
            let s = spots[i]
            let text = Text(g).font(.system(size: s.2, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(i == 4 ? 0.30 : (i % 2 == 0 ? 0.16 : 0.09)))
            ctx.draw(text, at: CGPoint(x: size.width * s.0, y: size.height * s.1), anchor: .center)
        }
        if forge {
            let c = CGPoint(x: size.width * 0.76, y: size.height * 0.52)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 64, y: c.y - 64, width: 128, height: 128)),
                       with: soft, style: StrokeStyle(lineWidth: 2.5, dash: [8, 8]))
        }
    }

    /// A field of identical shapes, one rotated stranger glowing.
    private static func oddOne(_ ctx: inout GraphicsContext, _ size: CGSize,
                               ink: GraphicsContext.Shading, soft: GraphicsContext.Shading,
                               glow: GraphicsContext.Shading) {
        let cell: CGFloat = 48
        for r in 0..<4 {
            for c in 0..<4 {
                let x = size.width - 24 - CGFloat(4 - c) * cell
                let y = size.height * 0.12 + CGFloat(r) * cell * 1.06
                let rect = CGRect(x: x, y: y, width: 26, height: 26)
                var p = Path(roundedRect: rect, cornerRadius: 7)
                let isOdd = r == 2 && c == 1
                if isOdd {
                    p = p.applying(CGAffineTransform(translationX: -rect.midX, y: -rect.midY)
                        .concatenating(.init(rotationAngle: .pi / 4))
                        .concatenating(.init(translationX: rect.midX, y: rect.midY)))
                    ctx.fill(p, with: glow)
                } else {
                    ctx.stroke(p, with: (r + c).isMultiple(of: 2) ? ink : soft, lineWidth: 2)
                }
            }
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

    /// A node path hopping across the space; oneLine closes the circuit.
    private static func path(_ ctx: inout GraphicsContext, _ size: CGSize, closed: Bool,
                             ink: GraphicsContext.Shading, soft: GraphicsContext.Shading,
                             glow: GraphicsContext.Shading) {
        let pts = [
            CGPoint(x: size.width * 0.46, y: size.height * 0.72),
            CGPoint(x: size.width * 0.60, y: size.height * 0.24),
            CGPoint(x: size.width * 0.76, y: size.height * 0.60),
            CGPoint(x: size.width * 0.88, y: size.height * 0.18),
            CGPoint(x: size.width * 0.94, y: size.height * 0.66),
        ]
        var line = Path()
        line.move(to: pts[0])
        for p in pts.dropFirst() { line.addLine(to: p) }
        if closed { line.addLine(to: pts[0]) }
        ctx.stroke(line, with: ink, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        for (i, p) in pts.enumerated() {
            let d: CGFloat = i == 0 ? 20 : 14
            let rect = CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)
            ctx.fill(Path(ellipseIn: rect), with: i == 0 ? glow : soft)
            ctx.stroke(Path(ellipseIn: rect), with: i == 0 ? glow : ink, lineWidth: 2)
        }
    }

    /// Letter tiles: a wheel for wordConnect, a guess row for memoryLock.
    private static func letters(_ ctx: inout GraphicsContext, _ size: CGSize, wheel: Bool,
                                ink: GraphicsContext.Shading, soft: GraphicsContext.Shading,
                                glow: GraphicsContext.Shading) {
        if wheel {
            let c = CGPoint(x: size.width * 0.74, y: size.height * 0.5)
            let r: CGFloat = 82
            let ls = ["W", "I", "T", "S", "E"]
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                       with: soft, lineWidth: 2)
            var link = Path()
            for (i, _) in ls.enumerated() {
                let a = -CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / CGFloat(ls.count)
                let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                if i == 0 { link.move(to: p) } else if i != 3 { link.addLine(to: p) }
            }
            ctx.stroke(link, with: glow, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            for (i, l) in ls.enumerated() {
                let a = -CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / CGFloat(ls.count)
                let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                let rect = CGRect(x: p.x - 19, y: p.y - 19, width: 38, height: 38)
                ctx.fill(Path(ellipseIn: rect), with: soft)
                ctx.draw(Text(l).font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55)), at: p, anchor: .center)
            }
        } else {
            let word = ["W", "I", "T", "S", "?"]
            let cell: CGFloat = 46, gap: CGFloat = 8
            let total = cell * CGFloat(word.count) + gap * CGFloat(word.count - 1)
            let ox = size.width - total - 26
            let oy = size.height / 2 - cell / 2
            for (i, l) in word.enumerated() {
                let rect = CGRect(x: ox + CGFloat(i) * (cell + gap), y: oy + (i.isMultiple(of: 2) ? -10 : 10),
                                  width: cell, height: cell)
                let p = Path(roundedRect: rect, cornerRadius: 10)
                if i == 2 { ctx.fill(p, with: glow) }
                else if i == 4 { ctx.stroke(p, with: glow, style: StrokeStyle(lineWidth: 2, dash: [5, 5])) }
                else { ctx.fill(p, with: i.isMultiple(of: 2) ? ink : soft) }
                if i != 4 {
                    ctx.draw(Text(l).font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(i == 2 ? 0.8 : 0.45)),
                             at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
                }
            }
        }
    }

    /// Three pegs, discs mid-migration.
    private static func tower(_ ctx: inout GraphicsContext, _ size: CGSize,
                              ink: GraphicsContext.Shading, soft: GraphicsContext.Shading,
                              glow: GraphicsContext.Shading) {
        let baseY = size.height * 0.78
        let pegXs: [CGFloat] = [0.52, 0.72, 0.92].map { size.width * $0 }
        var base = Path()
        base.move(to: CGPoint(x: pegXs[0] - 44, y: baseY))
        base.addLine(to: CGPoint(x: pegXs[2] + 44, y: baseY))
        ctx.stroke(base, with: ink, style: StrokeStyle(lineWidth: 4, lineCap: .round))
        for x in pegXs {
            var peg = Path()
            peg.move(to: CGPoint(x: x, y: baseY))
            peg.addLine(to: CGPoint(x: x, y: baseY - 116))
            ctx.stroke(peg, with: soft, style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
        func disc(_ x: CGFloat, _ level: Int, _ w: CGFloat, _ shading: GraphicsContext.Shading) {
            let rect = CGRect(x: x - w / 2, y: baseY - CGFloat(level) * 24 - 20, width: w, height: 16)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 8), with: shading)
        }
        disc(pegXs[0], 0, 76, ink)
        disc(pegXs[0], 1, 58, soft)
        disc(pegXs[2], 0, 66, ink)
        // the flying disc
        let rect = CGRect(x: pegXs[1] - 21, y: baseY - 148, width: 42, height: 16)
        ctx.fill(Path(roundedRect: rect, cornerRadius: 8), with: glow)
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
