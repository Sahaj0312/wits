//
//  WaterSortTutorial.swift
//  wits
//
//  Animated how-to-play demos for Water Sort on a mini three-tube board: tap
//  a tube to lift it, tap another and it flies over, tilts, and streams its
//  top colour across; a mismatched target refuses the pour; the last pour
//  sorts the board. Tubes render like the real game — round-bottomed glass,
//  stacked liquid units with a surface sheen, and the signature tilted pour
//  whose liquid stays level with the world.
//

import SwiftUI

enum WaterSortTutorial {
    static let slides: [TutorialSlide] = [
        TutorialSlide(caption: "tap a tube to pick it up, then tap another to pour its top colour") {
            WaterSortDemo(page: .pour)
        },
        TutorialSlide(caption: "a pour lands only on a matching colour or an empty tube") {
            WaterSortDemo(page: .match)
        },
        TutorialSlide(caption: "sort every colour into its own tube in as few pours as you can") {
            WaterSortDemo(page: .solve)
        },
    ]
}

private struct WaterSortDemo: View {
    enum Page { case pour, match, solve }
    let page: Page

    private var world: GameWorld { GameID.waterSort.world }

    /// Same liquid palette as WaterSortScreen (0-based here).
    private static let liquid: [Color] = [
        Color(hexAny: 0xF25757), // red
        Color(hexAny: 0xF7A72F), // orange
        Color(hexAny: 0xF8E14B), // yellow
        Color(hexAny: 0x5BC96A), // green
        Color(hexAny: 0x3ED8C3), // teal
        Color(hexAny: 0x4D8DF7), // blue
    ]

    var body: some View {
        DemoLoop(duration: script.duration) { t in
            Canvas { context, size in
                render(context, size: size, t: t)
            }
        }
    }

    // MARK: Script

    private struct Pour {
        let source: Int
        let dest: Int
        let units: Int
        let start: Double
        let flow: Double
        let travel = 0.35
        let back = 0.35
        var end: Double { start + travel + flow + back }
    }

    private struct Script {
        let duration: Double
        let capacity: Int
        let tubes: [[Int]]                      // bottom→top colour per tube
        let taps: [(time: Double, tube: Int)]
        let selectAt: Double                    // source lifts here…
        let pour: Pour                          // …and flies at pour.start
        var refusalAt: Double? = nil            // mismatched tap: shake + red
        var refusalDest: Int? = nil
        var solvedAt: Double? = nil
    }

    private var script: Script {
        switch page {
        case .pour:
            // Red rides on blue; pour it onto the tube whose top is also red.
            return Script(
                duration: 4.5,
                capacity: 3,
                tubes: [[5, 0], [0], [5]],
                taps: [(1.0, 0), (1.9, 1)],
                selectAt: 1.0,
                pour: Pour(source: 0, dest: 1, units: 1, start: 1.9, flow: 0.55))
        case .match:
            // Red over teal is refused, then the empty tube accepts it.
            return Script(
                duration: 5.9,
                capacity: 3,
                tubes: [[4, 0], [5, 4], []],
                taps: [(1.0, 0), (2.0, 1), (3.3, 2)],
                selectAt: 1.0,
                pour: Pour(source: 0, dest: 2, units: 1, start: 3.3, flow: 0.55),
                refusalAt: 2.0,
                refusalDest: 1)
        case .solve:
            // A two-unit run completes the green tube and solves the board.
            return Script(
                duration: 5.4,
                capacity: 3,
                tubes: [[3], [3, 3], [4, 4, 4]],
                taps: [(1.0, 1), (1.9, 0)],
                selectAt: 1.0,
                pour: Pour(source: 1, dest: 0, units: 2, start: 1.9, flow: 0.70),
                solvedAt: 3.35)
        }
    }

    // MARK: Geometry

    private struct Geo {
        let rects: [CGRect]
        let tubeW: CGFloat
        let tubeH: CGFloat

        init(size: CGSize, count: Int) {
            let w = min(size.width * 0.155, 52)
            let h = w * 2.7
            let gap = w * 0.62
            let total = CGFloat(count) * w + CGFloat(count - 1) * gap
            let x0 = (size.width - total) / 2
            let bottom = size.height * 0.78
            tubeW = w
            tubeH = h
            rects = (0..<count).map { index in
                CGRect(x: x0 + CGFloat(index) * (w + gap), y: bottom - h,
                       width: w, height: h)
            }
        }

        func center(_ index: Int) -> CGPoint {
            CGPoint(x: rects[index].midX, y: rects[index].midY)
        }
    }

    private func tubeShape(width: CGFloat) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: width * 0.16,
                               bottomLeadingRadius: width * 0.5,
                               bottomTrailingRadius: width * 0.5,
                               topTrailingRadius: width * 0.16,
                               style: .continuous)
    }

    private static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    // MARK: Pour choreography

    /// One frame of the flying tube, mirroring the real screen's pourFrame:
    /// glide to the destination while tilting to 55°, deepen to 69° as the
    /// run drains, then fly home upright.
    private struct Flight {
        var angle = 0.0
        var mouth = CGPoint.zero
        var drained = 0.0
        var added: CGFloat = 0
        var stream: (x: CGFloat, top: CGFloat, bottom: CGFloat)?
    }

    private func flight(_ p: Pour, t: Double, geo: Geo, capacity: Int,
                        destCount: Int, lift: CGFloat) -> Flight {
        let local = t - p.start
        let src = geo.rects[p.source]
        let dst = geo.rects[p.dest]
        let side: CGFloat = dst.midX >= src.midX ? 1 : -1
        let baseAngle = 55.0
        let extraAngle = 14.0

        // Park the low lip — where the stream leaves — over the destination.
        let midTilt = (baseAngle + extraAngle / 2) * .pi / 180
        let start = CGPoint(x: src.midX, y: src.minY)
        let target = CGPoint(x: dst.midX - side * geo.tubeW / 2 * cos(midTilt),
                             y: dst.minY - geo.tubeH * 0.30)

        var travelF = 0.0
        var pourP = 0.0
        var angle = 0.0
        var liftPart = 0.0
        if local < p.travel {
            travelF = Self.easeInOut(local / p.travel)
            angle = baseAngle * travelF
            liftPart = Double(-lift) * (1 - travelF)
        } else if local < p.travel + p.flow {
            travelF = 1
            pourP = (local - p.travel) / p.flow
            angle = baseAngle + extraAngle * pourP
        } else {
            let back = Self.easeInOut(min(1, (local - p.travel - p.flow) / p.back))
            travelF = 1 - back
            pourP = 1
            angle = (baseAngle + extraAngle) * travelF
        }
        angle *= Double(side)

        var frame = Flight()
        frame.angle = angle
        frame.mouth = CGPoint(x: start.x + (target.x - start.x) * travelF,
                              y: start.y + (target.y - start.y) * travelF + liftPart)
        frame.drained = Double(p.units) * pourP
        frame.added = CGFloat(frame.drained)
        if pourP > 0, pourP < 1 {
            let tilt = angle * .pi / 180
            let unitH = (geo.tubeH - 6) / CGFloat(capacity)
            let surface = dst.maxY - 3 - (CGFloat(destCount) + frame.added) * unitH
            frame.stream = (x: frame.mouth.x + side * geo.tubeW / 2 * cos(tilt),
                            top: frame.mouth.y + side * geo.tubeW / 2 * sin(tilt),
                            bottom: surface)
        }
        return frame
    }

    // MARK: Render

    private func render(_ context: GraphicsContext, size: CGSize, t: Double) {
        let script = script
        let geo = Geo(size: size, count: script.tubes.count)
        let pour = script.pour
        let finished = t >= pour.end
        let inFlight = t >= pour.start && !finished
        let pourColor = script.tubes[pour.source].last ?? 0

        // Board shows the pre-pour stacks until the tube lands home.
        var shown = script.tubes
        if finished {
            let run = Array(shown[pour.source].suffix(pour.units))
            shown[pour.source].removeLast(pour.units)
            shown[pour.dest].append(contentsOf: run)
        }

        let liftAmount = geo.tubeH * 0.12
        let liftU = DemoEase.ramp(t, script.selectAt, script.selectAt + 0.25)
        let solvedFlash = script.solvedAt.map { at in
            DemoEase.ramp(t, at, at + 0.16) * (1 - DemoEase.ramp(t, at + 0.6, at + 1.2))
        } ?? 0

        let fly = inFlight
            ? flight(pour, t: t, geo: geo, capacity: script.capacity,
                     destCount: script.tubes[pour.dest].count, lift: liftAmount)
            : nil

        for index in shown.indices {
            if inFlight, index == pour.source { continue }
            var rect = geo.rects[index]
            var extra: (color: Int, units: CGFloat)?
            if let fly, index == pour.dest { extra = (pourColor, fly.added) }

            if index == pour.source, !inFlight, !finished {
                rect = rect.offsetBy(dx: 0, dy: -liftAmount * liftU)
                // A refused pour shudders in the hand instead of moving.
                if let refusal = script.refusalAt, t >= refusal {
                    let decay = 1 - DemoEase.ramp(t, refusal + 0.05, refusal + 0.55)
                    rect = rect.offsetBy(dx: sin((t - refusal) * 34) * geo.tubeW * 0.09 * decay, dy: 0)
                }
            }

            var redPulse = 0.0
            if let refusal = script.refusalAt, index == script.refusalDest {
                redPulse = DemoEase.ramp(t, refusal, refusal + 0.12)
                    * (1 - DemoEase.ramp(t, refusal + 0.55, refusal + 0.95))
            }

            let complete = shown[index].count == script.capacity && Set(shown[index]).count == 1
            drawTube(context, colors: shown[index], rect: rect, capacity: script.capacity,
                     extra: extra, complete: complete,
                     flash: complete ? solvedFlash : 0, redPulse: redPulse)
        }

        if let fly {
            if let stream = fly.stream, stream.bottom > stream.top {
                context.fill(Path(roundedRect: CGRect(x: stream.x - 2.5, y: stream.top,
                                                      width: 5, height: stream.bottom - stream.top),
                                  cornerRadius: 2.5),
                             with: .color(Self.liquid[pourColor]))
            }
            drawPouringTube(context, colors: script.tubes[pour.source], drained: fly.drained,
                            mouth: fly.mouth, angleDeg: fly.angle, geo: geo,
                            capacity: script.capacity)
        }

        if let refusal = script.refusalAt, let dest = script.refusalDest {
            drawRefusal(context, over: geo.rects[dest], t: t, start: refusal)
        }
        if let solvedAt = script.solvedAt {
            drawSolvedBadge(context, size: size, geo: geo, t: t, at: solvedAt)
        }

        for tap in script.taps {
            DemoEase.drawTapRipple(context, at: geo.center(tap.tube),
                                   start: tap.time, t: t,
                                   radius: geo.tubeW * 0.75, color: world.accent)
        }
        let hand = DemoEase.handAlongTaps(
            script.taps.map { DemoEase.Tap(time: $0.time, point: geo.center($0.tube)) }, t: t)
        DemoEase.drawHand(context, tip: CGPoint(x: hand.tip.x + geo.tubeW * 0.10,
                                                y: hand.tip.y + geo.tubeW * 0.16),
                          size: geo.tubeW * 1.2, pressed: hand.pressed, alpha: hand.alpha)
    }

    // MARK: Tube drawing

    private func drawTube(_ context: GraphicsContext, colors: [Int], rect: CGRect,
                          capacity: Int, extra: (color: Int, units: CGFloat)?,
                          complete: Bool, flash: Double, redPulse: Double) {
        let shape = tubeShape(width: rect.width)
        let path = shape.path(in: rect)
        let unitH = (rect.height - 6) / CGFloat(capacity)

        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.22), radius: 4, y: 2))
            layer.fill(path, with: .color(.white.opacity(0.07)))
        }

        context.drawLayer { layer in
            layer.clip(to: shape.inset(by: 3).path(in: rect))
            for (index, color) in colors.enumerated() {
                let y = rect.maxY - 3 - CGFloat(index + 1) * unitH
                layer.fill(Path(CGRect(x: rect.minX + 3, y: y,
                                       width: rect.width - 6, height: unitH + 0.8)),
                           with: .color(Self.liquid[color]))
            }
            // liquid landing mid-pour rises smoothly above the stack
            if let extra, extra.units > 0 {
                let base = rect.maxY - 3 - CGFloat(colors.count) * unitH
                layer.fill(Path(CGRect(x: rect.minX + 3, y: base - unitH * extra.units,
                                       width: rect.width - 6, height: unitH * extra.units)),
                           with: .color(Self.liquid[extra.color]))
            }
            // resting-surface sheen on the top unit
            let fillUnits = CGFloat(colors.count) + (extra?.units ?? 0)
            if fillUnits > 0 {
                let y = rect.maxY - 3 - fillUnits * unitH
                layer.fill(Path(CGRect(x: rect.minX + 5, y: y,
                                       width: rect.width - 10, height: 3)),
                           with: .color(.white.opacity(0.22)))
            }
        }

        context.stroke(path, with: .color(.white.opacity(complete ? 0.55 : 0.28)), lineWidth: 2)
        if redPulse > 0 {
            context.stroke(path, with: .color(Color(hexAny: 0xFF5E5E).opacity(redPulse)),
                           lineWidth: 2.5)
        }
        if flash > 0 {
            context.fill(shape.inset(by: 3).path(in: rect), with: .color(.white.opacity(0.30 * flash)))
            context.stroke(path, with: .color(world.accent.opacity(flash)), lineWidth: 3)
        }
    }

    /// The tilted, draining source tube. The layer is rotated around the
    /// mouth, so liquid surfaces are drawn with the opposite slope to stay
    /// level with the world — the signature water sort look.
    private func drawPouringTube(_ context: GraphicsContext, colors: [Int], drained: Double,
                                 mouth: CGPoint, angleDeg: Double, geo: Geo, capacity: Int) {
        let w = geo.tubeW
        let h = geo.tubeH
        let shape = tubeShape(width: w)

        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.22), radius: 4, y: 2))
            layer.translateBy(x: mouth.x, y: mouth.y)
            layer.rotate(by: .degrees(angleDeg))
            layer.translateBy(x: -w / 2, y: 0)
            let rect = CGRect(x: 0, y: 0, width: w, height: h)
            let path = shape.path(in: rect)
            layer.fill(path, with: .color(.white.opacity(0.07)))

            layer.drawLayer { inner in
                inner.clip(to: shape.inset(by: 3).path(in: rect))
                let unitH = (h - 6) / CGFloat(capacity)
                let slope = CGFloat(tan(angleDeg * .pi / 180))
                let total = Double(colors.count) - drained
                guard total > 0 else { return }

                func surfaceY(_ units: Double, _ x: CGFloat) -> CGFloat {
                    let yMid = (h - 3) - CGFloat(units) * unitH
                    return yMid - (x - w / 2) * slope
                }
                // Paint each colour as everything below its level surface,
                // top colour first, so deeper colours overwrite from below.
                for index in stride(from: colors.count - 1, through: 0, by: -1) {
                    let units = min(Double(index + 1), total)
                    guard units > 0 else { continue }
                    var liquid = Path()
                    liquid.move(to: CGPoint(x: 0, y: surfaceY(units, 0)))
                    liquid.addLine(to: CGPoint(x: w, y: surfaceY(units, w)))
                    liquid.addLine(to: CGPoint(x: w, y: h))
                    liquid.addLine(to: CGPoint(x: 0, y: h))
                    liquid.closeSubpath()
                    inner.fill(liquid, with: .color(Self.liquid[colors[index]]))
                }
                var sheen = Path()
                sheen.move(to: CGPoint(x: 0, y: surfaceY(total, 0)))
                sheen.addLine(to: CGPoint(x: w, y: surfaceY(total, w)))
                inner.stroke(sheen, with: .color(.white.opacity(0.22)), lineWidth: 3)
            }

            layer.stroke(path, with: .color(.white.opacity(0.28)), lineWidth: 2)
        }
    }

    // MARK: Feedback

    /// A crossed-out ring above the mismatched tube — the pour is refused.
    private func drawRefusal(_ context: GraphicsContext, over rect: CGRect,
                             t: Double, start: Double) {
        let alpha = DemoEase.ramp(t, start, start + 0.15)
            * (1 - DemoEase.ramp(t, start + 0.75, start + 1.05))
        guard alpha > 0.01 else { return }
        let center = CGPoint(x: rect.midX, y: rect.minY - rect.width * 0.55)
        let radius = rect.width * 0.30
        let red = Color(hexAny: 0xFF5E5E)

        context.drawLayer { layer in
            layer.opacity = alpha
            layer.addFilter(.shadow(color: .black.opacity(0.4), radius: 4, y: 2))
            layer.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                width: radius * 2, height: radius * 2)),
                         with: .color(red), lineWidth: 3)
            let arm = radius * 0.45
            var cross = Path()
            cross.move(to: CGPoint(x: center.x - arm, y: center.y - arm))
            cross.addLine(to: CGPoint(x: center.x + arm, y: center.y + arm))
            cross.move(to: CGPoint(x: center.x + arm, y: center.y - arm))
            cross.addLine(to: CGPoint(x: center.x - arm, y: center.y + arm))
            layer.stroke(cross, with: .color(red), lineWidth: 3)
        }
    }

    private func drawSolvedBadge(_ context: GraphicsContext, size: CGSize, geo: Geo,
                                 t: Double, at: Double) {
        let u = DemoEase.ramp(t, at, at + 0.35)
        guard u > 0 else { return }
        let badge = CGRect(x: size.width / 2 - geo.tubeW * 2.2,
                           y: geo.rects[0].minY + geo.tubeH * 0.30 - (1 - u) * 8,
                           width: geo.tubeW * 4.4, height: geo.tubeW * 1.15)
        let pill = Path(roundedRect: badge, cornerRadius: badge.height / 2, style: .continuous)

        context.drawLayer { layer in
            layer.opacity = u
            layer.addFilter(.shadow(color: .black.opacity(0.45), radius: 8, y: 5))
            layer.fill(pill, with: .color(world.background.opacity(0.95)))
            layer.stroke(pill, with: .color(world.accent.opacity(0.9)), lineWidth: 2)
            layer.draw(Text("sorted!")
                        .font(.system(size: geo.tubeW * 0.46, weight: .black, design: world.titleDesign))
                        .foregroundColor(world.ink),
                       at: CGPoint(x: badge.midX, y: badge.midY))
        }
    }
}
