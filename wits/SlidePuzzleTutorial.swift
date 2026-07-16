//
//  SlidePuzzleTutorial.swift
//  wits
//
//  Animated how-to-play demos for Slide Puzzle on a mini 3×3 board: tap a tile
//  in line with the gap to slide it, one tap moves a whole line, and finishing
//  the ordering solves the board. Tiles render like the real game — raised
//  navy squares that turn orange once they sit in their solved spot.
//

import SwiftUI

enum SlidePuzzleTutorial {
    static let slides: [TutorialSlide] = [
        TutorialSlide(caption: "tap any tile in the same row or column as the gap to slide it") {
            SlidePuzzleDemo(page: .slide)
        },
        TutorialSlide(caption: "one tap slides every tile between it and the gap") {
            SlidePuzzleDemo(page: .lineSlide)
        },
        TutorialSlide(caption: "put the tiles back in order — fewer moves and a faster solve score higher") {
            SlidePuzzleDemo(page: .solve)
        },
    ]
}

private struct SlidePuzzleDemo: View {
    enum Page { case slide, lineSlide, solve }
    let page: Page

    private static let side = 3
    private static let slideTime = 0.28
    private var world: GameWorld { GameID.slidePuzzle.world }

    var body: some View {
        DemoLoop(duration: script.duration) { t in
            Canvas { context, size in
                render(context, size: size, t: t)
            }
        }
    }

    // MARK: Script

    private struct Move {
        let value: Int
        let from: Int
        let to: Int
        let start: Double
    }

    private struct Script {
        let duration: Double
        let base: [Int: Int]       // value → starting board index (0..8)
        let moves: [Move]
        let taps: [(time: Double, cell: Int)]
        var flashAt: Double? = nil // solved celebration
    }

    private var script: Script {
        switch page {
        case .slide:
            // r0: 1 2 3 / r1: 4 · 5 / r2: 7 8 6 — tap 8 (slides up a column),
            // then tap 6 (slides along a row).
            return Script(
                duration: 4.4,
                base: [1: 0, 2: 1, 3: 2, 4: 3, 5: 5, 7: 6, 8: 7, 6: 8],
                moves: [Move(value: 8, from: 7, to: 4, start: 1.1),
                        Move(value: 6, from: 8, to: 7, start: 2.7)],
                taps: [(1.1, 7), (2.7, 8)])
        case .lineSlide:
            // r0: · 2 1 — tapping 1 pushes both tiles left in one move.
            return Script(
                duration: 4.2,
                base: [2: 1, 1: 2, 3: 3, 5: 4, 4: 5, 6: 6, 7: 7, 8: 8],
                moves: [Move(value: 2, from: 1, to: 0, start: 1.5),
                        Move(value: 1, from: 2, to: 1, start: 1.5)],
                taps: [(1.5, 2)])
        case .solve:
            // Everything home except the last corner: tap 8 to finish.
            return Script(
                duration: 4.8,
                base: [1: 0, 2: 1, 3: 2, 4: 3, 5: 4, 6: 5, 7: 6, 8: 8],
                moves: [Move(value: 8, from: 8, to: 7, start: 1.6)],
                taps: [(1.6, 8)],
                flashAt: 2.1)
        }
    }

    // MARK: Geometry

    private struct Geo {
        let board: CGRect
        let cell: CGFloat
        let spacing: CGFloat
        let inset: CGFloat

        init(size: CGSize) {
            let side = min(size.width, size.height) * 0.94
            board = CGRect(x: (size.width - side) / 2,
                           y: (size.height - side) / 2,
                           width: side, height: side)
            inset = side * 0.045
            spacing = side * 0.024
            cell = (side - inset * 2 - spacing * 2) / 3
        }

        func center(_ index: Int) -> CGPoint {
            let row = CGFloat(index / 3)
            let col = CGFloat(index % 3)
            return CGPoint(x: board.minX + inset + col * (cell + spacing) + cell / 2,
                           y: board.minY + inset + row * (cell + spacing) + cell / 2)
        }
    }

    // MARK: Render

    private func render(_ context: GraphicsContext, size: CGSize, t: Double) {
        let geo = Geo(size: size)
        let script = script

        context.fill(Path(roundedRect: geo.board, cornerRadius: geo.board.width * 0.055,
                          style: .continuous),
                     with: .color(.black.opacity(0.28)))

        let flash = script.flashAt.map { at in
            DemoEase.ramp(t, at, at + 0.16) * (1 - DemoEase.ramp(t, at + 0.45, at + 1.0))
        } ?? 0

        for (value, baseIndex) in script.base.sorted(by: { $0.key < $1.key }) {
            var center = geo.center(baseIndex)
            var settledIndex = baseIndex
            for move in script.moves where move.value == value {
                let u = DemoEase.ramp(t, move.start, move.start + Self.slideTime)
                center = DemoEase.lerp(geo.center(move.from), geo.center(move.to), u)
                if u >= 1 { settledIndex = move.to }
            }
            drawTile(context, value: value, center: center, cell: geo.cell,
                     inPlace: settledIndex == value - 1, flash: flash)
        }

        for tap in script.taps {
            DemoEase.drawTapRipple(context, at: geo.center(tap.cell),
                                   start: tap.time, t: t,
                                   radius: geo.cell * 0.62, color: world.accent)
        }

        let hand = DemoEase.handAlongTaps(
            script.taps.map { DemoEase.Tap(time: $0.time, point: geo.center($0.cell)) }, t: t)
        DemoEase.drawHand(context, tip: CGPoint(x: hand.tip.x + geo.cell * 0.08,
                                                y: hand.tip.y + geo.cell * 0.14),
                          size: geo.cell * 0.98, pressed: hand.pressed, alpha: hand.alpha)
    }

    private func drawTile(_ context: GraphicsContext, value: Int, center: CGPoint,
                          cell: CGFloat, inPlace: Bool, flash: Double) {
        let rect = CGRect(x: center.x - cell / 2, y: center.y - cell / 2,
                          width: cell, height: cell)
        let radius = max(5, cell * 0.10)
        let path = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)

        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.18), radius: 4, y: 2))
            layer.fill(path, with: .color(inPlace ? world.secondary : world.raised))
        }
        context.stroke(path, with: .color(world.ink.opacity(0.18)), lineWidth: 1.5)
        if flash > 0 {
            context.fill(path, with: .color(.white.opacity(0.35 * flash)))
            context.stroke(path, with: .color(world.accent.opacity(flash)), lineWidth: 3)
        }
        context.draw(Text("\(value)")
                        .font(.system(size: cell * 0.42, weight: .heavy, design: .rounded))
                        .foregroundColor(world.ink),
                     at: center)
    }
}
