//
//  SplitTutorial.swift
//  wits
//
//  Animated how-to-play demos for Split Second: the left half teaches the
//  flyer rhythm, the right half teaches the apple/tomato go-no-go choice, and
//  the final beat shows why neither side can be ignored. The miniature arena
//  mirrors the real neon divider, gates, paper plane, and emoji targets.
//

import SwiftUI

enum SplitTutorial {
    static let slides: [TutorialSlide] = [
        TutorialSlide(caption: "tap the left side to lift the flyer through the gates") {
            SplitDemo(page: .fly)
        },
        TutorialSlide(caption: "on the right, tap the apple before it fades — never tap the tomato") {
            SplitDemo(page: .pick)
        },
        TutorialSlide(caption: "watch both sides at once — one collision, wrong pick, or missed apple ends the run") {
            SplitDemo(page: .survive)
        },
    ]
}

private struct SplitDemo: View {
    enum Page { case fly, pick, survive }
    let page: Page

    private var world: GameWorld { GameID.split.world }

    var body: some View {
        DemoLoop(duration: page == .survive ? 6.0 : 5.2) { t in
            Canvas { context, size in
                render(context, size: size, t: t)
            }
        }
    }

    private struct Geo {
        let size: CGSize
        let arena: CGRect
        let dividerX: CGFloat
        let leftTap: CGPoint
        let apple: CGPoint
        let tomato: CGPoint

        init(size: CGSize) {
            self.size = size
            let inset = min(size.width, size.height) * 0.045
            arena = CGRect(x: inset, y: inset,
                           width: size.width - inset * 2,
                           height: size.height - inset * 2)
            dividerX = arena.midX
            leftTap = CGPoint(x: arena.minX + arena.width * 0.21,
                              y: arena.maxY - arena.height * 0.18)
            apple = CGPoint(x: arena.minX + arena.width * 0.73,
                            y: arena.minY + arena.height * 0.43)
            tomato = CGPoint(x: arena.minX + arena.width * 0.84,
                             y: arena.minY + arena.height * 0.70)
        }
    }

    private func render(_ context: GraphicsContext, size: CGSize, t: Double) {
        let geo = Geo(size: size)
        drawArena(context, geo: geo)
        drawGates(context, geo: geo, t: t)
        drawFlyer(context, geo: geo, t: t)

        switch page {
        case .fly:
            drawPickLegend(context, geo: geo, muted: true)
        case .pick:
            drawPickScene(context, geo: geo, t: t, appleTap: 1.55, fatal: false)
        case .survive:
            drawPickScene(context, geo: geo, t: t, appleTap: 2.05, fatal: true)
        }

        let taps = tapScript(geo: geo)
        for tap in taps {
            DemoEase.drawTapRipple(context, at: tap.point, start: tap.time, t: t,
                                   radius: geo.arena.width * 0.075,
                                   color: tap.point.x < geo.dividerX ? world.secondary : world.accent)
        }
        let hand = DemoEase.handAlongTaps(taps, t: t)
        DemoEase.drawHand(context,
                          tip: CGPoint(x: hand.tip.x + geo.arena.width * 0.012,
                                       y: hand.tip.y + geo.arena.width * 0.018),
                          size: geo.arena.width * 0.12,
                          pressed: hand.pressed,
                          alpha: hand.alpha)
    }

    private func tapScript(geo: Geo) -> [DemoEase.Tap] {
        switch page {
        case .fly:
            return [0.85, 2.15, 3.55].map { DemoEase.Tap(time: $0, point: geo.leftTap) }
        case .pick:
            return [DemoEase.Tap(time: 1.55, point: geo.apple)]
        case .survive:
            return [DemoEase.Tap(time: 0.85, point: geo.leftTap),
                    DemoEase.Tap(time: 2.05, point: geo.apple),
                    DemoEase.Tap(time: 3.15, point: geo.leftTap)]
        }
    }

    // MARK: - Arena

    private func drawArena(_ context: GraphicsContext, geo: Geo) {
        let outer = Path(roundedRect: geo.arena, cornerRadius: 14, style: .continuous)
        context.fill(outer, with: .color(Color(hexAny: 0x090713)))
        context.stroke(outer, with: .color(world.ink.opacity(0.10)), lineWidth: 1)

        let zoneInset = geo.arena.width * 0.025
        let left = CGRect(x: geo.arena.minX + zoneInset,
                          y: geo.arena.minY + zoneInset,
                          width: geo.arena.width / 2 - zoneInset * 1.5,
                          height: geo.arena.height - zoneInset * 2)
        let right = CGRect(x: geo.dividerX + zoneInset * 0.5,
                           y: geo.arena.minY + zoneInset,
                           width: geo.arena.width / 2 - zoneInset * 1.5,
                           height: geo.arena.height - zoneInset * 2)
        context.fill(Path(roundedRect: left, cornerRadius: 11, style: .continuous),
                     with: .color(.white.opacity(0.035)))
        context.fill(Path(roundedRect: right, cornerRadius: 11, style: .continuous),
                     with: .color(world.accent.opacity(0.035)))

        for row in 1..<5 {
            let y = geo.arena.minY + CGFloat(row) * geo.arena.height / 5
            var line = Path()
            line.move(to: CGPoint(x: geo.arena.minX + 7, y: y))
            line.addLine(to: CGPoint(x: geo.arena.maxX - 7, y: y))
            context.stroke(line, with: .color(.white.opacity(0.035)), lineWidth: 1)
        }

        var divider = Path()
        divider.move(to: CGPoint(x: geo.dividerX, y: geo.arena.minY + 8))
        divider.addLine(to: CGPoint(x: geo.dividerX, y: geo.arena.maxY - 8))
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: world.secondary.opacity(0.65), radius: 7))
            layer.stroke(divider, with: .color(world.secondary.opacity(0.82)),
                         style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 6]))
        }

        let labelSize = geo.arena.width * 0.032
        context.draw(Text("FLY")
            .font(.system(size: labelSize, weight: .heavy, design: .rounded))
            .foregroundColor(world.muted),
            at: CGPoint(x: geo.arena.minX + geo.arena.width * 0.07,
                        y: geo.arena.minY + geo.arena.height * 0.075))
        context.draw(Text("PICK")
            .font(.system(size: labelSize, weight: .heavy, design: .rounded))
            .foregroundColor(world.muted),
            at: CGPoint(x: geo.dividerX + geo.arena.width * 0.08,
                        y: geo.arena.minY + geo.arena.height * 0.075))
    }

    private func drawGates(_ context: GraphicsContext, geo: Geo, t: Double) {
        let phase = (t * (page == .survive ? 0.11 : 0.08)).truncatingRemainder(dividingBy: 1)
        let leftWidth = geo.arena.width / 2
        let gateW = geo.arena.width * 0.055
        let gateX = geo.dividerX - CGFloat(phase) * (leftWidth + gateW)
        let gapCenter = geo.arena.minY + geo.arena.height * 0.48
        let gapH = geo.arena.height * 0.37
        let top = CGRect(x: gateX, y: geo.arena.minY,
                         width: gateW, height: gapCenter - gapH / 2 - geo.arena.minY)
        let bottom = CGRect(x: gateX, y: gapCenter + gapH / 2,
                            width: gateW, height: geo.arena.maxY - gapCenter - gapH / 2)
        for rect in [top, bottom] {
            let path = Path(roundedRect: rect, cornerRadius: 7, style: .continuous)
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: world.secondary.opacity(0.55), radius: 7))
                layer.fill(path, with: .color(world.secondary.opacity(0.72)))
            }
        }
    }

    private func drawFlyer(_ context: GraphicsContext, geo: Geo, t: Double) {
        let flapTimes: [Double]
        switch page {
        case .fly: flapTimes = [0.85, 2.15, 3.55]
        case .pick: flapTimes = [0.45, 2.55, 4.3]
        case .survive: flapTimes = [0.85, 3.15, 4.55]
        }
        var lift = 0.0
        for beat in flapTimes {
            let up = DemoEase.ramp(t, beat, beat + 0.24)
            let down = DemoEase.ramp(t, beat + 0.24, beat + 1.05)
            lift += up * (1 - down)
        }
        let bob = sin(t * 2.2) * geo.arena.height * 0.015
        let center = CGPoint(x: geo.arena.minX + geo.arena.width * 0.16,
                             y: geo.arena.minY + geo.arena.height * 0.58
                                - CGFloat(lift) * geo.arena.height * 0.17 + bob)
        let side = geo.arena.width * 0.09
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: world.secondary.opacity(0.85), radius: 8))
            var plane = layer.resolve(Image(systemName: "paperplane.fill"))
            plane.shading = .color(.white)
            layer.draw(plane, in: CGRect(x: center.x - side / 2, y: center.y - side / 2,
                                         width: side, height: side))
        }
    }

    // MARK: - Pick side

    private func drawPickLegend(_ context: GraphicsContext, geo: Geo, muted: Bool) {
        let alpha = muted ? 0.28 : 1.0
        context.draw(Text("🍎")
            .font(.system(size: geo.arena.width * 0.095))
            .foregroundColor(.white.opacity(alpha)), at: geo.apple)
        context.draw(Text("🍅")
            .font(.system(size: geo.arena.width * 0.095))
            .foregroundColor(.white.opacity(alpha)), at: geo.tomato)
    }

    private func drawPickScene(_ context: GraphicsContext, geo: Geo, t: Double,
                               appleTap: Double, fatal: Bool) {
        let appleGone = DemoEase.ramp(t, appleTap + 0.05, appleTap + 0.32)
        if appleGone < 1 {
            var appleLayer = context
            appleLayer.opacity = 1 - appleGone
            appleLayer.draw(Text("🍎").font(.system(size: geo.arena.width * 0.105)),
                            at: geo.apple)
        } else if t < appleTap + 1.15 {
            let rise = DemoEase.ramp(t, appleTap + 0.15, appleTap + 0.8)
            context.draw(Text("+1")
                .font(.system(size: geo.arena.width * 0.045, weight: .black, design: .rounded))
                .foregroundColor(world.secondary.opacity(1 - rise)),
                at: CGPoint(x: geo.apple.x, y: geo.apple.y - CGFloat(rise) * geo.arena.height * 0.12))
        }

        let dangerPulse = 0.72 + 0.28 * sin(t * 4.2)
        context.draw(Text("🍅")
            .font(.system(size: geo.arena.width * 0.105))
            .foregroundColor(.white.opacity(dangerPulse)), at: geo.tomato)

        let ringRadius = geo.arena.width * 0.065
        context.stroke(Path(ellipseIn: CGRect(x: geo.tomato.x - ringRadius,
                                              y: geo.tomato.y - ringRadius,
                                              width: ringRadius * 2, height: ringRadius * 2)),
                       with: .color(world.accent.opacity(0.58)),
                       style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
        context.draw(Text("AVOID")
            .font(.system(size: geo.arena.width * 0.025, weight: .black, design: .rounded))
            .foregroundColor(world.accent),
            at: CGPoint(x: geo.tomato.x, y: geo.tomato.y + ringRadius * 1.3))

        guard fatal, t >= 4.45 else { return }
        let u = DemoEase.ramp(t, 4.45, 4.7)
        let banner = CGRect(x: geo.arena.minX + geo.arena.width * 0.16,
                            y: geo.arena.midY - geo.arena.height * 0.09,
                            width: geo.arena.width * 0.68,
                            height: geo.arena.height * 0.18)
        context.fill(Path(roundedRect: banner, cornerRadius: 8, style: .continuous),
                     with: .color(world.accent.opacity(0.92 * u)))
        context.draw(Text("ONE SLIP = RUN OVER")
            .font(.system(size: geo.arena.width * 0.038, weight: .black, design: .rounded))
            .foregroundColor(world.ink.opacity(u)), at: CGPoint(x: banner.midX, y: banner.midY))
    }
}
