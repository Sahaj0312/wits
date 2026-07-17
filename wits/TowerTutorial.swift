//
//  TowerTutorial.swift
//  wits
//
//  Animated how-to-play demos for Tower on a mini isometric stack: a block
//  glides across the tower top, a tap drops it and slices off the overhang, a
//  dead-center drop keeps it whole, and a clean miss ends the run. Boxes are
//  painted with the real game's TowerShades faces over a starry stratosphere
//  so the tutorial tower reads exactly like the one in play.
//

import SwiftUI

enum TowerTutorial {
    static let slides: [TutorialSlide] = [
        TutorialSlide(caption: "tap anywhere to drop the sliding block. the overhang past the edge is sliced off") {
            TowerDemo(page: .slice)
        },
        TutorialSlide(caption: "land dead-center to keep the block whole and grow a perfect streak") {
            TowerDemo(page: .perfect)
        },
        TutorialSlide(caption: "every slice shrinks the block. miss the stack completely and the run ends") {
            TowerDemo(page: .miss)
        },
    ]
}

// MARK: - Demo scenes

private struct TowerDemo: View {
    enum Page { case slice, perfect, miss }
    let page: Page

    /// Matches TowerEngine.layerHeight so slab proportions read like the game.
    private static let layerH = 0.28
    /// Fixed start of the hue walk, the stratosphere's block pink.
    private static let baseHue = 0.945

    private var world: GameWorld { GameID.tower.world }

    var body: some View {
        DemoLoop(duration: script.duration) { t in
            Canvas { context, size in
                render(context, size: size, t: t)
            }
        }
    }

    // MARK: Script

    /// The block's plan-position is piecewise-linear through `sweep` (constant
    /// slide speed like the engine); the last key is the tap moment, so the
    /// drop lands wherever the sweep ends.
    private struct Script {
        let duration: Double
        let sweep: [(time: Double, pos: Double)]
        let tap: Double
        let handPoint: CGPoint    // unit coords, scaled to the canvas
    }

    private var script: Script {
        switch page {
        case .slice:
            // Two passes, then a drop hanging off the left edge.
            return Script(duration: 5.0,
                          sweep: [(0.0, -1.0), (1.15, 0.98), (2.05, -0.32)],
                          tap: 2.05,
                          handPoint: CGPoint(x: 0.78, y: 0.74))
        case .perfect:
            return Script(duration: 4.8,
                          sweep: [(0.0, -1.0), (1.15, 0.98), (2.1, 0.0)],
                          tap: 2.1,
                          handPoint: CGPoint(x: 0.78, y: 0.74))
        case .miss:
            // One slow pass that carries the block clean past the stack; the
            // hand sits on the far side so the falling block stays visible.
            return Script(duration: 5.4,
                          sweep: [(0.0, -1.0), (1.9, 1.02)],
                          tap: 1.9,
                          handPoint: CGPoint(x: 0.22, y: 0.74))
        }
    }

    // MARK: Stack

    /// A run already underway: base slab plus three slightly sliced layers.
    private struct Slab {
        var cx: Double, cz: Double, w: Double, d: Double
        var hue: Int
    }

    private static let stack: [Slab] = [
        Slab(cx: 0, cz: 0, w: 1, d: 1, hue: 0),
        Slab(cx: 0.02, cz: 0, w: 0.96, d: 1.0, hue: 1),
        Slab(cx: 0.02, cz: -0.03, w: 0.96, d: 0.94, hue: 2),
        Slab(cx: 0, cz: -0.03, w: 0.90, d: 0.94, hue: 3),
    ]
    private static var top: Slab { stack[stack.count - 1] }
    private static var topY: Double { Double(stack.count - 1) * layerH }

    // MARK: Render

    private func render(_ context: GraphicsContext, size: CGSize, t: Double) {
        let script = script
        let scale = Double(min(size.width, size.height)) * 0.26
        let midX = Double(size.width) / 2
        let anchorY = Double(size.height) * 0.56
        let focusY = Self.topY
        let h = Self.layerH

        // Same projection the game painter uses, camera pinned to the top.
        func project(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
            CGPoint(x: midX + (x - z) * 0.866 * scale,
                    y: anchorY - (y - focusY) * scale + (x + z) * 0.5 * scale)
        }

        func fillQuad(_ points: [CGPoint], _ color: Color, opacity: Double = 1) {
            var path = Path()
            path.move(to: points[0])
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
            context.fill(path, with: .color(color.opacity(opacity)))
        }

        /// One box: top face plus the two viewer-facing sides.
        func drawBox(cx bx: Double, cz bz: Double, w: Double, d: Double,
                     yBottom: Double, yTop: Double, hue: Int, opacity: Double = 1) {
            let x0 = bx - w / 2, x1 = bx + w / 2
            let z0 = bz - d / 2, z1 = bz + d / 2
            fillQuad([project(x0, yTop, z0), project(x1, yTop, z0),
                      project(x1, yTop, z1), project(x0, yTop, z1)],
                     TowerShades.top(Self.baseHue, hue), opacity: opacity)
            fillQuad([project(x1, yTop, z0), project(x1, yTop, z1),
                      project(x1, yBottom, z1), project(x1, yBottom, z0)],
                     TowerShades.right(Self.baseHue, hue), opacity: opacity)
            fillQuad([project(x0, yTop, z1), project(x1, yTop, z1),
                      project(x1, yBottom, z1), project(x0, yBottom, z1)],
                     TowerShades.left(Self.baseHue, hue), opacity: opacity)
        }

        func topFaceQuad(cx bx: Double, cz bz: Double, w: Double, d: Double,
                         y: Double) -> [CGPoint] {
            [project(bx - w / 2, y, bz - d / 2), project(bx + w / 2, y, bz - d / 2),
             project(bx + w / 2, y, bz + d / 2), project(bx - w / 2, y, bz + d / 2)]
        }

        drawStars(context, size: size)

        // Pedestal extrudes the base past the bottom edge, then the placed
        // slabs stack bottom to top.
        drawBox(cx: Self.stack[0].cx, cz: Self.stack[0].cz,
                w: Self.stack[0].w, d: Self.stack[0].d,
                yBottom: -2.6, yTop: 0, hue: 0)
        for index in 1..<Self.stack.count {
            let slab = Self.stack[index]
            drawBox(cx: slab.cx, cz: slab.cz, w: slab.w, d: slab.d,
                    yBottom: Double(index - 1) * h, yTop: Double(index) * h,
                    hue: slab.hue)
        }

        let top = Self.top
        let dropPos = script.sweep[script.sweep.count - 1].pos
        let dropped = t >= script.tap
        let age = t - script.tap

        // Overlap of the drop against the top slab, on the slide axis.
        let lo = max(dropPos - top.w / 2, top.cx - top.w / 2)
        let hi = min(dropPos + top.w / 2, top.cx + top.w / 2)
        let overlap = hi - lo
        let keptCx = (lo + hi) / 2

        if dropped {
            switch page {
            case .perfect:
                drawBox(cx: top.cx, cz: top.cz, w: top.w, d: top.d,
                        yBottom: Self.topY, yTop: Self.topY + h, hue: 4)
            case .slice:
                // The overlap becomes the new top; the overhang tumbles away.
                drawBox(cx: keptCx, cz: top.cz, w: overlap, d: top.d,
                        yBottom: Self.topY, yTop: Self.topY + h, hue: 4)
                let shedW = top.w - overlap
                let shedCx = dropPos < top.cx ? lo - shedW / 2 : hi + shedW / 2
                drawFallingCut(drawBox, cx: shedCx, cz: top.cz, w: shedW, d: top.d,
                               age: age, vx: -0.30)
                // The next block spawns at the kept size and slides the other
                // axis, the loop goes on.
                if age > 0.9 {
                    drawBox(cx: keptCx, cz: -1.05 + 0.7 * (age - 0.9),
                            w: overlap, d: top.d,
                            yBottom: Self.topY + h, yTop: Self.topY + 2 * h, hue: 5)
                }
            case .miss:
                // No overlap at all: the whole block falls and the run is over.
                drawFallingCut(drawBox, cx: dropPos, cz: top.cz, w: top.w, d: top.d,
                               age: age, vx: 0.30)
            }
        } else {
            drawBox(cx: sweepPos(t, script.sweep), cz: top.cz, w: top.w, d: top.d,
                    yBottom: Self.topY, yTop: Self.topY + h, hue: 4)
        }

        if page == .perfect, dropped {
            // Glint, expanding rings, and a rising PERFECT, the game's juice.
            if age < 0.22 {
                fillQuad(topFaceQuad(cx: top.cx, cz: top.cz, w: top.w, d: top.d,
                                     y: Self.topY + h),
                         .white, opacity: 0.55 * (1 - age / 0.22))
            }
            for ring in 0..<3 {
                let ringAge = age - Double(ring) * 0.12
                guard ringAge > 0, ringAge < 0.62 else { continue }
                let progress = ringAge / 0.62
                let grow = 1 + progress * 0.95
                var path = Path()
                let quad = topFaceQuad(cx: top.cx, cz: top.cz,
                                       w: top.w * grow, d: top.d * grow,
                                       y: Self.topY + h)
                path.move(to: quad[0])
                for point in quad.dropFirst() { path.addLine(to: point) }
                path.closeSubpath()
                context.stroke(path, with: .color(.white.opacity((1 - progress) * 0.85)),
                               lineWidth: 2.5 * (1 - progress) + 0.5)
            }
            drawPerfectText(context, at: project(0, Self.topY + h + 0.45, 0),
                            scale: scale, t: t, tap: script.tap)
        }

        if page == .miss {
            drawGameOver(context, size: size, scale: scale, t: t, tap: script.tap)
        }

        // The tap is a screen tap, not a tap on the tower: the hand presses
        // off to the side with a ripple at the fingertip.
        let handPoint = CGPoint(x: script.handPoint.x * size.width,
                                y: script.handPoint.y * size.height)
        DemoEase.drawTapRipple(context, at: handPoint, start: script.tap, t: t,
                               radius: scale * 0.42, color: world.accent)
        let hand = DemoEase.handAlongTaps([DemoEase.Tap(time: script.tap, point: handPoint)], t: t)
        DemoEase.drawHand(context, tip: hand.tip, size: scale * 1.0,
                          pressed: hand.pressed, alpha: hand.alpha)
    }

    /// A sliced-off piece: keeps a little slide velocity, falls with gravity,
    /// fades out, same feel as the engine's cuts.
    private func drawFallingCut(_ drawBox: (Double, Double, Double, Double, Double, Double, Int, Double) -> Void,
                                cx: Double, cz: Double, w: Double, d: Double,
                                age: Double, vx: Double) {
        let opacity = max(0, 1 - age / 1.1)
        guard opacity > 0 else { return }
        let fall = 4.5 * age * age
        drawBox(cx + vx * age, cz, w, d,
                Self.topY - fall, Self.topY + Self.layerH - fall, 4, opacity)
    }

    private func drawPerfectText(_ context: GraphicsContext, at base: CGPoint,
                                 scale: Double, t: Double, tap: Double) {
        let riseU = DemoEase.ramp(t, tap + 0.1, tap + 1.2)
        guard riseU > 0, riseU < 1 else { return }
        let alpha = min(1, riseU * 4) * (1 - DemoEase.ramp(riseU, 0.6, 1))
        let center = CGPoint(x: base.x, y: base.y - scale * 0.5 * riseU)
        let text = Text("PERFECT")
            .font(.system(size: scale * 0.30, weight: .black, design: world.titleDesign))
            .foregroundColor(world.secondary)
        context.drawLayer { layer in
            layer.opacity = alpha
            layer.addFilter(.shadow(color: .black.opacity(0.5), radius: 3, y: 2))
            layer.draw(text, at: center)
        }
    }

    private func drawGameOver(_ context: GraphicsContext, size: CGSize,
                              scale: Double, t: Double, tap: Double) {
        let u = DemoEase.ramp(t, tap + 1.0, tap + 1.5)
        guard u > 0 else { return }
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(.black.opacity(0.38 * u)))

        let badge = CGRect(x: size.width / 2 - scale * 1.35,
                           y: size.height * 0.42 - scale * 0.35,
                           width: scale * 2.7, height: scale * 0.7)
        context.drawLayer { layer in
            layer.opacity = u
            layer.addFilter(.shadow(color: .black.opacity(0.45), radius: 8, y: 5))
            layer.fill(Path(roundedRect: badge, cornerRadius: badge.height / 2, style: .continuous),
                       with: .color(world.background.opacity(0.95)))
            layer.stroke(Path(roundedRect: badge, cornerRadius: badge.height / 2, style: .continuous),
                         with: .color(Color(hexAny: 0xFF5C7A).opacity(0.9)), lineWidth: 2)
            layer.draw(Text("GAME OVER")
                        .font(.system(size: scale * 0.26, weight: .black, design: world.titleDesign))
                        .foregroundColor(world.ink),
                       at: CGPoint(x: badge.midX, y: badge.midY))
        }
    }

    /// Twinkle-free star field, deterministic like the world backdrop's.
    private func drawStars(_ context: GraphicsContext, size: CGSize) {
        for index in 0..<14 {
            let radius: CGFloat = index.isMultiple(of: 5) ? 1.6 : 1.0
            let x = CGFloat((index * 97) % 360) / 360 * size.width
            let y = CGFloat((index * 173) % 760) / 760 * size.height
            context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                                width: radius * 2, height: radius * 2)),
                         with: .color(world.ink.opacity(index.isMultiple(of: 3) ? 0.18 : 0.10)))
        }
    }

    // MARK: Sweep

    /// Piecewise-linear position through the script's keyframes (the engine
    /// slides at constant speed, so no smoothstep here).
    private func sweepPos(_ t: Double, _ keys: [(time: Double, pos: Double)]) -> Double {
        var pos = keys[0].pos
        for index in 1..<keys.count {
            let span = keys[index].time - keys[index - 1].time
            let u = max(0, min(1, (t - keys[index - 1].time) / span))
            pos += (keys[index].pos - pos) * u
        }
        return pos
    }
}
