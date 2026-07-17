//
//  CrosswordTutorial.swift
//  wits
//
//  Animated how-to-play demos for Crossword Craze: select a square and type,
//  flip the crossing direction by tapping the square again, and use the bulb
//  only when stuck. The miniature board keeps the real newsprint, blue-pen
//  selection, clue strip, and keyboard treatment.
//

import SwiftUI

enum CrosswordTutorial {
    static let slides: [TutorialSlide] = [
        TutorialSlide(caption: "tap a square, then type. the cursor advances through the answer") {
            CrosswordDemo(page: .type)
        },
        TutorialSlide(caption: "tap a crossing square again to flip between across and down") {
            CrosswordDemo(page: .crossing)
        },
        TutorialSlide(caption: "stuck? the bulb reveals one square, but clean solves score higher") {
            CrosswordDemo(page: .reveal)
        },
    ]
}

private struct CrosswordDemo: View {
    enum Page { case type, crossing, reveal }
    let page: Page

    private var world: GameWorld { GameID.crossword.world }
    private static let answer = Array("CARDS")
    private static let openCells: Set<Int> = [2, 6, 7, 8, 10, 11, 12, 13, 14, 16, 17, 18, 22]

    var body: some View {
        DemoLoop(duration: 5.4) { t in
            Canvas { context, size in
                render(context, size: size, t: t)
            }
        }
    }

    // MARK: - Geometry

    private struct Geo {
        let size: CGSize
        let board: CGRect
        let cell: CGFloat
        let clue: CGRect
        let keyboardTop: CGFloat
        let keySize: CGSize
        let keyGap: CGFloat
        let bulb: CGPoint

        init(size: CGSize) {
            self.size = size
            let side = min(size.width * 0.68, size.height * 0.55)
            board = CGRect(x: (size.width - side) / 2,
                           y: size.height * 0.045,
                           width: side, height: side)
            cell = side / 5
            clue = CGRect(x: size.width * 0.075,
                          y: board.maxY + size.height * 0.025,
                          width: size.width * 0.85,
                          height: size.height * 0.105)
            keyboardTop = clue.maxY + size.height * 0.025
            keyGap = max(2, size.width * 0.008)
            let keyW = (size.width * 0.90 - keyGap * 9) / 10
            keySize = CGSize(width: keyW, height: max(19, size.height * 0.075))
            bulb = CGPoint(x: board.maxX + cell * 0.42,
                           y: board.minY + cell * 0.42)
        }

        func center(_ index: Int) -> CGPoint {
            CGPoint(x: board.minX + (CGFloat(index % 5) + 0.5) * cell,
                    y: board.minY + (CGFloat(index / 5) + 0.5) * cell)
        }

        func keyCenter(_ letter: Character) -> CGPoint {
            let rows = [Array("QWERTYUIOP"), Array("ASDFGHJKL"), Array("ZXCVBNM")]
            for (row, letters) in rows.enumerated() {
                if let column = letters.firstIndex(of: letter) {
                    let rowWidth = CGFloat(letters.count) * keySize.width
                        + CGFloat(max(0, letters.count - 1)) * keyGap
                    let x0 = (size.width - rowWidth) / 2
                    return CGPoint(x: x0 + (CGFloat(column) + 0.5) * keySize.width
                                    + CGFloat(column) * keyGap,
                                   y: keyboardTop + CGFloat(row) * (keySize.height + keyGap)
                                    + keySize.height / 2)
                }
            }
            return CGPoint(x: size.width / 2, y: keyboardTop)
        }
    }

    // MARK: - Render

    private func render(_ context: GraphicsContext, size: CGSize, t: Double) {
        let geo = Geo(size: size)
        let state = boardState(t: t)

        drawBoard(context, geo: geo, entries: state.entries,
                  selected: state.selected, active: state.active)
        drawClue(context, geo: geo, down: state.down)
        drawKeyboard(context, geo: geo, pressed: state.pressedKey)

        var taps: [DemoEase.Tap] = []
        switch page {
        case .type:
            taps = [DemoEase.Tap(time: 0.85, point: geo.center(10))]
            for (index, letter) in Self.answer.enumerated() {
                taps.append(DemoEase.Tap(time: 1.55 + Double(index) * 0.58,
                                         point: geo.keyCenter(letter)))
            }
        case .crossing:
            taps = [DemoEase.Tap(time: 1.55, point: geo.center(12))]
        case .reveal:
            taps = [DemoEase.Tap(time: 1.45, point: geo.bulb)]
        }

        for tap in taps {
            DemoEase.drawTapRipple(context, at: tap.point, start: tap.time, t: t,
                                   radius: geo.cell * 0.48, color: world.accent)
        }
        let hand = DemoEase.handAlongTaps(taps, t: t)
        DemoEase.drawHand(context,
                          tip: CGPoint(x: hand.tip.x + geo.cell * 0.05,
                                       y: hand.tip.y + geo.cell * 0.09),
                          size: geo.cell * 0.82,
                          pressed: hand.pressed,
                          alpha: hand.alpha)
    }

    private struct BoardState {
        let entries: [Int: Character]
        let selected: Int
        let active: Set<Int>
        let down: Bool
        let pressedKey: Character?
    }

    private func boardState(t: Double) -> BoardState {
        switch page {
        case .type:
            let typed = max(0, min(5, Int(floor((t - 1.45) / 0.58)) + 1))
            var entries: [Int: Character] = [:]
            for index in 0..<typed { entries[10 + index] = Self.answer[index] }
            let selected = 10 + min(typed, 4)
            let pressed = (0..<5).first { index in
                t >= 1.55 + Double(index) * 0.58 && t < 1.73 + Double(index) * 0.58
            }.map { Self.answer[$0] }
            return BoardState(entries: entries, selected: selected,
                              active: Set(10...14), down: false, pressedKey: pressed)

        case .crossing:
            var entries = Dictionary(uniqueKeysWithValues:
                Self.answer.enumerated().map { (10 + $0.offset, $0.element) })
            entries[2] = "A"; entries[7] = "C"; entries[17] = "E"; entries[22] = "S"
            let down = t >= 1.72
            return BoardState(entries: entries, selected: 12,
                              active: down ? Set([2, 7, 12, 17, 22]) : Set(10...14),
                              down: down, pressedKey: nil)

        case .reveal:
            var entries = Dictionary(uniqueKeysWithValues:
                Self.answer.enumerated().compactMap { index, letter in
                    index == 2 ? nil : (10 + index, letter)
                })
            if t >= 1.65 { entries[12] = "R" }
            return BoardState(entries: entries, selected: 12,
                              active: Set(10...14), down: false, pressedKey: nil)
        }
    }

    private func drawBoard(_ context: GraphicsContext, geo: Geo,
                           entries: [Int: Character], selected: Int, active: Set<Int>) {
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: world.ink.opacity(0.18), radius: 7, y: 4))
            layer.fill(Path(roundedRect: geo.board, cornerRadius: 6, style: .continuous),
                       with: .color(world.ink))
        }

        for index in 0..<25 {
            let row = index / 5
            let column = index % 5
            let rect = CGRect(x: geo.board.minX + CGFloat(column) * geo.cell,
                              y: geo.board.minY + CGFloat(row) * geo.cell,
                              width: geo.cell, height: geo.cell)
                .insetBy(dx: 0.6, dy: 0.6)
            guard Self.openCells.contains(index) else {
                context.fill(Path(rect), with: .color(world.ink))
                continue
            }

            let fill: Color
            if index == selected { fill = world.accent.opacity(0.45) }
            else if active.contains(index) { fill = world.accent.opacity(0.16) }
            else { fill = world.surface }
            context.fill(Path(rect), with: .color(fill))
            context.stroke(Path(rect), with: .color(world.ink.opacity(0.25)), lineWidth: 0.7)

            if [2, 6, 10, 12].contains(index) {
                context.draw(Text("\([2: 1, 6: 2, 10: 3, 12: 4][index]!)")
                    .font(.system(size: geo.cell * 0.18, weight: .bold))
                    .foregroundColor(world.ink.opacity(0.62)),
                    at: CGPoint(x: rect.minX + geo.cell * 0.09,
                                y: rect.minY + geo.cell * 0.10), anchor: .topLeading)
            }
            if let letter = entries[index] {
                context.draw(Text(String(letter))
                    .font(.system(size: geo.cell * 0.52, weight: .heavy, design: .serif))
                    .foregroundColor(world.ink), at: geo.center(index))
            }
        }

        let bulbCircle = CGRect(x: geo.bulb.x - geo.cell * 0.28,
                                y: geo.bulb.y - geo.cell * 0.28,
                                width: geo.cell * 0.56, height: geo.cell * 0.56)
        context.fill(Path(ellipseIn: bulbCircle), with: .color(world.ink.opacity(0.08)))
        var bulb = context.resolve(Image(systemName: "lightbulb.fill"))
        bulb.shading = .color(page == .reveal ? world.secondary : world.ink)
        context.draw(bulb, in: bulbCircle.insetBy(dx: geo.cell * 0.13, dy: geo.cell * 0.13))
    }

    private func drawClue(_ context: GraphicsContext, geo: Geo, down: Bool) {
        let path = Path(roundedRect: geo.clue, cornerRadius: 8, style: .continuous)
        context.fill(path, with: .color(world.ink.opacity(0.07)))
        let label: String
        let clue: String
        switch page {
        case .crossing where down:
            label = "1D"; clue = "units of land"
        case .reveal:
            label = "3A"; clue = "a deck's contents"
        default:
            label = "3A"; clue = "a deck's contents"
        }
        context.draw(Text(label)
            .font(.system(size: geo.clue.height * 0.24, weight: .black, design: .rounded))
            .foregroundColor(world.accent),
            at: CGPoint(x: geo.clue.midX, y: geo.clue.minY + geo.clue.height * 0.28))
        context.draw(Text(clue)
            .font(.system(size: geo.clue.height * 0.31, weight: .bold))
            .foregroundColor(world.ink),
            at: CGPoint(x: geo.clue.midX, y: geo.clue.minY + geo.clue.height * 0.68))
    }

    private func drawKeyboard(_ context: GraphicsContext, geo: Geo, pressed: Character?) {
        let rows = [Array("QWERTYUIOP"), Array("ASDFGHJKL"), Array("ZXCVBNM")]
        for (row, letters) in rows.enumerated() {
            let rowWidth = CGFloat(letters.count) * geo.keySize.width
                + CGFloat(max(0, letters.count - 1)) * geo.keyGap
            let x0 = (geo.size.width - rowWidth) / 2
            for (column, letter) in letters.enumerated() {
                let rect = CGRect(x: x0 + CGFloat(column) * (geo.keySize.width + geo.keyGap),
                                  y: geo.keyboardTop + CGFloat(row) * (geo.keySize.height + geo.keyGap),
                                  width: geo.keySize.width, height: geo.keySize.height)
                let path = Path(roundedRect: rect, cornerRadius: 4, style: .continuous)
                context.fill(path, with: .color(letter == pressed ? world.accent.opacity(0.45) : world.surface))
                context.stroke(path, with: .color(world.ink.opacity(0.16)), lineWidth: 0.8)
                context.draw(Text(String(letter))
                    .font(.system(size: geo.keySize.height * 0.42, weight: .bold))
                    .foregroundColor(world.ink), at: CGPoint(x: rect.midX, y: rect.midY))
            }
        }
    }
}
