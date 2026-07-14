//
//  GameOverView.swift
//  wits
//
//  The shared post-run card for the endless games: the frozen game stays
//  dimmed behind a scrim, a big GAME OVER + score card sits on top, and a
//  light panel lists the run's bests (today / this week / all time) under a
//  mode badge. Home and PLAY AGAIN close it out. Everything is themed by the
//  game's color world; the trophy tints are fixed so the three rows always
//  read gold / pink / mint like little medals.
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
    let onHome: () -> Void
    let onPlayAgain: () -> Void

    private var world: GameWorld { game.world }

    var body: some View {
        ZStack {
            world.background.opacity(0.72).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 12)

                card

                Spacer(minLength: 20)

                buttons
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
            .frame(maxWidth: 560)
        }
        .overlay {
            if celebrate { ConfettiBurst().ignoresSafeArea() }
        }
        .transition(.opacity.combined(with: .scale(scale: 1.04)))
    }

    // MARK: Card

    private var card: some View {
        VStack(spacing: 0) {
            Text("GAME OVER")
                .font(.system(size: 34, weight: .black, design: world.titleDesign))
                .foregroundStyle(world.ink)
                .padding(.top, 30)

            Text("Score")
                .font(.system(size: 20, weight: .black, design: world.titleDesign))
                .foregroundStyle(world.accent)
                .padding(.top, 26)
            Text(String(score))
                .font(.system(size: 62, weight: .black, design: world.titleDesign))
                .foregroundStyle(world.accent)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.top, 2)

            if let caption {
                Text(caption)
                    .font(.system(size: 12, weight: .bold, design: world.bodyDesign))
                    .foregroundStyle(world.muted)
                    .padding(.top, 6)
            }

            bestsPanel
                .padding(.horizontal, 16)
                .padding(.top, 44)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(world.surface.opacity(0.94),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(world.ink.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: Bests panel

    private var bestsPanel: some View {
        VStack(spacing: 8) {
            Text(contextTitle.uppercased())
                .font(.system(size: 19, weight: .black, design: world.titleDesign))
                .foregroundStyle(Color(hexAny: 0xD9A13B))
                .padding(.top, 34)

            VStack(spacing: 7) {
                ForEach(bests) { line in
                    bestRow(line)
                }
            }
            .padding(.horizontal, 13)
            .padding(.top, 4)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .background(world.ink,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .top) { badge.offset(y: -30) }
    }

    private var badge: some View {
        ZStack {
            Circle()
                .fill(world.background)
                .overlay(Circle().strokeBorder(world.ink, lineWidth: 4))
            Image(systemName: badgeSymbol)
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(Color(hexAny: 0xF2C14E))
        }
        .frame(width: 62, height: 62)
        .overlay(alignment: .top) {
            Image(systemName: "crown.fill")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(world.ink)
                .offset(y: -15)
        }
    }

    private func bestRow(_ line: RunBestLine) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 15, weight: .black))
            Text(line.title)
                .font(.system(size: 17, weight: .black, design: world.titleDesign))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            Text(String(line.value))
                .font(.system(size: 17, weight: .black, design: world.titleDesign))
                .monospacedDigit()
        }
        .foregroundStyle(line.tint)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(world.background.opacity(0.88),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack(spacing: 12) {
            Button(action: onHome) {
                Image(systemName: "house.fill")
                    .font(.system(size: 19, weight: .black))
                    .foregroundStyle(world.ink)
                    .frame(width: 64, height: 56)
                    .background(world.raised,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PressScale())
            .accessibilityLabel("Back to games")

            Button(action: onPlayAgain) {
                Text("PLAY AGAIN")
                    .font(.system(size: 17, weight: .black, design: world.titleDesign))
                    .foregroundStyle(world.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(world.accent,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PressScale())
        }
    }
}
