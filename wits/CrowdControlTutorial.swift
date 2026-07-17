//
//  CrowdControlTutorial.swift
//  wits
//
//  Animated how-to-play demos for Crowd Control on a mini six-dot board: two
//  dots glow and pulse, the glow drops and the whole crowd drifts while every
//  dot looks identical, then the freeze, the hand picks the tracked dots for
//  points, and a dropped target burns a heart. Board, dots, glow treatment,
//  and the reveal rings all mirror the real game's rendering.
//

import SwiftUI

enum CrowdControlTutorial {
    static let slides: [TutorialSlide] = [
        TutorialSlide(caption: "memorize the glowing dots, then track them while every dot moves") {
            CrowdControlDemo(page: .track)
        },
        TutorialSlide(caption: "when they freeze, tap the ones you were tracking. each catch is a point") {
            CrowdControlDemo(page: .pick)
        },
        TutorialSlide(caption: "every target you lose costs a heart. lose all three and the run ends") {
            CrowdControlDemo(page: .hearts)
        },
    ]
}

// MARK: - Demo scenes

private struct CrowdControlDemo: View {
    enum Page { case track, pick, hearts }
    let page: Page

    private var world: GameWorld { GameID.crowdControl.world }
    private static let heartColor = Color(hexAny: 0xEF476F)

    var body: some View {
        DemoLoop(duration: script.duration) { t in
            Canvas { context, size in
                render(context, size: size, t: t)
            }
        }
    }

    // MARK: Script

    /// One dot's whole run in normalized board coords: it eases start→end
    /// while a sine wobble (zeroed at both endpoints) bends the path, so the
    /// motion stays smooth and the freeze lands exactly on `end`.
    private struct DotPath {
        let start: CGPoint
        let end: CGPoint
        let amp: CGVector
        let freq: (Double, Double)
        let phase: (Double, Double)
        var isTarget = false
    }

    private struct Script {
        let duration: Double
        let dots: [DotPath]
        let markEnd: Double              // target glow finishes fading here
        let move: (Double, Double)
        var taps: [(time: Double, dot: Int)] = []
        var revealAt: Double? = nil      // hearts page: verdict + heart loss
        var recapAt: Double? = nil       // track page: targets re-light at the end
        var showHearts = false
    }

    private var script: Script {
        switch page {
        case .track:
            // Long mark so the pulse registers, then a full drift and a recap
            // glow proving the pair really can be followed.
            return Script(
                duration: 5.8,
                dots: [
                    DotPath(start: CGPoint(x: 0.20, y: 0.28), end: CGPoint(x: 0.63, y: 0.42),
                            amp: CGVector(dx: 0.08, dy: 0.09), freq: (1.3, 0.9), phase: (0.4, 2.1),
                            isTarget: true),
                    DotPath(start: CGPoint(x: 0.74, y: 0.60), end: CGPoint(x: 0.28, y: 0.56),
                            amp: CGVector(dx: 0.09, dy: 0.08), freq: (0.9, 1.4), phase: (3.5, 1.0),
                            isTarget: true),
                    DotPath(start: CGPoint(x: 0.50, y: 0.15), end: CGPoint(x: 0.18, y: 0.20),
                            amp: CGVector(dx: 0.06, dy: 0.09), freq: (1.1, 1.2), phase: (1.2, 4.4)),
                    DotPath(start: CGPoint(x: 0.26, y: 0.74), end: CGPoint(x: 0.72, y: 0.80),
                            amp: CGVector(dx: 0.08, dy: 0.06), freq: (1.4, 1.0), phase: (5.0, 0.6)),
                    DotPath(start: CGPoint(x: 0.82, y: 0.22), end: CGPoint(x: 0.80, y: 0.58),
                            amp: CGVector(dx: 0.09, dy: 0.07), freq: (1.0, 1.3), phase: (2.6, 3.8)),
                    DotPath(start: CGPoint(x: 0.52, y: 0.88), end: CGPoint(x: 0.48, y: 0.16),
                            amp: CGVector(dx: 0.07, dy: 0.07), freq: (1.2, 1.1), phase: (0.0, 2.9)),
                ],
                markEnd: 1.9,
                move: (2.0, 4.2),
                recapAt: 4.7)
        case .pick:
            // Quick mark + drift, then the hand catches both targets.
            return Script(
                duration: 5.6,
                dots: [
                    DotPath(start: CGPoint(x: 0.24, y: 0.22), end: CGPoint(x: 0.32, y: 0.64),
                            amp: CGVector(dx: 0.08, dy: 0.07), freq: (1.2, 0.9), phase: (0.8, 2.6),
                            isTarget: true),
                    DotPath(start: CGPoint(x: 0.72, y: 0.66), end: CGPoint(x: 0.66, y: 0.28),
                            amp: CGVector(dx: 0.08, dy: 0.08), freq: (0.9, 1.3), phase: (4.1, 1.4),
                            isTarget: true),
                    DotPath(start: CGPoint(x: 0.50, y: 0.14), end: CGPoint(x: 0.84, y: 0.54),
                            amp: CGVector(dx: 0.06, dy: 0.08), freq: (1.3, 1.0), phase: (2.0, 5.1)),
                    DotPath(start: CGPoint(x: 0.28, y: 0.76), end: CGPoint(x: 0.16, y: 0.30),
                            amp: CGVector(dx: 0.06, dy: 0.08), freq: (1.1, 1.2), phase: (5.6, 0.3)),
                    DotPath(start: CGPoint(x: 0.84, y: 0.28), end: CGPoint(x: 0.54, y: 0.86),
                            amp: CGVector(dx: 0.08, dy: 0.06), freq: (1.0, 1.4), phase: (1.7, 3.3)),
                    DotPath(start: CGPoint(x: 0.52, y: 0.88), end: CGPoint(x: 0.50, y: 0.44),
                            amp: CGVector(dx: 0.08, dy: 0.06), freq: (1.4, 1.1), phase: (3.0, 0.9)),
                ],
                markEnd: 1.0,
                move: (1.1, 2.5),
                taps: [(3.1, 0), (4.0, 1)])
        case .hearts:
            // One catch, one mix-up: dot 4 freezes near where target 1 started
            // and gets tapped instead, so the verdict shows both fail states.
            return Script(
                duration: 6.0,
                dots: [
                    DotPath(start: CGPoint(x: 0.22, y: 0.30), end: CGPoint(x: 0.30, y: 0.58),
                            amp: CGVector(dx: 0.07, dy: 0.08), freq: (1.1, 0.9), phase: (0.5, 2.2),
                            isTarget: true),
                    DotPath(start: CGPoint(x: 0.70, y: 0.62), end: CGPoint(x: 0.76, y: 0.24),
                            amp: CGVector(dx: 0.07, dy: 0.08), freq: (0.9, 1.2), phase: (3.8, 1.1),
                            isTarget: true),
                    DotPath(start: CGPoint(x: 0.48, y: 0.14), end: CGPoint(x: 0.18, y: 0.18),
                            amp: CGVector(dx: 0.06, dy: 0.07), freq: (1.2, 1.0), phase: (1.5, 4.7)),
                    DotPath(start: CGPoint(x: 0.30, y: 0.78), end: CGPoint(x: 0.62, y: 0.80),
                            amp: CGVector(dx: 0.08, dy: 0.05), freq: (1.3, 1.1), phase: (5.2, 0.7)),
                    DotPath(start: CGPoint(x: 0.82, y: 0.24), end: CGPoint(x: 0.52, y: 0.38),
                            amp: CGVector(dx: 0.08, dy: 0.07), freq: (1.0, 1.3), phase: (2.4, 3.6)),
                    DotPath(start: CGPoint(x: 0.56, y: 0.88), end: CGPoint(x: 0.86, y: 0.60),
                            amp: CGVector(dx: 0.06, dy: 0.07), freq: (1.4, 1.0), phase: (0.2, 2.8)),
                ],
                markEnd: 1.0,
                move: (1.1, 2.5),
                taps: [(3.0, 0), (3.85, 4)],
                revealAt: 4.4,
                showHearts: true)
        }
    }

    // MARK: Geometry

    private struct Geo {
        let board: CGRect
        let dot: CGFloat            // diameter
        let heartsCenter: CGPoint

        init(size: CGSize, showHearts: Bool) {
            let top: CGFloat = showHearts ? size.height * 0.12 : 0
            board = CGRect(x: 0, y: top, width: size.width, height: size.height - top)
                .insetBy(dx: size.width * 0.012, dy: size.height * 0.012)
            dot = board.width * 0.105
            heartsCenter = CGPoint(x: size.width / 2, y: top * 0.42)
        }

        /// Normalized (0..1) board coords → points, inset so dots clear the wall.
        func point(_ n: CGPoint) -> CGPoint {
            let inset = dot * 0.85
            return CGPoint(x: board.minX + inset + n.x * (board.width - inset * 2),
                           y: board.minY + inset + n.y * (board.height - inset * 2))
        }

        func dotRect(_ center: CGPoint, scale: CGFloat = 1) -> CGRect {
            let r = dot / 2 * scale
            return CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        }
    }

    // MARK: Render

    private func render(_ context: GraphicsContext, size: CGSize, t: Double) {
        let script = script
        let geo = Geo(size: size, showHearts: script.showHearts)
        let revealU = script.revealAt.map { DemoEase.ramp(t, $0, $0 + 0.30) } ?? 0

        drawBoard(context, geo: geo)

        for index in script.dots.indices {
            drawDot(context, script: script, index: index, t: t, geo: geo, revealU: revealU)
        }

        for tap in script.taps {
            DemoEase.drawTapRipple(context, at: geo.point(script.dots[tap.dot].end),
                                   start: tap.time, t: t,
                                   radius: geo.dot * 0.95, color: world.accent)
            if page == .pick {
                drawPlusOne(context, at: geo.point(script.dots[tap.dot].end),
                            start: tap.time, t: t, geo: geo)
            }
        }

        if !script.taps.isEmpty {
            let hand = DemoEase.handAlongTaps(
                script.taps.map { DemoEase.Tap(time: $0.time, point: geo.point(script.dots[$0.dot].end)) },
                t: t)
            DemoEase.drawHand(context,
                              tip: CGPoint(x: hand.tip.x + geo.dot * 0.10,
                                           y: hand.tip.y + geo.dot * 0.16),
                              size: geo.dot * 1.55, pressed: hand.pressed, alpha: hand.alpha)
        }

        if script.showHearts {
            drawHearts(context, geo: geo, t: t, script: script)
        }
    }

    private func drawBoard(_ ctx: GraphicsContext, geo: Geo) {
        let shape = Path(roundedRect: geo.board, cornerRadius: geo.board.width * 0.065,
                         style: .continuous)
        ctx.fill(shape, with: .color(world.surface))
        ctx.fill(shape, with: .radialGradient(
            Gradient(colors: [world.accent.opacity(0.10), .clear]),
            center: CGPoint(x: geo.board.midX, y: geo.board.midY),
            startRadius: 0,
            endRadius: max(geo.board.width, geo.board.height) * 0.65))
        ctx.stroke(shape, with: .color(world.accent.opacity(0.28)), lineWidth: 1.5)
    }

    /// Frozen-at-ends drift: smoothstep start→end with a sine wobble whose
    /// envelope hits zero at both endpoints.
    private func position(_ d: DotPath, t: Double, script: Script, geo: Geo) -> CGPoint {
        let p = DemoEase.ramp(t, script.move.0, script.move.1)
        let envelope = sin(.pi * p)
        let base = DemoEase.lerp(d.start, d.end, p)
        let x = base.x + d.amp.dx * CGFloat(sin(2 * .pi * d.freq.0 * p + d.phase.0) * envelope)
        let y = base.y + d.amp.dy * CGFloat(sin(2 * .pi * d.freq.1 * p + d.phase.1) * envelope)
        return geo.point(CGPoint(x: x, y: y))
    }

    private func drawDot(_ ctx: GraphicsContext, script: Script, index: Int,
                         t: Double, geo: Geo, revealU: Double) {
        let d = script.dots[index]
        let center = position(d, t: t, script: script, geo: geo)
        let tapTime = script.taps.first { $0.dot == index }?.time

        // Lit = the real game's accent-glow treatment: mark phase, a landed
        // pick, or the track page's closing recap.
        let markA = d.isTarget ? 1 - DemoEase.ramp(t, script.markEnd - 0.45, script.markEnd) : 0
        let pickedA = tapTime.map { DemoEase.ramp(t, $0, $0 + 0.15) } ?? 0
        let recapA = (d.isTarget ? script.recapAt : nil).map { DemoEase.ramp(t, $0, $0 + 0.45) } ?? 0
        let litA = max(markA, max(pickedA, recapA))
        let wrongU = (tapTime != nil && !d.isTarget) ? revealU : 0
        let missed = d.isTarget && tapTime == nil && script.revealAt != nil

        // Pulse while marked; small pop as a pick lands.
        let pulse = 1 + 0.15 * (0.5 - 0.5 * cos(2 * .pi * t / 0.9)) * markA
        let pop = tapTime.map { 1 + 0.13 * sin(.pi * DemoEase.ramp(t, $0, $0 + 0.30)) } ?? 1
        let rect = geo.dotRect(center, scale: CGFloat(pulse * pop))
        let circle = Path(ellipseIn: rect)

        ctx.fill(circle, with: .color(world.ink.opacity(0.30)))
        if litA > 0.01, wrongU < 1 {
            ctx.drawLayer { layer in
                layer.opacity = litA * (1 - wrongU)
                layer.addFilter(.shadow(color: world.accent.opacity(0.75), radius: geo.dot * 0.22))
                layer.fill(circle, with: .color(world.accent.opacity(0.92)))
            }
        }
        if wrongU > 0.01 {
            ctx.drawLayer { layer in
                layer.opacity = wrongU
                layer.addFilter(.shadow(color: world.secondary.opacity(0.7), radius: geo.dot * 0.22))
                layer.fill(circle, with: .color(world.secondary))
            }
        }

        let hot = max(litA, wrongU)
        ctx.stroke(circle,
                   with: .color(.white.opacity(0.12 + 0.78 * hot)),
                   lineWidth: 1 + hot)

        // Reveal ring around a dropped target, popping in like the real game.
        if missed, revealU > 0 {
            let ringR = rect.width / 2 + geo.dot * (0.18 + 0.30 * (1 - revealU))
            let ringRect = CGRect(x: center.x - ringR, y: center.y - ringR,
                                  width: ringR * 2, height: ringR * 2)
            ctx.stroke(Path(ellipseIn: ringRect),
                       with: .color(world.secondary.opacity(revealU)),
                       lineWidth: geo.dot * 0.095)
        }
    }

    private func drawPlusOne(_ ctx: GraphicsContext, at center: CGPoint,
                             start: Double, t: Double, geo: Geo) {
        let u = DemoEase.ramp(t, start + 0.05, start + 1.0)
        guard u > 0, u < 1 else { return }
        let alpha = min(1, u * 4) * (1 - DemoEase.ramp(u, 0.6, 1))
        let pos = CGPoint(x: center.x, y: center.y - geo.dot * (0.95 + 1.1 * CGFloat(u)))
        ctx.drawLayer { layer in
            layer.opacity = alpha
            layer.addFilter(.shadow(color: .black.opacity(0.5), radius: 3, y: 2))
            layer.draw(Text("+1")
                        .font(.system(size: geo.dot * 0.62, weight: .black, design: world.titleDesign))
                        .foregroundColor(world.accent),
                       at: pos)
        }
    }

    private func drawHearts(_ ctx: GraphicsContext, geo: Geo, t: Double, script: Script) {
        let lossU = script.revealAt.map { DemoEase.ramp(t, $0 + 0.10, $0 + 0.50) } ?? 0
        let side = geo.dot * 0.70
        let spacing = side * 1.45
        // The verdict rattles the row for a beat, like losing a life should.
        var shake: CGFloat = 0
        if let reveal = script.revealAt, t > reveal {
            shake = CGFloat(sin(t * 40) * 2.4 * (1 - DemoEase.ramp(t, reveal + 0.10, reveal + 0.60)))
        }

        for i in 0..<3 {
            let center = CGPoint(x: geo.heartsCenter.x + CGFloat(i - 1) * spacing + shake,
                                 y: geo.heartsCenter.y)
            let losing = i == 2
            let gone = losing ? lossU : 0

            if gone < 1 {
                let scale = 1 - 0.35 * CGFloat(gone)
                var filled = ctx.resolve(Image(systemName: "heart.fill"))
                filled.shading = .color(Self.heartColor.opacity(1 - gone))
                ctx.draw(filled, in: geo.dotRect(center, scale: scale * side / geo.dot))
            }
            if gone > 0 {
                var empty = ctx.resolve(Image(systemName: "heart"))
                empty.shading = .color(world.muted.opacity(0.45 * gone))
                ctx.draw(empty, in: geo.dotRect(center, scale: 0.88 * side / geo.dot))
            }
        }
    }
}
