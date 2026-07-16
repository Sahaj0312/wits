//
//  ArrowStormTutorial.swift
//  wits
//
//  Animated how-to-play demos for Arrow Storm on a mini trial screen: a row of
//  five arrows where only the middle one matters, a per-trial deadline bar that
//  drains faster as you score, and three hearts that a wrong tap or timeout
//  burns through. Everything renders like the real game — storm-yellow
//  monospaced world, heavy triangle glyphs, and the two answer buttons.
//

import SwiftUI

enum ArrowStormTutorial {
    static let slides: [TutorialSlide] = [
        TutorialSlide(caption: "only the middle arrow matters — tap the side it points, the flankers lie") {
            ArrowStormDemo(page: .answer)
        },
        TutorialSlide(caption: "beat the shrinking deadline — too slow counts as a miss") {
            ArrowStormDemo(page: .deadline)
        },
        TutorialSlide(caption: "every miss costs a heart — lose all three and the run ends") {
            ArrowStormDemo(page: .hearts)
        },
    ]
}

private struct ArrowStormDemo: View {
    enum Page { case answer, deadline, hearts }
    let page: Page

    private var world: GameWorld { GameID.arrowStorm.world }
    private static let heartColor = Color(hexAny: 0xEF476F)

    var body: some View {
        DemoLoop(duration: script.duration) { t in
            Canvas { context, size in
                render(context, size: size, t: t)
            }
        }
    }

    // MARK: Script

    private struct Trial {
        let right: Bool       // middle arrow direction
        let congruent: Bool   // flankers agree with the middle
        let start: Double     // arrows pop in
        let window: Double    // seconds for the deadline bar to empty
        let tapAt: Double
        let tapRight: Bool    // which answer button the hand presses
        var correct: Bool { tapRight == right }
    }

    private struct Script {
        let duration: Double
        let trials: [Trial]
        let livesAtStart: Int
        var pulseMiddle: Bool = false   // teaching ring around the center arrow
        var loseHeartAt: Double? = nil
        var runOverAt: Double? = nil
    }

    private var script: Script {
        switch page {
        case .answer:
            // Two incongruent trials, one each direction: the ring singles out
            // the middle arrow, then the hand answers RIGHT and LEFT.
            return Script(
                duration: 5.2,
                trials: [Trial(right: true, congruent: false, start: 0,
                               window: 5.0, tapAt: 1.9, tapRight: true),
                         Trial(right: false, congruent: false, start: 2.05,
                               window: 5.0, tapAt: 3.6, tapRight: false)],
                livesAtStart: 3,
                pulseMiddle: true)
        case .deadline:
            // The bar drains for real here — both answers land in the red
            // sliver, and the second trial's window is visibly tighter.
            return Script(
                duration: 5.4,
                trials: [Trial(right: true, congruent: false, start: 0.2,
                               window: 2.1, tapAt: 2.1, tapRight: true),
                         Trial(right: false, congruent: true, start: 2.25,
                               window: 1.5, tapAt: 3.55, tapRight: false)],
                livesAtStart: 3)
        case .hearts:
            // Last life, classic flanker trap (flankers RIGHT, middle LEFT):
            // the hand follows the crowd, the heart breaks, the run is over.
            return Script(
                duration: 5.6,
                trials: [Trial(right: false, congruent: false, start: 0,
                               window: 4.5, tapAt: 1.8, tapRight: true)],
                livesAtStart: 1,
                loseHeartAt: 1.85,
                runOverAt: 2.9)
        }
    }

    // MARK: Geometry

    private struct Geo {
        let size: CGSize
        let heartsY: CGFloat
        let heartSize: CGFloat
        let heartGap: CGFloat
        let card: CGRect
        let arrowSize: CGFloat
        let arrowGap: CGFloat
        let labelCenter: CGPoint
        let bar: CGRect
        let leftButton: CGRect
        let rightButton: CGRect

        init(size: CGSize) {
            self.size = size
            let w = size.width
            let h = size.height
            let margin = w * 0.05
            heartsY = h * 0.075
            heartSize = w * 0.062
            heartGap = w * 0.026
            card = CGRect(x: margin, y: h * 0.15, width: w - margin * 2, height: h * 0.30)
            arrowSize = card.width * 0.085
            arrowGap = card.width * 0.048
            labelCenter = CGPoint(x: w / 2, y: card.maxY + h * 0.05)
            bar = CGRect(x: (w - w * 0.42) / 2, y: labelCenter.y + h * 0.045,
                         width: w * 0.42, height: max(3, h * 0.013))
            let buttonHeight = h * 0.145
            let buttonGap = w * 0.03
            let buttonWidth = (w - margin * 2 - buttonGap) / 2
            leftButton = CGRect(x: margin, y: h * 0.76, width: buttonWidth, height: buttonHeight)
            rightButton = CGRect(x: margin + buttonWidth + buttonGap, y: h * 0.76,
                                 width: buttonWidth, height: buttonHeight)
        }

        func arrowCenter(_ index: Int) -> CGPoint {
            let step = arrowSize + arrowGap
            let x = card.midX + (CGFloat(index) - 2) * step
            return CGPoint(x: x, y: card.midY)
        }

        func button(_ right: Bool) -> CGRect { right ? rightButton : leftButton }
    }

    // MARK: Render

    private func render(_ context: GraphicsContext, size: CGSize, t: Double) {
        let geo = Geo(size: size)
        let s = script
        let current = s.trials.last { $0.start <= t } ?? s.trials[0]

        drawHearts(context, geo: geo, script: s, t: t)
        drawCard(context, geo: geo, script: s, trial: current, t: t)
        drawBar(context, geo: geo, script: s, trial: current, t: t)
        drawButtons(context, geo: geo, script: s, t: t)
        drawScorePops(context, geo: geo, script: s, t: t)
        drawRunOver(context, geo: geo, script: s, t: t)

        for trial in s.trials {
            DemoEase.drawTapRipple(context, at: geo.button(trial.tapRight).center,
                                   start: trial.tapAt, t: t,
                                   radius: geo.leftButton.height * 0.72,
                                   color: trial.correct ? world.accent : world.secondary)
        }
        let hand = DemoEase.handAlongTaps(
            s.trials.map { DemoEase.Tap(time: $0.tapAt, point: geo.button($0.tapRight).center) },
            t: t)
        DemoEase.drawHand(context, tip: hand.tip,
                          size: geo.leftButton.height * 0.95,
                          pressed: hand.pressed, alpha: hand.alpha)
    }

    // MARK: Hearts

    private func drawHearts(_ context: GraphicsContext, geo: Geo, script: Script, t: Double) {
        let lossU = script.loseHeartAt.map { DemoEase.ramp(t, $0, $0 + 0.3) } ?? 0
        let totalX = CGFloat(3) * geo.heartSize + 2 * geo.heartGap
        for i in 0..<3 {
            let center = CGPoint(x: (geo.size.width - totalX) / 2 + geo.heartSize / 2
                                    + CGFloat(i) * (geo.heartSize + geo.heartGap),
                                 y: geo.heartsY)
            let filled = i < script.livesAtStart
            // The breaking heart pops as it crossfades from filled to empty.
            let breaking = filled && i == script.livesAtStart - 1 && lossU > 0
            let pop = breaking ? 1 + 0.3 * sin(.pi * lossU) : 1
            if breaking {
                drawHeart(context, at: center, size: geo.heartSize * pop,
                          filled: true, alpha: 1 - lossU)
                drawHeart(context, at: center, size: geo.heartSize * 0.88 * pop,
                          filled: false, alpha: lossU)
            } else {
                drawHeart(context, at: center,
                          size: geo.heartSize * (filled ? 1 : 0.88),
                          filled: filled, alpha: 1)
            }
        }
    }

    private func drawHeart(_ context: GraphicsContext, at center: CGPoint,
                           size: CGFloat, filled: Bool, alpha: Double) {
        guard alpha > 0.01 else { return }
        let color = filled ? Self.heartColor : world.muted.opacity(0.45)
        drawGlyph(context, systemName: filled ? "heart.fill" : "heart",
                  at: center, height: size, color: color.opacity(alpha))
    }

    /// Symbols must go through a resolved image (Text-wrapped images don't
    /// survive Canvas snapshotting) — draw fitted to `height`, keeping aspect.
    private func drawGlyph(_ context: GraphicsContext, systemName: String,
                           at center: CGPoint, height: CGFloat, color: Color) {
        var glyph = context.resolve(Image(systemName: systemName))
        glyph.shading = .color(color)
        let natural = glyph.size
        let width = natural.height > 0 ? height * natural.width / natural.height : height
        context.draw(glyph, in: CGRect(x: center.x - width / 2, y: center.y - height / 2,
                                       width: width, height: height))
    }

    // MARK: Trial card

    private func drawCard(_ context: GraphicsContext, geo: Geo, script: Script,
                          trial: Trial, t: Double) {
        let radius = geo.size.width * 0.02
        let cardPath = Path(roundedRect: geo.card, cornerRadius: radius, style: .continuous)
        context.fill(cardPath, with: .color(world.surface))
        context.stroke(cardPath, with: .color(world.ink.opacity(0.12)), lineWidth: 1)

        // Arrows pop in with the real game's quick scale+fade transition.
        let appear = trial.start == 0 ? 1 : DemoEase.ramp(t, trial.start, trial.start + 0.2)
        let scale = 0.92 + 0.08 * appear
        for i in 0..<5 {
            let isCenter = i == 2
            let pointsRight = isCenter ? trial.right : (trial.congruent ? trial.right : !trial.right)
            drawGlyph(context,
                      systemName: pointsRight ? "arrowtriangle.right.fill" : "arrowtriangle.left.fill",
                      at: geo.arrowCenter(i),
                      height: geo.arrowSize * scale,
                      color: world.ink.opacity(appear))
        }

        // Teaching ring: breathe around the middle arrow before the first tap.
        if script.pulseMiddle {
            let ringU = DemoEase.ramp(t, 0.3, 0.6) * (1 - DemoEase.ramp(t, 1.55, 1.9))
            if ringU > 0.01 {
                let breathe = geo.arrowSize * (0.32 + 0.05 * sin(t * 7))
                let center = geo.arrowCenter(2)
                let half = geo.arrowSize / 2 + breathe
                let ring = CGRect(x: center.x - half, y: center.y - half,
                                  width: half * 2, height: half * 2)
                context.stroke(Path(roundedRect: ring, cornerRadius: geo.arrowSize * 0.32,
                                    style: .continuous),
                               with: .color(world.accent.opacity(0.9 * ringU)),
                               lineWidth: 2.5)
            }
        }

        // Answer feedback border, accent for correct and secondary for wrong.
        for answered in script.trials {
            let flash = DemoEase.ramp(t, answered.tapAt, answered.tapAt + 0.12)
                * (1 - DemoEase.ramp(t, answered.tapAt + 0.5, answered.tapAt + 0.9))
            guard flash > 0.01 else { continue }
            let border = geo.card.insetBy(dx: -geo.size.width * 0.028,
                                          dy: -geo.size.width * 0.028)
            context.stroke(Path(roundedRect: border, cornerRadius: radius,
                                style: .continuous),
                           with: .color((answered.correct ? world.accent : world.secondary)
                                            .opacity(flash)),
                           lineWidth: 2.5)
        }

        context.draw(Text("THE MIDDLE ONE")
                        .font(.system(size: geo.size.width * 0.034, weight: .bold, design: .monospaced))
                        .kerning(0.7)
                        .foregroundColor(world.muted),
                     at: geo.labelCenter)
    }

    // MARK: Deadline bar

    private func drawBar(_ context: GraphicsContext, geo: Geo, script: Script,
                         trial: Trial, t: Double) {
        // Drains until the answer lands; a mistake freezes it (the run ends),
        // a correct answer resets it for the next trial.
        let clock = min(t, trial.tapAt)
        var frac = max(0, 1 - (clock - trial.start) / trial.window)
        if t >= trial.tapAt, trial.correct { frac = 1 }
        context.fill(Path(roundedRect: geo.bar, cornerRadius: geo.bar.height / 2),
                     with: .color(world.surface))
        if frac > 0 {
            var fill = geo.bar
            fill.size.width = geo.bar.width * CGFloat(frac)
            context.fill(Path(roundedRect: fill, cornerRadius: geo.bar.height / 2),
                         with: .color(frac < 0.35 ? world.secondary : world.muted))
        }
    }

    // MARK: Answer buttons

    private func drawButtons(_ context: GraphicsContext, geo: Geo, script: Script, t: Double) {
        let radius = geo.size.width * 0.018
        for right in [false, true] {
            var rect = geo.button(right)
            let pressed = script.trials.contains {
                $0.tapRight == right && t >= $0.tapAt && t < $0.tapAt + 0.18
            }
            if pressed { rect = rect.insetBy(dx: rect.height * 0.04, dy: rect.height * 0.04) }
            let path = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
            context.fill(path, with: .color(right ? world.accent : world.surface))
            if !right {
                context.stroke(path, with: .color(world.ink.opacity(0.12)), lineWidth: 1)
            }
            if pressed { context.fill(path, with: .color(.white.opacity(0.22))) }
            drawGlyph(context,
                      systemName: right ? "arrowtriangle.right.fill" : "arrowtriangle.left.fill",
                      at: rect.center,
                      height: rect.height * 0.34,
                      color: right ? world.background : world.ink)
        }
    }

    // MARK: Juice

    private func drawScorePops(_ context: GraphicsContext, geo: Geo, script: Script, t: Double) {
        for trial in script.trials where trial.correct {
            let u = DemoEase.ramp(t, trial.tapAt, trial.tapAt + 0.8)
            guard u > 0, u < 1 else { continue }
            let alpha = min(1, u * 4) * (1 - DemoEase.ramp(t, trial.tapAt + 0.5, trial.tapAt + 0.8))
            let y = DemoEase.lerp(geo.card.minY + geo.size.height * 0.045,
                                  geo.card.minY - geo.size.height * 0.035, u)
            context.drawLayer { layer in
                layer.opacity = alpha
                layer.addFilter(.shadow(color: .black.opacity(0.5), radius: 3, y: 2))
                layer.draw(Text("+1")
                            .font(.system(size: geo.size.width * 0.065, weight: .black, design: .monospaced))
                            .foregroundColor(world.accent),
                           at: CGPoint(x: geo.card.maxX - geo.size.width * 0.09, y: y))
            }
        }
    }

    private func drawRunOver(_ context: GraphicsContext, geo: Geo, script: Script, t: Double) {
        guard let at = script.runOverAt else { return }
        let u = DemoEase.ramp(t, at, at + 0.45)
        guard u > 0 else { return }
        context.fill(Path(CGRect(origin: .zero, size: geo.size)),
                     with: .color(.black.opacity(0.38 * u)))

        let badge = CGRect(x: geo.card.midX - geo.card.width * 0.31,
                           y: geo.card.midY - geo.size.height * 0.048,
                           width: geo.card.width * 0.62,
                           height: geo.size.height * 0.096)
        context.drawLayer { layer in
            layer.opacity = u
            layer.addFilter(.shadow(color: .black.opacity(0.45), radius: 8, y: 5))
            layer.fill(Path(roundedRect: badge, cornerRadius: badge.height / 2, style: .continuous),
                       with: .color(world.background.opacity(0.95)))
            layer.stroke(Path(roundedRect: badge, cornerRadius: badge.height / 2, style: .continuous),
                         with: .color(world.secondary.opacity(0.9)), lineWidth: 2)
            layer.draw(Text("RUN OVER")
                        .font(.system(size: badge.height * 0.42, weight: .black, design: .monospaced))
                        .foregroundColor(world.ink),
                       at: CGPoint(x: badge.midX, y: badge.midY))
        }
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
