//
//  MahjongTutorial.swift
//  wits
//
//  Animated how-to-play demos for Mahjong on a tiny two-layer stack with the
//  five-slot rack below: a blocked tile refuses the tap, a free tile flies
//  into the rack, twins pop gold and vanish, and a rack full of singles turns
//  the border red until undo rewinds the risky pick. Tiles are drawn like the
//  real game — ivory faces on jade sides, buried tiles falling into shade.
//

import SwiftUI

enum MahjongTutorial {
    static let slides: [TutorialSlide] = [
        TutorialSlide(caption: "tap a free tile — an open side and nothing on top — to lift it into the rack") {
            MahjongDemo(page: .pick)
        },
        TutorialSlide(caption: "when its twin lands in the rack, the pair vanishes") {
            MahjongDemo(page: .match)
        },
        TutorialSlide(caption: "five singles fill the rack and end the run — undo rewinds a risky pick") {
            MahjongDemo(page: .danger)
        },
    ]
}

private struct MahjongDemo: View {
    enum Page { case pick, match, danger }
    let page: Page

    private var world: GameWorld { GameID.mahjong.world }

    // Lifted straight from MahjongTileView / rackView so the demo is
    // instantly recognizable as the real table.
    private static let ivoryTop = Color(hexAny: 0xFFFBEF)
    private static let ivoryBottom = Color(hexAny: 0xF1E8CF)
    private static let jade = Color(hexAny: 0x3E7A5C)
    private static let jadeDim = Color(hexAny: 0x2E5B45)
    private static let rackWood = Color(hexAny: 0x241014)
    private static let danger = Color(hexAny: 0xE05563)
    private static let inkBlue = Color(hexAny: 0x22437A)
    private static let inkRed = Color(hexAny: 0xC93B3B)
    private static let inkGreen = Color(hexAny: 0x2F7D4F)

    var body: some View {
        DemoLoop(duration: script.duration) { t in
            Canvas { context, size in
                render(context, size: size, t: t)
            }
        }
    }

    // MARK: Script

    /// Simplified drawn faces — one of each suit family so the pair on the
    /// match page is unmistakable.
    enum Face { case dot1, dot2, dot3, bam2, char, wind }

    private struct Script {
        let duration: Double
        let bottom: [Face]        // 4 bottom-layer tiles, left to right
        let top: Face             // one tile straddling the middle seam
        let rackStart: [Face]     // singles already sitting in the rack
        let pickIndex: Int        // bottom tile the hand lifts
        let pickAt: Double
        var blockedAt: Double? = nil   // refused tap on a covered tile first
        var popAt: Double? = nil       // twin match celebration
        var undoAt: Double? = nil      // rewind tap on the undo button
    }

    private var script: Script {
        switch page {
        case .pick:
            // Refuse a covered tile first, then lift the free right-end tile.
            return Script(duration: 5.6,
                          bottom: [.bam2, .char, .dot1, .dot3], top: .wind,
                          rackStart: [], pickIndex: 3, pickAt: 2.8,
                          blockedAt: 1.1)
        case .match:
            // Its twin already waits in the rack; the pair pops gold and clears.
            return Script(duration: 5.2,
                          bottom: [.char, .bam2, .dot1, .dot3], top: .wind,
                          rackStart: [.dot3], pickIndex: 3, pickAt: 1.5,
                          popAt: 2.5)
        case .danger:
            // A fourth single lights the rack red; undo pulls the pick back out.
            return Script(duration: 6.0,
                          bottom: [.wind, .char, .bam2, .dot1], top: .dot2,
                          rackStart: [.dot3, .bam2, .char], pickIndex: 3, pickAt: 1.0,
                          undoAt: 3.2)
        }
    }

    // Shared move timing: the pick leaves the board shortly after the tap.
    private static let flyDelay = 0.15
    private static let flyTime = 0.5

    // MARK: Geometry

    private struct Geo {
        let size: CGSize
        let tileW: CGFloat
        let tileH: CGFloat
        let depth: CGFloat
        let slotW: CGFloat
        let slotH: CGFloat
        let rackPanel: CGRect

        init(size: CGSize) {
            self.size = size
            tileW = size.width * 0.165
            tileH = tileW * 1.24
            depth = tileW * 0.16
            slotW = size.width * 0.13
            slotH = slotW * 1.24
            let pad = size.width * 0.035
            let gap = size.width * 0.02
            let panelW = slotW * 5 + gap * 4 + pad * 2
            let panelH = slotH + slotW * 0.10 + pad * 2
            rackPanel = CGRect(x: (size.width - panelW) / 2,
                               y: size.height * 0.86 - panelH / 2,
                               width: panelW, height: panelH)
        }

        func bottomCenter(_ index: Int) -> CGPoint {
            CGPoint(x: size.width / 2 + (CGFloat(index) - 1.5) * tileW,
                    y: size.height * 0.36)
        }

        /// The z=1 tile straddles the seam between bottom tiles 1 and 2,
        /// lifted up-left by one depth step like the real board.
        var topCenter: CGPoint {
            CGPoint(x: size.width / 2 - depth * 0.6,
                    y: size.height * 0.36 - depth)
        }

        func slotCenter(_ index: Int) -> CGPoint {
            let gap = size.width * 0.02
            return CGPoint(x: size.width / 2 + (CGFloat(index) - 2) * (slotW + gap),
                           y: rackPanel.midY - slotW * 0.05)
        }

        var undoCenter: CGPoint {
            CGPoint(x: size.width * 0.88, y: size.height * 0.08)
        }
    }

    // MARK: Render

    private func render(_ context: GraphicsContext, size: CGSize, t: Double) {
        let geo = Geo(size: size)
        let script = script

        let flyStart = script.pickAt + Self.flyDelay
        let flyU = DemoEase.ramp(t, flyStart, flyStart + Self.flyTime)
        let landedSlot = script.rackStart.count

        // Undo reverses the same flight; between the two the pick lives in the rack.
        let undoU: Double
        if let undoAt = script.undoAt {
            let backStart = undoAt + Self.flyDelay
            undoU = DemoEase.ramp(t, backStart, backStart + Self.flyTime)
        } else {
            undoU = 0
        }

        // How full the rack reads right now (drives the warning border).
        let rackCount = script.rackStart.count + (flyU >= 1 && undoU < 1 ? 1 : 0)
        let warning = rackCount >= 4

        // Match pop: both twins swell with a gold glow, then fade away.
        let pop = script.popAt.map { at in
            DemoEase.ramp(t, at, at + 0.22)
        } ?? 0
        let gone = script.popAt.map { at in
            DemoEase.ramp(t, at + 0.55, at + 0.9)
        } ?? 0

        drawRack(context, geo: geo, script: script, t: t,
                 landedSlot: landedSlot, flyU: flyU, undoU: undoU,
                 warning: warning, pop: pop, gone: gone)
        drawBoard(context, geo: geo, script: script, t: t, flyU: flyU, undoU: undoU)

        if script.undoAt != nil {
            drawUndoButton(context, geo: geo, script: script, t: t,
                           armed: flyU >= 1 && undoU <= 0)
        }

        drawPickedTile(context, geo: geo, script: script,
                       flyU: flyU, undoU: undoU, landedSlot: landedSlot,
                       pop: pop, gone: gone, t: t)

        if let popAt = script.popAt {
            drawMatchBurst(context, geo: geo, slots: [0, 1].map(geo.slotCenter),
                           at: popAt, t: t)
        }

        drawFeedback(context, geo: geo, script: script, t: t)
        drawHand(context, geo: geo, script: script, t: t)
    }

    // MARK: Board + rack

    private func drawBoard(_ context: GraphicsContext, geo: Geo, script: Script,
                           t: Double, flyU: Double, undoU: Double) {
        // Bottom layer first; the two tiles under the top tile fall into shade.
        for (index, face) in script.bottom.enumerated() {
            let covered = index == 1 || index == 2
            var center = geo.bottomCenter(index)

            if index == script.pickIndex {
                // Skip while the tile is flying, racked, or popped away.
                if flyU >= 1 && undoU < 1 { continue }
                if flyU > 0 && undoU <= 0 { continue }
                if undoU > 0 && undoU < 1 { continue }
                if script.popAt != nil && flyU > 0 { continue }
            }

            // Refused tap: the covered tile shakes its head.
            if let blockedAt = script.blockedAt, index == 1 {
                let u = DemoEase.ramp(t, blockedAt, blockedAt + 0.38)
                if u > 0, u < 1 {
                    center.x += sin(u * .pi * 5) * geo.tileW * 0.07 * (1 - u)
                }
            }

            drawTile(context, face: face, center: center,
                     width: geo.tileW, height: geo.tileH, depth: geo.depth,
                     dimmed: covered)
        }
        drawTile(context, face: script.top, center: geo.topCenter,
                 width: geo.tileW, height: geo.tileH, depth: geo.depth,
                 dimmed: false)
    }

    private func drawRack(_ context: GraphicsContext, geo: Geo, script: Script,
                          t: Double, landedSlot: Int, flyU: Double, undoU: Double,
                          warning: Bool, pop: Double, gone: Double) {
        let panel = Path(roundedRect: geo.rackPanel, cornerRadius: geo.size.width * 0.035,
                         style: .continuous)
        context.fill(panel, with: .color(Self.rackWood.opacity(0.9)))
        if warning {
            // Same red breathing border the real rack shows one slot from full.
            let pulse = 0.55 + 0.45 * sin(t * 5)
            context.stroke(panel, with: .color(Self.danger.opacity(0.8 * pulse)), lineWidth: 2)
        } else {
            context.stroke(panel, with: .color(world.accent.opacity(0.25)), lineWidth: 1)
        }

        for slot in 0..<5 {
            let center = geo.slotCenter(slot)
            let rect = CGRect(x: center.x - geo.slotW / 2, y: center.y - geo.slotH / 2,
                              width: geo.slotW, height: geo.slotH)
            let path = Path(roundedRect: rect, cornerRadius: geo.slotW * 0.14, style: .continuous)
            context.fill(path, with: .color(.black.opacity(0.30)))
            context.stroke(path, with: .color(.white.opacity(0.10)), lineWidth: 1)

            guard slot < script.rackStart.count else { continue }
            // A pre-racked twin joins the pop-and-vanish on the match page.
            let partner = script.popAt != nil && slot == 0
            let scale = partner ? 1 + 0.18 * pop - (1 + 0.18 * pop - 0.5) * gone : 1
            let alpha = partner ? 1 - gone : 1
            if alpha > 0.01 {
                drawTile(context, face: script.rackStart[slot], center: center,
                         width: geo.slotW, height: geo.slotH, depth: geo.slotW * 0.10,
                         dimmed: false, scale: scale, alpha: alpha,
                         glow: partner ? pop * (1 - gone) : 0)
            }
        }
    }

    /// The lifted tile, from board tap through flight, rack rest, and either
    /// the match pop or the undo flight home.
    private func drawPickedTile(_ context: GraphicsContext, geo: Geo, script: Script,
                                flyU: Double, undoU: Double, landedSlot: Int,
                                pop: Double, gone: Double, t: Double) {
        guard flyU > 0, gone < 1 else { return }
        let boardPos = geo.bottomCenter(script.pickIndex)
        let slotPos = geo.slotCenter(landedSlot)

        var center = DemoEase.lerp(boardPos, slotPos, flyU)
        var width = DemoEase.lerp(geo.tileW, geo.slotW, flyU)
        if undoU > 0 {
            center = DemoEase.lerp(slotPos, boardPos, undoU)
            width = DemoEase.lerp(geo.slotW, geo.tileW, undoU)
        }
        let height = width * 1.24
        let scale = 1 + 0.18 * pop - (1 + 0.18 * pop - 0.5) * gone
        drawTile(context, face: script.bottom[script.pickIndex], center: center,
                 width: width, height: height, depth: width * 0.10,
                 dimmed: false, scale: scale, alpha: 1 - gone,
                 glow: pop * (1 - gone))
    }

    // MARK: Chrome + feedback

    private func drawUndoButton(_ context: GraphicsContext, geo: Geo, script: Script,
                                t: Double, armed: Bool) {
        let r = geo.size.width * 0.055
        var center = geo.undoCenter
        let pressed = script.undoAt.map { t >= $0 && t < $0 + 0.18 } ?? false
        let side = r * 2 * (pressed ? 0.88 : 1)
        let rect = CGRect(x: center.x - side / 2, y: center.y - side / 2,
                          width: side, height: side)
        context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.18)))
        var glyph = context.resolve(Image(systemName: "arrow.uturn.backward"))
        glyph.shading = .color(.white.opacity(armed || pressed ? 1 : 0.35))
        center.y += 0 // fingertip lands dead-center
        context.draw(glyph, in: rect.insetBy(dx: side * 0.28, dy: side * 0.28))
    }

    private func drawMatchBurst(_ context: GraphicsContext, geo: Geo,
                                slots: [CGPoint], at: Double, t: Double) {
        let u = DemoEase.ramp(t, at, at + 0.55)
        guard u > 0, u < 1 else { return }
        for center in slots {
            let r = geo.slotW * (0.5 + 0.9 * CGFloat(u))
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            context.stroke(Path(ellipseIn: rect),
                           with: .color(world.accent.opacity(0.9 * (1 - u))),
                           lineWidth: 3)
        }
        // Rising "pair" cheer between the two vanishing twins.
        let mid = CGPoint(x: (slots[0].x + slots[1].x) / 2,
                          y: min(slots[0].y, slots[1].y) - geo.slotH * (0.6 + 0.5 * CGFloat(u)))
        context.draw(Text("pair!")
                        .font(.system(size: geo.slotW * 0.42, weight: .black, design: .rounded))
                        .foregroundColor(world.accent.opacity(1 - u * u)),
                     at: mid)
    }

    private func drawFeedback(_ context: GraphicsContext, geo: Geo, script: Script, t: Double) {
        guard let blockedAt = script.blockedAt else { return }
        // Brief red "blocked" chip over the covered tile, echoing the game's hint.
        let alpha = DemoEase.ramp(t, blockedAt + 0.05, blockedAt + 0.3)
            * (1 - DemoEase.ramp(t, blockedAt + 1.0, blockedAt + 1.4))
        guard alpha > 0.01 else { return }
        let tile = geo.bottomCenter(1)
        let center = CGPoint(x: tile.x, y: tile.y - geo.tileH * 0.95)
        let chipW = geo.tileW * 1.5
        let chipH = geo.tileH * 0.34
        let rect = CGRect(x: center.x - chipW / 2, y: center.y - chipH / 2,
                          width: chipW, height: chipH)
        context.fill(Path(roundedRect: rect, cornerRadius: chipH / 2),
                     with: .color(Self.danger.opacity(0.9 * alpha)))
        context.draw(Text("blocked")
                        .font(.system(size: chipH * 0.55, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(alpha)),
                     at: center)
    }

    private func drawHand(_ context: GraphicsContext, geo: Geo, script: Script, t: Double) {
        var taps: [DemoEase.Tap] = []
        if let blockedAt = script.blockedAt {
            // Aim below the top tile so the press clearly lands on the shaded tile.
            var p = geo.bottomCenter(1)
            p.y += geo.tileH * 0.24
            taps.append(DemoEase.Tap(time: blockedAt, point: p))
        }
        taps.append(DemoEase.Tap(time: script.pickAt, point: geo.bottomCenter(script.pickIndex)))
        if let undoAt = script.undoAt {
            taps.append(DemoEase.Tap(time: undoAt, point: geo.undoCenter))
        }

        for (index, tap) in taps.enumerated() {
            let blocked = script.blockedAt != nil && index == 0
            DemoEase.drawTapRipple(context, at: tap.point, start: tap.time, t: t,
                                   radius: geo.tileW * 0.6,
                                   color: blocked ? Self.danger : world.accent)
        }

        let hand = DemoEase.handAlongTaps(taps, t: t)
        DemoEase.drawHand(context,
                          tip: CGPoint(x: hand.tip.x + geo.tileW * 0.08,
                                       y: hand.tip.y + geo.tileH * 0.12),
                          size: geo.tileW * 0.95, pressed: hand.pressed, alpha: hand.alpha)
    }

    // MARK: Tile

    private func drawTile(_ context: GraphicsContext, face: Face, center: CGPoint,
                          width: CGFloat, height: CGFloat, depth: CGFloat,
                          dimmed: Bool, scale: CGFloat = 1, alpha: Double = 1,
                          glow: Double = 0) {
        context.drawLayer { layer in
            layer.opacity = alpha
            layer.translateBy(x: center.x, y: center.y)
            layer.scaleBy(x: scale, y: scale)
            layer.translateBy(x: -center.x, y: -center.y)
            if glow > 0 {
                layer.addFilter(.shadow(color: world.accent.opacity(0.85 * glow),
                                        radius: width * 0.22))
            } else {
                layer.addFilter(.shadow(color: .black.opacity(0.28), radius: 3, y: 2))
            }

            let rect = CGRect(x: center.x - width / 2, y: center.y - height / 2,
                              width: width, height: height)
            let radius = width * 0.14
            let shape = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
            let side = Path(roundedRect: rect.offsetBy(dx: depth * 0.45, dy: depth),
                            cornerRadius: radius, style: .continuous)

            layer.fill(side, with: .color(dimmed ? Self.jadeDim : Self.jade))
            layer.fill(shape, with: .linearGradient(
                Gradient(colors: [Self.ivoryTop, Self.ivoryBottom]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
            drawFace(layer, face: face, rect: rect)
            if dimmed {
                layer.fill(shape, with: .color(.black.opacity(0.30)))
            }
            layer.stroke(shape, with: .color(.black.opacity(0.16)), lineWidth: 1)
        }
    }

    /// Simplified renditions of MahjongFaceView's drawn suits: dot pips on the
    /// 3x3 grid, bamboo capsules, and the stacked character glyphs.
    private func drawFace(_ context: GraphicsContext, face: Face, rect: CGRect) {
        let s = rect.width * 0.72
        let cell = s / 3
        let grid = { (col: CGFloat, row: CGFloat) -> CGPoint in
            CGPoint(x: rect.midX + (col - 1) * cell, y: rect.midY + (row - 1) * cell)
        }
        let pipColors = [Self.inkBlue, Self.inkRed, Self.inkGreen]

        func dot(_ point: CGPoint, _ d: CGFloat, _ color: Color) {
            let r = CGRect(x: point.x - d / 2, y: point.y - d / 2, width: d, height: d)
            context.fill(Path(ellipseIn: r), with: .color(color))
            context.stroke(Path(ellipseIn: r), with: .color(.black.opacity(0.18)),
                           lineWidth: max(0.5, d * 0.06))
        }
        func stick(_ point: CGPoint, _ d: CGFloat, _ color: Color) {
            let r = CGRect(x: point.x - d * 0.19, y: point.y - d * 0.575,
                           width: d * 0.38, height: d * 1.15)
            context.fill(Path(roundedRect: r, cornerRadius: d * 0.19), with: .color(color))
        }
        func glyph(_ text: String, _ size: CGFloat, _ color: Color, _ at: CGPoint) {
            context.draw(Text(verbatim: text)
                            .font(.system(size: size, weight: .semibold))
                            .foregroundColor(color),
                         at: at)
        }

        let d = cell * 0.72
        switch face {
        case .dot1:
            dot(grid(1, 1), d, Self.inkBlue)
        case .dot2:
            dot(grid(1, 0), d, Self.inkBlue)
            dot(grid(1, 2), d, Self.inkRed)
        case .dot3:
            dot(grid(0, 0), d, Self.inkBlue)
            dot(grid(1, 1), d, Self.inkRed)
            dot(grid(2, 2), d, Self.inkGreen)
        case .bam2:
            stick(grid(1, 0), d, Self.inkRed)
            stick(grid(1, 2), d, Self.inkGreen)
        case .char:
            glyph("三", s * 0.46, Self.inkBlue, CGPoint(x: rect.midX, y: rect.midY - s * 0.24))
            glyph("萬", s * 0.46, Self.inkRed, CGPoint(x: rect.midX, y: rect.midY + s * 0.24))
        case .wind:
            glyph("東", s * 0.72, Self.inkBlue, CGPoint(x: rect.midX, y: rect.midY))
        }
    }
}
