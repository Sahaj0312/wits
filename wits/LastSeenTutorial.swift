//
//  LastSeenTutorial.swift
//  wits
//
//  Animated how-to-play demos for Last Seen on a mini 3×2 board: tap an
//  object you haven't chosen yet for a point, watch the board reshuffle
//  after every pick, and see a repeat tap cost a heart. Tiles render like
//  the real game, cream cards with heavy ink glyphs, blue flash for a new
//  pick, red-orange flash for a repeat.
//

import SwiftUI

enum LastSeenTutorial {
    static let slides: [TutorialSlide] = [
        TutorialSlide(caption: "tap an object you haven't chosen yet. every new one is a point") {
            LastSeenDemo(page: .pick)
        },
        TutorialSlide(caption: "the board reshuffles after each pick. clear the whole set and it grows") {
            LastSeenDemo(page: .reshuffle)
        },
        TutorialSlide(caption: "tapping a repeat costs a heart. lose all three and the run ends") {
            LastSeenDemo(page: .mistake)
        },
    ]
}

private struct LastSeenDemo: View {
    enum Page { case pick, reshuffle, mistake }
    let page: Page

    // Same pool the real board draws from, in the real tile treatment.
    private static let icons = ["star.fill", "heart.fill", "bolt.fill",
                                "leaf.fill", "flame.fill", "drop.fill"]
    private static let shuffleTime = 0.55
    private static let heartColor = Color(hexAny: 0xEF476F)

    private var world: GameWorld { GameID.lastSeen.world }

    var body: some View {
        DemoLoop(duration: script.duration) { t in
            Canvas { context, size in
                render(context, size: size, t: t)
            }
        }
    }

    // MARK: Script

    private struct TapBeat {
        let time: Double
        let icon: Int
        let ok: Bool
    }

    private struct Script {
        let duration: Double
        /// stage → icon index → cell index; shuffles[k] animates stage k → k+1.
        let stages: [[Int]]
        let shuffles: [Double]
        let taps: [TapBeat]
        let foundStart: Int
        /// Icons chosen on earlier (implied) picks, ghost-echoed on a mistake.
        var picked: [Int] = []
        var heartLossAt: Double? = nil
    }

    private var script: Script {
        switch page {
        case .pick:
            // Tap the star on the bottom row, then everything moves.
            return Script(
                duration: 4.8,
                stages: [[4, 0, 1, 2, 5, 3],
                         [0, 2, 5, 3, 1, 4]],
                shuffles: [2.1],
                taps: [TapBeat(time: 1.3, icon: 0, ok: true)],
                foundStart: 0)
        case .reshuffle:
            // Two picks, two reshuffles, the memory load is the same objects
            // landing in new places.
            return Script(
                duration: 6.0,
                stages: [[0, 2, 5, 3, 1, 4],
                         [2, 0, 1, 4, 3, 5],
                         [4, 1, 0, 2, 5, 3]],
                shuffles: [1.75, 3.85],
                taps: [TapBeat(time: 1.1, icon: 2, ok: true),
                       TapBeat(time: 3.2, icon: 3, ok: true)],
                foundStart: 1)
        case .mistake:
            // The star was already chosen, tapping it again flashes red,
            // echoes the other past picks, and breaks a heart.
            return Script(
                duration: 5.4,
                stages: [[4, 0, 2, 1, 5, 3],
                         [1, 3, 0, 5, 2, 4]],
                shuffles: [2.7],
                taps: [TapBeat(time: 1.4, icon: 0, ok: false)],
                foundStart: 3,
                picked: [4, 5],
                heartLossAt: 1.55)
        }
    }

    // MARK: Geometry

    private struct Geo {
        let size: CGSize
        let cell: CGFloat
        let gap: CGFloat
        let origin: CGPoint
        let heartsY: CGFloat
        let counterY: CGFloat

        init(size: CGSize) {
            self.size = size
            let side = min(size.width, size.height)
            cell = side * 0.272
            gap = cell * 0.13
            let gridW = 3 * cell + 2 * gap
            let gridH = 2 * cell + gap
            origin = CGPoint(x: (size.width - gridW) / 2,
                             y: (size.height - gridH) / 2 + side * 0.015)
            heartsY = origin.y - side * 0.105
            counterY = origin.y + gridH + side * 0.085
        }

        func center(_ cellIndex: Int) -> CGPoint {
            let row = CGFloat(cellIndex / 3)
            let col = CGFloat(cellIndex % 3)
            return CGPoint(x: origin.x + col * (cell + gap) + cell / 2,
                           y: origin.y + row * (cell + gap) + cell / 2)
        }
    }

    // MARK: Render

    private func render(_ context: GraphicsContext, size: CGSize, t: Double) {
        let geo = Geo(size: size)
        let script = script

        for icon in Self.icons.indices {
            let (center, lift) = position(of: icon, t: t, script: script, geo: geo)
            let tap = script.taps.first { $0.icon == icon }
            let flash = tap.map { flashU(t, $0.time) } ?? 0
            let echo = script.picked.contains(icon) ? echoU(t, script: script) : 0
            drawTile(context, icon: icon, center: center, geo: geo,
                     flash: flash, ok: tap?.ok ?? true, lift: lift, echo: echo)
        }

        for tap in script.taps {
            let point = position(of: tap.icon, t: tap.time, script: script, geo: geo).point
            DemoEase.drawTapRipple(context, at: point, start: tap.time, t: t,
                                   radius: geo.cell * 0.60,
                                   color: tap.ok ? world.secondary : world.accent)
            if tap.ok {
                drawPlusOne(context, at: point, start: tap.time, t: t, geo: geo)
            }
        }

        drawHearts(context, geo: geo, t: t, script: script)
        drawCounter(context, geo: geo, t: t, script: script)

        let hand = DemoEase.handAlongTaps(
            script.taps.map {
                DemoEase.Tap(time: $0.time,
                             point: position(of: $0.icon, t: $0.time, script: script, geo: geo).point)
            }, t: t)
        DemoEase.drawHand(context,
                          tip: CGPoint(x: hand.tip.x + geo.cell * 0.08,
                                       y: hand.tip.y + geo.cell * 0.14),
                          size: geo.cell * 0.95, pressed: hand.pressed, alpha: hand.alpha)
    }

    /// Where an icon sits at time t, plus a 0..1 "lift" while it's mid-shuffle.
    private func position(of icon: Int, t: Double, script: Script,
                          geo: Geo) -> (point: CGPoint, lift: Double) {
        var point = geo.center(script.stages[0][icon])
        var lift = 0.0
        for (k, start) in script.shuffles.enumerated() {
            let u = DemoEase.ramp(t, start, start + Self.shuffleTime)
            if u > 0 {
                point = DemoEase.lerp(geo.center(script.stages[k][icon]),
                                      geo.center(script.stages[k + 1][icon]), u)
            }
            lift = max(lift, sin(.pi * u))
        }
        return (point, lift)
    }

    private func flashU(_ t: Double, _ tapTime: Double) -> Double {
        DemoEase.ramp(t, tapTime, tapTime + 0.12)
            * (1 - DemoEase.ramp(t, tapTime + 0.50, tapTime + 0.80))
    }

    /// Ghost-highlight on previously picked tiles while the mistake flashes,
    /// so "you already chose these" reads without any persistent marker.
    private func echoU(_ t: Double, script: Script) -> Double {
        guard let tap = script.taps.first(where: { !$0.ok }) else { return 0 }
        return DemoEase.ramp(t, tap.time + 0.05, tap.time + 0.30)
            * (1 - DemoEase.ramp(t, tap.time + 0.85, tap.time + 1.25))
    }

    private func drawTile(_ context: GraphicsContext, icon: Int, center: CGPoint,
                          geo: Geo, flash: Double, ok: Bool, lift: Double, echo: Double) {
        let side = geo.cell * (1 + 0.06 * CGFloat(lift))
        let rect = CGRect(x: center.x - side / 2, y: center.y - side / 2,
                          width: side, height: side)
        let path = Path(roundedRect: rect, cornerRadius: side * 0.085, style: .continuous)

        context.drawLayer { layer in
            layer.addFilter(.shadow(color: world.ink.opacity(0.12 + 0.10 * lift),
                                    radius: 4 + 3 * lift, y: 2 + 2 * lift))
            layer.fill(path, with: .color(world.surface))
        }
        if flash > 0 {
            context.fill(path, with: .color((ok ? world.secondary : world.accent)
                .opacity(0.88 * flash)))
        }
        if echo > 0 {
            context.fill(path, with: .color(world.accent.opacity(0.12 * echo)))
            let inner = rect.insetBy(dx: side * 0.05, dy: side * 0.05)
            context.stroke(Path(roundedRect: inner, cornerRadius: side * 0.07, style: .continuous),
                           with: .color(world.accent.opacity(0.55 * echo)), lineWidth: 2)
        }

        let glyph = Text(Image(systemName: Self.icons[icon]))
            .font(.system(size: side * 0.30, weight: .heavy))
        context.draw(glyph.foregroundColor(world.ink.opacity(1 - flash)), at: center)
        if flash > 0 {
            context.draw(glyph.foregroundColor(world.background.opacity(flash)), at: center)
        }
    }

    private func drawPlusOne(_ context: GraphicsContext, at point: CGPoint,
                             start: Double, t: Double, geo: Geo) {
        let u = DemoEase.ramp(t, start, start + 0.95)
        guard u > 0, u < 1 else { return }
        let alpha = min(1, u * 4) * (1 - DemoEase.ramp(u, 0.60, 1))
        let center = CGPoint(x: point.x, y: point.y - geo.cell * 1.05 * CGFloat(u))
        let text = Text("+1")
            .font(.system(size: geo.cell * 0.42, weight: .black, design: world.titleDesign))
            .foregroundColor(world.secondary)
        context.drawLayer { layer in
            layer.opacity = alpha
            layer.addFilter(.shadow(color: world.background.opacity(0.9), radius: 3))
            layer.draw(text, at: center)
        }
    }

    private func drawHearts(_ context: GraphicsContext, geo: Geo, t: Double, script: Script) {
        let size = geo.cell * 0.30
        let spacing = size * 1.55
        for index in 0..<3 {
            let center = CGPoint(x: geo.size.width / 2 + CGFloat(index - 1) * spacing,
                                 y: geo.heartsY)
            // Only the last heart ever breaks in the demo.
            let lossU = (index == 2 && script.heartLossAt != nil)
                ? DemoEase.ramp(t, script.heartLossAt!, script.heartLossAt! + 0.40) : 0
            if lossU < 1 {
                let pop = 1 + 0.35 * sin(.pi * lossU)
                drawHeart(context, symbol: "heart.fill", color: Self.heartColor,
                          center: center, size: size * CGFloat(pop), alpha: 1 - lossU)
            }
            if lossU > 0 {
                drawHeart(context, symbol: "heart", color: world.muted.opacity(0.45),
                          center: center, size: size * 0.88, alpha: lossU)
            }
        }
    }

    private func drawHeart(_ context: GraphicsContext, symbol: String, color: Color,
                           center: CGPoint, size: CGFloat, alpha: Double) {
        let text = Text(Image(systemName: symbol))
            .font(.system(size: size, weight: .black))
            .foregroundColor(color)
        context.drawLayer { layer in
            layer.opacity = alpha
            layer.draw(text, at: center)
        }
    }

    private func drawCounter(_ context: GraphicsContext, geo: Geo, t: Double, script: Script) {
        let found = script.foundStart
            + script.taps.filter { $0.ok && t >= $0.time }.count
        let text = Text("\(found) of \(Self.icons.count) found")
            .font(.system(size: geo.cell * 0.20, weight: .semibold, design: world.bodyDesign))
            .foregroundColor(world.muted)
        context.draw(text, at: CGPoint(x: geo.size.width / 2, y: geo.counterY))
    }
}
