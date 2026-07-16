//
//  AnimatedTutorial.swift
//  wits
//
//  Paged "how to play" tutorial with looping animated demos, replacing the
//  static text-step tutorial one game at a time. Each game registers an array
//  of TutorialSlides (caption + a small self-animating demo view); games
//  without slides keep falling back to FirstPlayTutorial at the call site.
//

import SwiftUI

// MARK: - Slide registry

struct TutorialSlide {
    let caption: String
    let demo: AnyView

    init(caption: String, @ViewBuilder demo: () -> some View) {
        self.caption = caption
        self.demo = AnyView(demo())
    }
}

extension GameID {
    /// Animated how-to-play slides, nil while a game hasn't been converted yet.
    var animatedTutorialSlides: [TutorialSlide]? {
        switch self {
        case .blockFit: BlockFitTutorial.slides
        default: nil
        }
    }
}

// MARK: - Screen

struct AnimatedHowToPlay: View {
    let game: GameID
    let slides: [TutorialSlide]
    /// Label on the last page's confirm button ("play" pre-game, "got it" when
    /// reviewing from the selector's help button).
    var doneTitle: String = "play"
    var onStart: () -> Void
    var onBack: (() -> Void)? = nil

    @State private var page = 0

    private var world: GameWorld { game.world }
    private var isLast: Bool { page == slides.count - 1 }

    var body: some View {
        ZStack {
            GameWorldBackdrop(game: game)

            VStack(spacing: 0) {
                header
                    .padding(.top, 10)

                Spacer(minLength: 14)

                card

                dots
                    .padding(.top, 20)

                Spacer(minLength: 14)

                controls
                    .padding(.bottom, 14)
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(world.ink)
                        .frame(width: 44, height: 44)
                        .background(world.surface, in: Circle())
                }
                .buttonStyle(PressScale())
                .accessibilityLabel("Back")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            Spacer()
            Text(game.worldTitle())
                .font(.system(size: 15, weight: .black, design: world.titleDesign))
                .foregroundStyle(world.ink)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            Text(game.worldTitle("how to play"))
                .font(.system(size: 23, weight: .black, design: world.titleDesign))
                .foregroundStyle(world.ink)
                .padding(.top, 20)

            ZStack {
                ForEach(slides.indices, id: \.self) { index in
                    if index == page {
                        slideBody(slides[index])
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)))
                    }
                }
            }
            .animation(.snappy(duration: 0.3), value: page)
            .clipped()
        }
        .frame(maxWidth: .infinity)
        .background(world.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(world.ink.opacity(0.10), lineWidth: 1)
        )
    }

    private func slideBody(_ slide: TutorialSlide) -> some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(world.background.opacity(0.55))
                slide.demo
                    .padding(8)
            }
            .aspectRatio(0.95, contentMode: .fit)
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Text(slide.caption)
                .font(.system(size: 15, weight: .bold, design: world.bodyDesign))
                .foregroundStyle(world.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .frame(minHeight: 74, alignment: .top)
        }
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(slides.indices, id: \.self) { index in
                Capsule()
                    .fill(index == page ? world.accent : world.ink.opacity(0.20))
                    .frame(width: index == page ? 22 : 7, height: 7)
            }
        }
        .animation(.snappy(duration: 0.25), value: page)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            iconButton("chevron.left", label: "Previous step", enabled: page > 0) {
                withAnimation(.snappy(duration: 0.3)) { page -= 1 }
            }

            Button(action: advance) {
                Text(game.worldTitle(isLast ? doneTitle : "ok"))
                    .font(.system(size: 17, weight: .black, design: world.titleDesign))
                    .foregroundStyle(world.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(world.accent,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(PressScale())

            iconButton("chevron.right", label: "Next step", enabled: !isLast) {
                withAnimation(.snappy(duration: 0.3)) { page += 1 }
            }
        }
    }

    private func advance() {
        if isLast {
            onStart()
        } else {
            withAnimation(.snappy(duration: 0.3)) { page += 1 }
        }
    }

    private func iconButton(_ symbol: String,
                            label: String,
                            enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(world.ink)
                .frame(width: 52, height: 56)
                .background(world.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(PressScale())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }
}

// MARK: - Demo helpers

/// Restarting loop clock: renders `content` with t in 0..<duration, restarting
/// from zero whenever the view (re)appears, so every slide opens at the start
/// of its script.
struct DemoLoop<Content: View>: View {
    var duration: Double
    @ViewBuilder var content: (Double) -> Content

    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(start))
            content(elapsed.truncatingRemainder(dividingBy: duration))
        }
        .onAppear { start = Date() }
    }
}

enum DemoEase {
    /// Smoothstepped 0→1 as t crosses from..to; clamped outside.
    static func ramp(_ t: Double, _ from: Double, _ to: Double) -> Double {
        guard t > from else { return 0 }
        guard t < to else { return 1 }
        let x = (t - from) / (to - from)
        return x * x * (3 - 2 * x)
    }

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ u: Double) -> CGFloat {
        a + (b - a) * CGFloat(u)
    }

    static func lerp(_ a: CGPoint, _ b: CGPoint, _ u: Double) -> CGPoint {
        CGPoint(x: lerp(a.x, b.x, u), y: lerp(a.y, b.y, u))
    }

    /// Draws the pointer-hand cursor with its fingertip at `tip`.
    static func drawHand(_ context: GraphicsContext,
                         tip: CGPoint,
                         size: CGFloat,
                         pressed: Bool,
                         alpha: Double) {
        guard alpha > 0.01 else { return }
        let side = size * (pressed ? 0.92 : 1)
        let rect = CGRect(x: tip.x - side * 0.16,
                          y: tip.y - side * 0.10,
                          width: side, height: side)
        context.drawLayer { layer in
            layer.opacity = alpha
            layer.addFilter(.shadow(color: .black.opacity(0.45), radius: size * 0.14, y: size * 0.10))
            var glyph = layer.resolve(Image(systemName: "hand.point.up.left.fill"))
            glyph.shading = .color(.white)
            layer.draw(glyph, in: rect)
        }
    }
}
