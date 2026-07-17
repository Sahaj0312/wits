//
//  WelcomeView.swift
//  wits
//
//  First-launch welcome: a slow marquee of game posters drifting across the
//  top, a short serif letter about why wits exists, and one quiet button in.
//  Shown once, before the library (and so before any ATT prompts
//  can stack on it). The marquee height tracks the screen and the letter is
//  set at the largest of three type scales that fits, so nothing scrolls on
//  any device size.
//

import SwiftUI

struct WelcomeView: View {
    var isStarting = false
    var onDone: () -> Void

    var body: some View {
        GeometryReader { geo in
            let cardHeight = min(240, geo.size.height * 0.28)

            VStack(alignment: .leading, spacing: 0) {
                PosterMarquee(cardHeight: cardHeight)
                    .padding(.top, 6)

                ViewThatFits(in: .vertical) {
                    letter(titleSize: 21, bodySize: 18, lineSpacing: 6, paragraphSpacing: 22, topPadding: 40)
                    letter(titleSize: 20, bodySize: 16.5, lineSpacing: 5, paragraphSpacing: 18, topPadding: 30)
                    letter(titleSize: 18, bodySize: 15, lineSpacing: 4, paragraphSpacing: 14, topPadding: 22)
                }

                Spacer(minLength: 10)

                Button(action: onDone) {
                    Text("get started")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color(hexAny: 0x232327),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(TactilePressScale(feedback: .primary))
                .disabled(isStarting)
                .opacity(isStarting ? 0.7 : 1)
                .padding(.horizontal, WitsMetrics.screenPadding)
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .background(Color(hexAny: 0x09090B).ignoresSafeArea())
    }

    private func letter(titleSize: CGFloat,
                        bodySize: CGFloat,
                        lineSpacing: CGFloat,
                        paragraphSpacing: CGFloat,
                        topPadding: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: paragraphSpacing) {
            Text("welcome to \(Text("wits").foregroundStyle(Color.witsAccent))")
                .font(.system(size: titleSize, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
                .padding(.top, topPadding)

            Group {
                Text("wits exists for the minutes that usually vanish into the feed. quick, honest games that leave your brain sharper than they found it.")
                Text("it's completely free. every game, every level. the occasional ad keeps the lights on, and one small purchase turns them off forever.")
                Text("next time your thumb reaches for the scroll, come here instead. play something. your brain will thank you.")
            }
            .font(.system(size: bodySize, weight: .regular, design: .serif))
            .foregroundStyle(.white.opacity(0.88))
            .lineSpacing(lineSpacing)

            Text("- sahaj")
                .font(.system(size: bodySize - 0.5, weight: .medium, design: .serif))
                .italic()
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, WitsMetrics.screenPadding + 4)
    }
}

/// An endless leftward drift of game posters, bleeding off both screen edges.
/// The row lives in an overlay of a fixed-height spacer so its (huge) natural
/// width never participates in the page's layout, and the drift is computed
/// from the clock instead of a repeatForever animation so nothing leaks into
/// other transitions.
private struct PosterMarquee: View {
    let cardHeight: CGFloat

    private let games = GameID.allCases.filter(\.isPlayable)
    private let spacing: CGFloat = 12
    /// Drift speed in points per second.
    private let speed: Double = 22
    /// Start mid-card so the row bleeds off the left edge from frame one.
    private let leadIn: CGFloat = 56

    @State private var startedAt = Date()

    /// Library poster aspect ratio.
    private var cardWidth: CGFloat { cardHeight * 0.74 }
    private var loopWidth: CGFloat { CGFloat(games.count) * (cardWidth + spacing) }

    var body: some View {
        Color.clear
            .frame(height: cardHeight)
            .overlay(alignment: .leading) {
                TimelineView(.animation) { context in
                    let travelled = context.date.timeIntervalSince(startedAt) * speed
                    let phase = (leadIn + CGFloat(travelled)).truncatingRemainder(dividingBy: loopWidth)
                    HStack(spacing: spacing) {
                        ForEach(0..<(games.count * 2), id: \.self) { i in
                            posterCard(games[i % games.count])
                        }
                    }
                    .offset(x: -phase)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func posterCard(_ g: GameID) -> some View {
        ZStack(alignment: .topLeading) {
            GameWorldBackdrop(game: g, patternOpacity: 1)
            GamePosterArt(game: g)
            // Same poster anatomy as the library cards: name top-left with
            // the accent underline bar.
            VStack(alignment: .leading, spacing: 5) {
                Text(g.worldTitle())
                    .font(.system(size: max(12, cardWidth * 0.082),
                                  weight: .black, design: g.world.titleDesign))
                    .foregroundStyle(g.world.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Rectangle()
                    .fill(g.world.accent)
                    .frame(width: cardWidth * 0.15, height: 3.5)
            }
            .padding(.horizontal, cardWidth * 0.08)
            .padding(.top, cardWidth * 0.08)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: cardWidth * 0.157, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardWidth * 0.157, style: .continuous)
                .strokeBorder(g.world.accent.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: g.world.accent.opacity(0.28), radius: 14, y: 6)
    }
}
