//
//  ColorClashTutorial.swift
//  wits
//
//  Animated how-to-play demos for Color Clash: a colour word drawn in a
//  clashing ink, four colour buttons below, a shrinking deadline bar and three
//  hearts. Slide 1 lands the core trick (answer with the ink), slide 2 races
//  the deadline, slide 3 falls into the word trap and pays a heart for it.
//

import SwiftUI

enum ColorClashTutorial {
    static let slides: [TutorialSlide] = [
        TutorialSlide(caption: "tap the colour of the ink, not what the word says") {
            ColorClashDemo(page: .ink)
        },
        TutorialSlide(caption: "beat the shrinking deadline — too slow counts as a miss") {
            ColorClashDemo(page: .deadline)
        },
        TutorialSlide(caption: "tapping the word costs a heart — lose all three and the run ends") {
            ColorClashDemo(page: .trap)
        },
    ]
}

private struct ColorClashDemo: View {
    enum Page { case ink, deadline, trap }
    let page: Page

    private var world: GameWorld { GameID.colorClash.world }

    /// Trial palette copied from StroopColor in ColorClash.swift so the demo
    /// words and buttons match the real game exactly.
    private enum Hue: String, CaseIterable {
        case red, blue, green, yellow
        var color: Color {
            switch self {
            case .red: Color(red: 0.91, green: 0.26, blue: 0.27)
            case .blue: Color(red: 0.20, green: 0.52, blue: 0.95)
            case .green: Color(red: 0.16, green: 0.70, blue: 0.46)
            case .yellow: Color(red: 0.95, green: 0.74, blue: 0.16)
            }
        }
    }

    private static let heartColor = Color(red: 0xEF / 255.0, green: 0x47 / 255.0, blue: 0x6F / 255.0)

    var body: some View {
        DemoLoop(duration: script.duration) { t in
            Canvas { context, size in
                render(context, size: size, t: t)
            }
        }
    }

    // MARK: Script

    private struct Trial {
        let word: Hue
        let ink: Hue
    }

    private struct Script {
        let duration: Double
        let first: Trial
        /// Replacement trial after a correct answer, so the loop reads as an
        /// endless run rather than a single frozen question.
        var next: Trial? = nil
        var swapAt: Double? = nil
        let tapTime: Double
        let tapHue: Hue      // button the hand presses
        let correct: Bool
        let barStart: Double // deadline starts draining
        let barEnd: Double   // time at which the bar would hit empty
        var hintRing: Hue? = nil // trap page: circle the answer that was missed
    }

    private var script: Script {
        switch page {
        case .ink:
            // "blue" in green ink — the hand ignores the word and taps GREEN.
            return Script(duration: 5.0,
                          first: Trial(word: .blue, ink: .green),
                          next: Trial(word: .red, ink: .blue),
                          swapAt: 2.6,
                          tapTime: 1.7, tapHue: .green, correct: true,
                          barStart: 0.4, barEnd: 7.0)
        case .deadline:
            // Same trick, but the bar nearly runs dry before the answer lands.
            return Script(duration: 5.4,
                          first: Trial(word: .red, ink: .yellow),
                          next: Trial(word: .green, ink: .blue),
                          swapAt: 3.7,
                          tapTime: 3.0, tapHue: .yellow, correct: true,
                          barStart: 0.5, barEnd: 3.4)
        case .trap:
            // "green" in red ink — the hand falls for the word and taps GREEN.
            return Script(duration: 5.6,
                          first: Trial(word: .green, ink: .red),
                          tapTime: 1.9, tapHue: .green, correct: false,
                          barStart: 0.5, barEnd: 7.5,
                          hintRing: .red)
        }
    }

    // MARK: Geometry

    private struct Geo {
        let size: CGSize
        let heartsCenterY: CGFloat
        let heartSize: CGFloat
        let card: CGRect
        let hintY: CGFloat
        let bar: CGRect
        let buttons: [CGRect] // Hue.allCases order

        init(size: CGSize) {
            self.size = size
            let w = size.width
            let h = size.height
            heartSize = w * 0.058
            heartsCenterY = h * 0.075
            card = CGRect(x: w * 0.10, y: h * 0.155, width: w * 0.80, height: h * 0.315)
            hintY = card.maxY + h * 0.048
            // Chunkier than the real game's 4pt bar so the deadline lesson
            // reads at tutorial size.
            let barWidth = w * 0.42
            let barHeight = h * 0.021
            bar = CGRect(x: (w - barWidth) / 2, y: hintY + h * 0.042,
                         width: barWidth, height: barHeight)
            let inset = w * 0.10
            let gap = w * 0.032
            let bw = (w - inset * 2 - gap) / 2
            let bh = h * 0.105
            let topY = h * 0.705
            buttons = (0..<4).map { i in
                CGRect(x: inset + CGFloat(i % 2) * (bw + gap),
                       y: topY + CGFloat(i / 2) * (bh + gap),
                       width: bw, height: bh)
            }
        }

        func button(_ hue: Hue) -> CGRect {
            buttons[Hue.allCases.firstIndex(of: hue)!]
        }
    }

    // MARK: Render

    private func render(_ context: GraphicsContext, size: CGSize, t: Double) {
        let geo = Geo(size: size)
        let s = script

        drawHearts(context, geo: geo, s: s, t: t)
        drawCard(context, geo: geo, s: s, t: t)
        drawDeadlineBar(context, geo: geo, s: s, t: t)
        drawButtons(context, geo: geo, s: s, t: t)

        let tapPoint = CGPoint(x: geo.button(s.tapHue).midX, y: geo.button(s.tapHue).midY)
        DemoEase.drawTapRipple(context, at: tapPoint, start: s.tapTime, t: t,
                               radius: geo.button(s.tapHue).height * 0.75,
                               color: s.correct ? world.secondary : world.accent)
        let hand = DemoEase.handAlongTaps([DemoEase.Tap(time: s.tapTime, point: tapPoint)], t: t)
        DemoEase.drawHand(context,
                          tip: CGPoint(x: hand.tip.x + geo.button(s.tapHue).height * 0.10,
                                       y: hand.tip.y + geo.button(s.tapHue).height * 0.16),
                          size: geo.button(s.tapHue).height * 1.15,
                          pressed: hand.pressed, alpha: hand.alpha)
    }

    private func drawHearts(_ context: GraphicsContext, geo: Geo, s: Script, t: Double) {
        // On the trap page the last heart empties just after the wrong tap.
        let lossAt = s.correct ? Double.infinity : s.tapTime + 0.15
        let spacing = geo.heartSize * 1.55
        for i in 0..<3 {
            let lost = !s.correct && i == 2 && t >= lossAt
            let pop = (!s.correct && i == 2)
                ? 1 + 0.45 * DemoEase.ramp(t, lossAt, lossAt + 0.12) * (1 - DemoEase.ramp(t, lossAt + 0.12, lossAt + 0.4))
                : 1
            let center = CGPoint(x: geo.size.width / 2 + (CGFloat(i) - 1) * spacing,
                                 y: geo.heartsCenterY)
            let side = geo.heartSize * CGFloat(pop) * (lost ? 0.88 : 1)
            var glyph = context.resolve(Image(systemName: lost ? "heart" : "heart.fill"))
            glyph.shading = .color(lost ? world.muted.opacity(0.45) : Self.heartColor)
            context.draw(glyph, in: CGRect(x: center.x - side / 2, y: center.y - side / 2,
                                           width: side, height: side))
        }
    }

    private func drawCard(_ context: GraphicsContext, geo: Geo, s: Script, t: Double) {
        // Miss feedback shakes the card the way a slap of red border should.
        var shakeX: CGFloat = 0
        if !s.correct, t > s.tapTime {
            let decay = 1 - DemoEase.ramp(t, s.tapTime, s.tapTime + 0.4)
            shakeX = CGFloat(sin((t - s.tapTime) * 42) * decay) * geo.size.width * 0.013
        }

        context.drawLayer { layer in
            layer.translateBy(x: shakeX, y: 0)
            let path = Path(roundedRect: geo.card, cornerRadius: geo.card.height * 0.09,
                            style: .continuous)
            layer.drawLayer { shadowed in
                shadowed.addFilter(.shadow(color: .black.opacity(0.10), radius: 5, y: 3))
                shadowed.fill(path, with: .color(world.surface))
            }
            layer.stroke(path, with: .color(world.ink.opacity(0.12)), lineWidth: 1.2)

            // Crossfade to the follow-up trial after a correct answer.
            let swapU = s.swapAt.map { DemoEase.ramp(t, $0, $0 + 0.28) } ?? 0
            let wordSize = geo.card.height * 0.37
            let center = CGPoint(x: geo.card.midX, y: geo.card.midY)
            if swapU < 1 {
                layer.opacity = 1 - swapU
                layer.draw(word(s.first, size: wordSize), at: center)
            }
            if swapU > 0, let next = s.next {
                layer.opacity = swapU
                layer.draw(word(next, size: wordSize * (0.9 + 0.1 * CGFloat(swapU))), at: center)
            }
            layer.opacity = 1

            // Feedback border: teal for a hit, world pink for a miss — the
            // miss border lingers so the lesson lands.
            let holdOut = s.correct ? s.tapTime + 0.75 : s.tapTime + 2.6
            let flash = DemoEase.ramp(t, s.tapTime, s.tapTime + 0.12)
                * (1 - DemoEase.ramp(t, holdOut, holdOut + 0.5))
            if flash > 0 {
                let border = Path(roundedRect: geo.card.insetBy(dx: -9, dy: -9),
                                  cornerRadius: geo.card.height * 0.11, style: .continuous)
                layer.stroke(border,
                             with: .color((s.correct ? world.secondary : world.accent).opacity(flash)),
                             lineWidth: 3)
            }
        }

        context.draw(Text("TAP THE COLOUR, NOT THE WORD")
                        .font(.system(size: geo.size.width * 0.031, weight: .bold, design: .rounded))
                        .kerning(0.7)
                        .foregroundColor(world.muted),
                     at: CGPoint(x: geo.size.width / 2, y: geo.hintY))

        // Rising +1 for the correct answer.
        if s.correct {
            let rise = DemoEase.ramp(t, s.tapTime + 0.05, s.tapTime + 0.8)
            let fade = DemoEase.ramp(t, s.tapTime, s.tapTime + 0.12)
                * (1 - DemoEase.ramp(t, s.tapTime + 0.65, s.tapTime + 1.0))
            if fade > 0 {
                context.draw(Text("+1")
                                .font(.system(size: geo.size.width * 0.075, weight: .heavy, design: .rounded))
                                .foregroundColor(world.secondary.opacity(fade)),
                             at: CGPoint(x: geo.card.maxX - geo.size.width * 0.03,
                                         y: geo.card.minY - geo.size.height * 0.038
                                             - CGFloat(rise) * geo.size.height * 0.05))
            }
        }
    }

    private func word(_ trial: Trial, size: CGFloat) -> Text {
        Text(trial.word.rawValue)
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .foregroundColor(trial.ink.color)
    }

    private func drawDeadlineBar(_ context: GraphicsContext, geo: Geo, s: Script, t: Double) {
        let span = s.barEnd - s.barStart
        var frac: Double
        if let swapAt = s.swapAt, t >= swapAt {
            frac = max(0, 1 - (t - swapAt) / span) // fresh trial, fresh clock
        } else {
            frac = max(0, 1 - max(0, min(t, s.tapTime) - s.barStart) / span)
        }
        context.fill(Path(roundedRect: geo.bar, cornerRadius: geo.bar.height / 2),
                     with: .color(world.raised))
        if frac > 0 {
            var fill = geo.bar
            fill.size.width = geo.bar.width * CGFloat(frac)
            // Low-time pulse: the real bar just turns pink, the demo breathes a
            // little so the eye lands on the urgency.
            let low = frac < 0.35
            let pulse = low ? 0.75 + 0.25 * abs(sin(t * 6)) : 1
            context.fill(Path(roundedRect: fill, cornerRadius: geo.bar.height / 2),
                         with: .color((low ? world.accent : world.muted).opacity(pulse)))
        }
    }

    private func drawButtons(_ context: GraphicsContext, geo: Geo, s: Script, t: Double) {
        let pressed = t >= s.tapTime && t < s.tapTime + 0.18
        for hue in Hue.allCases {
            var rect = geo.button(hue)
            if hue == s.tapHue, pressed {
                rect = rect.insetBy(dx: rect.width * 0.02, dy: rect.height * 0.05)
            }
            let path = Path(roundedRect: rect, cornerRadius: 7, style: .continuous)
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.12), radius: 3, y: 2))
                layer.fill(path, with: .color(hue.color))
            }
            if hue == s.tapHue {
                let hit = DemoEase.ramp(t, s.tapTime, s.tapTime + 0.1)
                    * (1 - DemoEase.ramp(t, s.tapTime + 0.35, s.tapTime + 0.7))
                if hit > 0 { context.fill(path, with: .color(.white.opacity(0.3 * hit))) }
            }
            context.draw(Text(hue.rawValue)
                            .font(.system(size: rect.height * 0.40, weight: .heavy, design: .rounded))
                            .foregroundColor(.white),
                         at: CGPoint(x: rect.midX, y: rect.midY))

            // After the trap, pulse a ring on the button that matched the ink.
            if let hint = s.hintRing, hue == hint {
                let show = DemoEase.ramp(t, s.tapTime + 0.8, s.tapTime + 1.15)
                if show > 0 {
                    let pulse = 0.55 + 0.45 * abs(sin((t - s.tapTime) * 3.2))
                    let ring = Path(roundedRect: rect.insetBy(dx: -5, dy: -5),
                                    cornerRadius: 10, style: .continuous)
                    context.stroke(ring,
                                   with: .color(world.secondary.opacity(show * pulse)),
                                   lineWidth: 3)
                }
            }
        }
    }
}
