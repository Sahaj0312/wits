//
//  ArcadeDraw.swift
//  wits
//
//  Shared Canvas drawing helpers that give the arcade games depth and glow — a
//  dark "arena" stage and glossy, lit entities instead of flat primitives.
//

import SwiftUI

extension GraphicsContext {
    /// A glowing, top-lit orb with a glossy highlight.
    func orb(_ rect: CGRect, color: Color, glow: Double = 0.7) {
        var g = self
        g.addFilter(.shadow(color: color.opacity(glow), radius: rect.width * 0.45))
        let shading = GraphicsContext.Shading.radialGradient(
            Gradient(colors: [color.opacity(1), color.opacity(0.82)]),
            center: CGPoint(x: rect.midX, y: rect.midY - rect.height * 0.18),
            startRadius: 0, endRadius: rect.width * 0.7
        )
        g.fill(Path(ellipseIn: rect), with: shading)
        // glossy highlight (no shadow)
        let hl = CGRect(x: rect.minX + rect.width * 0.24, y: rect.minY + rect.height * 0.14,
                        width: rect.width * 0.34, height: rect.height * 0.24)
        fill(Path(ellipseIn: hl), with: .color(.white.opacity(0.55)))
    }

    /// A rounded chip with a soft drop shadow + subtle top sheen — a "game piece".
    func chip(_ rect: CGRect, fill color: Color, corner: CGFloat, glow: Color? = nil) {
        var g = self
        g.addFilter(.shadow(color: (glow ?? .black).opacity(glow == nil ? 0.35 : 0.6),
                            radius: glow == nil ? 6 : rect.width * 0.3, y: glow == nil ? 4 : 0))
        let path = Path(roundedRect: rect, cornerRadius: corner)
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [color.opacity(1.0), color.opacity(0.86)]),
            startPoint: CGPoint(x: rect.midX, y: rect.minY),
            endPoint: CGPoint(x: rect.midX, y: rect.maxY)
        )
        g.fill(path, with: shading)
        // top sheen
        let sheen = Path(roundedRect: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.45),
                         cornerRadius: corner)
        fill(sheen, with: .color(.white.opacity(0.12)))
    }

    /// Centered SF Symbol.
    func symbol(_ name: String, in rect: CGRect, size: CGFloat, color: Color) {
        draw(Text(Image(systemName: name)).font(.system(size: size, weight: .heavy)).foregroundStyle(color),
             at: CGPoint(x: rect.midX, y: rect.midY))
    }
}

/// The dark game stage behind every arcade field — gradient + soft accent glows.
struct ArcadeArena: View {
    var game: GameID = .split

    var body: some View {
        ZStack {
            game.world.surface
            GameWorldBackdrop(game: game, patternOpacity: 0.5)
        }
    }
}

/// Colour constants matching the dark arena for entity contrast.
enum ArcadeInk {
    /// Light text/strokes that read on the dark arena.
    static let onDark = Color.white
    static let onDarkDim = Color.white.opacity(0.42)
}
