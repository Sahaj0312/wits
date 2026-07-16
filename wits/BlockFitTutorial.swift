//
//  BlockFitTutorial.swift
//  wits
//
//  Animated how-to-play demos for Block Fit: a hand drags pieces from a mini
//  tray onto a 6×6 board and the core beats play out on loop — place, clear a
//  line, clear two lines at once, and the no-moves ending. Rendering mirrors
//  the real game (same palette, ghost preview, telegraphed clears) so nothing
//  in the tutorial needs relearning in play.
//

import SwiftUI

enum BlockFitTutorial {
    static let slides: [TutorialSlide] = [
        TutorialSlide(caption: "drag pieces from the tray onto the board") {
            BlockFitDemo(page: .place)
        },
        TutorialSlide(caption: "fill a full row or column to clear it") {
            BlockFitDemo(page: .clearLine)
        },
        TutorialSlide(caption: "clear more than one line in a single move for bonus points") {
            BlockFitDemo(page: .doubleClear)
        },
        TutorialSlide(caption: "pieces never rotate — the run ends when nothing in the tray fits") {
            BlockFitDemo(page: .gameOver)
        },
    ]
}

// MARK: - Demo scenes

private struct BlockFitDemo: View {
    enum Page { case place, clearLine, doubleClear, gameOver }
    let page: Page

    private static let side = 6
    private var world: GameWorld { GameID.blockFit.world }

    var body: some View {
        DemoLoop(duration: scene.duration) { t in
            Canvas { context, size in
                render(context, size: size, t: t)
            }
        }
    }

    // MARK: Scene data

    private struct Scene {
        var duration: Double
        var filled: [Int: Int] = [:]          // r * side + c → color index
        var piece: [BlockCell]                // the dragged piece, normalized
        var pieceColor: Int
        var trayPieces: [(cells: [BlockCell], color: Int)]  // static slots
        var traySlot: Int                     // slot the dragged piece starts in
        var target: BlockCell                 // board origin the piece drops on
        var clearRows: [Int] = []
        var clearCols: [Int] = []
        var valid = true                      // gameOver page drags an unplaceable piece
    }

    private var scene: Scene {
        func fill(_ cells: [(Int, Int, Int)]) -> [Int: Int] {
            var map: [Int: Int] = [:]
            for (r, c, color) in cells { map[r * Self.side + c] = color }
            return map
        }
        switch page {
        case .place:
            return Scene(
                duration: 4.0,
                filled: fill([(4, 0, 3), (5, 0, 2), (5, 1, 2), (5, 5, 5)]),
                piece: [BlockCell(r: 0, c: 0), BlockCell(r: 0, c: 1),
                        BlockCell(r: 1, c: 0), BlockCell(r: 1, c: 1)],
                pieceColor: 1,
                trayPieces: [([BlockCell(r: 0, c: 0), BlockCell(r: 0, c: 1), BlockCell(r: 0, c: 2)], 2),
                             ([BlockCell(r: 0, c: 0), BlockCell(r: 0, c: 1), BlockCell(r: 1, c: 1)], 4)],
                traySlot: 1,
                target: BlockCell(r: 2, c: 2))
        case .clearLine:
            return Scene(
                duration: 4.4,
                filled: fill([(4, 0, 3), (4, 1, 1), (4, 2, 2), (4, 3, 5),
                              (5, 1, 2), (5, 4, 4)]),
                piece: [BlockCell(r: 0, c: 0), BlockCell(r: 0, c: 1)],
                pieceColor: 1,
                trayPieces: [([BlockCell(r: 0, c: 0)], 6),
                             ([BlockCell(r: 0, c: 0), BlockCell(r: 1, c: 0)], 3)],
                traySlot: 1,
                target: BlockCell(r: 4, c: 4),
                clearRows: [4])
        case .doubleClear:
            return Scene(
                duration: 5.0,
                filled: fill([(0, 2, 2), (1, 2, 4), (4, 2, 1), (5, 2, 3),
                              (3, 0, 1), (3, 1, 5), (3, 3, 2), (3, 4, 6), (3, 5, 4),
                              (5, 0, 3), (5, 5, 5)]),
                piece: [BlockCell(r: 0, c: 0), BlockCell(r: 1, c: 0)],
                pieceColor: 1,
                trayPieces: [([BlockCell(r: 0, c: 0), BlockCell(r: 0, c: 1)], 6),
                             ([BlockCell(r: 0, c: 0), BlockCell(r: 1, c: 0), BlockCell(r: 1, c: 1)], 2)],
                traySlot: 1,
                target: BlockCell(r: 2, c: 2),
                clearRows: [3],
                clearCols: [2])
        case .gameOver:
            let grid: [[Int]] = [
                [3, 1, 0, 2, 5, 4],
                [1, 6, 2, 4, 1, 3],
                [4, 2, 5, 1, 3, 0],
                [2, 5, 1, 6, 4, 2],
                [0, 3, 4, 2, 6, 1],
                [5, 1, 3, 0, 2, 5],
            ]
            var cells: [(Int, Int, Int)] = []
            for r in 0..<Self.side {
                for c in 0..<Self.side where grid[r][c] != 0 {
                    cells.append((r, c, grid[r][c]))
                }
            }
            return Scene(
                duration: 5.6,
                filled: fill(cells),
                piece: [BlockCell(r: 0, c: 0), BlockCell(r: 0, c: 1),
                        BlockCell(r: 1, c: 0), BlockCell(r: 1, c: 1)],
                pieceColor: 3,
                trayPieces: [([BlockCell(r: 0, c: 0), BlockCell(r: 1, c: 0)], 4),
                             ([BlockCell(r: 0, c: 0), BlockCell(r: 0, c: 1)], 6)],
                traySlot: 1,
                target: BlockCell(r: 0, c: 2),
                valid: false)
        }
    }

    // MARK: Geometry

    private struct Geo {
        let board: CGRect
        let cell: CGFloat
        let trayCell: CGFloat
        let traySlots: [CGPoint]

        init(size: CGSize) {
            let side = min(size.width * 0.76, size.height * 0.64)
            board = CGRect(x: (size.width - side) / 2,
                           y: size.height * 0.055,
                           width: side, height: side)
            cell = side / 6
            trayCell = cell * 0.58
            let trayY = board.maxY + (size.height - board.maxY) * 0.48
            let spacing = side / 2.9
            traySlots = (0..<3).map {
                CGPoint(x: size.width / 2 + CGFloat($0 - 1) * spacing, y: trayY)
            }
        }

        func cellRect(_ r: Int, _ c: Int) -> CGRect {
            CGRect(x: board.minX + CGFloat(c) * cell,
                   y: board.minY + CGFloat(r) * cell,
                   width: cell, height: cell)
        }
    }

    // MARK: Timeline

    private struct Beats {
        var handIn = (0.15, 0.55)
        var press = (0.75, 0.95)
        var drag = (0.95, 2.05)
        var drop = 2.05
        var handOut = (2.25, 2.75)
        var flash = (2.10, 2.45)
        var pop = (2.45, 2.80)
        // gameOver only
        var back = (2.75, 3.45)
        var trayDim = (3.55, 3.95)
        var noMoves = (3.85, 4.25)
    }

    private var beats: Beats {
        var b = Beats()
        if page == .gameOver { b.handOut = (3.05, 3.45) }
        return b
    }

    // MARK: Render

    private func render(_ context: GraphicsContext, size: CGSize, t: Double) {
        var ctx = context
        let geo = Geo(size: size)
        let scene = scene
        let beats = beats

        let dragU = DemoEase.ramp(t, beats.drag.0, beats.drag.1)
        let dropped = scene.valid && t >= beats.drop
        let popU = DemoEase.ramp(t, beats.pop.0, beats.pop.1)
        let cleared = dropped && popU >= 1

        // Multi-line clears rattle the board for a beat.
        if page == .doubleClear, t > beats.flash.0 {
            let decay = 1 - DemoEase.ramp(t, beats.flash.0, beats.flash.0 + 0.45)
            ctx.translateBy(x: CGFloat(sin(t * 42) * 2.6 * decay), y: 0)
        }

        // On the gameOver page the failed drag retreats to the tray (backU
        // winds the piece home).
        let backU = scene.valid ? 0 : DemoEase.ramp(t, beats.back.0, beats.back.1)

        drawBoard(ctx, geo: geo, scene: scene, t: t, beats: beats,
                  dropped: dropped, popU: popU, cleared: cleared)

        if !dropped, dragU > 0.62, backU < 0.05 {
            drawGhost(ctx, geo: geo, scene: scene)
        }

        drawTray(ctx, geo: geo, scene: scene, t: t, beats: beats, dropped: dropped)
        if !dropped, backU < 1 {
            drawFloatingPiece(ctx, geo: geo, scene: scene, t: t, beats: beats,
                              u: dragU * (1 - backU))
        }

        drawHand(ctx, geo: geo, scene: scene, t: t, beats: beats, dragU: dragU)

        if page == .doubleClear, cleared || popU > 0 {
            drawBonus(ctx, geo: geo, t: t, beats: beats)
        }
        if page == .gameOver {
            drawNoMoves(ctx, geo: geo, size: size, t: t, beats: beats)
        }
    }

    private func drawBoard(_ ctx: GraphicsContext, geo: Geo, scene: Scene,
                           t: Double, beats: Beats,
                           dropped: Bool, popU: Double, cleared: Bool) {
        ctx.fill(Path(roundedRect: geo.board.insetBy(dx: -geo.cell * 0.14, dy: -geo.cell * 0.14),
                      cornerRadius: geo.cell * 0.32, style: .continuous),
                 with: .color(world.surface.opacity(0.72)))

        // Board contents at time t: base cells, plus the dropped piece, minus
        // cleared lines once the pop-out finishes.
        var board = scene.filled
        if dropped {
            for cell in scene.piece {
                board[(scene.target.r + cell.r) * Self.side + (scene.target.c + cell.c)] = scene.pieceColor
            }
        }
        let flashAlpha = dropped
            ? DemoEase.ramp(t, beats.flash.0, beats.flash.0 + 0.12) * (1 - DemoEase.ramp(t, beats.flash.1, beats.pop.0))
            : 0

        for r in 0..<Self.side {
            for c in 0..<Self.side {
                let rect = geo.cellRect(r, c).insetBy(dx: geo.cell * 0.055, dy: geo.cell * 0.055)
                let value = board[r * Self.side + c] ?? 0
                let inClearLine = dropped && value != 0 &&
                    (scene.clearRows.contains(r) || scene.clearCols.contains(c))

                if value == 0 || (inClearLine && cleared) {
                    ctx.fill(Path(roundedRect: rect, cornerRadius: geo.cell * 0.16, style: .continuous),
                             with: .color(world.raised.opacity(0.5)))
                    continue
                }

                let scale = inClearLine ? 1 - popU : 1
                if scale <= 0.02 {
                    ctx.fill(Path(roundedRect: rect, cornerRadius: geo.cell * 0.16, style: .continuous),
                             with: .color(world.raised.opacity(0.5)))
                    continue
                }
                let drawRect = rect.insetBy(dx: rect.width * (1 - scale) / 2,
                                            dy: rect.height * (1 - scale) / 2)
                fillBlock(ctx, rect: drawRect, color: value, alpha: inClearLine ? Double(scale) : 1)
                if inClearLine, flashAlpha > 0 {
                    ctx.fill(Path(roundedRect: drawRect, cornerRadius: geo.cell * 0.16, style: .continuous),
                             with: .color(.white.opacity(0.75 * flashAlpha)))
                }
            }
        }
    }

    private func drawGhost(_ ctx: GraphicsContext, geo: Geo, scene: Scene) {
        let ghostColor = scene.valid
            ? BlockFitPalette.color(scene.pieceColor).opacity(0.42)
            : Color(hexAny: 0xFF4D4D).opacity(0.30)
        for cell in scene.piece {
            let rect = geo.cellRect(scene.target.r + cell.r, scene.target.c + cell.c)
                .insetBy(dx: geo.cell * 0.055, dy: geo.cell * 0.055)
            let path = Path(roundedRect: rect, cornerRadius: geo.cell * 0.16, style: .continuous)
            ctx.fill(path, with: .color(ghostColor))
            if !scene.valid {
                ctx.stroke(path, with: .color(Color(hexAny: 0xFF4D4D).opacity(0.9)), lineWidth: 2)
            }
        }
        guard scene.valid else { return }
        // Telegraph completed lines exactly like the in-game ghost preview.
        for r in scene.clearRows {
            for c in 0..<Self.side where scene.filled[r * Self.side + c] != nil {
                strokeClearHint(ctx, geo: geo, r: r, c: c)
            }
        }
        for c in scene.clearCols {
            for r in 0..<Self.side where scene.filled[r * Self.side + c] != nil {
                strokeClearHint(ctx, geo: geo, r: r, c: c)
            }
        }
    }

    private func strokeClearHint(_ ctx: GraphicsContext, geo: Geo, r: Int, c: Int) {
        let rect = geo.cellRect(r, c).insetBy(dx: geo.cell * 0.055, dy: geo.cell * 0.055)
        ctx.stroke(Path(roundedRect: rect, cornerRadius: geo.cell * 0.16, style: .continuous),
                   with: .color(world.ink.opacity(0.85)), lineWidth: 2)
    }

    private func drawTray(_ ctx: GraphicsContext, geo: Geo, scene: Scene,
                          t: Double, beats: Beats, dropped: Bool) {
        let dim = page == .gameOver ? DemoEase.ramp(t, beats.trayDim.0, beats.trayDim.1) : 0
        var slot = 0
        for index in 0..<3 {
            if index == scene.traySlot {
                continue
            }
            let piece = scene.trayPieces[slot]
            slot += 1
            drawPiece(ctx, cells: piece.cells, color: piece.color,
                      topLeft: trayTopLeft(geo: geo, slot: index, cells: piece.cells),
                      cellSize: geo.trayCell,
                      alpha: 1 - 0.72 * dim,
                      shadow: false)
        }
        // After the failed drag the returned piece dims with the rest.
        if page == .gameOver, DemoEase.ramp(t, beats.back.0, beats.back.1) >= 1 {
            drawPiece(ctx, cells: scene.piece, color: scene.pieceColor,
                      topLeft: trayTopLeft(geo: geo, slot: scene.traySlot, cells: scene.piece),
                      cellSize: geo.trayCell,
                      alpha: 1 - 0.72 * dim,
                      shadow: false)
        }
    }

    private func trayTopLeft(geo: Geo, slot: Int, cells: [BlockCell]) -> CGPoint {
        let cols = CGFloat((cells.map(\.c).max() ?? 0) + 1)
        let rows = CGFloat((cells.map(\.r).max() ?? 0) + 1)
        let center = geo.traySlots[slot]
        return CGPoint(x: center.x - cols * geo.trayCell / 2,
                       y: center.y - rows * geo.trayCell / 2)
    }

    private func drawFloatingPiece(_ ctx: GraphicsContext, geo: Geo, scene: Scene,
                                   t: Double, beats: Beats, u: Double) {
        let pressU = DemoEase.ramp(t, beats.press.0, beats.press.1)
        let start = trayTopLeft(geo: geo, slot: scene.traySlot, cells: scene.piece)
        let end = CGPoint(x: geo.board.minX + CGFloat(scene.target.c) * geo.cell,
                          y: geo.board.minY + CGFloat(scene.target.r) * geo.cell)
        var topLeft = DemoEase.lerp(start, end, u)
        // Hovering an invalid spot: the piece shudders in the hand.
        if !scene.valid, DemoEase.ramp(t, beats.drag.0, beats.drag.1) >= 1,
           DemoEase.ramp(t, beats.back.0, beats.back.1) == 0 {
            topLeft.x += CGFloat(sin(t * 16)) * geo.cell * 0.10
        }
        let pop = 1 + 0.07 * pressU * (1 - u)
        let cellSize = DemoEase.lerp(geo.trayCell, geo.cell, u) * CGFloat(pop)
        drawPiece(ctx, cells: scene.piece, color: scene.pieceColor,
                  topLeft: topLeft, cellSize: cellSize,
                  alpha: 1, shadow: u > 0.02)
    }

    private func drawPiece(_ ctx: GraphicsContext, cells: [BlockCell], color: Int,
                           topLeft: CGPoint, cellSize: CGFloat,
                           alpha: Double, shadow: Bool) {
        ctx.drawLayer { layer in
            layer.opacity = alpha
            if shadow {
                layer.addFilter(.shadow(color: .black.opacity(0.32),
                                        radius: cellSize * 0.28, y: cellSize * 0.22))
            }
            for cell in cells {
                let rect = CGRect(x: topLeft.x + CGFloat(cell.c) * cellSize,
                                  y: topLeft.y + CGFloat(cell.r) * cellSize,
                                  width: cellSize, height: cellSize)
                    .insetBy(dx: cellSize * 0.055, dy: cellSize * 0.055)
                fillBlock(layer, rect: rect, color: color, alpha: 1)
            }
        }
    }

    /// Candy block with the same top-light gloss the real board uses.
    private func fillBlock(_ ctx: GraphicsContext, rect: CGRect, color: Int, alpha: Double) {
        let radius = rect.width * 0.18
        ctx.fill(Path(roundedRect: rect, cornerRadius: radius, style: .continuous),
                 with: .color(BlockFitPalette.color(color).opacity(alpha)))
        let gloss = rect.insetBy(dx: rect.width * 0.16, dy: rect.height * 0.16)
            .offsetBy(dx: -rect.width * 0.05, dy: -rect.height * 0.05)
        ctx.fill(Path(roundedRect: gloss, cornerRadius: radius * 0.7, style: .continuous),
                 with: .color(.white.opacity(0.20 * alpha)))
    }

    private func drawHand(_ ctx: GraphicsContext, geo: Geo, scene: Scene,
                          t: Double, beats: Beats, dragU: Double) {
        let inU = DemoEase.ramp(t, beats.handIn.0, beats.handIn.1)
        let outU = DemoEase.ramp(t, beats.handOut.0, beats.handOut.1)
        let alpha = inU * (1 - outU)
        guard alpha > 0.01 else { return }

        let backU = scene.valid ? 0 : DemoEase.ramp(t, beats.back.0, beats.back.1)
        let u = scene.valid ? dragU : dragU * (1 - backU)

        let pieceCols = CGFloat((scene.piece.map(\.c).max() ?? 0) + 1)
        let pieceRows = CGFloat((scene.piece.map(\.r).max() ?? 0) + 1)
        let start = trayTopLeft(geo: geo, slot: scene.traySlot, cells: scene.piece)
        let end = CGPoint(x: geo.board.minX + CGFloat(scene.target.c) * geo.cell,
                          y: geo.board.minY + CGFloat(scene.target.r) * geo.cell)
        let topLeft = DemoEase.lerp(start, end, u)
        let cellSize = DemoEase.lerp(geo.trayCell, geo.cell, u)

        // Fingertip rides just below the piece's center.
        var tip = CGPoint(x: topLeft.x + pieceCols * cellSize * 0.5,
                          y: topLeft.y + pieceRows * cellSize * 0.62)
        // Wiggle while hovering an invalid spot; drift away after the drop.
        if !scene.valid, dragU >= 1, backU == 0 {
            tip.x += CGFloat(sin(t * 16) * geo.cell * 0.10)
        }
        let dropDrift = scene.valid ? DemoEase.ramp(t, beats.drop, beats.handOut.1) : 0
        tip.x += CGFloat(dropDrift) * geo.cell * 0.7
        tip.y += CGFloat(dropDrift) * geo.cell * 1.1

        let pressed = t >= beats.press.0 && (scene.valid ? t < beats.drop : backU < 1)
        DemoEase.drawHand(ctx, tip: tip, size: geo.cell * 1.5, pressed: pressed, alpha: alpha)
    }

    private func drawBonus(_ ctx: GraphicsContext, geo: Geo, t: Double, beats: Beats) {
        let riseU = DemoEase.ramp(t, beats.pop.0, beats.pop.0 + 1.1)
        guard riseU > 0, riseU < 1 else { return }
        let alpha = min(1, riseU * 4) * (1 - DemoEase.ramp(riseU, 0.62, 1))
        let center = CGPoint(x: geo.board.minX + 2.5 * geo.cell,
                             y: geo.board.minY + 3.0 * geo.cell - geo.cell * 1.4 * CGFloat(riseU))
        let text = Text("+40")
            .font(.system(size: geo.cell * 0.72, weight: .black, design: world.titleDesign))
            .foregroundColor(world.accent)
        ctx.drawLayer { layer in
            layer.opacity = alpha
            layer.addFilter(.shadow(color: .black.opacity(0.5), radius: 3, y: 2))
            layer.draw(text, at: center)
        }
    }

    private func drawNoMoves(_ ctx: GraphicsContext, geo: Geo, size: CGSize,
                             t: Double, beats: Beats) {
        let u = DemoEase.ramp(t, beats.noMoves.0, beats.noMoves.1)
        guard u > 0 else { return }
        ctx.fill(Path(roundedRect: geo.board.insetBy(dx: -geo.cell * 0.14, dy: -geo.cell * 0.14),
                      cornerRadius: geo.cell * 0.32, style: .continuous),
                 with: .color(.black.opacity(0.40 * u)))

        let badge = CGRect(x: geo.board.midX - geo.cell * 2.1,
                           y: geo.board.midY - geo.cell * 0.55,
                           width: geo.cell * 4.2, height: geo.cell * 1.1)
        ctx.drawLayer { layer in
            layer.opacity = u
            layer.addFilter(.shadow(color: .black.opacity(0.45), radius: 8, y: 5))
            layer.fill(Path(roundedRect: badge, cornerRadius: badge.height / 2, style: .continuous),
                       with: .color(world.background.opacity(0.95)))
            layer.stroke(Path(roundedRect: badge, cornerRadius: badge.height / 2, style: .continuous),
                         with: .color(Color(hexAny: 0xFF5E7A).opacity(0.9)), lineWidth: 2)
            layer.draw(Text("NO MOVES")
                        .font(.system(size: geo.cell * 0.42, weight: .black, design: world.titleDesign))
                        .foregroundColor(world.ink),
                       at: CGPoint(x: badge.midX, y: badge.midY))
        }
    }
}
