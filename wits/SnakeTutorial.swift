//
//  SnakeTutorial.swift
//  wits
//
//  Animated how-to-play demos for Snake Snack: swipe through a corner, eat an
//  apple and grow, then see a wall collision end the run. The mini board uses
//  the real night-garden checker, striped green body, googly head, and apple.
//

import SwiftUI

enum SnakeTutorial {
    static let slides: [TutorialSlide] = [
        TutorialSlide(caption: "swipe to steer — the snake keeps moving between every turn") {
            SnakeDemo(page: .steer)
        },
        TutorialSlide(caption: "eat apples to score and grow — every apple also quickens the pace") {
            SnakeDemo(page: .eat)
        },
        TutorialSlide(caption: "don't hit a wall or your own body — one collision ends the run") {
            SnakeDemo(page: .crash)
        },
    ]
}

private struct SnakeDemo: View {
    enum Page { case steer, eat, crash }
    let page: Page

    private static let cols = 11
    private static let rows = 12
    private var world: GameWorld { GameID.snake.world }

    var body: some View {
        DemoLoop(duration: page == .crash ? 5.6 : 5.0) { t in
            Canvas { context, size in
                render(context, size: size, t: t)
            }
        }
    }

    private struct Geo {
        let board: CGRect
        let cell: CGFloat

        init(size: CGSize) {
            cell = min(size.width * 0.82 / CGFloat(SnakeDemo.cols),
                       size.height * 0.94 / CGFloat(SnakeDemo.rows))
            let boardSize = CGSize(width: cell * CGFloat(SnakeDemo.cols),
                                   height: cell * CGFloat(SnakeDemo.rows))
            board = CGRect(x: (size.width - boardSize.width) / 2,
                           y: (size.height - boardSize.height) / 2,
                           width: boardSize.width, height: boardSize.height)
        }

        func point(_ grid: CGPoint) -> CGPoint {
            CGPoint(x: board.minX + (grid.x + 0.5) * cell,
                    y: board.minY + (grid.y + 0.5) * cell)
        }
    }

    private struct Script {
        let route: [CGPoint]
        let startDistance: CGFloat
        let endDistance: CGFloat
        let moveStart: Double
        let moveEnd: Double
        let baseLength: Int
        var growAt: Double? = nil
        var crashAt: Double? = nil
    }

    private var script: Script {
        switch page {
        case .steer:
            return Script(route: [CGPoint(x: 3, y: 11.5), CGPoint(x: 3, y: 4), CGPoint(x: 9, y: 4)],
                          startDistance: 4.5, endDistance: 13.5,
                          moveStart: 0.45, moveEnd: 3.75, baseLength: 6)
        case .eat:
            return Script(route: [CGPoint(x: -1, y: 6), CGPoint(x: 9, y: 6)],
                          startDistance: 4, endDistance: 10,
                          moveStart: 0.55, moveEnd: 3.35, baseLength: 5,
                          growAt: 2.95)
        case .crash:
            return Script(route: [CGPoint(x: 3, y: 11), CGPoint(x: 3, y: 2), CGPoint(x: 10, y: 2)],
                          startDistance: 4.5, endDistance: 16,
                          moveStart: 0.45, moveEnd: 3.55, baseLength: 7,
                          crashAt: 3.5)
        }
    }

    private func render(_ context: GraphicsContext, size: CGSize, t: Double) {
        let geo = Geo(size: size)
        let script = script
        drawBoard(context, geo: geo)

        if page == .eat {
            drawApple(context, at: geo.point(CGPoint(x: 8, y: 6)),
                      cell: geo.cell, t: t, eatenAt: script.growAt)
        }

        let moveU = DemoEase.ramp(t, script.moveStart, script.moveEnd)
        let headDistance = script.startDistance
            + (script.endDistance - script.startDistance) * CGFloat(moveU)
        let grown = script.growAt.map { t >= $0 } ?? false
        let length = script.baseLength + (grown ? 2 : 0)
        let positions = (0..<length).map { index in
            point(on: script.route,
                  distance: max(0, headDistance - CGFloat(index) * 0.72), geo: geo)
        }
        drawSnake(context, positions: positions, cell: geo.cell,
                  dimmed: script.crashAt.map { t >= $0 } ?? false)

        if let growAt = script.growAt {
            drawEatFeedback(context, geo: geo, start: growAt, t: t)
        }
        if let crashAt = script.crashAt {
            drawCrash(context, geo: geo, start: crashAt, t: t)
        }
        if page == .steer {
            drawSwipe(context, geo: geo, t: t)
        }
    }

    // MARK: - Board and route

    private func drawBoard(_ context: GraphicsContext, geo: Geo) {
        let path = Path(roundedRect: geo.board, cornerRadius: 10, style: .continuous)
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.24), radius: 8, y: 5))
            layer.fill(path, with: .color(world.surface.opacity(0.74)))
        }
        context.drawLayer { layer in
            layer.clip(to: path)
            for x in 0..<Self.cols {
                for y in 0..<Self.rows where (x + y).isMultiple(of: 2) {
                    let rect = CGRect(x: geo.board.minX + CGFloat(x) * geo.cell,
                                      y: geo.board.minY + CGFloat(y) * geo.cell,
                                      width: geo.cell, height: geo.cell)
                    layer.fill(Path(rect), with: .color(world.ink.opacity(0.04)))
                }
            }
        }
        context.stroke(path, with: .color(world.ink.opacity(0.12)), lineWidth: 1)
    }

    private func point(on route: [CGPoint], distance: CGFloat, geo: Geo) -> CGPoint {
        guard let first = route.first else {
            return CGPoint(x: geo.board.midX, y: geo.board.midY)
        }
        var remaining = distance
        for index in route.indices.dropFirst() {
            let a = route[index - 1]
            let b = route[index]
            let length = hypot(b.x - a.x, b.y - a.y)
            if remaining <= length {
                let u = length > 0 ? remaining / length : 0
                return geo.point(CGPoint(x: a.x + (b.x - a.x) * u,
                                         y: a.y + (b.y - a.y) * u))
            }
            remaining -= length
        }
        return geo.point(route.last ?? first)
    }

    // MARK: - Snake

    private func drawSnake(_ context: GraphicsContext, positions: [CGPoint],
                           cell: CGFloat, dimmed: Bool) {
        guard let head = positions.first else { return }
        let alpha = dimmed ? 0.48 : 1.0

        if positions.count >= 2, let tail = positions.last {
            let beforeTail = positions[positions.count - 2]
            let dx = tail.x - beforeTail.x
            let dy = tail.y - beforeTail.y
            let length = max(0.001, hypot(dx, dy))
            let ux = dx / length, uy = dy / length
            let r = cell * 0.38
            var cone = Path()
            cone.move(to: CGPoint(x: tail.x - uy * r, y: tail.y + ux * r))
            cone.addLine(to: CGPoint(x: tail.x + uy * r, y: tail.y - ux * r))
            cone.addLine(to: CGPoint(x: tail.x + ux * cell, y: tail.y + uy * cell))
            cone.closeSubpath()
            context.fill(cone, with: .color(SnakePalette.body.opacity(alpha)))
        }

        for index in positions.indices.reversed() where index > 0 {
            let center = positions[index]
            let radius = cell * 0.51
            let circle = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                width: radius * 2, height: radius * 2))
            let color = index.isMultiple(of: 2) ? SnakePalette.body : SnakePalette.bodyAlt
            context.fill(circle, with: .color(color.opacity(alpha)))
            context.stroke(circle, with: .color(SnakePalette.rim.opacity(0.45 * alpha)),
                           lineWidth: radius * 0.12)
        }

        let headRadius = cell * 0.59
        let headPath = Path(ellipseIn: CGRect(x: head.x - headRadius, y: head.y - headRadius,
                                             width: headRadius * 2, height: headRadius * 2))
        context.fill(headPath, with: .color(SnakePalette.head.opacity(alpha)))

        let heading: CGVector = {
            guard positions.count > 1 else { return CGVector(dx: 1, dy: 0) }
            let dx = head.x - positions[1].x
            let dy = head.y - positions[1].y
            let length = max(0.001, hypot(dx, dy))
            return CGVector(dx: dx / length, dy: dy / length)
        }()
        let perpendicular = CGVector(dx: -heading.dy, dy: heading.dx)
        for sign in [-1.0, 1.0] {
            let eye = CGPoint(x: head.x + heading.dx * headRadius * 0.24
                                + perpendicular.dx * headRadius * 0.48 * sign,
                              y: head.y + heading.dy * headRadius * 0.24
                                + perpendicular.dy * headRadius * 0.48 * sign)
            let eyeR = headRadius * 0.31
            context.fill(Path(ellipseIn: CGRect(x: eye.x - eyeR, y: eye.y - eyeR,
                                                width: eyeR * 2, height: eyeR * 2)),
                         with: .color(.white.opacity(alpha)))
            let pupilR = eyeR * 0.5
            let pupil = CGPoint(x: eye.x + heading.dx * eyeR * 0.34,
                                y: eye.y + heading.dy * eyeR * 0.34)
            context.fill(Path(ellipseIn: CGRect(x: pupil.x - pupilR, y: pupil.y - pupilR,
                                                width: pupilR * 2, height: pupilR * 2)),
                         with: .color(.black.opacity(alpha)))
        }
    }

    // MARK: - Apple and feedback

    private func drawApple(_ context: GraphicsContext, at center: CGPoint,
                           cell: CGFloat, t: Double, eatenAt: Double?) {
        let vanish = eatenAt.map { DemoEase.ramp(t, $0, $0 + 0.25) } ?? 0
        guard vanish < 1 else { return }
        let pulse = 1 + 0.06 * sin(t * 4)
        let radius = cell * 0.48 * pulse * CGFloat(1 - vanish)
        let path = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                         width: radius * 2, height: radius * 2))
        context.fill(path, with: .color(SnakePalette.apple))
        context.stroke(path, with: .color(SnakePalette.appleRim), lineWidth: radius * 0.2)
        var leaf = Path()
        leaf.move(to: CGPoint(x: center.x, y: center.y - radius * 0.7))
        leaf.addQuadCurve(to: CGPoint(x: center.x + radius * 0.72, y: center.y - radius * 0.9),
                          control: CGPoint(x: center.x + radius * 0.45, y: center.y - radius * 1.2))
        leaf.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius * 0.7),
                          control: CGPoint(x: center.x + radius * 0.38, y: center.y - radius * 0.48))
        context.fill(leaf, with: .color(SnakePalette.leaf))
    }

    private func drawEatFeedback(_ context: GraphicsContext, geo: Geo,
                                 start: Double, t: Double) {
        let u = DemoEase.ramp(t, start, start + 0.9)
        guard u > 0, u < 1 else { return }
        let at = geo.point(CGPoint(x: 8, y: 6))
        context.draw(Text("+1  FASTER!")
            .font(.system(size: geo.cell * 0.58, weight: .black, design: .rounded))
            .foregroundColor(world.accent.opacity(1 - u)),
            at: CGPoint(x: at.x - geo.cell * 0.7,
                        y: at.y - geo.cell * (1.0 + CGFloat(u))))
        DemoEase.drawTapRipple(context, at: at, start: start, t: t,
                               radius: geo.cell * 1.2, color: world.secondary)
    }

    private func drawCrash(_ context: GraphicsContext, geo: Geo,
                           start: Double, t: Double) {
        let flash = DemoEase.ramp(t, start, start + 0.16)
            * (1 - DemoEase.ramp(t, start + 0.55, start + 1.1))
        if flash > 0 {
            context.fill(Path(roundedRect: geo.board, cornerRadius: 10, style: .continuous),
                         with: .color(world.secondary.opacity(0.32 * flash)))
        }
        let badgeU = DemoEase.ramp(t, start + 0.18, start + 0.48)
        guard badgeU > 0 else { return }
        let badge = CGRect(x: geo.board.minX + geo.board.width * 0.14,
                           y: geo.board.midY - geo.board.height * 0.075,
                           width: geo.board.width * 0.72,
                           height: geo.board.height * 0.15)
        context.fill(Path(roundedRect: badge, cornerRadius: 8, style: .continuous),
                     with: .color(world.secondary.opacity(0.94 * badgeU)))
        context.draw(Text("RUN OVER")
            .font(.system(size: geo.cell * 0.72, weight: .black, design: .rounded))
            .foregroundColor(world.ink.opacity(badgeU)),
            at: CGPoint(x: badge.midX, y: badge.midY))
    }

    // MARK: - Swipe cue

    private func drawSwipe(_ context: GraphicsContext, geo: Geo, t: Double) {
        let start = geo.point(CGPoint(x: 3.7, y: 6.1))
        let end = geo.point(CGPoint(x: 7.4, y: 6.1))
        let u = DemoEase.ramp(t, 1.45, 2.0)
        let tip = DemoEase.lerp(start, end, u)
        let alpha = DemoEase.ramp(t, 0.9, 1.25)
            * (1 - DemoEase.ramp(t, 2.12, 2.55))
        if u > 0.02, alpha > 0.01 {
            var trail = Path()
            trail.move(to: start)
            trail.addLine(to: tip)
            context.stroke(trail,
                           with: .linearGradient(
                            Gradient(colors: [world.accent.opacity(0), world.accent.opacity(0.75 * alpha)]),
                            startPoint: start, endPoint: tip),
                           style: StrokeStyle(lineWidth: geo.cell * 0.26, lineCap: .round))
        }
        DemoEase.drawHand(context,
                          tip: CGPoint(x: tip.x + geo.cell * 0.12, y: tip.y + geo.cell * 0.18),
                          size: geo.cell * 1.6,
                          pressed: t >= 1.35 && t < 2.05,
                          alpha: alpha)
    }
}
