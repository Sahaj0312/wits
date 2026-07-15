//
//  GamePosterArt.swift
//  wits
//
//  Poster-style library cards: every game owns a color world and a small
//  illustrated gameplay vignette drawn in SwiftUI shapes, so the library reads
//  like a shelf of tiny game posters instead of a list of icons. Art uses
//  fixed (hexAny) colors so posters look identical in light and dark mode.
//

import SwiftUI

// MARK: - Game worlds

struct GameWorld {
    let background: Color
    let surface: Color
    let raised: Color
    let ink: Color
    let muted: Color
    let accent: Color
    let secondary: Color
    let difficultyColors: [Color]
    let titleDesign: Font.Design
    let bodyDesign: Font.Design
    let uppercaseTitles: Bool

    func difficultyColor(_ difficulty: ChallengeDifficulty) -> Color {
        difficultyColors[min(difficulty.ordinal, difficultyColors.count - 1)]
    }
}

extension GameID {
    var world: GameWorld {
        switch self {
        case .arrowStorm:
            GameWorld(background: Color(hexAny: 0x15130E),
                      surface: Color(hexAny: 0x252116), raised: Color(hexAny: 0x332C1A),
                      ink: Color(hexAny: 0xFFF8DD), muted: Color(hexAny: 0xBEB696),
                      accent: Color(hexAny: 0xFFD43B), secondary: Color(hexAny: 0xF05A28),
                      difficultyColors: [0xFFE36A, 0xFFB52E, 0xF26A2E, 0xE33D35].map { Color(hexAny: $0) },
                      titleDesign: .monospaced, bodyDesign: .monospaced, uppercaseTitles: true)
        case .crowdControl:
            GameWorld(background: Color(hexAny: 0x031E2A),
                      surface: Color(hexAny: 0x073344), raised: Color(hexAny: 0x0B4356),
                      ink: Color(hexAny: 0xE9FCFF), muted: Color(hexAny: 0x8DBAC4),
                      accent: Color(hexAny: 0x5DE7FF), secondary: Color(hexAny: 0xFF6B6B),
                      difficultyColors: [0x7DF3D0, 0x5DE7FF, 0xFFB44F, 0xFF6B6B].map { Color(hexAny: $0) },
                      titleDesign: .rounded, bodyDesign: .rounded, uppercaseTitles: false)
        case .echoGrid:
            GameWorld(background: Color(hexAny: 0x160D2C),
                      surface: Color(hexAny: 0x281849), raised: Color(hexAny: 0x382263),
                      ink: Color(hexAny: 0xFAF4FF), muted: Color(hexAny: 0xBAA5D0),
                      accent: Color(hexAny: 0xB693FF), secondary: Color(hexAny: 0x4FFFD7),
                      difficultyColors: [0x4FFFD7, 0x84C7FF, 0xB693FF, 0xFF5EBE].map { Color(hexAny: $0) },
                      titleDesign: .monospaced, bodyDesign: .rounded, uppercaseTitles: true)
        case .colorClash:
            GameWorld(background: Color(hexAny: 0xFFF4E8),
                      surface: Color(hexAny: 0xFFFFFF), raised: Color(hexAny: 0xFFE1D2),
                      ink: Color(hexAny: 0x17120F), muted: Color(hexAny: 0x71635B),
                      accent: Color(hexAny: 0xFF3D96), secondary: Color(hexAny: 0x00BFC6),
                      difficultyColors: [0x00BFC6, 0xF2B705, 0xFF6B35, 0xFF3D96].map { Color(hexAny: $0) },
                      titleDesign: .rounded, bodyDesign: .default, uppercaseTitles: true)
        case .tileShift:
            GameWorld(background: Color(hexAny: 0x002F2A),
                      surface: Color(hexAny: 0x07463F), raised: Color(hexAny: 0x0D5A50),
                      ink: Color(hexAny: 0xF7FFE8), muted: Color(hexAny: 0xA4C5B8),
                      accent: Color(hexAny: 0xC9F227), secondary: Color(hexAny: 0xF45B9B),
                      difficultyColors: [0xC9F227, 0x70E0B2, 0xF9A826, 0xF45B9B].map { Color(hexAny: $0) },
                      titleDesign: .rounded, bodyDesign: .rounded, uppercaseTitles: false)
        case .lastSeen:
            GameWorld(background: Color(hexAny: 0xF4E4C4),
                      surface: Color(hexAny: 0xFFF7E6), raised: Color(hexAny: 0xE9D2A5),
                      ink: Color(hexAny: 0x29233C), muted: Color(hexAny: 0x71677F),
                      accent: Color(hexAny: 0xFF704D), secondary: Color(hexAny: 0x4777E6),
                      difficultyColors: [0x45B97C, 0x4777E6, 0xF2A93B, 0xFF704D].map { Color(hexAny: $0) },
                      titleDesign: .serif, bodyDesign: .rounded, uppercaseTitles: false)
        case .slidePuzzle:
            GameWorld(background: Color(hexAny: 0x071C3A),
                      surface: Color(hexAny: 0x0C2B55), raised: Color(hexAny: 0x123A70),
                      ink: Color(hexAny: 0xEAF4FF), muted: Color(hexAny: 0x91AFCC),
                      accent: Color(hexAny: 0x59A9FF), secondary: Color(hexAny: 0xFF9D3D),
                      difficultyColors: [0x7BDFF2, 0x59A9FF, 0xA68CFF, 0xFF9D3D].map { Color(hexAny: $0) },
                      titleDesign: .monospaced, bodyDesign: .monospaced, uppercaseTitles: true)
        case .blockEscape:
            GameWorld(background: Color(hexAny: 0x211B17),
                      surface: Color(hexAny: 0x332A24), raised: Color(hexAny: 0x493B31),
                      ink: Color(hexAny: 0xF6E8D2), muted: Color(hexAny: 0xB6A08F),
                      accent: Color(hexAny: 0xFF4D3D), secondary: Color(hexAny: 0xF0C27B),
                      difficultyColors: [0xF0C27B, 0xE99A52, 0xFF7448, 0xFF4D3D].map { Color(hexAny: $0) },
                      titleDesign: .monospaced, bodyDesign: .default, uppercaseTitles: true)
        case .pegSolitaire:
            GameWorld(background: Color(hexAny: 0x063C2E),
                      surface: Color(hexAny: 0x0A503D), raised: Color(hexAny: 0x11654D),
                      ink: Color(hexAny: 0xF6E8C9), muted: Color(hexAny: 0xA9C7B7),
                      accent: Color(hexAny: 0xE9B949), secondary: Color(hexAny: 0xD85B4B),
                      difficultyColors: [0x91D6A8, 0xE9D45C, 0xE9A449, 0xD85B4B].map { Color(hexAny: $0) },
                      titleDesign: .serif, bodyDesign: .serif, uppercaseTitles: false)
        case .waterSort:
            GameWorld(background: Color(hexAny: 0x201134),
                      surface: Color(hexAny: 0x321D4E), raised: Color(hexAny: 0x422865),
                      ink: Color(hexAny: 0xF6EEFF), muted: Color(hexAny: 0xB2A0CC),
                      accent: Color(hexAny: 0x5EE6D0), secondary: Color(hexAny: 0xFFB84D),
                      difficultyColors: [0x7DEBC9, 0x6FB1FF, 0xFFB84D, 0xFF6E8A].map { Color(hexAny: $0) },
                      titleDesign: .rounded, bodyDesign: .rounded, uppercaseTitles: false)
        case .numberNests:
            // Chalkboard arithmetic: deep green slate, warm chalk and coral marks.
            GameWorld(background: Color(hexAny: 0x102A2A),
                      surface: Color(hexAny: 0x193C3A), raised: Color(hexAny: 0x24504C),
                      ink: Color(hexAny: 0xFFF7E6), muted: Color(hexAny: 0x9BBDB4),
                      accent: Color(hexAny: 0xF4C95D), secondary: Color(hexAny: 0xFF746C),
                      difficultyColors: [0x7DDEB5, 0xF4C95D, 0xF39C55, 0xFF746C].map { Color(hexAny: $0) },
                      titleDesign: .rounded, bodyDesign: .rounded, uppercaseTitles: false)
        case .mahjong:
            // Lacquer and ivory: deep red-brown table, gold and jade accents.
            GameWorld(background: Color(hexAny: 0x2E1013),
                      surface: Color(hexAny: 0x451B1F), raised: Color(hexAny: 0x59262B),
                      ink: Color(hexAny: 0xFFF3E0), muted: Color(hexAny: 0xC79E92),
                      accent: Color(hexAny: 0xF2C14E), secondary: Color(hexAny: 0x5BC08D),
                      difficultyColors: [0x5BC08D, 0xF2C14E, 0xF08A4B, 0xE05563].map { Color(hexAny: $0) },
                      titleDesign: .serif, bodyDesign: .rounded, uppercaseTitles: false)
        case .crossword:
            // The morning paper: newsprint cream, black ink, one blue pen.
            GameWorld(background: Color(hexAny: 0xF5F0E2),
                      surface: Color(hexAny: 0xFFFDF6), raised: Color(hexAny: 0xE9E1CB),
                      ink: Color(hexAny: 0x1C1A15), muted: Color(hexAny: 0x6E6757),
                      accent: Color(hexAny: 0x2B62E3), secondary: Color(hexAny: 0xD8442E),
                      difficultyColors: [0x3F9C5A, 0x2B62E3, 0xE0812F, 0xD8442E].map { Color(hexAny: $0) },
                      titleDesign: .serif, bodyDesign: .default, uppercaseTitles: false)
        case .split:
            GameWorld(background: Color(hexAny: 0x090713),
                      surface: Color(hexAny: 0x191329), raised: Color(hexAny: 0x251B3B),
                      ink: Color(hexAny: 0xFFF7FF), muted: Color(hexAny: 0xA99CB8),
                      accent: Color(hexAny: 0xFF466D), secondary: Color(hexAny: 0x39E6E2),
                      difficultyColors: [0x39E6E2, 0x9E8CFF, 0xFFB13B, 0xFF466D].map { Color(hexAny: $0) },
                      titleDesign: .rounded, bodyDesign: .monospaced, uppercaseTitles: true)
        case .blockFit:
            GameWorld(background: Color(hexAny: 0x141C4F),
                      surface: Color(hexAny: 0x1F2A6B), raised: Color(hexAny: 0x2A3785),
                      ink: Color(hexAny: 0xF0F4FF), muted: Color(hexAny: 0x93A0D9),
                      accent: Color(hexAny: 0xFFB13B), secondary: Color(hexAny: 0x4BE3A9),
                      difficultyColors: [0x4BE3A9, 0x58B4FF, 0xFFB13B, 0xFF5E7A].map { Color(hexAny: $0) },
                      titleDesign: .rounded, bodyDesign: .rounded, uppercaseTitles: true)
        case .fuse:
            // The reactor room: near-black steel with charged teal and amber.
            GameWorld(background: Color(hexAny: 0x0D141F),
                      surface: Color(hexAny: 0x1A2333), raised: Color(hexAny: 0x263248),
                      ink: Color(hexAny: 0xEDF3FF), muted: Color(hexAny: 0x8A97B0),
                      accent: Color(hexAny: 0x4DD9C6), secondary: Color(hexAny: 0xFFA13B),
                      difficultyColors: [0x4DD9C6, 0x6E8BFF, 0xFFA13B, 0xFF5FA8].map { Color(hexAny: $0) },
                      titleDesign: .rounded, bodyDesign: .monospaced, uppercaseTitles: true)
        case .snake:
            // The night garden: green-black pitch, leaf greens, one red apple.
            GameWorld(background: Color(hexAny: 0x0B120C),
                      surface: Color(hexAny: 0x18251A), raised: Color(hexAny: 0x243727),
                      ink: Color(hexAny: 0xEFFFEF), muted: Color(hexAny: 0x97B69B),
                      accent: Color(hexAny: 0x5FE868), secondary: Color(hexAny: 0xFF5F52),
                      difficultyColors: [0x5FE868, 0xFFC93B, 0xFF8A3B, 0xFF5F52].map { Color(hexAny: $0) },
                      titleDesign: .rounded, bodyDesign: .rounded, uppercaseTitles: true)
        case .tower:
            // The stratosphere: twilight indigo sky, block pink, one mint ring.
            GameWorld(background: Color(hexAny: 0x161C38),
                      surface: Color(hexAny: 0x242D55), raised: Color(hexAny: 0x303B6E),
                      ink: Color(hexAny: 0xF2F4FF), muted: Color(hexAny: 0x9AA3C9),
                      accent: Color(hexAny: 0xFF8FA8), secondary: Color(hexAny: 0x6FD6C3),
                      difficultyColors: [0x7FE3B4, 0xFFC24D, 0xFF9D5C, 0xFF5C7A].map { Color(hexAny: $0) },
                      titleDesign: .rounded, bodyDesign: .rounded, uppercaseTitles: true)
        }
    }

    var posterBackground: Color { world.background }
    var posterAccent: Color { world.accent }

    func worldTitle(_ text: String? = nil) -> String {
        let value = text ?? displayName
        return world.uppercaseTitles ? value.uppercased() : value
    }
}

/// Full-screen material for a game. Patterns are geometric and specific to the
/// game instead of a shared decorative layer.
struct GameWorldBackdrop: View {
    let game: GameID
    var patternOpacity: Double = 1

    var body: some View {
        ZStack {
            game.world.background
            GameWorldPattern(game: game)
                .opacity(patternOpacity)
        }
        .ignoresSafeArea()
    }
}

private struct GameWorldPattern: View {
    let game: GameID

    var body: some View {
        Canvas { context, size in
            let world = game.world
            switch game {
            case .arrowStorm:
                for offset in stride(from: -size.height, through: size.width, by: 54) {
                    var path = Path()
                    path.move(to: CGPoint(x: offset, y: 0))
                    path.addLine(to: CGPoint(x: offset + size.height, y: size.height))
                    context.stroke(path, with: .color(world.accent.opacity(0.08)), lineWidth: 18)
                }
            case .crowdControl:
                for row in 0..<9 {
                    for col in 0..<6 {
                        let x = (CGFloat(col) + (row.isMultiple(of: 2) ? 0.25 : 0.75)) * size.width / 6
                        let y = CGFloat(row) * size.height / 8
                        let radius: CGFloat = (row + col).isMultiple(of: 5) ? 7 : 3
                        context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                                           width: radius * 2, height: radius * 2)),
                                     with: .color(((row + col).isMultiple(of: 5) ? world.secondary : world.accent).opacity(0.13)))
                    }
                }
            case .echoGrid, .slidePuzzle:
                let step: CGFloat = game == .echoGrid ? 46 : 32
                for x in stride(from: 0 as CGFloat, through: size.width, by: step) {
                    var path = Path(); path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(path, with: .color(world.accent.opacity(0.08)), lineWidth: 1)
                }
                for y in stride(from: 0 as CGFloat, through: size.height, by: step) {
                    var path = Path(); path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: .color(world.secondary.opacity(0.07)), lineWidth: 1)
                }
            case .colorClash:
                let blocks = [
                    CGRect(x: -30, y: size.height * 0.12, width: size.width * 0.45, height: 54),
                    CGRect(x: size.width * 0.68, y: size.height * 0.33, width: size.width * 0.42, height: 72),
                    CGRect(x: size.width * 0.10, y: size.height * 0.80, width: size.width * 0.34, height: 42)
                ]
                for (index, rect) in blocks.enumerated() {
                    context.fill(Path(rect), with: .color((index.isMultiple(of: 2) ? world.accent : world.secondary).opacity(0.12)))
                }
            case .tileShift:
                for index in 0..<8 {
                    let side: CGFloat = index.isMultiple(of: 2) ? 36 : 22
                    let x = CGFloat((index * 71) % 330) / 330 * size.width
                    let y = CGFloat((index * 137) % 700) / 700 * size.height
                    context.stroke(Path(roundedRect: CGRect(x: x, y: y, width: side, height: side), cornerRadius: 4),
                                   with: .color((index.isMultiple(of: 3) ? world.secondary : world.accent).opacity(0.13)),
                                   lineWidth: 3)
                }
            case .lastSeen:
                for index in 0..<11 {
                    let radius: CGFloat = index.isMultiple(of: 3) ? 12 : 6
                    let x = CGFloat((index * 89) % 360) / 360 * size.width
                    let y = CGFloat((index * 151) % 760) / 760 * size.height
                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    context.stroke(Path(ellipseIn: rect),
                                   with: .color((index.isMultiple(of: 2) ? world.accent : world.secondary).opacity(0.16)),
                                   lineWidth: 3)
                }
            case .blockEscape:
                for y in stride(from: 24 as CGFloat, through: size.height, by: 92) {
                    let rect = CGRect(x: 18, y: y, width: size.width - 36, height: 54)
                    context.stroke(Path(roundedRect: rect, cornerRadius: 5),
                                   with: .color(world.secondary.opacity(0.08)), lineWidth: 3)
                }
            case .pegSolitaire:
                for row in 0..<12 {
                    for col in 0..<7 where (row + col).isMultiple(of: 2) {
                        let center = CGPoint(x: CGFloat(col) * size.width / 6,
                                             y: CGFloat(row) * size.height / 11)
                        context.stroke(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)),
                                       with: .color(world.ink.opacity(0.09)), lineWidth: 2)
                    }
                }
            case .waterSort:
                // faint standing tubes with rising bubbles
                for index in 0..<5 {
                    let tubeW: CGFloat = 26
                    let x = CGFloat((index * 83) % 340) / 340 * (size.width - tubeW)
                    let y = CGFloat((index * 173) % 620) / 620 * size.height * 0.75
                    let rect = CGRect(x: x, y: y, width: tubeW, height: 88)
                    context.stroke(Path(roundedRect: rect, cornerRadius: 12),
                                   with: .color((index.isMultiple(of: 2) ? world.accent : world.secondary).opacity(0.10)),
                                   lineWidth: 3)
                }
                for index in 0..<9 {
                    let radius: CGFloat = index.isMultiple(of: 3) ? 5 : 3
                    let x = CGFloat((index * 127) % 360) / 360 * size.width
                    let y = CGFloat((index * 211) % 740) / 740 * size.height
                    context.stroke(Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                                          width: radius * 2, height: radius * 2)),
                                   with: .color(world.ink.opacity(0.10)), lineWidth: 2)
                }
            case .numberNests:
                // Arithmetic cages drifting across a chalkboard grid.
                let step: CGFloat = 52
                for x in stride(from: -12 as CGFloat, through: size.width, by: step) {
                    for y in stride(from: -12 as CGFloat, through: size.height, by: step) {
                        let rect = CGRect(x: x, y: y, width: step, height: step)
                        context.stroke(Path(rect), with: .color(world.ink.opacity(0.045)), lineWidth: 1)
                    }
                }
                let clues = ["6+", "3−", "8×", "2÷"]
                for index in clues.indices {
                    let x = CGFloat((index * 103) % 310) / 310 * max(1, size.width - 70)
                    let y = CGFloat((index * 181) % 650) / 650 * max(1, size.height - 70)
                    let rect = CGRect(x: x, y: y, width: 70, height: index.isMultiple(of: 2) ? 104 : 70)
                    context.stroke(Path(roundedRect: rect, cornerRadius: 7),
                                   with: .color((index.isMultiple(of: 2) ? world.accent : world.secondary).opacity(0.11)),
                                   lineWidth: 3)
                    context.draw(Text(clues[index])
                                    .font(.system(size: 13, weight: .black, design: .rounded))
                                    .foregroundStyle(world.ink.opacity(0.10)),
                                 at: CGPoint(x: rect.minX + 15, y: rect.minY + 13), anchor: .center)
                }
            case .mahjong:
                // Sparse ivory tile backs resting on the lacquer, a few pips.
                for index in 0..<6 {
                    let tileW: CGFloat = 42
                    let x = CGFloat((index * 127) % 330) / 330 * (size.width - tileW)
                    let y = CGFloat((index * 211) % 700) / 700 * size.height * 0.9
                    let rect = CGRect(x: x, y: y, width: tileW, height: tileW * 1.24)
                    context.fill(Path(roundedRect: rect, cornerRadius: 7),
                                 with: .color(world.ink.opacity(0.05)))
                    context.stroke(Path(roundedRect: rect, cornerRadius: 7),
                                   with: .color((index.isMultiple(of: 2) ? world.accent : world.secondary).opacity(0.14)),
                                   lineWidth: 1.5)
                }
                for index in 0..<8 {
                    let radius: CGFloat = index.isMultiple(of: 3) ? 6 : 3.5
                    let x = CGFloat((index * 149) % 360) / 360 * size.width
                    let y = CGFloat((index * 233) % 760) / 760 * size.height
                    context.stroke(Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                                          width: radius * 2, height: radius * 2)),
                                   with: .color(world.ink.opacity(0.10)), lineWidth: 2)
                }
            case .crossword:
                // Faint newsprint rules and a few scattered ink blocks.
                for y in stride(from: 26 as CGFloat, through: size.height, by: 30) {
                    var line = Path()
                    line.move(to: CGPoint(x: 14, y: y))
                    line.addLine(to: CGPoint(x: size.width - 14, y: y))
                    context.stroke(line, with: .color(world.ink.opacity(0.05)), lineWidth: 1)
                }
                for index in 0..<7 {
                    let side: CGFloat = 22
                    let x = CGFloat((index * 131) % 340) / 340 * (size.width - side)
                    let y = CGFloat((index * 219) % 720) / 720 * size.height
                    let rect = CGRect(x: x, y: y, width: side, height: side)
                    if index.isMultiple(of: 3) {
                        context.fill(Path(rect), with: .color(world.ink.opacity(0.10)))
                    } else {
                        context.stroke(Path(rect), with: .color(world.ink.opacity(0.12)), lineWidth: 1.5)
                    }
                }
            case .split:
                context.fill(Path(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height)),
                             with: .color(world.accent.opacity(0.06)))
                context.fill(Path(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height)),
                             with: .color(world.secondary.opacity(0.06)))
                var divider = Path(); divider.move(to: CGPoint(x: size.width / 2, y: 0)); divider.addLine(to: CGPoint(x: size.width / 2, y: size.height))
                context.stroke(divider, with: .color(world.ink.opacity(0.12)), lineWidth: 2)
            case .blockFit:
                let step: CGFloat = 44
                for x in stride(from: 0 as CGFloat, through: size.width, by: step) {
                    for y in stride(from: 0 as CGFloat, through: size.height, by: step) {
                        let cell = CGRect(x: x + 3, y: y + 3, width: step - 6, height: step - 6)
                        context.stroke(Path(roundedRect: cell, cornerRadius: 6),
                                       with: .color(world.ink.opacity(0.05)), lineWidth: 1.5)
                    }
                }
                for index in 0..<5 {
                    let x = CGFloat((index * 113) % 340) / 340 * size.width
                    let y = CGFloat((index * 197) % 720) / 720 * size.height
                    let cell = CGRect(x: x, y: y, width: step - 6, height: step - 6)
                    context.fill(Path(roundedRect: cell, cornerRadius: 6),
                                 with: .color((index.isMultiple(of: 2) ? world.accent : world.secondary).opacity(0.10)))
                }
            case .fuse:
                // Charged cells drifting in the dark; a few carry the doubles.
                let step: CGFloat = 72
                for x in stride(from: 8 as CGFloat, through: size.width, by: step) {
                    for y in stride(from: 8 as CGFloat, through: size.height, by: step) {
                        let cell = CGRect(x: x, y: y, width: step - 14, height: step - 14)
                        context.stroke(Path(roundedRect: cell, cornerRadius: 10),
                                       with: .color(world.accent.opacity(0.07)), lineWidth: 1.5)
                    }
                }
                let numbers = ["2", "4", "8", "16", "32"]
                for index in 0..<numbers.count {
                    let x = (CGFloat((index * 131) % 320) / 320) * (size.width - step) + step / 2
                    let y = (CGFloat((index * 223) % 680) / 680) * (size.height - step) + step / 2
                    let cell = CGRect(x: x - (step - 14) / 2, y: y - (step - 14) / 2,
                                      width: step - 14, height: step - 14)
                    context.fill(Path(roundedRect: cell, cornerRadius: 10),
                                 with: .color((index.isMultiple(of: 2) ? world.accent : world.secondary).opacity(0.09)))
                    context.draw(Text(numbers[index])
                                    .font(.system(size: 24, weight: .black, design: .rounded))
                                    .foregroundStyle(world.ink.opacity(0.12)),
                                 at: CGPoint(x: x, y: y), anchor: .center)
                }
            case .snake:
                // Faint checkerboard with a dotted snake winding toward an apple.
                let step: CGFloat = 40
                for x in stride(from: 0 as CGFloat, through: size.width, by: step) {
                    for y in stride(from: 0 as CGFloat, through: size.height, by: step)
                    where (Int(x / step) + Int(y / step)).isMultiple(of: 2) {
                        context.fill(Path(CGRect(x: x, y: y, width: step, height: step)),
                                     with: .color(world.ink.opacity(0.03)))
                    }
                }
                let trail: [(CGFloat, CGFloat)] = [(0.16, 0.78), (0.24, 0.72), (0.32, 0.68),
                                                   (0.40, 0.62), (0.46, 0.54), (0.50, 0.44),
                                                   (0.56, 0.36), (0.64, 0.32), (0.72, 0.28)]
                for (index, point) in trail.enumerated() {
                    let radius: CGFloat = index == trail.count - 1 ? 9 : 7
                    let rect = CGRect(x: point.0 * size.width - radius,
                                      y: point.1 * size.height - radius,
                                      width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(world.accent.opacity(0.12)))
                }
                context.fill(Path(ellipseIn: CGRect(x: size.width * 0.84 - 8,
                                                    y: size.height * 0.24 - 8,
                                                    width: 16, height: 16)),
                             with: .color(world.secondary.opacity(0.22)))
            case .tower:
                // High-altitude sky: a soft glow band, scattered stars, clouds.
                context.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .linearGradient(
                                Gradient(colors: [world.accent.opacity(0.10), .clear, world.secondary.opacity(0.06)]),
                                startPoint: .zero,
                                endPoint: CGPoint(x: 0, y: size.height)))
                for index in 0..<18 {
                    let radius: CGFloat = index.isMultiple(of: 5) ? 1.8 : 1.1
                    let x = CGFloat((index * 97) % 360) / 360 * size.width
                    let y = CGFloat((index * 173) % 760) / 760 * size.height
                    context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                                        width: radius * 2, height: radius * 2)),
                                 with: .color(world.ink.opacity(index.isMultiple(of: 3) ? 0.22 : 0.12)))
                }
                for index in 0..<3 {
                    let w = size.width * 0.34
                    let x = CGFloat((index * 151) % 300) / 300 * (size.width - w)
                    let y = size.height * (0.24 + 0.27 * CGFloat(index))
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: w, height: w * 0.22)),
                                 with: .color(world.ink.opacity(0.045)))
                }
            }
        }
    }
}

// MARK: - Vignette host

/// The illustrated gameplay preview that fills a library card. Purely
/// decorative — the card's texts carry accessibility.
struct GamePosterArt: View {
    let game: GameID

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                switch game {
                case .arrowStorm: ArrowStormPoster(w: w, h: h)
                case .crowdControl: CrowdControlPoster(w: w, h: h)
                case .echoGrid: EchoGridPoster(w: w, h: h)
                case .colorClash: ColorClashPoster(w: w, h: h)
                case .tileShift: TileShiftPoster(w: w, h: h)
                case .lastSeen: LastSeenPoster(w: w, h: h)
                case .slidePuzzle: SlidePuzzlePoster(w: w, h: h)
                case .blockEscape: BlockEscapePoster(w: w, h: h)
                case .pegSolitaire: PegSolitairePoster(w: w, h: h)
                case .waterSort: WaterSortPoster(w: w, h: h)
                case .numberNests: NumberNestsPoster(w: w, h: h)
                case .mahjong: MahjongPoster(w: w, h: h)
                case .crossword: CrosswordPoster(w: w, h: h)
                case .split: SplitPoster(w: w, h: h)
                case .blockFit: BlockFitPoster(w: w, h: h)
                case .fuse: FusePoster(w: w, h: h)
                case .snake: SnakePoster(w: w, h: h)
                case .tower: TowerPoster(w: w, h: h)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Arrow storm — flankers pull left, the middle arrow points right.

private struct ArrowStormPoster: View {
    let w: CGFloat, h: CGFloat

    var body: some View {
        let xs: [CGFloat] = [0.16, 0.33, 0.50, 0.67, 0.84]
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                let isTarget = i == 2
                Image(systemName: isTarget ? "arrow.right" : "arrow.left")
                    .font(.system(size: w * (isTarget ? 0.16 : 0.105), weight: .heavy))
                    .foregroundStyle(isTarget ? .white : Color(hexAny: 0xC98F1F))
                    .shadow(color: isTarget ? Color(hexAny: 0xFFC53D).opacity(0.8) : .clear,
                            radius: 7)
                    .position(x: xs[i] * w, y: h * 0.56)
            }
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: "arrow.left")
                    .font(.system(size: w * 0.08, weight: .heavy))
                    .foregroundStyle(Color(hexAny: 0xC98F1F).opacity(0.35))
                    .position(x: (0.26 + 0.24 * CGFloat(i)) * w, y: h * 0.80)
            }
        }
    }
}

// MARK: - Crowd control — a few glowing dots hide in an identical crowd.

private struct CrowdControlPoster: View {
    let w: CGFloat, h: CGFloat

    private let dots: [(x: CGFloat, y: CGFloat, glow: Bool)] = [
        (0.22, 0.48, true), (0.52, 0.44, false), (0.80, 0.50, false),
        (0.36, 0.63, false), (0.66, 0.62, true), (0.20, 0.78, false),
        (0.46, 0.82, false), (0.80, 0.79, true),
    ]

    var body: some View {
        let r = w * 0.058
        ZStack {
            ForEach(0..<dots.count, id: \.self) { i in
                let d = dots[i]
                Circle()
                    .fill(d.glow ? Color(hexAny: 0x53C9F5) : .white.opacity(0.22))
                    .frame(width: r * 2, height: r * 2)
                    .overlay(Circle().strokeBorder(.white.opacity(d.glow ? 0.9 : 0), lineWidth: 2))
                    .shadow(color: d.glow ? Color(hexAny: 0x53C9F5).opacity(0.8) : .clear, radius: 6)
                    .position(x: d.x * w, y: d.y * h)
            }
        }
    }
}

// MARK: - Echo grid — a lit path to play back in reverse.

private struct EchoGridPoster: View {
    let w: CGFloat, h: CGFloat

    // (index, step label) — the path the player has to echo backwards.
    private let lit: [Int: Int] = [6: 1, 4: 2, 2: 3]

    var body: some View {
        let s = w * 0.175
        let gap = w * 0.024
        ZStack {
            ForEach(0..<9, id: \.self) { i in
                let col = CGFloat(i % 3) - 1
                let row = CGFloat(i / 3) - 1
                let step = lit[i]
                RoundedRectangle(cornerRadius: s * 0.26, style: .continuous)
                    .fill(step != nil ? Color(hexAny: 0x8B6DF5) : .white.opacity(0.10))
                    .frame(width: s, height: s)
                    .overlay {
                        if let step {
                            Text("\(step)")
                                .font(.system(size: s * 0.52, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                        }
                    }
                    .shadow(color: step != nil ? Color(hexAny: 0x8B6DF5).opacity(0.7) : .clear, radius: 6)
                    .position(x: w * 0.5 + col * (s + gap), y: h * 0.64 + row * (s + gap))
            }
        }
    }
}

// MARK: - Color clash — the word never matches its ink.

private struct ColorClashPoster: View {
    let w: CGFloat, h: CGFloat

    var body: some View {
        ZStack {
            wordChip("pink", ink: Color(hexAny: 0x43DDC7))
                .rotationEffect(.degrees(-5))
                .position(x: w * 0.42, y: h * 0.54)
            wordChip("teal", ink: Color(hexAny: 0xFF6FB5))
                .rotationEffect(.degrees(4))
                .position(x: w * 0.58, y: h * 0.78)
        }
    }

    private func wordChip(_ word: String, ink: Color) -> some View {
        Text(word)
            .font(.system(size: w * 0.13, weight: .heavy, design: .rounded))
            .foregroundStyle(ink)
            .padding(.horizontal, w * 0.06)
            .padding(.vertical, w * 0.030)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: w * 0.05, style: .continuous))
    }
}

// MARK: - Tile shift — the matching rule keeps flipping.

private struct TileShiftPoster: View {
    let w: CGFloat, h: CGFloat

    var body: some View {
        let s = w * 0.24
        ZStack {
            tile(at: CGPoint(x: w * 0.30, y: h * 0.54), size: s) {
                Circle()
                    .fill(Color(hexAny: 0xFFD166))
                    .frame(width: s * 0.5, height: s * 0.5)
            }
            tile(at: CGPoint(x: w * 0.70, y: h * 0.80), size: s) {
                TrianglePoster()
                    .fill(Color(hexAny: 0xFF6FB5))
                    .frame(width: s * 0.54, height: s * 0.48)
            }
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: w * 0.13, weight: .heavy))
                .foregroundStyle(.white)
                .shadow(color: Color(hexAny: 0x43DDC7).opacity(0.7), radius: 6)
                .position(x: w * 0.56, y: h * 0.62)
        }
    }

    private func tile<Content: View>(at p: CGPoint, size: CGFloat,
                                     @ViewBuilder content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(.white.opacity(0.12))
            .frame(width: size, height: size)
            .overlay(content())
            .position(p)
    }
}

private struct TrianglePoster: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Last seen — one of these was already tapped.

private struct LastSeenPoster: View {
    let w: CGFloat, h: CGFloat

    private let items: [(symbol: String, hex: UInt32, x: CGFloat, y: CGFloat, seen: Bool)] = [
        ("star.fill", 0xFFD166, 0.26, 0.50, false),
        ("heart.fill", 0xFF6FB5, 0.71, 0.47, false),
        ("bolt.fill", 0x43DDC7, 0.50, 0.64, true),
        ("moon.fill", 0xB4A0FF, 0.28, 0.80, false),
        ("cloud.fill", 0x9BD6FF, 0.74, 0.80, false),
    ]

    var body: some View {
        ZStack {
            ForEach(0..<items.count, id: \.self) { i in
                let item = items[i]
                Image(systemName: item.symbol)
                    .font(.system(size: w * 0.115, weight: .heavy))
                    .foregroundStyle(Color(hexAny: item.hex))
                    .padding(w * 0.035)
                    .overlay {
                        if item.seen {
                            Circle()
                                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [4, 3.5]))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    .position(x: item.x * w, y: item.y * h)
            }
        }
    }
}

// MARK: - Slide puzzle — scrambled tiles, one gap.

private struct SlidePuzzlePoster: View {
    let w: CGFloat, h: CGFloat

    private let tiles: [Int?] = [2, 8, 3, 1, 6, 5, 7, nil, 4]

    var body: some View {
        let s = w * 0.185
        let gap = w * 0.022
        ZStack {
            ForEach(0..<9, id: \.self) { i in
                if let n = tiles[i] {
                    let col = CGFloat(i % 3) - 1
                    let row = CGFloat(i / 3) - 1
                    RoundedRectangle(cornerRadius: s * 0.24, style: .continuous)
                        .fill(Color(hexAny: 0x4C6FD9))
                        .frame(width: s, height: s)
                        .overlay(
                            Text("\(n)")
                                .font(.system(size: s * 0.5, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                        )
                        .position(x: w * 0.5 + col * (s + gap), y: h * 0.64 + row * (s + gap))
                }
            }
        }
    }
}

// MARK: - Block escape — free the big red block (bottom exit).

private struct BlockEscapePoster: View {
    let w: CGFloat, h: CGFloat

    var body: some View {
        let s = w * 0.175
        let gap = w * 0.02
        let step = s + gap
        let cx = w * 0.5
        let cy = h * 0.65
        let tan = Color(hexAny: 0xD9B98A)

        func center(_ col: CGFloat, _ row: CGFloat) -> CGPoint {
            CGPoint(x: cx + (col - 1) * step, y: cy + (row - 1) * step)
        }

        return ZStack {
            RoundedRectangle(cornerRadius: s * 0.3, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 2.5)
                .frame(width: step * 3 + gap * 3, height: step * 3 + gap * 3)
                .position(x: cx, y: cy)

            block(tan, w: s, h: s).position(center(0, 0))
            block(tan, w: s, h: s).position(center(1, 0))
            block(tan, w: s, h: s * 2 + gap).position(center(2, 0.5))
            block(tan, w: s, h: s).position(center(0, 2))
            block(tan, w: s, h: s).position(center(2, 2))

            // The hero block, one row above the open exit cell.
            block(Color(hexAny: 0xE84545), w: s * 2 + gap, h: s)
                .shadow(color: Color(hexAny: 0xE84545).opacity(0.55), radius: 7)
                .position(center(0.5, 1))

            Image(systemName: "chevron.down")
                .font(.system(size: s * 0.42, weight: .heavy))
                .foregroundStyle(.white.opacity(0.7))
                .position(center(1, 2))
        }
    }

    private func block(_ color: Color, w bw: CGFloat, h bh: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: min(bw, bh) * 0.26, style: .continuous)
            .fill(color)
            .frame(width: bw, height: bh)
    }
}

// MARK: - Peg solitaire — jump pegs, leave one.

private struct PegSolitairePoster: View {
    let w: CGFloat, h: CGFloat

    // Cross layout: (col, row) on a 3x3-with-arms grid; center is the hole.
    private let pegs: [(CGFloat, CGFloat)] = [
        (1, -0.1), (0, 1), (2, 1), (1, 2.1), (0.15, 0.15), (1.85, 0.15), (0.15, 1.85), (1.85, 1.85),
    ]

    var body: some View {
        let r = w * 0.062
        let step = w * 0.20
        let cx = w * 0.5
        let cy = h * 0.65

        func center(_ col: CGFloat, _ row: CGFloat) -> CGPoint {
            CGPoint(x: cx + (col - 1) * step, y: cy + (row - 1) * step)
        }

        return ZStack {
            ForEach(0..<pegs.count, id: \.self) { i in
                Circle()
                    .fill(Color(hexAny: 0x74E39F))
                    .frame(width: r * 2, height: r * 2)
                    .overlay(
                        Circle()
                            .fill(.white.opacity(0.35))
                            .frame(width: r * 0.7, height: r * 0.7)
                            .offset(x: -r * 0.3, y: -r * 0.3)
                    )
                    .position(center(pegs[i].0, pegs[i].1))
            }
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [4, 3.5]))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: r * 2, height: r * 2)
                .position(center(1, 1))
        }
    }
}

// MARK: - Water sort — pour the top colours until every tube runs clean.

private struct WaterSortPoster: View {
    let w: CGFloat, h: CGFloat

    // Segments bottom → top per tube; the middle tube is one pour from done.
    private let fills: [[Int]] = [[0, 2, 1, 2], [1, 1, 1], [2, 0, 0]]
    private static let liquid: [Color] = [
        Color(hexAny: 0xF25757), Color(hexAny: 0x3ED8C3), Color(hexAny: 0xF8E14B)
    ]

    var body: some View {
        let tubeW = w * 0.155
        let tubeH = h * 0.46
        let unit = tubeH / 4.6
        let xs: [CGFloat] = [0.28, 0.50, 0.72]
        let cy = h * 0.66

        ZStack {
            ForEach(0..<fills.count, id: \.self) { i in
                tube(fills[i], tubeW: tubeW, tubeH: tubeH, unit: unit)
                    .position(x: w * xs[i], y: cy)
            }

            // the pour: a teal drop falling toward the middle tube
            Capsule()
                .fill(Self.liquid[1])
                .frame(width: w * 0.035, height: h * 0.085)
                .position(x: w * 0.50, y: cy - tubeH * 0.68)
                .shadow(color: Self.liquid[1].opacity(0.7), radius: 5)
        }
    }

    private func tube(_ segments: [Int], tubeW: CGFloat, tubeH: CGFloat, unit: CGFloat) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: tubeW * 0.18,
                                           bottomLeadingRadius: tubeW * 0.5,
                                           bottomTrailingRadius: tubeW * 0.5,
                                           topTrailingRadius: tubeW * 0.18,
                                           style: .continuous)
        return ZStack(alignment: .bottom) {
            shape.fill(.white.opacity(0.08))
            VStack(spacing: 0) {
                ForEach(Array(segments.reversed().enumerated()), id: \.offset) { _, color in
                    Rectangle()
                        .fill(Self.liquid[color])
                        .frame(height: unit)
                }
            }
            .padding(2.5)
            .clipShape(shape.inset(by: 2.5))
            shape.strokeBorder(.white.opacity(0.30), lineWidth: 2)
        }
        .frame(width: tubeW, height: tubeH)
    }
}

// MARK: - Number Nests — arithmetic cages inside a Latin-square grid.

private struct NumberNestsPoster: View {
    let w: CGFloat, h: CGFloat

    private let values = [[1, 3, 2], [2, 1, 3], [3, 2, 1]]
    private let clues: [Int: String] = [0: "4+", 2: "2", 3: "6×", 4: "5+", 7: "2"]

    var body: some View {
        let isWide = w > h * 1.15
        let side = isWide ? min(w * 0.46, h * 0.72) : min(w * 0.70, h * 0.52)
        let cell = side / 3
        let origin = CGPoint(x: (w - side) / 2,
                             y: isWide ? h * 0.08 : h * 0.31)

        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(hexAny: 0x193C3A))
                .frame(width: side, height: side)
                .offset(x: origin.x, y: origin.y)
                .shadow(color: .black.opacity(0.18), radius: 9, y: 6)

            ForEach(0..<9, id: \.self) { index in
                let r = index / 3, c = index % 3
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .strokeBorder(.white.opacity(0.24), lineWidth: 1)
                    if let clue = clues[index] {
                        Text(clue)
                            .font(.system(size: cell * 0.18, weight: .black, design: .rounded))
                            .foregroundStyle(Color(hexAny: 0xF4C95D))
                            .padding(3)
                    }
                    Text("\(values[r][c])")
                        .font(.system(size: cell * 0.46, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: cell, height: cell)
                        .offset(y: cell * 0.08)
                }
                .frame(width: cell, height: cell)
                .offset(x: origin.x + CGFloat(c) * cell,
                        y: origin.y + CGFloat(r) * cell)
            }

            // Five valid arithmetic nests, including one L-shaped region.
            Path { path in
                path.addRect(CGRect(origin: origin, size: CGSize(width: side, height: side)))

                path.move(to: CGPoint(x: origin.x, y: origin.y + cell))
                path.addLine(to: CGPoint(x: origin.x + side, y: origin.y + cell))

                path.move(to: CGPoint(x: origin.x + cell, y: origin.y + cell * 2))
                path.addLine(to: CGPoint(x: origin.x + cell * 2, y: origin.y + cell * 2))

                path.move(to: CGPoint(x: origin.x + cell, y: origin.y + cell))
                path.addLine(to: CGPoint(x: origin.x + cell, y: origin.y + side))

                path.move(to: CGPoint(x: origin.x + cell * 2, y: origin.y))
                path.addLine(to: CGPoint(x: origin.x + cell * 2, y: origin.y + cell))

                path.move(to: CGPoint(x: origin.x + cell * 2, y: origin.y + cell * 2))
                path.addLine(to: CGPoint(x: origin.x + cell * 2, y: origin.y + side))
            }
            .stroke(.white.opacity(0.88),
                    style: StrokeStyle(lineWidth: max(2, cell * 0.065),
                                       lineCap: .square,
                                       lineJoin: .round))
        }
    }
}

// MARK: - Mahjong — a small stack with a matched pair glowing gold.

private struct MahjongPoster: View {
    let w: CGFloat, h: CGFloat

    var body: some View {
        let tileW = w * 0.165
        let tileH = tileW * 1.24
        let depth = tileW * 0.13
        // (x, y in tile-position fractions, face, selected)
        let placed: [(CGFloat, CGFloat, MahjongFace, Bool)] = [
            (0.16, 0.52, MahjongFace(suit: .bamboo, rank: 3), false),
            (0.36, 0.50, MahjongFace(suit: .dots, rank: 5), true),
            (0.57, 0.55, MahjongFace(suit: .characters, rank: 3), false),
            (0.78, 0.50, MahjongFace(suit: .winds, rank: 1), false),
            (0.22, 0.74, MahjongFace(suit: .dragons, rank: 1), false),
            (0.44, 0.76, MahjongFace(suit: .bamboo, rank: 7), false),
            (0.68, 0.75, MahjongFace(suit: .dots, rank: 5), true),
        ]

        return ZStack {
            // one straddling tile on top sells the stack
            ForEach(0..<placed.count, id: \.self) { index in
                let tile = placed[index]
                MahjongTileView(face: tile.2,
                                width: tileW,
                                height: tileH,
                                depth: depth)
                    .shadow(color: tile.3 ? Color(hexAny: 0xF2C14E).opacity(0.55) : .clear, radius: 8)
                    .position(x: tile.0 * w + tileW / 2, y: tile.1 * h + tileH / 2)
            }
            MahjongTileView(face: MahjongFace(suit: .dragons, rank: 2),
                            width: tileW,
                            height: tileH,
                            depth: depth)
                .rotationEffect(.degrees(-3))
                .position(x: w * 0.52, y: h * 0.44)
        }
    }
}

// MARK: - Split — steer on the left, pick on the right, all at once.

private struct SplitPoster: View {
    let w: CGFloat, h: CGFloat

    var body: some View {
        let pillar = Color(hexAny: 0x39E6E2)
        ZStack {
            // The screen divide runs down the middle, like the game.
            Capsule()
                .fill(.white.opacity(0.16))
                .frame(width: 3, height: h * 0.50)
                .position(x: w * 0.5, y: h * 0.665)

            // Left hand: flyer threading a pillar gap.
            Image(systemName: "paperplane.fill")
                .font(.system(size: w * 0.115, weight: .heavy))
                .foregroundStyle(.white)
                .shadow(color: Color(hexAny: 0xFF6B6B).opacity(0.7), radius: 6)
                .position(x: w * 0.20, y: h * 0.70)

            RoundedRectangle(cornerRadius: w * 0.025, style: .continuous)
                .fill(pillar)
                .frame(width: w * 0.11, height: h * 0.11)
                .position(x: w * 0.37, y: h * 0.505)
            RoundedRectangle(cornerRadius: w * 0.025, style: .continuous)
                .fill(pillar)
                .frame(width: w * 0.11, height: h * 0.11)
                .position(x: w * 0.37, y: h * 0.825)

            // Right hand: two targets and the green look-alike trap.
            apple(Color(hexAny: 0xFF5964)).position(x: w * 0.66, y: h * 0.50)
            apple(Color(hexAny: 0xFF5964)).position(x: w * 0.85, y: h * 0.61)
            apple(Color(hexAny: 0x8FD65A)).position(x: w * 0.70, y: h * 0.76)
        }
    }

    /// Emoji-free apple: a circle with a stem tick, so posters don't depend on
    /// the simulator/device emoji fallback at odd sizes.
    private func apple(_ color: Color) -> some View {
        let d = w * 0.115
        return ZStack {
            Capsule()
                .fill(Color(hexAny: 0x8A5A2B))
                .frame(width: d * 0.10, height: d * 0.30)
                .rotationEffect(.degrees(14))
                .offset(y: -d * 0.55)
            Circle()
                .fill(color)
                .frame(width: d, height: d)
                .overlay(
                    Circle()
                        .fill(.white.opacity(0.35))
                        .frame(width: d * 0.28, height: d * 0.28)
                        .offset(x: -d * 0.18, y: -d * 0.18)
                )
        }
    }
}

// MARK: - Block fit — a hand piece hovers over the almost-full bottom row.

private struct BlockFitPoster: View {
    let w: CGFloat, h: CGFloat

    // (col, row, palette hex) on a 5-wide board; row 3 is one cell from full.
    private let placed: [(Int, Int, UInt32)] = [
        (0, 3, 0xFFB13B), (1, 3, 0x4BE3A9), (2, 3, 0x58B4FF), (4, 3, 0xFF5E7A),
        (0, 2, 0x4BE3A9), (1, 2, 0xA78BFF),
        (4, 2, 0xFFB13B), (4, 1, 0x58B4FF),
    ]

    var body: some View {
        let s = w * 0.145
        let gap = w * 0.014
        let step = s + gap
        let originX = w * 0.5 - step * 2.5 + gap / 2
        let originY = h * 0.86 - step * 4

        func position(_ col: Int, _ row: Int) -> CGPoint {
            CGPoint(x: originX + (CGFloat(col) + 0.5) * step,
                    y: originY + (CGFloat(row) + 0.5) * step)
        }

        return ZStack {
            // Faint empty grid.
            ForEach(0..<20, id: \.self) { i in
                RoundedRectangle(cornerRadius: s * 0.2, style: .continuous)
                    .fill(.white.opacity(0.07))
                    .frame(width: s, height: s)
                    .position(position(i % 5, i / 5))
            }
            ForEach(0..<placed.count, id: \.self) { i in
                let cell = placed[i]
                block(Color(hexAny: cell.2), size: s)
                    .position(position(cell.0, cell.1))
            }
            // The missing cell, marked like a landing slot.
            RoundedRectangle(cornerRadius: s * 0.2, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [4, 3.5]))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: s, height: s)
                .position(position(3, 3))

            // The floating hand piece, mid-drag with a glow.
            ZStack {
                block(Color(hexAny: 0xFFE066), size: s).offset(x: -step / 2, y: -step / 2)
                block(Color(hexAny: 0xFFE066), size: s).offset(x: step / 2, y: -step / 2)
                block(Color(hexAny: 0xFFE066), size: s).offset(x: -step / 2, y: step / 2)
            }
            .shadow(color: Color(hexAny: 0xFFE066).opacity(0.55), radius: 8)
            .position(x: w * 0.62, y: h * 0.42)
        }
    }

    private func block(_ color: Color, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                    .fill(.white.opacity(0.28))
                    .frame(width: size * 0.42, height: size * 0.42)
                    .offset(x: -size * 0.16, y: -size * 0.16)
            )
    }
}

// MARK: - Fuse — two 32s about to fuse under the charged result.

private struct FusePoster: View {
    let w: CGFloat, h: CGFloat

    // (col, row, value) on the 4×4 board; the bottom row stages the fusion.
    private let placed: [(Int, Int, Int)] = [
        (1, 1, 2), (3, 1, 8),
        (0, 2, 4), (2, 2, 16),
        (0, 3, 32), (1, 3, 32), (3, 3, 128),
    ]

    var body: some View {
        let s = w * 0.16
        let gap = w * 0.018
        let step = s + gap
        let originX = w * 0.5 - step * 2 + gap / 2
        let originY = h * 0.90 - step * 4

        func position(_ col: Int, _ row: Int) -> CGPoint {
            CGPoint(x: originX + (CGFloat(col) + 0.5) * step,
                    y: originY + (CGFloat(row) + 0.5) * step)
        }

        return ZStack {
            // The steel board with its empty wells.
            RoundedRectangle(cornerRadius: s * 0.22, style: .continuous)
                .fill(Color(hexAny: 0x1A2333))
                .frame(width: step * 4 + gap * 2, height: step * 4 + gap * 2)
                .position(x: originX + step * 2, y: originY + step * 2)
            ForEach(0..<16, id: \.self) { i in
                RoundedRectangle(cornerRadius: s * 0.16, style: .continuous)
                    .fill(Color(hexAny: 0x263248))
                    .frame(width: s, height: s)
                    .position(position(i % 4, i / 4))
            }
            ForEach(0..<placed.count, id: \.self) { i in
                let cell = placed[i]
                FusePosterTile(value: cell.2, size: s)
                    .position(position(cell.0, cell.1))
            }

            // The fusion arrow between the two 32s.
            Image(systemName: "arrow.right")
                .font(.system(size: s * 0.34, weight: .black))
                .foregroundStyle(.white)
                .shadow(color: Color(hexAny: 0x4DD9C6).opacity(0.8), radius: 4)
                .position(x: originX + step, y: originY + step * 3.5)

            // The charged result, floating above the board with a glow.
            FusePosterTile(value: 64, size: s * 1.28)
                .shadow(color: Color(hexAny: 0xFF5FA8).opacity(0.6), radius: 10)
                .rotationEffect(.degrees(-4))
                .position(x: w * 0.62, y: originY - s * 0.62)
        }
    }
}

private struct FusePosterTile: View {
    let value: Int
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
            .fill(FusePalette.fill(value))
            .frame(width: size, height: size)
            .overlay {
                Text("\(value)")
                    .font(.system(size: size * (value < 100 ? 0.5 : 0.4),
                                  weight: .black, design: .rounded))
                    .foregroundStyle(FusePalette.ink(value))
                    .minimumScaleFactor(0.5)
            }
    }
}

// MARK: - Snake — a green snake winds across the pitch toward one red apple.

private struct SnakePoster: View {
    let w: CGFloat, h: CGFloat

    // Body path in relative coords, head last.
    private let trail: [(CGFloat, CGFloat)] = [
        (0.20, 0.86), (0.30, 0.86), (0.40, 0.86), (0.50, 0.86), (0.60, 0.86),
        (0.70, 0.86), (0.70, 0.74), (0.70, 0.62),
        (0.60, 0.62), (0.50, 0.62), (0.40, 0.62), (0.30, 0.62),
        (0.30, 0.50), (0.30, 0.38),
        (0.40, 0.38), (0.50, 0.38),
    ]

    var body: some View {
        let r = w * 0.062

        ZStack {
            // A soft checkerboard patch behind the action.
            ForEach(0..<24, id: \.self) { i in
                let col = i % 6, row = i / 6
                if (col + row).isMultiple(of: 2) {
                    Rectangle()
                        .fill(Color.white.opacity(0.03))
                        .frame(width: w * 0.14, height: w * 0.14)
                        .position(x: w * (0.16 + 0.14 * CGFloat(col)),
                                  y: h * 0.34 + w * 0.14 * CGFloat(row))
                }
            }

            ForEach(0..<trail.count, id: \.self) { i in
                let isHead = i == trail.count - 1
                Circle()
                    .fill(Color(hexAny: i.isMultiple(of: 2) ? 0x58C452 : 0x6ED95F))
                    .frame(width: r * (isHead ? 2.4 : 2), height: r * (isHead ? 2.4 : 2))
                    .overlay {
                        if isHead {
                            HStack(spacing: r * 0.34) {
                                ForEach(0..<2, id: \.self) { _ in
                                    ZStack {
                                        Circle().fill(.white)
                                            .frame(width: r * 0.8, height: r * 0.8)
                                        Circle().fill(.black)
                                            .frame(width: r * 0.4, height: r * 0.4)
                                            .offset(x: r * 0.14)
                                    }
                                }
                            }
                            .offset(y: -r * 0.1)
                        }
                    }
                    .shadow(color: isHead ? Color(hexAny: 0x5FE868).opacity(0.5) : .clear,
                            radius: 6)
                    .position(x: trail[i].0 * w, y: trail[i].1 * h)
            }

            // The apple just out of reach.
            ZStack {
                Circle()
                    .fill(Color(hexAny: 0xF05B4C))
                Ellipse()
                    .fill(Color(hexAny: 0x1F4A22))
                    .frame(width: r * 0.7, height: r * 0.36)
                    .rotationEffect(.degrees(-24))
                    .offset(x: r * 0.16, y: -r * 0.9)
            }
            .frame(width: r * 2.1, height: r * 2.1)
            .shadow(color: Color(hexAny: 0xF05B4C).opacity(0.6), radius: 7)
            .position(x: 0.70 * w, y: 0.38 * h)
        }
    }
}

// MARK: - Crossword — a mini grid mid-solve, one word inked in blue.

private struct CrosswordPoster: View {
    let w: CGFloat, h: CGFloat

    // 5×5 mini: "" = empty, "#" = block, letters = solved.
    private let cells: [[String]] = [
        ["#", "#", "W", "I", "T"],
        ["#", "M", "I", "N", "D"],
        ["W", "O", "R", "D", ""],
        ["", "P", "E", "", "#"],
        ["", "S", "", "#", "#"]
    ]

    var body: some View {
        // Sized and dropped to clear the two-line title above the vignette.
        let side = w * 0.122
        let originX = w * 0.5 - side * 2.5
        let originY = h * 0.60 - side * 2.5

        ZStack {
            ForEach(0..<25, id: \.self) { index in
                let r = index / 5, c = index % 5
                let value = cells[r][c]
                ZStack {
                    Rectangle()
                        .fill(value == "#" ? Color(hexAny: 0x1C1A15)
                              : (r == 2 ? Color(hexAny: 0x2B62E3).opacity(0.18) : Color(hexAny: 0xFFFDF6)))
                    Rectangle()
                        .strokeBorder(Color(hexAny: 0x1C1A15).opacity(0.5), lineWidth: 1)
                    if value != "#", !value.isEmpty {
                        Text(value)
                            .font(.system(size: side * 0.58, weight: .heavy, design: .serif))
                            .foregroundStyle(Color(hexAny: r == 2 ? 0x2B62E3 : 0x1C1A15))
                    }
                }
                .frame(width: side, height: side)
                .position(x: originX + (CGFloat(c) + 0.5) * side,
                          y: originY + (CGFloat(r) + 0.5) * side)
            }
        }
        .shadow(color: Color(hexAny: 0x1C1A15).opacity(0.12), radius: 8, y: 4)
    }
}

// MARK: - Tower — an isometric stack climbing the sky, one block sliding in.

private struct TowerPoster: View {
    let w: CGFloat, h: CGFloat

    var body: some View {
        Canvas { context, size in
            let s = Double(size.width) * 0.26
            let cx = Double(size.width) * 0.5
            let baseY = Double(size.height) * 0.92
            let layerH = 0.30
            // (hue-walked pinks, bottom to top; footprints shrink slightly.)
            let hues: [Double] = [0.955, 0.965, 0.978, 0.99, 0.005]

            func project(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
                CGPoint(x: cx + (x - z) * 0.866 * s,
                        y: baseY - y * s + (x + z) * 0.5 * s)
            }

            func quad(_ points: [CGPoint], _ color: Color) {
                var path = Path()
                path.move(to: points[0])
                for point in points.dropFirst() { path.addLine(to: point) }
                path.closeSubpath()
                context.fill(path, with: .color(color))
            }

            func box(cx bx: Double, cz bz: Double, size half: Double,
                     yBottom: Double, yTop: Double, hue: Double) {
                let x0 = bx - half, x1 = bx + half
                let z0 = bz - half, z1 = bz + half
                quad([project(x0, yTop, z0), project(x1, yTop, z0),
                      project(x1, yTop, z1), project(x0, yTop, z1)],
                     Color(hue: hue, saturation: 0.48, brightness: 0.94))
                quad([project(x1, yTop, z0), project(x1, yTop, z1),
                      project(x1, yBottom, z1), project(x1, yBottom, z0)],
                     Color(hue: hue, saturation: 0.48, brightness: 0.58))
                quad([project(x0, yTop, z1), project(x1, yTop, z1),
                      project(x1, yBottom, z1), project(x0, yBottom, z1)],
                     Color(hue: hue, saturation: 0.48, brightness: 0.74))
            }

            // Pedestal and the stacked slabs.
            box(cx: 0, cz: 0, size: 0.5, yBottom: -1.2, yTop: 0, hue: hues[0])
            for i in 0..<4 {
                box(cx: 0, cz: 0, size: 0.5 - Double(i) * 0.05,
                    yBottom: Double(i) * layerH, yTop: Double(i + 1) * layerH,
                    hue: hues[min(i + 1, hues.count - 1)])
            }

            // The next block slides in from the upper left.
            box(cx: -0.85, cz: 0, size: 0.35,
                yBottom: 4 * layerH, yTop: 5 * layerH, hue: hues[4])

            // A perfect-drop ring around the current top.
            let top = 4 * layerH
            var ring = Path()
            ring.move(to: project(-0.55, top, -0.55))
            ring.addLine(to: project(0.55, top, -0.55))
            ring.addLine(to: project(0.55, top, 0.55))
            ring.addLine(to: project(-0.55, top, 0.55))
            ring.closeSubpath()
            context.stroke(ring, with: .color(.white.opacity(0.5)), lineWidth: 2)
        }
        .allowsHitTesting(false)
    }
}
