//
//  EchoGridTutorial.swift
//  wits
//
//  Animated how-to-play demos for Echo Grid on a mini 3×3 board: tiles glow
//  violet one at a time, the board goes dark, and the hand plays the path
//  back in reverse — mint taps landing 3 → 2 → 1. The third slide shows the
//  trap: starting from the first tile fails the round.
//

import SwiftUI

enum EchoGridTutorial {
    static let slides: [TutorialSlide] = [
        TutorialSlide(caption: "watch the tiles light up in order") {
            EchoGridDemo(page: .watch)
        },
        TutorialSlide(caption: "when the board goes dark, tap them backwards — last tile first") {
            EchoGridDemo(page: .echo)
        },
        TutorialSlide(caption: "replaying it forwards fails the round — clear enough rounds to pass") {
            EchoGridDemo(page: .wrongWay)
        },
    ]
}

private struct EchoGridDemo: View {
    enum Page { case watch, echo, wrongWay }
    let page: Page

    private var world: GameWorld { GameID.echoGrid.world }
    /// Failed-round tint (the world's hottest difficulty colour in-game).
    private let danger = Color(hexAny: 0xFF5EBE)

    /// Demo path, poster-style diagonal: bottom-left → center → top-right.
    private static let path = [6, 4, 2]

    var body: some View {
        DemoLoop(duration: beats.duration) { t in
            Canvas { context, size in
                render(context, size: size, t: t)
            }
        }
    }

    // MARK: Script

    private struct Beats {
        var duration: Double
        var show: [Double] = []              // per-step light-up start (watch)
        var showLen: Double = 0.7            // lit window, 70% of the real step
        var ghostIn: (Double, Double) = (0, 0)   // numbered recall path fades in
        var dark: (Double, Double) = (0, 0)      // …then the board goes dark
        var taps: [Double] = []
        var tappedCells: [Int] = []          // cell per tap, aligned with taps
        var flash: Double? = nil             // perfect-round celebration
        var fail: Double? = nil              // the forwards tap lands
    }

    private var beats: Beats {
        switch page {
        case .watch:
            Beats(duration: 5.2, show: [0.7, 1.7, 2.7])
        case .echo:
            Beats(duration: 6.0, ghostIn: (0.3, 0.7), dark: (1.3, 1.7),
                  taps: [2.4, 3.3, 4.2], tappedCells: [2, 4, 6], flash: 4.55)
        case .wrongWay:
            Beats(duration: 5.4, ghostIn: (0.3, 0.7), dark: (1.2, 1.6),
                  taps: [2.3], tappedCells: [6], fail: 2.3)
        }
    }

    // MARK: Geometry

    private struct Geo {
        let centers: [CGPoint]          // 9 cells, row-major, row 0 on top
        let tile: CGFloat
        let gridCenter: CGPoint
        let gridSide: CGFloat
        let labelY: CGFloat
        let pipsY: CGFloat

        init(size: CGSize) {
            gridSide = min(size.width, size.height) * 0.74
            tile = gridSide * 0.30
            let gap = gridSide * 0.05
            let center = CGPoint(x: size.width / 2, y: size.height * 0.43)
            gridCenter = center
            let pitch = tile + gap
            centers = (0..<9).map { i in
                CGPoint(x: center.x + (CGFloat(i % 3) - 1) * pitch,
                        y: center.y + (CGFloat(i / 3) - 1) * pitch)
            }
            labelY = gridCenter.y + gridSide / 2 + size.height * 0.075
            pipsY = size.height * 0.92
        }
    }

    // MARK: Render

    private func render(_ context: GraphicsContext, size: CGSize, t: Double) {
        var context = context
        let geo = Geo(size: size)
        let b = beats

        // the whole grid recoils when the forwards tap lands
        if let fail = b.fail, t >= fail {
            let decay = max(0, 1 - (t - fail) / 0.45)
            context.translateBy(x: CGFloat(sin((t - fail) * 34)) * 3.5 * decay, y: 0)
        }

        // recall ghosts are visible until the board "goes dark"
        let ghostAlpha = DemoEase.ramp(t, b.ghostIn.0, b.ghostIn.1)
            * (1 - DemoEase.ramp(t, b.dark.0, b.dark.1))

        let flashU = b.flash.map { at in
            DemoEase.ramp(t, at, at + 0.16) * (1 - DemoEase.ramp(t, at + 0.5, at + 1.1))
        } ?? 0

        for cell in 0..<9 {
            drawTile(context, cell: cell, geo: geo, t: t, b: b,
                     ghostAlpha: ghostAlpha, flashU: flashU)
        }

        drawLabel(context, geo: geo, size: size, t: t, b: b)
        drawPips(context, geo: geo, t: t, b: b)

        if page == .echo { drawScorePop(context, geo: geo, t: t, b: b) }
        if page == .wrongWay { drawWrongBadge(context, geo: geo, t: t, b: b) }

        let taps = zip(b.taps, b.tappedCells).map {
            DemoEase.Tap(time: $0, point: geo.centers[$1])
        }
        for tap in taps {
            DemoEase.drawTapRipple(context, at: tap.point, start: tap.time, t: t,
                                   radius: geo.tile * 0.62,
                                   color: page == .wrongWay ? danger : world.secondary)
        }
        let hand = DemoEase.handAlongTaps(taps, t: t)
        DemoEase.drawHand(context, tip: CGPoint(x: hand.tip.x + geo.tile * 0.08,
                                                y: hand.tip.y + geo.tile * 0.14),
                          size: geo.tile * 0.98, pressed: hand.pressed, alpha: hand.alpha)
    }

    private func drawTile(_ context: GraphicsContext, cell: Int, geo: Geo,
                          t: Double, b: Beats, ghostAlpha: Double, flashU: Double) {
        let step = Self.path.firstIndex(of: cell)     // 0-based path order, nil off-path

        var fill = world.raised
        var stroke = world.ink.opacity(0.12)
        var scale: CGFloat = 1
        var glow = 0.0
        var number: (String, Color)? = nil

        if let step {
            switch page {
            case .watch:
                let start = b.show[step]
                if t >= start && t < start + b.showLen {
                    // actively lit — bright violet with a glow, like the real game
                    fill = world.accent; glow = 1; scale = 1.14
                    number = ("\(step + 1)", world.background)
                } else if t >= start + b.showLen {
                    // leave a numbered ghost so the finished path reads 1-2-3
                    fill = world.accent.opacity(0.30)
                    stroke = world.accent.opacity(0.50)
                    number = ("\(step + 1)", world.ink.opacity(0.9))
                }
            case .echo, .wrongWay:
                if let i = b.tappedCells.firstIndex(of: cell), t >= b.taps[i] {
                    // tap landed — mint (or danger on the forwards mistake),
                    // revealing the tile's original order number
                    let pop = DemoEase.ramp(t, b.taps[i], b.taps[i] + 0.12)
                    scale = 1 + 0.14 * CGFloat(pop)
                    if page == .wrongWay {
                        fill = danger.opacity(0.88)
                        stroke = danger
                        number = ("\(step + 1)", world.background)
                    } else {
                        fill = world.secondary.opacity(0.72)
                        stroke = world.secondary.opacity(0.9)
                        number = ("\(step + 1)", world.background)
                    }
                } else if ghostAlpha > 0.01 {
                    fill = world.accent.opacity(0.30 * ghostAlpha)
                    stroke = world.accent.opacity(0.50 * ghostAlpha)
                    number = ("\(step + 1)", world.ink.opacity(0.9 * ghostAlpha))
                }
            }
        }

        let s = geo.tile * scale
        let center = geo.centers[cell]
        let rect = CGRect(x: center.x - s / 2, y: center.y - s / 2, width: s, height: s)
        let path = Path(roundedRect: rect, cornerRadius: s * 0.275, style: .continuous)

        if glow > 0 {
            var g = context
            g.addFilter(.shadow(color: world.accent.opacity(0.9 * glow), radius: s * 0.45))
            g.fill(path, with: .color(fill))
        } else {
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.20), radius: 3, y: 2))
                layer.fill(path, with: .color(fill))
            }
        }
        context.stroke(path, with: .color(stroke), lineWidth: 1.5)

        if step != nil, flashU > 0 {
            context.fill(path, with: .color(.white.opacity(0.35 * flashU)))
            context.stroke(path, with: .color(world.accent.opacity(flashU)), lineWidth: 3)
        }
        if let number {
            context.draw(Text(number.0)
                            .font(.system(size: geo.tile * 0.44, weight: .heavy, design: .rounded))
                            .foregroundColor(number.1),
                         at: center)
        }
    }

    /// The real game's phase hint under the board.
    private func drawLabel(_ context: GraphicsContext, geo: Geo, size: CGSize,
                           t: Double, b: Beats) {
        let text = page == .watch ? "watch"
            : t < b.dark.1 ? "watch" : "tap it backwards"
        context.draw(Text(text)
                        .font(.system(size: size.width * 0.048, weight: .semibold, design: .rounded))
                        .foregroundColor(world.muted),
                     at: CGPoint(x: geo.gridCenter.x, y: geo.labelY))
    }

    /// Six round pips: two already cleared, the current one resolves mint on
    /// the perfect round and danger on the forwards mistake.
    private func drawPips(_ context: GraphicsContext, geo: Geo, t: Double, b: Beats) {
        guard page != .watch else { return }
        let r = geo.gridSide * 0.030
        let gap = r * 3.2
        let startX = geo.gridCenter.x - gap * 2.5
        for i in 0..<6 {
            let rect = CGRect(x: startX + CGFloat(i) * gap - r, y: geo.pipsY - r,
                              width: r * 2, height: r * 2)
            let circle = Path(ellipseIn: rect)
            if i < 2 {
                context.fill(circle, with: .color(world.secondary.opacity(0.9)))
            } else if i == 2, let flash = b.flash, t >= flash {
                context.fill(circle, with: .color(world.secondary))
            } else if i == 2, let fail = b.fail, t >= fail + 0.25 {
                context.fill(circle, with: .color(danger))
            } else {
                context.stroke(circle,
                               with: .color(world.ink.opacity(i == 2 ? 0.55 : 0.25)),
                               lineWidth: 1.5)
            }
        }
    }

    /// Rising "+180" over the board on the perfect round (60 points × 3 tiles).
    private func drawScorePop(_ context: GraphicsContext, geo: Geo, t: Double, b: Beats) {
        guard let flash = b.flash else { return }
        let alpha = DemoEase.ramp(t, flash, flash + 0.2)
            * (1 - DemoEase.ramp(t, flash + 0.9, flash + 1.4))
        guard alpha > 0.01 else { return }
        let rise = DemoEase.ramp(t, flash, flash + 0.9)
        let y = geo.gridCenter.y - geo.gridSide * 0.66 - geo.gridSide * 0.10 * CGFloat(rise)
        context.draw(Text("+180")
                        .font(.system(size: geo.gridSide * 0.13, weight: .black, design: .rounded))
                        .foregroundColor(world.secondary.opacity(alpha)),
                     at: CGPoint(x: geo.gridCenter.x, y: y))
    }

    /// "WRONG ORDER" pill in world colours, BlockFit "NO MOVES"-style.
    private func drawWrongBadge(_ context: GraphicsContext, geo: Geo, t: Double, b: Beats) {
        guard let fail = b.fail else { return }
        let u = DemoEase.ramp(t, fail + 0.35, fail + 0.6)
        guard u > 0.01 else { return }
        let w = geo.gridSide * 0.78
        let h = geo.gridSide * 0.17
        let badge = CGRect(x: geo.gridCenter.x - w / 2, y: geo.gridCenter.y - h / 2,
                           width: w, height: h)
        let pill = Path(roundedRect: badge, cornerRadius: h / 2, style: .continuous)
        context.drawLayer { layer in
            layer.opacity = u
            layer.addFilter(.shadow(color: .black.opacity(0.35), radius: 8, y: 3))
            layer.fill(pill, with: .color(world.raised))
            layer.stroke(pill, with: .color(danger.opacity(0.9)), lineWidth: 2)
            layer.draw(Text("WRONG ORDER")
                            .font(.system(size: h * 0.42, weight: .black, design: .monospaced))
                            .foregroundColor(world.ink),
                       at: CGPoint(x: badge.midX, y: badge.midY))
        }
    }
}
