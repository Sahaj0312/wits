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

// MARK: - Poster palette

extension GameID {
    /// Full-bleed card background.
    var posterBackground: Color {
        switch self {
        case .arrowStorm: Color(hexAny: 0x5C3A06)
        case .crowdControl: Color(hexAny: 0x0C3B58)
        case .echoGrid: Color(hexAny: 0x2E2160)
        case .colorClash: Color(hexAny: 0x511437)
        case .tileShift: Color(hexAny: 0x0D4744)
        case .lastSeen: Color(hexAny: 0x3B1A55)
        case .slidePuzzle: Color(hexAny: 0x1A2F6E)
        case .blockEscape: Color(hexAny: 0x4A2C12)
        case .pegSolitaire: Color(hexAny: 0x123F26)
        case .split: Color(hexAny: 0x1D1D33)
        }
    }

    /// Title + underline color on the poster.
    var posterAccent: Color {
        switch self {
        case .arrowStorm: Color(hexAny: 0xFFC53D)
        case .crowdControl: Color(hexAny: 0x53C9F5)
        case .echoGrid: Color(hexAny: 0xB4A0FF)
        case .colorClash: Color(hexAny: 0xFF6FB5)
        case .tileShift: Color(hexAny: 0x43DDC7)
        case .lastSeen: Color(hexAny: 0xFFD166)
        case .slidePuzzle: Color(hexAny: 0x92B4FF)
        case .blockEscape: Color(hexAny: 0xFF8A5C)
        case .pegSolitaire: Color(hexAny: 0x74E39F)
        case .split: Color(hexAny: 0xFF6B6B)
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
                case .split: SplitPoster(w: w, h: h)
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

// MARK: - Split — steer below, pick above, all at once.

private struct SplitPoster: View {
    let w: CGFloat, h: CGFloat

    var body: some View {
        let pillar = Color(hexAny: 0x74E39F)
        ZStack {
            // Go/no-go up top: two red targets and the green look-alike trap.
            apple(Color(hexAny: 0xFF5964)).position(x: w * 0.28, y: h * 0.49)
            apple(Color(hexAny: 0xFF5964)).position(x: w * 0.50, y: h * 0.46)
            apple(Color(hexAny: 0x8FD65A)).position(x: w * 0.73, y: h * 0.50)

            Capsule()
                .fill(.white.opacity(0.16))
                .frame(width: w * 0.74, height: 3)
                .position(x: w * 0.5, y: h * 0.615)

            // Flappy lane below: flyer + a pillar gap to thread.
            Image(systemName: "paperplane.fill")
                .font(.system(size: w * 0.115, weight: .heavy))
                .foregroundStyle(.white)
                .shadow(color: Color(hexAny: 0xFF6B6B).opacity(0.7), radius: 6)
                .position(x: w * 0.30, y: h * 0.76)

            RoundedRectangle(cornerRadius: w * 0.025, style: .continuous)
                .fill(pillar)
                .frame(width: w * 0.11, height: h * 0.085)
                .position(x: w * 0.72, y: h * 0.685)
            RoundedRectangle(cornerRadius: w * 0.025, style: .continuous)
                .fill(pillar)
                .frame(width: w * 0.11, height: h * 0.085)
                .position(x: w * 0.72, y: h * 0.845)
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
