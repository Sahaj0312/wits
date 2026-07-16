//
//  TileShiftTutorial.swift
//  wits
//
//  Animated how-to-play demos for Tile Shift: a banner names the rule —
//  match by colour or by shape — and the hand taps the candidate tile that
//  fits the target. Page two flips the rule over identical tiles so the
//  "same tiles, different answer" insight lands; page three spends a heart
//  on a tap made by the stale rule.
//

import SwiftUI

enum TileShiftTutorial {
    static let slides: [TutorialSlide] = [
        TutorialSlide(caption: "read the rule, then tap the tile that matches the target by that rule") {
            TileShiftDemo(page: .matchRule)
        },
        TutorialSlide(caption: "the rule keeps flipping — same tiles, different right answer") {
            TileShiftDemo(page: .ruleFlip)
        },
        TutorialSlide(caption: "you have three hearts: a wrong tap or a timeout costs one") {
            TileShiftDemo(page: .hearts)
        },
    ]
}

private struct TileShiftDemo: View {
    enum Page { case matchRule, ruleFlip, hearts }
    let page: Page

    // Tile art mirrors TileShift.swift: SF-symbol shapes in the game's triad.
    private static let shapes = ["circle.fill", "square.fill", "triangle.fill"]
    private static let colors: [Color] = [
        Color(red: 0.09, green: 0.70, blue: 0.64),
        Color(red: 0.94, green: 0.47, blue: 0.37),
        Color(red: 0.95, green: 0.74, blue: 0.16),
    ]
    // EndlessHeartsRow's heart red.
    private static let heartColor = Color(red: 239 / 255, green: 71 / 255, blue: 111 / 255)

    private var world: GameWorld { GameID.tileShift.world }

    var body: some View {
        DemoLoop(duration: script.duration) { t in
            Canvas { context, size in
                render(context, size: size, t: t)
            }
        }
    }

    // MARK: Script

    private struct Tile {
        let shape: Int
        let color: Int
    }

    private struct Trial {
        let start: Double
        let byColor: Bool
        let target: Tile
        let left: Tile
        let right: Tile
    }

    private struct TapBeat {
        let time: Double
        let onLeft: Bool
        let correct: Bool
    }

    private struct Script {
        let duration: Double
        let trials: [Trial]
        let taps: [TapBeat]
        var flipAt: Double? = nil      // rule flips mid-trial, tiles unchanged
        var missAt: Double? = nil      // moment the heart empties
        var showHearts = false
        var deadlineStart = 1.0        // page three opens with the bar already tight
        var drainRate = 0.16
    }

    private var script: Script {
        switch page {
        case .matchRule:
            // COLOUR rule twice over — two different trials so the tap-after-tap
            // rhythm of a run reads, not just one lucky answer.
            return Script(
                duration: 5.6,
                trials: [Trial(start: 0, byColor: true,
                               target: Tile(shape: 0, color: 0),
                               left: Tile(shape: 0, color: 1),
                               right: Tile(shape: 1, color: 0)),
                         Trial(start: 2.8, byColor: true,
                               target: Tile(shape: 2, color: 2),
                               left: Tile(shape: 1, color: 2),
                               right: Tile(shape: 2, color: 1))],
                taps: [TapBeat(time: 1.5, onLeft: false, correct: true),
                       TapBeat(time: 3.8, onLeft: true, correct: true)])
        case .ruleFlip:
            // The hand drifts toward the colour match, the banner flips to
            // SHAPE over the exact same tiles, and the hand has to swerve.
            return Script(
                duration: 5.8,
                trials: [Trial(start: 0, byColor: true,
                               target: Tile(shape: 0, color: 0),
                               left: Tile(shape: 0, color: 1),
                               right: Tile(shape: 1, color: 0))],
                taps: [TapBeat(time: 3.1, onLeft: true, correct: true)],
                flipAt: 1.7)
        case .hearts:
            // Rule says SHAPE but the hand answers by the old COLOUR rule
            // under a short deadline — red feedback, one heart gone.
            return Script(
                duration: 5.4,
                trials: [Trial(start: 0, byColor: false,
                               target: Tile(shape: 0, color: 0),
                               left: Tile(shape: 1, color: 0),
                               right: Tile(shape: 0, color: 1))],
                taps: [TapBeat(time: 1.8, onLeft: true, correct: false)],
                missAt: 1.8,
                showHearts: true,
                deadlineStart: 0.55,
                drainRate: 0.20)
        }
    }

    // MARK: Geometry

    private struct Geo {
        let size: CGSize
        let heartsCenter: CGPoint
        let heartSize: CGFloat
        let heartGap: CGFloat
        let bannerRect: CGRect
        let targetRect: CGRect
        let barRect: CGRect
        let leftRect: CGRect
        let rightRect: CGRect

        init(size: CGSize, showHearts: Bool) {
            self.size = size
            let w = size.width
            let h = size.height
            heartsCenter = CGPoint(x: w / 2, y: h * 0.065)
            heartSize = w * 0.062
            heartGap = w * 0.09
            let bannerY = showHearts ? h * 0.185 : h * 0.13
            bannerRect = CGRect(x: w / 2 - w * 0.345, y: bannerY - h * 0.048,
                                width: w * 0.69, height: h * 0.096)
            let side = w * 0.30
            let targetY = showHearts ? h * 0.44 : h * 0.415
            targetRect = CGRect(x: w / 2 - side / 2, y: targetY - side / 2,
                                width: side, height: side)
            barRect = CGRect(x: w / 2 - w * 0.20, y: targetRect.maxY + h * 0.055,
                             width: w * 0.40, height: 5)
            let optW = w * 0.435
            let optH = h * 0.195
            let optY = h * 0.845 - optH / 2
            leftRect = CGRect(x: w / 2 - optW - w * 0.022, y: optY, width: optW, height: optH)
            rightRect = CGRect(x: w / 2 + w * 0.022, y: optY, width: optW, height: optH)
        }

        func option(_ left: Bool) -> CGRect { left ? leftRect : rightRect }
    }

    // MARK: Render

    private func render(_ context: GraphicsContext, size: CGSize, t: Double) {
        let s = script
        let geo = Geo(size: size, showHearts: s.showHearts)
        let trial = s.trials.last(where: { $0.start <= t }) ?? s.trials[0]
        let flipped = s.flipAt.map { t >= $0 } ?? false
        let byColor = flipped ? !trial.byColor : trial.byColor

        if s.showHearts {
            drawHearts(context, geo: geo, missAt: s.missAt, t: t)
        }
        drawBanner(context, geo: geo, trial: trial, flipAt: s.flipAt, t: t)

        // deadline bar drains within each trial and refills after an answer
        let resets = s.trials.map(\.start) + s.taps.map { $0.time + 0.05 }
        let lastReset = resets.filter { $0 <= t }.max() ?? 0
        let frac = max(0, s.deadlineStart - s.drainRate * (t - lastReset))
        drawDeadline(context, geo: geo, frac: frac)

        // fresh trials pop in quickly, like the real 0.12s round swap
        let trialIn = trial.start == 0 ? 1 : DemoEase.ramp(t, trial.start, trial.start + 0.15)

        // per-tap feedback: target border tint + flash fill on the tapped tile
        var targetFeedback: (Color, Double)?
        for tap in s.taps {
            let u = DemoEase.ramp(t, tap.time, tap.time + 0.10)
                * (1 - DemoEase.ramp(t, tap.time + 0.55, tap.time + 1.0))
            guard u > 0 else { continue }
            targetFeedback = (tap.correct ? world.accent : world.secondary, u)
        }

        drawTile(context, rect: geo.targetRect, tile: trial.target, alpha: trialIn)
        if let (color, u) = targetFeedback {
            let border = geo.targetRect.insetBy(dx: -8, dy: -8)
            context.stroke(Path(roundedRect: border, cornerRadius: 9, style: .continuous),
                           with: .color(color.opacity(u)), lineWidth: 2.5)
        }

        for left in [true, false] {
            var rect = geo.option(left)
            var flash: (Color, Double)?
            for tap in s.taps where tap.onLeft == left {
                let u = DemoEase.ramp(t, tap.time, tap.time + 0.10)
                    * (1 - DemoEase.ramp(t, tap.time + 0.55, tap.time + 1.0))
                if u > 0 { flash = (tap.correct ? world.accent : world.secondary, u) }
                // wrong answers rattle the tile they were spent on
                if !tap.correct, t >= tap.time {
                    let amp = 1 - DemoEase.ramp(t, tap.time, tap.time + 0.45)
                    rect.origin.x += sin((t - tap.time) * 34) * 5 * amp
                }
            }
            drawTile(context, rect: rect, tile: left ? trial.left : trial.right,
                     alpha: trialIn, flash: flash)
        }

        // score / heart juice above the tapped tile
        for tap in s.taps {
            let rise = DemoEase.ramp(t, tap.time + 0.05, tap.time + 0.8)
            let alpha = rise * (1 - DemoEase.ramp(t, tap.time + 0.9, tap.time + 1.3))
            guard alpha > 0.01 else { continue }
            let rect = geo.option(tap.onLeft)
            let at = CGPoint(x: rect.midX, y: rect.minY - 12 - 22 * rise)
            context.draw(Text(tap.correct ? "+1" : "-1")
                            .font(.system(size: size.width * 0.075, weight: .black, design: .rounded))
                            .foregroundColor((tap.correct ? world.accent : Self.heartColor).opacity(alpha)),
                         at: at)
        }

        for tap in s.taps {
            DemoEase.drawTapRipple(context, at: CGPoint(x: geo.option(tap.onLeft).midX,
                                                        y: geo.option(tap.onLeft).midY),
                                   start: tap.time, t: t,
                                   radius: geo.option(tap.onLeft).height * 0.62,
                                   color: tap.correct ? world.accent : world.secondary)
        }

        drawHandFor(context, geo: geo, t: t)
        _ = byColor
    }

    /// Page two steers the hand by hand (drift → swerve after the flip); the
    /// other pages just walk the scripted taps.
    private func drawHandFor(_ context: GraphicsContext, geo: Geo, t: Double) {
        let handSize = geo.option(true).height * 0.92
        if page == .ruleFlip {
            let start = CGPoint(x: geo.size.width * 0.52, y: geo.size.height * 0.99)
            let hoverRight = CGPoint(x: geo.rightRect.midX, y: geo.rightRect.midY - geo.rightRect.height * 0.10)
            let leftCenter = CGPoint(x: geo.leftRect.midX, y: geo.leftRect.midY)
            var tip = DemoEase.lerp(start, hoverRight, DemoEase.ramp(t, 0.8, 1.5))
            tip = DemoEase.lerp(tip, leftCenter, DemoEase.ramp(t, 2.2, 3.0))
            let alpha = DemoEase.ramp(t, 0.55, 0.95) * (1 - DemoEase.ramp(t, 4.2, 4.8))
            let pressed = t >= 3.1 && t < 3.28
            DemoEase.drawHand(context, tip: tip, size: handSize, pressed: pressed, alpha: alpha)
        } else {
            let taps = script.taps.map {
                DemoEase.Tap(time: $0.time, point: CGPoint(x: geo.option($0.onLeft).midX,
                                                           y: geo.option($0.onLeft).midY))
            }
            let hand = DemoEase.handAlongTaps(taps, t: t)
            DemoEase.drawHand(context, tip: hand.tip, size: handSize,
                              pressed: hand.pressed, alpha: hand.alpha)
        }
    }

    // MARK: Pieces

    private func drawTile(_ context: GraphicsContext, rect: CGRect, tile: Tile,
                          alpha: Double, flash: (Color, Double)? = nil) {
        let path = Path(roundedRect: rect, cornerRadius: 7, style: .continuous)
        context.drawLayer { layer in
            layer.opacity = alpha
            layer.fill(path, with: .color(world.surface))
            layer.stroke(path, with: .color(world.ink.opacity(0.12)), lineWidth: 1)
            let side = min(rect.width, rect.height) * 0.46
            let glyphRect = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2,
                                   width: side, height: side)
            var glyph = layer.resolve(Image(systemName: Self.shapes[tile.shape]))
            glyph.shading = .color(Self.colors[tile.color])
            layer.draw(glyph, in: glyphRect)
            if let (color, u) = flash {
                layer.fill(path, with: .color(color.opacity(0.22 * u)))
                layer.stroke(path, with: .color(color.opacity(u)), lineWidth: 2.5)
            }
        }
    }

    private func drawBanner(_ context: GraphicsContext, geo: Geo, trial: Trial,
                            flipAt: Double?, t: Double) {
        // crossfade colour→shape at the flip, with a pop so it can't be missed
        let flipU = flipAt.map { DemoEase.ramp(t, $0 - 0.02, $0 + 0.20) } ?? 0
        let startsByColor = trial.byColor
        let pulse = flipAt.map { DemoEase.ramp(t, $0, $0 + 0.15) * (1 - DemoEase.ramp(t, $0 + 0.4, $0 + 0.9)) } ?? 0
        let scale = 1 + 0.20 * pulse

        func half(_ byColor: Bool, _ alpha: Double) {
            guard alpha > 0.01 else { return }
            let color = byColor ? world.accent : world.secondary
            context.drawLayer { layer in
                layer.opacity = alpha
                layer.translateBy(x: geo.bannerRect.midX, y: geo.bannerRect.midY)
                layer.scaleBy(x: scale, y: scale)
                layer.translateBy(x: -geo.bannerRect.midX, y: -geo.bannerRect.midY)
                layer.fill(Path(roundedRect: geo.bannerRect, cornerRadius: geo.bannerRect.height / 2),
                           with: .color(color.opacity(0.14 + 0.25 * pulse)))
                layer.draw(Text(byColor ? "MATCH THE COLOUR" : "MATCH THE SHAPE")
                                .font(.system(size: geo.size.width * 0.047, weight: .heavy, design: .rounded))
                                .kerning(1)
                                .foregroundColor(color),
                           at: CGPoint(x: geo.bannerRect.midX, y: geo.bannerRect.midY))
            }
        }
        half(startsByColor, 1 - flipU)
        half(!startsByColor, flipU)

        // shout the flip: a ring bursts out of the banner
        if let flipAt {
            let u = DemoEase.ramp(t, flipAt, flipAt + 0.5)
            if u > 0, u < 1 {
                let grow = geo.bannerRect.insetBy(dx: -24 * u, dy: -14 * u)
                context.stroke(Path(roundedRect: grow, cornerRadius: grow.height / 2),
                               with: .color(world.secondary.opacity(0.8 * (1 - u))),
                               lineWidth: 3)
            }
        }
    }

    private func drawDeadline(_ context: GraphicsContext, geo: Geo, frac: Double) {
        let track = Path(roundedRect: geo.barRect, cornerRadius: geo.barRect.height / 2)
        context.fill(track, with: .color(world.surface))
        var fill = geo.barRect
        fill.size.width = geo.barRect.width * frac
        if fill.width > 1 {
            context.fill(Path(roundedRect: fill, cornerRadius: fill.height / 2),
                         with: .color(frac < 0.35 ? world.secondary : world.muted))
        }
    }

    private func drawHearts(_ context: GraphicsContext, geo: Geo, missAt: Double?, t: Double) {
        for i in 0..<3 {
            let x = geo.heartsCenter.x + CGFloat(i - 1) * geo.heartGap
            var full = true
            var scale: CGFloat = 1
            if i == 2, let missAt {
                let pop = DemoEase.ramp(t, missAt, missAt + 0.35)
                full = pop < 0.5
                // quick swell then settle small, like the row's snappy loss animation
                scale = pop == 0 ? 1 : 1 + 0.35 * sin(pop * .pi) - 0.12 * CGFloat(pop)
            }
            let side = geo.heartSize * scale
            let rect = CGRect(x: x - side / 2, y: geo.heartsCenter.y - side / 2,
                              width: side, height: side)
            var glyph = context.resolve(Image(systemName: full ? "heart.fill" : "heart"))
            glyph.shading = .color(full ? Self.heartColor : world.muted.opacity(0.45))
            context.draw(glyph, in: rect)
        }
    }
}
