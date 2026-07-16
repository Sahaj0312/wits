//
//  FuseTutorial.swift
//  wits
//
//  Animated how-to-play demos for Fuse: a hand swipes across the 4×4 board,
//  every cell slides to the wall, and matching numbers fuse and double. Three
//  beats — the swipe itself, fusions paying points toward a big glowing cell,
//  and the jammed-board ending. Rendering mirrors the real board (same
//  palette, gaps, corner radii, fuse pop) so nothing needs relearning.
//

import SwiftUI

enum FuseTutorial {
    static let slides: [TutorialSlide] = [
        TutorialSlide(caption: "swipe any direction — every cell slides as far as it can") {
            FuseDemo(page: .swipe)
        },
        TutorialSlide(caption: "matching numbers fuse into one and double — build the biggest cell you can") {
            FuseDemo(page: .fuse)
        },
        TutorialSlide(caption: "keep the board open — the run ends when nothing can move") {
            FuseDemo(page: .gameOver)
        },
    ]
}

// MARK: - Demo scenes

private struct FuseDemo: View {
    enum Page { case swipe, fuse, gameOver }
    let page: Page

    private static let side = 4
    private var world: GameWorld { GameID.fuse.world }

    var body: some View {
        DemoLoop(duration: scene.duration) { t in
            Canvas { context, size in
                render(context, size: size, t: t)
            }
        }
    }

    // MARK: Scene data

    /// One cell's whole story for the loop: where it starts, where the swipe
    /// leaves it, and whether it vanishes into a partner or doubles.
    private struct TileSpec {
        let value: Int
        let from: (r: Int, c: Int)
        let to: (r: Int, c: Int)
        var doomed = false      // slides onto its partner and vanishes at settle
        var grows = false       // the partner: doubles and pops at settle
    }

    private struct Scene {
        var duration: Double
        var tiles: [TileSpec]
        var spawn: (value: Int, r: Int, c: Int)?
        var leftward: Bool          // swipe direction (both demos are horizontal)
        var bonus: Int = 0          // rising "+N" over the biggest fusion
        var bonusCell: (r: Int, c: Int) = (0, 0)
    }

    private var scene: Scene {
        switch page {
        case .swipe:
            // One pair meets at the left wall; bystanders just slide.
            return Scene(
                duration: 4.4,
                tiles: [
                    TileSpec(value: 2, from: (0, 1), to: (0, 0), grows: true),
                    TileSpec(value: 2, from: (0, 3), to: (0, 0), doomed: true),
                    TileSpec(value: 4, from: (1, 2), to: (1, 0)),
                    TileSpec(value: 8, from: (2, 3), to: (2, 0)),
                    TileSpec(value: 2, from: (3, 2), to: (3, 0)),
                ],
                spawn: (2, 1, 3),
                leftward: true)
        case .fuse:
            // Double fusion on one swipe; the 64s make the first glowing 128.
            return Scene(
                duration: 4.8,
                tiles: [
                    TileSpec(value: 64, from: (1, 2), to: (1, 3), grows: true),
                    TileSpec(value: 64, from: (1, 0), to: (1, 3), doomed: true),
                    TileSpec(value: 8, from: (2, 1), to: (2, 3), grows: true),
                    TileSpec(value: 8, from: (2, 0), to: (2, 3), doomed: true),
                    TileSpec(value: 4, from: (0, 2), to: (0, 3)),
                    TileSpec(value: 2, from: (3, 3), to: (3, 3)),
                ],
                spawn: (2, 2, 0),
                leftward: false,
                bonus: 144,
                bonusCell: (1, 3))
        case .gameOver:
            // Full board, no equal neighbours anywhere: the swipe changes nothing.
            let grid: [[Int]] = [
                [2, 4, 8, 16],
                [4, 8, 16, 32],
                [8, 16, 32, 64],
                [16, 32, 64, 128],
            ]
            var tiles: [TileSpec] = []
            for r in 0..<Self.side {
                for c in 0..<Self.side {
                    tiles.append(TileSpec(value: grid[r][c], from: (r, c), to: (r, c)))
                }
            }
            return Scene(duration: 5.6, tiles: tiles, spawn: nil, leftward: true)
        }
    }

    // MARK: Geometry (same gap/cell proportions as the real board)

    private struct Geo {
        let board: CGRect
        let gap: CGFloat
        let cell: CGFloat

        init(size: CGSize) {
            let side = min(size.width * 0.94, size.height * 0.86)
            board = CGRect(x: (size.width - side) / 2,
                           y: (size.height - side) / 2,
                           width: side, height: side)
            gap = side * 0.022
            cell = (side - gap * 5) / 4
        }

        func center(_ r: Int, _ c: Int) -> CGPoint {
            CGPoint(x: board.minX + gap + (cell + gap) * CGFloat(c) + cell / 2,
                    y: board.minY + gap + (cell + gap) * CGFloat(r) + cell / 2)
        }
    }

    // MARK: Timeline

    private struct Beats {
        var handIn = (0.2, 0.6)
        var stroke = (0.9, 1.45)     // pressed swipe, tip crosses the board
        var slide = (1.02, 1.42)     // cells chase the finger
        var settle = 1.55            // doomed vanish, partners double
        var pop = (1.55, 1.95)
        var spawnAt = 1.75
        var handOut = (1.8, 2.3)
        // gameOver only
        var dim = (2.4, 2.9)
        var badge = (2.7, 3.1)
    }

    private var beats: Beats { Beats() }

    // MARK: Render

    private func render(_ context: GraphicsContext, size: CGSize, t: Double) {
        var ctx = context
        let geo = Geo(size: size)
        let scene = scene
        let beats = beats

        // A jammed board strains toward the swipe and snaps back, moving nothing.
        if page == .gameOver {
            let u = DemoEase.ramp(t, beats.stroke.0, beats.stroke.1)
            ctx.translateBy(x: -CGFloat(sin(Double.pi * u)) * geo.cell * 0.09, y: 0)
        }

        drawBoard(ctx, geo: geo)
        drawTiles(ctx, geo: geo, scene: scene, t: t, beats: beats)
        if let spawn = scene.spawn {
            drawSpawn(ctx, geo: geo, spawn: spawn, t: t, beats: beats)
        }
        drawSwipe(ctx, geo: geo, t: t, beats: beats, leftward: scene.leftward)
        if scene.bonus > 0 {
            drawBonus(ctx, geo: geo, scene: scene, t: t, beats: beats)
        }
        if page == .gameOver {
            drawNoMoves(ctx, geo: geo, t: t, beats: beats)
        }
    }

    private func drawBoard(_ ctx: GraphicsContext, geo: Geo) {
        ctx.fill(Path(roundedRect: geo.board, cornerRadius: geo.board.width * 0.03, style: .continuous),
                 with: .color(world.surface))
        for r in 0..<Self.side {
            for c in 0..<Self.side {
                ctx.fill(cellPath(geo, at: geo.center(r, c)),
                         with: .color(world.raised.opacity(0.55)))
            }
        }
    }

    private func drawTiles(_ ctx: GraphicsContext, geo: Geo, scene: Scene,
                           t: Double, beats: Beats) {
        let slideU = DemoEase.ramp(t, beats.slide.0, beats.slide.1)
        let settled = t >= beats.settle
        let popU = DemoEase.ramp(t, beats.pop.0, beats.pop.1)

        // Doomed cells first so partners cover them as the lines compress.
        for tile in scene.tiles.filter(\.doomed) where !settled {
            let at = DemoEase.lerp(geo.center(tile.from.r, tile.from.c),
                                   geo.center(tile.to.r, tile.to.c), slideU)
            drawCell(ctx, geo: geo, at: at, value: tile.value)
        }
        for tile in scene.tiles where !tile.doomed {
            let at = DemoEase.lerp(geo.center(tile.from.r, tile.from.c),
                                   geo.center(tile.to.r, tile.to.c), slideU)
            let value = (tile.grows && settled) ? tile.value * 2 : tile.value
            let pop = tile.grows ? 1 + 0.15 * sin(popU * .pi) : 1
            drawCell(ctx, geo: geo, at: at, value: value, scale: CGFloat(pop))
            if tile.grows, settled, popU < 1 {
                // Brief white flash sells the doubling, like the in-game fuse pop.
                let rect = CGRect(x: at.x - geo.cell / 2, y: at.y - geo.cell / 2,
                                  width: geo.cell, height: geo.cell)
                ctx.fill(Path(roundedRect: rect, cornerRadius: geo.cell * 0.13, style: .continuous),
                         with: .color(.white.opacity(0.30 * sin(popU * .pi))))
            }
        }
    }

    private func drawSpawn(_ ctx: GraphicsContext, geo: Geo,
                           spawn: (value: Int, r: Int, c: Int),
                           t: Double, beats: Beats) {
        let u = DemoEase.ramp(t, beats.spawnAt, beats.spawnAt + 0.3)
        guard u > 0 else { return }
        drawCell(ctx, geo: geo, at: geo.center(spawn.r, spawn.c),
                 value: spawn.value, scale: 0.35 + 0.65 * CGFloat(u), alpha: u)
    }

    /// One board cell in the real trade dress: charged-gem fill, black-weight
    /// numeral, hum glow from 128 up.
    private func drawCell(_ ctx: GraphicsContext, geo: Geo, at: CGPoint,
                          value: Int, scale: CGFloat = 1, alpha: Double = 1) {
        let side = geo.cell * scale
        let rect = CGRect(x: at.x - side / 2, y: at.y - side / 2, width: side, height: side)
        let path = Path(roundedRect: rect, cornerRadius: side * 0.13, style: .continuous)
        ctx.drawLayer { layer in
            layer.opacity = alpha
            if value >= 128 {
                layer.addFilter(.shadow(color: FusePalette.glow(value), radius: side * 0.16))
            }
            layer.fill(path, with: .color(FusePalette.fill(value)))
            layer.draw(Text(String(value))
                        .font(.system(size: side * fontScale(value), weight: .black,
                                      design: world.titleDesign))
                        .foregroundColor(FusePalette.ink(value)),
                       at: at)
        }
    }

    private func fontScale(_ value: Int) -> CGFloat {
        value < 100 ? 0.46 : 0.38
    }

    // MARK: Swipe hand

    private func drawSwipe(_ ctx: GraphicsContext, geo: Geo,
                           t: Double, beats: Beats, leftward: Bool) {
        // Ride between the bottom rows so the fusions stay in clear view.
        let y = geo.board.midY + geo.cell * 0.55
        let reach = geo.cell * 1.45
        let x0 = geo.board.midX + (leftward ? reach : -reach)
        let x1 = geo.board.midX - (leftward ? reach : -reach)
        let u = DemoEase.ramp(t, beats.stroke.0, beats.stroke.1)
        let strokeTip = CGPoint(x: DemoEase.lerp(x0, x1, u), y: y)

        // Motion trail: the swept segment, fading off after the release.
        let trailAlpha = (1 - DemoEase.ramp(t, beats.stroke.1 + 0.05, beats.stroke.1 + 0.4))
        if u > 0.04, trailAlpha > 0.01 {
            var path = Path()
            path.move(to: CGPoint(x: x0, y: y))
            path.addLine(to: strokeTip)
            ctx.stroke(path,
                       with: .linearGradient(
                           Gradient(colors: [world.accent.opacity(0),
                                             world.accent.opacity(0.7 * trailAlpha)]),
                           startPoint: CGPoint(x: x0, y: y),
                           endPoint: strokeTip),
                       style: StrokeStyle(lineWidth: geo.cell * 0.16, lineCap: .round))
        }

        // Drift off the fused cells after release so the pop stays in view.
        var tip = strokeTip
        let drift = CGFloat(DemoEase.ramp(t, beats.stroke.1 + 0.05, beats.handOut.1))
        tip.x += drift * geo.cell * (leftward ? -0.4 : 0.4)
        tip.y += drift * geo.cell * 0.9

        let alpha = DemoEase.ramp(t, beats.handIn.0, beats.handIn.1)
            * (1 - DemoEase.ramp(t, beats.handOut.0, beats.handOut.1))
        let pressed = t >= beats.stroke.0 - 0.12 && t < beats.stroke.1 + 0.1
        DemoEase.drawHand(ctx, tip: tip, size: geo.cell * 0.95, pressed: pressed, alpha: alpha)
    }

    // MARK: Juice

    private func drawBonus(_ ctx: GraphicsContext, geo: Geo, scene: Scene,
                           t: Double, beats: Beats) {
        let riseU = DemoEase.ramp(t, beats.pop.0, beats.pop.0 + 1.1)
        guard riseU > 0, riseU < 1 else { return }
        let alpha = min(1, riseU * 4) * (1 - DemoEase.ramp(riseU, 0.62, 1))
        let cell = geo.center(scene.bonusCell.r, scene.bonusCell.c)
        let at = CGPoint(x: cell.x - geo.cell * 0.45,
                         y: cell.y - geo.cell * (0.6 + 0.85 * CGFloat(riseU)))
        ctx.drawLayer { layer in
            layer.opacity = alpha
            layer.addFilter(.shadow(color: .black.opacity(0.5), radius: 3, y: 2))
            layer.draw(Text("+\(scene.bonus)")
                        .font(.system(size: geo.cell * 0.5, weight: .black,
                                      design: world.titleDesign))
                        .foregroundColor(world.accent),
                       at: at)
        }
    }

    private func drawNoMoves(_ ctx: GraphicsContext, geo: Geo, t: Double, beats: Beats) {
        let u = DemoEase.ramp(t, beats.dim.0, beats.dim.1)
        guard u > 0 else { return }
        ctx.fill(Path(roundedRect: geo.board, cornerRadius: geo.board.width * 0.03, style: .continuous),
                 with: .color(.black.opacity(0.45 * u)))

        let badgeU = DemoEase.ramp(t, beats.badge.0, beats.badge.1)
        guard badgeU > 0 else { return }
        let badge = CGRect(x: geo.board.midX - geo.cell * 1.55,
                           y: geo.board.midY - geo.cell * 0.4,
                           width: geo.cell * 3.1, height: geo.cell * 0.8)
        ctx.drawLayer { layer in
            layer.opacity = badgeU
            layer.addFilter(.shadow(color: .black.opacity(0.45), radius: 8, y: 5))
            layer.fill(Path(roundedRect: badge, cornerRadius: badge.height / 2, style: .continuous),
                       with: .color(world.background.opacity(0.95)))
            layer.stroke(Path(roundedRect: badge, cornerRadius: badge.height / 2, style: .continuous),
                         with: .color(world.secondary.opacity(0.9)), lineWidth: 2)
            layer.draw(Text("NO MOVES")
                        .font(.system(size: geo.cell * 0.30, weight: .black,
                                      design: world.titleDesign))
                        .foregroundColor(world.ink),
                       at: CGPoint(x: badge.midX, y: badge.midY))
        }
    }

    private func cellPath(_ geo: Geo, at: CGPoint) -> Path {
        let rect = CGRect(x: at.x - geo.cell / 2, y: at.y - geo.cell / 2,
                          width: geo.cell, height: geo.cell)
        return Path(roundedRect: rect, cornerRadius: geo.cell * 0.13, style: .continuous)
    }
}
