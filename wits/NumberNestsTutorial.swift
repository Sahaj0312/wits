//
//  NumberNestsTutorial.swift
//  wits
//
//  Animated how-to-play demos for Number Nests on a mini 3×3 board: tap a
//  square then a keypad number to fill it, nests glow when their arithmetic
//  target is met, row repeats flash coral until corrected, and CHECK sweeps
//  the finished grid. Mirrors the real chalkboard rendering, slate cells,
//  heavy nest outlines, corner clues, and the 1–3 keypad with NOTES/CHECK.
//

import SwiftUI

enum NumberNestsTutorial {
    static let slides: [TutorialSlide] = [
        TutorialSlide(caption: "tap a square, then a number. each outlined nest must combine to its target") {
            NumberNestsDemo(page: .nest)
        },
        TutorialSlide(caption: "every row and column uses 1–3 once. repeats flash until you fix them") {
            NumberNestsDemo(page: .conflict)
        },
        TutorialSlide(caption: "pencil notes to test ideas, then check the full grid to win") {
            NumberNestsDemo(page: .check)
        },
    ]
}

private struct NumberNestsDemo: View {
    enum Page { case nest, conflict, check }
    let page: Page

    private var world: GameWorld { GameID.numberNests.world }

    // Demo board is one fixed 3×3 puzzle so every slide shows the same nests:
    // solution 1 2 3 / 3 1 2 / 2 3 1 with cages A "3+" (top-left pair),
    // B "6×" (right column) and C "9+" (bottom-left quad).
    private static let cageOf = [0, 0, 1, 2, 2, 1, 2, 2, 1]
    private static let clues: [(cell: Int, text: String)] = [(0, "3+"), (2, "6×"), (3, "9+")]

    var body: some View {
        DemoLoop(duration: script.duration) { t in
            Canvas { context, size in
                render(context, size: size, t: t)
            }
        }
    }

    // MARK: Script

    private enum Target {
        case cell(Int)
        case key(Int)
        case check
    }

    private struct Fill {
        let cell: Int
        let value: Int
        let at: Double
    }

    private struct Script {
        let duration: Double
        let base: [Int: Int]                    // cell index → pre-filled value
        let selects: [(cell: Int, at: Double)]
        let fills: [Fill]
        let taps: [(target: Target, at: Double)]
        var notes: [Int: [Int]] = [:]           // pencilled candidates until the cell fills
        var conflictCells: [Int] = []
        var conflictWindow: (start: Double, end: Double)? = nil
        var nestFlashAt: Double? = nil          // cage A hits its target
        var sweepAt: Double? = nil              // CHECK success wave
    }

    private var script: Script {
        switch page {
        case .nest:
            // Bottom rows pre-filled; the hand completes the "3+" nest 1 then 2.
            return Script(
                duration: 5.8,
                base: [3: 3, 4: 1, 5: 2, 6: 2, 7: 3, 8: 1],
                selects: [(0, 0.9), (1, 2.7)],
                fills: [Fill(cell: 0, value: 1, at: 1.8),
                        Fill(cell: 1, value: 2, at: 3.6)],
                taps: [(.cell(0), 0.9), (.key(1), 1.8), (.cell(1), 2.7), (.key(2), 3.6)],
                nestFlashAt: 3.65)
        case .conflict:
            // A second 3 lands in the middle row, both flash coral, then 1 fixes it.
            return Script(
                duration: 5.6,
                base: [0: 1, 1: 2, 2: 3, 3: 3, 6: 2, 8: 1],
                selects: [(4, 0.9)],
                fills: [Fill(cell: 4, value: 3, at: 1.8),
                        Fill(cell: 4, value: 1, at: 3.5)],
                taps: [(.cell(4), 0.9), (.key(3), 1.8), (.key(1), 3.5)],
                conflictCells: [3, 4],
                conflictWindow: (1.85, 3.52))
        case .check:
            // One pencilled square left; filling it arms CHECK for the win sweep.
            return Script(
                duration: 6.0,
                base: [0: 1, 1: 2, 2: 3, 3: 3, 4: 1, 5: 2, 7: 3, 8: 1],
                selects: [(6, 0.9)],
                fills: [Fill(cell: 6, value: 2, at: 1.8)],
                taps: [(.cell(6), 0.9), (.key(2), 1.8), (.check, 3.0)],
                notes: [6: [2]],
                sweepAt: 3.15)
        }
    }

    // MARK: Geometry

    private struct Geo {
        let board: CGRect
        let cell: CGFloat
        let guideCenter: CGPoint
        let keyRects: [CGRect]     // keypad 1..3
        let notesRect: CGRect
        let eraseRect: CGRect
        let checkRect: CGRect

        init(size: CGSize) {
            let side = min(size.width * 0.70, size.height * 0.56)
            board = CGRect(x: (size.width - side) / 2, y: size.height * 0.03,
                           width: side, height: side)
            cell = side / 3

            guideCenter = CGPoint(x: size.width / 2, y: board.maxY + size.height * 0.055)

            let rowWidth = min(size.width * 0.88, side * 1.28)
            let rowX = (size.width - rowWidth) / 2
            let gap: CGFloat = 7
            let keyH = size.height * 0.105
            let keyTop = board.maxY + size.height * 0.095
            let keyW = (rowWidth - gap * 2) / 3
            keyRects = (0..<3).map {
                CGRect(x: rowX + CGFloat($0) * (keyW + gap), y: keyTop, width: keyW, height: keyH)
            }

            let barH = size.height * 0.095
            let barTop = keyTop + keyH + size.height * 0.03
            let eraseW = rowWidth * 0.16
            let notesW = rowWidth * 0.36
            let checkW = rowWidth - notesW - eraseW - gap * 2
            notesRect = CGRect(x: rowX, y: barTop, width: notesW, height: barH)
            eraseRect = CGRect(x: notesRect.maxX + gap, y: barTop, width: eraseW, height: barH)
            checkRect = CGRect(x: eraseRect.maxX + gap, y: barTop, width: checkW, height: barH)
        }

        func cellRect(_ index: Int) -> CGRect {
            CGRect(x: board.minX + CGFloat(index % 3) * cell,
                   y: board.minY + CGFloat(index / 3) * cell,
                   width: cell, height: cell)
        }

        func center(_ target: NumberNestsDemo.Target) -> CGPoint {
            switch target {
            case .cell(let index):
                let rect = cellRect(index)
                return CGPoint(x: rect.midX, y: rect.midY)
            case .key(let value):
                let rect = keyRects[value - 1]
                return CGPoint(x: rect.midX, y: rect.midY)
            case .check:
                return CGPoint(x: checkRect.midX, y: checkRect.midY)
            }
        }
    }

    // MARK: Render

    private func render(_ context: GraphicsContext, size: CGSize, t: Double) {
        let geo = Geo(size: size)
        let script = script

        drawChalkGrid(context, size: size)
        drawBoard(context, geo: geo, script: script, t: t)
        drawGuide(context, geo: geo, script: script, t: t)
        drawKeypad(context, geo: geo, script: script, t: t)
        drawActionBar(context, geo: geo, script: script, t: t)

        for tap in script.taps {
            DemoEase.drawTapRipple(context, at: geo.center(tap.target),
                                   start: tap.at, t: t,
                                   radius: geo.cell * 0.55, color: world.accent)
        }
        let hand = DemoEase.handAlongTaps(
            script.taps.map { DemoEase.Tap(time: $0.at, point: geo.center($0.target)) }, t: t)
        DemoEase.drawHand(context, tip: CGPoint(x: hand.tip.x + geo.cell * 0.08,
                                                y: hand.tip.y + geo.cell * 0.14),
                          size: geo.cell * 0.95, pressed: hand.pressed, alpha: hand.alpha)
    }

    /// Faint chalk squares behind the board, echoing the real stage backdrop.
    private func drawChalkGrid(_ context: GraphicsContext, size: CGSize) {
        let step = size.width / 6
        for x in stride(from: -step / 2, through: size.width, by: step) {
            for y in stride(from: -step / 2, through: size.height, by: step) {
                context.stroke(Path(CGRect(x: x, y: y, width: step, height: step)),
                               with: .color(world.ink.opacity(0.045)), lineWidth: 1)
            }
        }
    }

    private func drawBoard(_ context: GraphicsContext, geo: Geo, script: Script, t: Double) {
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.24), radius: 9, y: 5))
            layer.fill(Path(geo.board), with: .color(world.surface))
        }

        let selected = script.selects.last { $0.at <= t }?.cell
        let conflictOn = script.conflictWindow.map { t >= $0.start && t < $0.end } ?? false

        for index in 0..<9 {
            let rect = geo.cellRect(index)
            let inConflict = conflictOn && script.conflictCells.contains(index)
            if inConflict {
                context.fill(Path(rect), with: .color(world.secondary.opacity(0.26)))
            } else if index == selected {
                context.fill(Path(rect), with: .color(world.accent.opacity(0.24)))
            }
            context.stroke(Path(rect), with: .color(world.ink.opacity(0.14)), lineWidth: 0.6)

            if let entry = value(at: index, script: script, t: t) {
                // Freshly typed numbers pop slightly, like chalk pressed down.
                let pop = 1 + 0.22 * (1 - DemoEase.ramp(t, entry.at, entry.at + 0.22))
                context.draw(Text("\(entry.value)")
                                .font(.system(size: geo.cell * 0.47 * pop, weight: .black,
                                              design: world.titleDesign))
                                .foregroundColor(inConflict ? world.secondary : world.ink),
                             at: CGPoint(x: rect.midX, y: rect.midY + geo.cell * 0.06))
            } else if let noted = script.notes[index] {
                drawNotes(context, values: noted, rect: rect, cell: geo.cell)
            }
        }

        drawCageBorders(context, geo: geo)
        drawClues(context, geo: geo, script: script, t: t)

        if let flashAt = script.nestFlashAt {
            // Cage A glows when its "3+" target is met.
            let u = DemoEase.ramp(t, flashAt, flashAt + 0.16)
                * (1 - DemoEase.ramp(t, flashAt + 0.55, flashAt + 1.2))
            if u > 0 {
                let nest = geo.cellRect(0).union(geo.cellRect(1))
                context.fill(Path(nest), with: .color(.white.opacity(0.22 * u)))
                context.stroke(Path(nest), with: .color(world.accent.opacity(u)), lineWidth: 3.4)
            }
        }

        if let sweepAt = script.sweepAt {
            for index in 0..<9 {
                let delay = sweepAt + Double(index / 3 + index % 3) * 0.09
                let u = DemoEase.ramp(t, delay, delay + 0.18)
                    * (1 - DemoEase.ramp(t, delay + 0.42, delay + 1.0))
                guard u > 0 else { continue }
                let rect = geo.cellRect(index)
                context.fill(Path(rect), with: .color(.white.opacity(0.32 * u)))
                context.stroke(Path(rect), with: .color(world.accent.opacity(u)), lineWidth: 2.6)
            }
        }

        context.stroke(Path(geo.board), with: .color(world.ink), lineWidth: 3)
    }

    private func drawNotes(_ context: GraphicsContext, values: [Int], rect: CGRect, cell: CGFloat) {
        for value in values {
            let col = CGFloat((value - 1) % 2)
            let row = CGFloat((value - 1) / 2)
            context.draw(Text("\(value)")
                            .font(.system(size: cell * 0.16, weight: .bold, design: .rounded))
                            .foregroundColor(world.muted),
                         at: CGPoint(x: rect.minX + (col + 0.5) * cell / 2,
                                     y: rect.minY + cell * 0.52 + (row + 0.5) * cell * 0.22))
        }
    }

    private func drawCageBorders(_ context: GraphicsContext, geo: Geo) {
        var path = Path()
        for index in 0..<9 {
            let rect = geo.cellRect(index)
            let r = index / 3, c = index % 3
            let cage = Self.cageOf[index]
            if r > 0, Self.cageOf[index - 3] != cage {
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            }
            if c > 0, Self.cageOf[index - 1] != cage {
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            }
        }
        context.stroke(path, with: .color(world.ink), lineWidth: 2.4)
    }

    private func drawClues(_ context: GraphicsContext, geo: Geo, script: Script, t: Double) {
        for clue in Self.clues {
            let rect = geo.cellRect(clue.cell)
            // The satisfied nest's clue stays lit once its numbers land.
            let satisfied = clue.cell == 0 && script.nestFlashAt.map { t >= $0 } == true
            context.draw(Text(clue.text)
                            .font(.system(size: max(9, geo.cell * 0.20), weight: .black,
                                          design: .rounded))
                            .foregroundColor(satisfied ? world.accent : world.muted),
                         at: CGPoint(x: rect.minX + geo.cell * 0.22,
                                     y: rect.minY + geo.cell * 0.17))
        }
    }

    private func drawGuide(_ context: GraphicsContext, geo: Geo, script: Script, t: Double) {
        let text: String
        var color = world.muted
        switch page {
        case .nest:
            text = t >= 0.95 ? "make 3 using +" : "each row and column uses 1–3 once"
        case .conflict:
            text = "each row and column uses 1–3 once"
        case .check:
            if let sweepAt = script.sweepAt, t >= sweepAt + 0.2 {
                text = "every nest fits"
                color = world.secondary
            } else {
                text = t >= 0.95 ? "make 9 using +" : "each row and column uses 1–3 once"
            }
        }
        context.draw(Text(text)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(color),
                     at: geo.guideCenter)
    }

    private func drawKeypad(_ context: GraphicsContext, geo: Geo, script: Script, t: Double) {
        for value in 1...3 {
            let rect = geo.keyRects[value - 1]
            let path = Path(roundedRect: rect, cornerRadius: 7, style: .continuous)
            context.fill(path, with: .color(world.surface))
            // Pressed keys flash amber under the fingertip.
            let press = script.taps
                .filter { if case .key(value) = $0.target { true } else { false } }
                .map { DemoEase.ramp(t, $0.at, $0.at + 0.08) * (1 - DemoEase.ramp(t, $0.at + 0.2, $0.at + 0.5)) }
                .max() ?? 0
            if press > 0 {
                context.fill(path, with: .color(world.accent.opacity(0.35 * press)))
            }
            context.stroke(path, with: .color(world.ink.opacity(0.14)), lineWidth: 1)
            context.draw(Text("\(value)")
                            .font(.system(size: rect.height * 0.52, weight: .black, design: .rounded))
                            .foregroundColor(world.ink),
                         at: CGPoint(x: rect.midX, y: rect.midY))
        }
    }

    private func drawActionBar(_ context: GraphicsContext, geo: Geo, script: Script, t: Double) {
        let labelSize = geo.notesRect.height * 0.32

        let notesPath = Path(roundedRect: geo.notesRect, cornerRadius: 7, style: .continuous)
        context.fill(notesPath, with: .color(world.surface))
        context.stroke(notesPath, with: .color(world.ink.opacity(0.14)), lineWidth: 1)
        var pencil = context.resolve(Image(systemName: "pencil"))
        pencil.shading = .color(world.ink)
        let iconSide = labelSize * 1.1
        context.draw(pencil, in: CGRect(x: geo.notesRect.midX - labelSize * 2.5,
                                        y: geo.notesRect.midY - iconSide / 2,
                                        width: iconSide, height: iconSide))
        context.draw(Text("NOTES")
                        .font(.system(size: labelSize, weight: .black, design: .rounded))
                        .foregroundColor(world.ink),
                     at: CGPoint(x: geo.notesRect.midX + labelSize * 0.8, y: geo.notesRect.midY))

        let erasePath = Path(roundedRect: geo.eraseRect, cornerRadius: 7, style: .continuous)
        context.fill(erasePath, with: .color(world.raised))
        var eraser = context.resolve(Image(systemName: "delete.left.fill"))
        eraser.shading = .color(world.ink)
        let eraseSide = geo.eraseRect.height * 0.4
        context.draw(eraser, in: CGRect(x: geo.eraseRect.midX - eraseSide / 2,
                                        y: geo.eraseRect.midY - eraseSide / 2,
                                        width: eraseSide, height: eraseSide))

        // CHECK arms (full opacity) only once the grid is full, like the real pad.
        let fullAt = gridFullTime(script)
        let armed = fullAt.map { t >= $0 } ?? false
        let checkPress = script.taps
            .filter { if case .check = $0.target { true } else { false } }
            .map { DemoEase.ramp(t, $0.at, $0.at + 0.08) * (1 - DemoEase.ramp(t, $0.at + 0.2, $0.at + 0.5)) }
            .max() ?? 0
        let checkPath = Path(roundedRect: geo.checkRect, cornerRadius: 7, style: .continuous)
        context.fill(checkPath, with: .color(world.accent.opacity(armed ? 1 : 0.48)))
        if checkPress > 0 {
            context.fill(checkPath, with: .color(.white.opacity(0.30 * checkPress)))
        }
        context.draw(Text("CHECK")
                        .font(.system(size: labelSize, weight: .black, design: .rounded))
                        .foregroundColor(world.background.opacity(armed ? 1 : 0.7)),
                     at: CGPoint(x: geo.checkRect.midX, y: geo.checkRect.midY))
    }

    // MARK: State helpers

    private func value(at cell: Int, script: Script, t: Double) -> (value: Int, at: Double)? {
        if let fill = script.fills.last(where: { $0.cell == cell && $0.at <= t }) {
            return (fill.value, fill.at)
        }
        return script.base[cell].map { ($0, -1) }
    }

    /// Moment every cell holds a value, if the script gets there.
    private func gridFullTime(_ script: Script) -> Double? {
        let missing = (0..<9).filter { script.base[$0] == nil }
        guard !missing.isEmpty else { return 0 }
        var latest = 0.0
        for cell in missing {
            guard let at = script.fills.filter({ $0.cell == cell }).map(\.at).max() else { return nil }
            latest = max(latest, at)
        }
        return latest
    }
}
