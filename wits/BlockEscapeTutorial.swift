//
//  BlockEscapeTutorial.swift
//  wits
//
//  Animated how-to-play demos for Block Escape on a mini 4×4 tray: a hand
//  drags a block sideways into a neighbour (blocked, so it shudders), slides
//  it along its free axis, clears the corridor under the big red block, and
//  walks the hero out the bottom exit. Rendering mirrors the real tray —
//  same warm surface, tan blocks, red hero with its down arrow, and the
//  accent exit notch — so nothing needs relearning in play.
//

import SwiftUI

enum BlockEscapeTutorial {
    static let slides: [TutorialSlide] = [
        TutorialSlide(caption: "drag blocks along their row or column — they can't jump or turn") {
            BlockEscapeDemo(page: .dragAxis)
        },
        TutorialSlide(caption: "slide blocks aside to clear a path for the big red block") {
            BlockEscapeDemo(page: .clearPath)
        },
        TutorialSlide(caption: "walk the red block out the bottom exit in as few moves as you can") {
            BlockEscapeDemo(page: .escape)
        },
    ]
}

// MARK: - Demo scenes

private struct BlockEscapeDemo: View {
    enum Page { case dragAxis, clearPath, escape }
    let page: Page

    // All pages share one 4×4 easy-band tray so the layout reads as a story:
    // free a lane, open the corridor, walk the hero out.
    private static let side = 4
    private static let exitX = 1
    private var world: GameWorld { GameID.blockEscape.world }

    var body: some View {
        DemoLoop(duration: scene.duration) { t in
            Canvas { context, size in
                render(context, size: size, t: t)
            }
        }
    }

    // MARK: Scene data

    private struct Block {
        var x: Int, y: Int, w: Int, h: Int
        var hero = false
    }

    private struct Drag {
        let block: Int
        let dx: Int, dy: Int
        let start: Double
        let duration: Double
        var end: Double { start + duration }
    }

    private struct Scene {
        var duration: Double
        var blocks: [Block]           // hero (if any mover) is index 0
        var drags: [Drag]
        var nudge: (block: Int, start: Double)? = nil   // blocked sideways try
        var blocker: Int? = nil       // flashes while the nudge fails
        var pathGlowAt: Double? = nil // corridor highlight once it's clear
        var escapeAt: Double? = nil   // hero slides out and fades, real-game style
        var handIn: (Double, Double)
        var handOut: (Double, Double)
    }

    private var scene: Scene {
        switch page {
        case .dragAxis:
            // Nudge the flat block into the single on its right (no jump),
            // then slide it left along its row and the single up its column.
            return Scene(
                duration: 5.6,
                blocks: [Block(x: 1, y: 0, w: 2, h: 2, hero: true),
                         Block(x: 1, y: 2, w: 2, h: 1),
                         Block(x: 3, y: 2, w: 1, h: 1),
                         Block(x: 0, y: 3, w: 1, h: 1)],
                drags: [Drag(block: 1, dx: -1, dy: 0, start: 2.0, duration: 0.7),
                        Drag(block: 2, dx: 0, dy: -1, start: 3.5, duration: 0.6)],
                nudge: (block: 1, start: 1.0),
                blocker: 2,
                handIn: (0.15, 0.55),
                handOut: (4.3, 4.8))
        case .clearPath:
            // Two singles sit in the hero's corridor; sweep them to the walls
            // and the cleared lane lights up down to the exit.
            return Scene(
                duration: 5.8,
                blocks: [Block(x: 1, y: 0, w: 2, h: 2, hero: true),
                         Block(x: 1, y: 2, w: 1, h: 1),
                         Block(x: 2, y: 3, w: 1, h: 1),
                         Block(x: 3, y: 0, w: 1, h: 2),
                         Block(x: 0, y: 0, w: 1, h: 1)],
                drags: [Drag(block: 1, dx: -1, dy: 0, start: 1.0, duration: 0.7),
                        Drag(block: 2, dx: 1, dy: 0, start: 2.6, duration: 0.7)],
                pathGlowAt: 3.5,
                handIn: (0.15, 0.55),
                handOut: (3.5, 4.0))
        case .escape:
            // Same tray after the clear: drag the hero down the open corridor
            // and it keeps going out through the notch.
            return Scene(
                duration: 6.0,
                blocks: [Block(x: 1, y: 0, w: 2, h: 2, hero: true),
                         Block(x: 0, y: 2, w: 1, h: 1),
                         Block(x: 3, y: 3, w: 1, h: 1),
                         Block(x: 3, y: 0, w: 1, h: 2),
                         Block(x: 0, y: 0, w: 1, h: 1)],
                drags: [Drag(block: 0, dx: 0, dy: 2, start: 1.0, duration: 1.1)],
                escapeAt: 2.4,
                handIn: (0.2, 0.6),
                handOut: (2.2, 2.7))
        }
    }

    // MARK: Geometry

    private struct Geo {
        let tray: CGRect
        let inset: CGFloat
        let cell: CGFloat

        init(size: CGSize) {
            let side = min(size.width * 0.88, size.height * 0.84)
            inset = side * 0.045
            cell = (side - inset * 2) / 4
            // Nudged up a touch so the exit chevron fits under the tray.
            tray = CGRect(x: (size.width - side) / 2,
                          y: (size.height - side) / 2 - cell * 0.14,
                          width: side, height: side)
        }

        /// Top-left of a cell-unit coordinate (fractional mid-slide positions).
        func origin(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: tray.minX + inset + x * cell,
                    y: tray.minY + inset + y * cell)
        }

        var exitCenterX: CGFloat {
            tray.minX + inset + CGFloat(BlockEscapeDemo.exitX + 1) * cell
        }
    }

    // MARK: Block positions

    /// Cell-unit origin of block i at time t: base spot plus eased drags plus
    /// the blocked-nudge shudder.
    private func cellOrigin(_ i: Int, scene: Scene, t: Double) -> CGPoint {
        var x = CGFloat(scene.blocks[i].x)
        var y = CGFloat(scene.blocks[i].y)
        for drag in scene.drags where drag.block == i {
            let u = DemoEase.ramp(t, drag.start, drag.end)
            x += CGFloat(drag.dx) * u
            y += CGFloat(drag.dy) * u
        }
        if let nudge = scene.nudge, nudge.block == i {
            x += nudgeOffset(t, start: nudge.start)
        }
        return CGPoint(x: x, y: y)
    }

    /// Two short right-bumps that spring straight back: the drag is clamped
    /// by the neighbour, exactly how a blocked pull feels in game.
    private func nudgeOffset(_ t: Double, start: Double) -> CGFloat {
        func bump(_ s: Double) -> Double {
            DemoEase.ramp(t, s, s + 0.16) * (1 - DemoEase.ramp(t, s + 0.18, s + 0.42))
        }
        return CGFloat(bump(start) + bump(start + 0.55)) * 0.20
    }

    /// SF symbol drawn as a resolved image (symbols inside Text don't render
    /// in Canvas), sized by height with the symbol's own aspect.
    private func drawGlyph(_ ctx: GraphicsContext, _ systemName: String,
                           at center: CGPoint, height: CGFloat, color: Color) {
        var glyph = ctx.resolve(Image(systemName: systemName))
        glyph.shading = .color(color)
        let width = height * glyph.size.width / max(glyph.size.height, 1)
        ctx.draw(glyph, in: CGRect(x: center.x - width / 2, y: center.y - height / 2,
                                   width: width, height: height))
    }

    private func blockRect(_ i: Int, scene: Scene, geo: Geo, t: Double) -> CGRect {
        let block = scene.blocks[i]
        let origin = cellOrigin(i, scene: scene, t: t)
        let point = geo.origin(origin.x, origin.y)
        return CGRect(x: point.x, y: point.y,
                      width: geo.cell * CGFloat(block.w),
                      height: geo.cell * CGFloat(block.h))
    }

    // MARK: Render

    private func render(_ context: GraphicsContext, size: CGSize, t: Double) {
        let geo = Geo(size: size)
        let scene = scene

        drawTray(context, geo: geo, t: t)
        if let glowAt = scene.pathGlowAt {
            drawPathGlow(context, geo: geo, t: t, start: glowAt)
        }
        drawBlocks(context, geo: geo, scene: scene, t: t)
        if let escapeAt = scene.escapeAt {
            drawEscapeGlow(context, geo: geo, t: t, start: escapeAt)
            drawEscapedBadge(context, geo: geo, t: t, start: escapeAt + 0.8)
        }
        drawHand(context, geo: geo, scene: scene, t: t)
    }

    private func drawTray(_ ctx: GraphicsContext, geo: Geo, t: Double) {
        ctx.fill(Path(roundedRect: geo.tray, cornerRadius: max(6, geo.cell * 0.10),
                      style: .continuous),
                 with: .color(world.surface.opacity(0.88)))

        // Exit notch + chevron under the hero's target columns, as in game.
        let notch = CGRect(x: geo.tray.minX + geo.inset + CGFloat(Self.exitX) * geo.cell + geo.cell * 0.07,
                           y: geo.tray.maxY - geo.cell * 0.07,
                           width: geo.cell * 2 - geo.cell * 0.14,
                           height: geo.cell * 0.10)
        ctx.fill(Path(roundedRect: notch, cornerRadius: notch.height * 0.5, style: .continuous),
                 with: .color(world.accent))
        drawGlyph(ctx, "chevron.down", at: CGPoint(x: geo.exitCenterX, y: geo.tray.maxY + geo.cell * 0.30),
                  height: geo.cell * 0.24, color: world.accent)
    }

    /// Soft accent corridor over the freed lane, so "path" is literal.
    private func drawPathGlow(_ ctx: GraphicsContext, geo: Geo, t: Double, start: Double) {
        let u = DemoEase.ramp(t, start, start + 0.5)
        guard u > 0 else { return }
        let pulse = 0.75 + 0.25 * sin((t - start) * 4)
        let origin = geo.origin(CGFloat(Self.exitX), 2)
        let lane = CGRect(x: origin.x + geo.cell * 0.06, y: origin.y + geo.cell * 0.06,
                          width: geo.cell * 2 - geo.cell * 0.12,
                          height: geo.cell * 2 + geo.inset - geo.cell * 0.06)
        let path = Path(roundedRect: lane, cornerRadius: geo.cell * 0.14, style: .continuous)
        ctx.fill(path, with: .color(world.accent.opacity(0.20 * u * pulse)))
        ctx.stroke(path, with: .color(world.accent.opacity(0.65 * u * pulse)), lineWidth: 2)
        drawGlyph(ctx, "arrow.down", at: CGPoint(x: geo.exitCenterX, y: lane.midY),
                  height: geo.cell * 0.50, color: world.accent.opacity(0.85 * u * pulse))
    }

    private func drawBlocks(_ ctx: GraphicsContext, geo: Geo, scene: Scene, t: Double) {
        // Hero last so it rides over the notch on its way out.
        let order = scene.blocks.indices.sorted { !scene.blocks[$0].hero && scene.blocks[$1].hero }
        for i in order {
            let block = scene.blocks[i]
            var rect = blockRect(i, scene: scene, geo: geo, t: t)
            var alpha = 1.0
            if block.hero, let escapeAt = scene.escapeAt {
                let escU = DemoEase.ramp(t, escapeAt, escapeAt + 0.55)
                rect.origin.y += geo.cell * 2.4 * CGFloat(escU)
                alpha = 1 - escU
            }
            guard alpha > 0.01 else { continue }

            let gap = max(2, geo.cell * 0.05)
            let body = rect.insetBy(dx: gap, dy: gap)
            let radius = max(5, geo.cell * 0.10)
            let path = Path(roundedRect: body, cornerRadius: radius, style: .continuous)

            ctx.drawLayer { layer in
                layer.opacity = alpha
                layer.addFilter(.shadow(color: .black.opacity(0.18), radius: 4, y: 2))
                layer.fill(path, with: .color(block.hero ? world.accent : world.secondary))
                layer.stroke(path, with: .color(.black.opacity(0.12)), lineWidth: 1.5)
                if block.hero {
                    drawGlyph(layer, "arrow.down", at: CGPoint(x: body.midX, y: body.midY),
                              height: geo.cell * 0.42, color: world.background.opacity(0.88))
                }
            }

            // The neighbour that stops the nudge flashes while the pull fails.
            if i == scene.blocker, let nudge = scene.nudge {
                let flash = DemoEase.ramp(t, nudge.start - 0.05, nudge.start + 0.15)
                    * (1 - DemoEase.ramp(t, nudge.start + 0.85, nudge.start + 1.15))
                if flash > 0.01 {
                    ctx.stroke(path, with: .color(world.ink.opacity(0.85 * flash)), lineWidth: 2.5)
                }
            }
        }
    }

    /// Warm burst at the notch as the hero leaves.
    private func drawEscapeGlow(_ ctx: GraphicsContext, geo: Geo, t: Double, start: Double) {
        let u = DemoEase.ramp(t, start, start + 0.30)
        let fade = 1 - DemoEase.ramp(t, start + 0.75, start + 1.35)
        let alpha = u * fade
        guard alpha > 0.01 else { return }
        let center = CGPoint(x: geo.exitCenterX, y: geo.tray.maxY)
        for (radius, opacity) in [(geo.cell * 1.35, 0.16), (geo.cell * 0.85, 0.30), (geo.cell * 0.42, 0.55)] {
            let r = radius * CGFloat(0.6 + 0.4 * u)
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r,
                                            width: r * 2, height: r * 2)),
                     with: .color(world.accent.opacity(opacity * alpha)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - geo.cell * 0.20, y: center.y - geo.cell * 0.20,
                                        width: geo.cell * 0.40, height: geo.cell * 0.40)),
                 with: .color(.white.opacity(0.65 * alpha)))
    }

    private func drawEscapedBadge(_ ctx: GraphicsContext, geo: Geo, t: Double, start: Double) {
        let u = DemoEase.ramp(t, start, start + 0.4)
        guard u > 0 else { return }
        let badge = CGRect(x: geo.tray.midX - geo.cell * 1.6,
                           y: geo.tray.midY - geo.cell * 0.44,
                           width: geo.cell * 3.2, height: geo.cell * 0.88)
        ctx.drawLayer { layer in
            layer.opacity = u
            layer.addFilter(.shadow(color: .black.opacity(0.45), radius: 8, y: 5))
            layer.fill(Path(roundedRect: badge, cornerRadius: badge.height / 2, style: .continuous),
                       with: .color(world.background.opacity(0.95)))
            layer.stroke(Path(roundedRect: badge, cornerRadius: badge.height / 2, style: .continuous),
                         with: .color(world.accent.opacity(0.9)), lineWidth: 2)
            layer.draw(Text("ESCAPED")
                        .font(.system(size: geo.cell * 0.34, weight: .black, design: world.titleDesign))
                        .foregroundColor(world.ink),
                       at: CGPoint(x: badge.midX, y: badge.midY))
        }
    }

    // MARK: Hand

    private func drawHand(_ ctx: GraphicsContext, geo: Geo, scene: Scene, t: Double) {
        let alpha = DemoEase.ramp(t, scene.handIn.0, scene.handIn.1)
            * (1 - DemoEase.ramp(t, scene.handOut.0, scene.handOut.1))
        guard alpha > 0.01, let firstDrag = scene.drags.first else { return }

        // The tip rides the centre of whichever block it's working, gliding
        // between grips; nudge shudder comes along for free via cellOrigin.
        var tip = blockCenter(firstDrag.block, scene: scene, geo: geo, t: t)
        for k in scene.drags.indices.dropFirst() {
            let u = DemoEase.ramp(t, scene.drags[k - 1].end + 0.15, scene.drags[k].start - 0.10)
            tip = DemoEase.lerp(tip, blockCenter(scene.drags[k].block, scene: scene, geo: geo, t: t), u)
        }
        tip.x += geo.cell * 0.06
        tip.y += geo.cell * 0.12

        var pressed = scene.drags.contains { t >= $0.start - 0.25 && t < $0.end + 0.05 }
        if let nudge = scene.nudge, t >= nudge.start - 0.2, t < nudge.start + 1.0 {
            pressed = true
        }
        DemoEase.drawHand(ctx, tip: tip, size: geo.cell * 1.25, pressed: pressed, alpha: alpha)
    }

    private func blockCenter(_ i: Int, scene: Scene, geo: Geo, t: Double) -> CGPoint {
        let rect = blockRect(i, scene: scene, geo: geo, t: t)
        return CGPoint(x: rect.midX, y: rect.midY)
    }
}
