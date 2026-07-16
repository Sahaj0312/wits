//
//  GameOverView.swift
//  wits
//
//  The shared post-run card for the endless games: the frozen game stays
//  visible behind a soft scrim while one cohesive result surface carries the
//  score, run context, and bests. Home and PLAY AGAIN sit safely above the
//  bottom-edge resting zone.
//  Everything is themed by the game's color world; the three bests retain a
//  fixed gold / pink / mint medal language across every game.
//

import SwiftUI

/// One "…best" row on the panel.
struct RunBestLine: Identifiable {
    let title: String
    let value: Int
    let tint: Color

    var id: String { title }

    /// The standard today / week / all-time trio.
    static func standard(today: Int, week: Int, allTime: Int) -> [RunBestLine] {
        [RunBestLine(title: "Today's best", value: today, tint: Color(hexAny: 0xF2C14E)),
         RunBestLine(title: "Week's best", value: week, tint: Color(hexAny: 0xFF8FA8)),
         RunBestLine(title: "All-time best", value: allTime, tint: Color(hexAny: 0x6FD6C3))]
    }

    var shortTitle: String {
        switch title.lowercased() {
        case let value where value.contains("today"): "TODAY"
        case let value where value.contains("week"): "THIS WEEK"
        case let value where value.contains("all-time"): "ALL TIME"
        default: title.uppercased()
        }
    }
}

struct GameRunOverView: View {
    let game: GameID
    /// Panel header, e.g. "MEDIUM MODE" or "ENDLESS RUN".
    let contextTitle: String
    /// SF Symbol in the badge straddling the panel's top edge.
    let badgeSymbol: String
    let score: Int
    /// Optional one-liner under the score for game-specific stats.
    var caption: String? = nil
    let bests: [RunBestLine]
    /// Confetti — the run set a new all-time best.
    var celebrate: Bool = false
    /// Present → a "watch ad to keep playing" button sits above the buttons;
    /// the host owns the rewarded-ad flow and revives the run on success.
    var onContinue: (() -> Void)? = nil
    /// Disables the continue button while the rewarded ad is presenting.
    var continueBusy: Bool = false
    let onHome: () -> Void
    let onPlayAgain: () -> Void

    private var world: GameWorld { game.world }

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 760 || onContinue != nil

            ZStack {
                scrim

                VStack(spacing: compact ? 10 : 12) {
                    card(compact: compact)
                    buttons(compact: compact)
                }
                .frame(width: min(360, max(280, geo.size.width - 64)))
                // Keep the actions attached to the result card and away from
                // the bottom-edge thumb/resting zone.
                .offset(y: compact ? -8 : -24)
            }
        }
        .overlay {
            if celebrate { ConfettiBurst().ignoresSafeArea() }
        }
        .transition(.opacity.combined(with: .scale(scale: 1.04)))
        .onAppear {
            // Interstitial slot: this card is a static screen, but never
            // interrupt a live rewarded-continue decision.
            if onContinue == nil { AdManager.shared.maybeShowInterstitial() }
        }
    }

    private var scrim: some View {
        ZStack {
            Color.black.opacity(0.28)
            world.background.opacity(0.52)
            RadialGradient(colors: [world.accent.opacity(0.10), .clear],
                           center: .top, startRadius: 20, endRadius: 520)
        }
        .ignoresSafeArea()
    }

    // MARK: Result surface

    private func card(compact: Bool) -> some View {
        VStack(spacing: 0) {
            statusPill
                .padding(.top, compact ? 16 : 22)

            Text("GAME OVER")
                .font(.system(size: compact ? 28 : 34,
                              weight: .black,
                              design: world.titleDesign))
                .foregroundStyle(world.ink)
                .padding(.top, compact ? 8 : 11)

            Text("SCORE")
                .font(.system(size: compact ? 12 : 14,
                              weight: .black,
                              design: world.bodyDesign))
                .foregroundStyle(world.accent)
                .tracking(1.4)
                .padding(.top, compact ? 12 : 18)
            Text(String(score))
                .font(.system(size: compact ? 62 : 76,
                              weight: .black,
                              design: world.titleDesign))
                .foregroundStyle(world.accent)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .contentTransition(.numericText())
                .shadow(color: celebrate ? world.accent.opacity(0.35) : .clear,
                        radius: 14, y: 5)
                .padding(.top, -2)

            if let caption {
                captionPill(caption, compact: compact)
                    .padding(.top, compact ? 2 : 5)
            }

            Rectangle()
                .fill(world.ink.opacity(0.09))
                .frame(height: 1)
                .padding(.horizontal, compact ? 16 : 22)
                .padding(.top, compact ? 14 : 20)

            contextRow(compact: compact)
                .padding(.horizontal, compact ? 16 : 22)
                .padding(.top, compact ? 12 : 16)

            bestsGrid(compact: compact)
                .padding(.horizontal, compact ? 12 : 16)
                .padding(.top, compact ? 10 : 14)
                .padding(.bottom, compact ? 14 : 18)
        }
        .frame(maxWidth: .infinity)
        .background(cardBackground,
                    in: RoundedRectangle(cornerRadius: compact ? 20 : 26,
                                         style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 20 : 26, style: .continuous)
                .strokeBorder(world.ink.opacity(0.14), lineWidth: 1.2)
        )
        .shadow(color: .black.opacity(0.28), radius: 24, y: 14)
    }

    private var cardBackground: some ShapeStyle {
        LinearGradient(colors: [world.raised.opacity(0.98), world.surface.opacity(0.98)],
                       startPoint: .topLeading,
                       endPoint: .bottomTrailing)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Image(systemName: celebrate ? "sparkles" : "flag.checkered")
                .font(.system(size: 10, weight: .black))
            Text(celebrate ? "NEW ALL-TIME BEST" : "RUN COMPLETE")
                .font(.system(size: 10.5, weight: .black, design: world.bodyDesign))
                .tracking(0.8)
        }
        .foregroundStyle(celebrate ? world.background : world.muted)
        .padding(.horizontal, 11)
        .frame(height: 25)
        .background(celebrate ? world.accent : world.ink.opacity(0.07),
                    in: Capsule())
    }

    private func captionPill(_ caption: String, compact: Bool) -> some View {
        Text(caption.uppercased())
            .font(.system(size: compact ? 10.5 : 11.5,
                          weight: .black,
                          design: world.bodyDesign))
            .foregroundStyle(world.muted)
            .tracking(0.35)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 12)
            .frame(height: compact ? 25 : 29)
            .background(world.background.opacity(0.42), in: Capsule())
            .overlay(Capsule().strokeBorder(world.ink.opacity(0.10), lineWidth: 1))
    }

    private func contextRow(compact: Bool) -> some View {
        HStack(spacing: compact ? 10 : 13) {
            badge(compact: compact)

            VStack(alignment: .leading, spacing: 2) {
                Text("RUN TYPE")
                    .font(.system(size: 9.5, weight: .black, design: world.bodyDesign))
                    .foregroundStyle(world.muted)
                    .tracking(0.8)
                Text(contextTitle.uppercased())
                    .font(.system(size: compact ? 16 : 19,
                                  weight: .black,
                                  design: world.titleDesign))
                    .foregroundStyle(Color(hexAny: 0xF2C14E))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(world.muted.opacity(0.55))
        }
        .padding(.horizontal, compact ? 12 : 15)
        .frame(height: compact ? 54 : 62)
        .frame(maxWidth: .infinity)
        .background(world.background.opacity(0.36),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(world.ink.opacity(0.09), lineWidth: 1)
        )
    }

    private func badge(compact: Bool) -> some View {
        ZStack {
            Circle()
                .fill(world.background)
                .overlay(Circle().strokeBorder(Color(hexAny: 0xF2C14E).opacity(0.75),
                                               lineWidth: 2))
            Image(systemName: badgeSymbol)
                .font(.system(size: compact ? 17 : 20, weight: .black))
                .foregroundStyle(Color(hexAny: 0xF2C14E))
        }
        .frame(width: compact ? 38 : 44, height: compact ? 38 : 44)
    }

    private func bestsGrid(compact: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(bests.enumerated()), id: \.element.id) { index, line in
                if index > 0 {
                    Rectangle()
                        .fill(world.ink.opacity(0.10))
                        .frame(width: 1, height: compact ? 46 : 55)
                }
                bestMetric(line, compact: compact)
            }
        }
        .padding(.vertical, compact ? 10 : 13)
        .frame(maxWidth: .infinity)
        .background(world.background.opacity(0.48),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(world.ink.opacity(0.10), lineWidth: 1)
        )
    }

    private func bestMetric(_ line: RunBestLine, compact: Bool) -> some View {
        VStack(spacing: compact ? 2 : 4) {
            Image(systemName: "trophy.fill")
                .font(.system(size: compact ? 11 : 13, weight: .black))
            Text(line.shortTitle)
                .font(.system(size: compact ? 8.5 : 9.5,
                              weight: .black,
                              design: world.bodyDesign))
                .tracking(0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(String(line.value))
                .font(.system(size: compact ? 19 : 23,
                              weight: .black,
                              design: world.titleDesign))
                .monospacedDigit()
        }
        .foregroundStyle(line.tint)
        .frame(maxWidth: .infinity)
    }

    // MARK: Buttons

    private func buttons(compact: Bool) -> some View {
        VStack(spacing: compact ? 9 : 12) {
            if let onContinue {
                Button(action: onContinue) {
                    HStack(spacing: 9) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 18, weight: .black))
                        Text(continueBusy ? "LOADING AD…" : "WATCH AD · KEEP PLAYING")
                            .font(.system(size: 16, weight: .black, design: world.titleDesign))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(world.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 50 : 56)
                    .background(world.surface.opacity(0.96),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(world.accent, lineWidth: 2)
                    )
                }
                .buttonStyle(PressScale())
                .disabled(continueBusy)
                .opacity(continueBusy ? 0.6 : 1)
            }

            homeAndPlayAgain(compact: compact)
        }
    }

    private func homeAndPlayAgain(compact: Bool) -> some View {
        HStack(spacing: compact ? 10 : 12) {
            Button(action: onHome) {
                Image(systemName: "house.fill")
                    .font(.system(size: 19, weight: .black))
                    .foregroundStyle(world.ink)
                    .frame(width: compact ? 54 : 62, height: compact ? 52 : 58)
                    .background(world.raised.opacity(0.96),
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(world.ink.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(PressScale())
            .accessibilityLabel("Back to games")

            Button(action: onPlayAgain) {
                Text("PLAY AGAIN")
                    .font(.system(size: 17, weight: .black, design: world.titleDesign))
                    .foregroundStyle(world.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 52 : 58)
                    .background(world.accent,
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .shadow(color: world.accent.opacity(0.25), radius: 10, y: 5)
            }
            .buttonStyle(PressScale())
        }
    }
}
