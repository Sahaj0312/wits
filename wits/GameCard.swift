//
//  GameCard.swift
//  wits
//
//  The pre-game detail card shown before every game (workout + free play):
//  themed hero, title, DOMAIN › SUBSKILL breadcrumb, what-it-trains copy, and a
//  stats block (best score, best stat, rank, total plays). Modelled on the
//  Lumosity game card, in wits' voice and design language.
//

import SwiftUI

private let rankNames = ["newcomer", "novice", "skilled", "sharp", "expert", "master"]

struct GameCard: View {
    let game: GameID
    var stats: GameStats?
    var primaryTitle: String = "play"
    var onPlay: () -> Void
    var onBack: (() -> Void)? = nil
    /// Optional content above the hero (e.g. workout progress dots).
    var accessory: AnyView? = nil

    private var rankIndex: Int {
        let plays = stats?.totalPlays ?? 0
        return min(rankNames.count - 1, plays / 5)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let accessory {
                accessory.padding(.horizontal, WitsMetrics.screenPadding).padding(.top, 8)
            }
            hero
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    breadcrumb
                    Text(game.cardHow)
                        .font(.witsBody(15.5))
                        .foregroundStyle(Color.witsMuted)
                    Text(game.cardAbout)
                        .font(.witsBody(15.5))
                        .foregroundStyle(Color.witsMuted)
                    Divider().overlay(Color.witsLine)
                    statsBlock
                }
                .padding(.horizontal, WitsMetrics.screenPadding)
                .padding(.top, 18)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .background(Color.witsBg.ignoresSafeArea())
    }

    // MARK: Hero

    private var hero: some View {
        let (a, b) = game.heroColors
        return ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(hexAny: a), Color(hexAny: b)],
                           startPoint: .top, endPoint: .bottom)
            Circle().fill(Color.witsAccent.opacity(0.12)).frame(width: 200, height: 200).offset(x: 120, y: -70)
            Image(systemName: game.symbol)
                .font(.system(size: 120, weight: .heavy))
                .foregroundStyle(.white.opacity(0.07))
                .offset(x: 150, y: 10)
            Text(game.displayName)
                .font(.witsDisplay(34))
                .foregroundStyle(.white)
                .padding(.horizontal, WitsMetrics.screenPadding)
                .padding(.bottom, 18)
        }
        .frame(height: 210)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Text(game.domainTitle.uppercased())
                .foregroundStyle(Color.witsAccent)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Color.witsAccent.opacity(0.7))
            Text(game.subskill.uppercased())
                .foregroundStyle(Color.witsAccent)
        }
        .font(.system(size: 12, weight: .heavy, design: .rounded))
        .kerning(0.6)
    }

    // MARK: Stats

    private var statsBlock: some View {
        VStack(spacing: 14) {
            statRow("best score", value: (stats?.bestScore).flatMap { $0 > 0 ? "\($0)" : nil } ?? "—")
            statRow("best stat", value: stats?.bestStat.map { game.statLabel($0) } ?? "—")
            HStack {
                Text("rank")
                    .font(.witsBody(15, weight: .semibold))
                    .foregroundStyle(Color.witsInk)
                Spacer()
                HStack(spacing: 5) {
                    ForEach(0..<rankNames.count, id: \.self) { i in
                        Circle()
                            .fill(i <= rankIndex ? Color.witsAccent : Color.witsLine)
                            .frame(width: 8, height: 8)
                    }
                    Text(rankNames[rankIndex])
                        .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsMuted)
                        .padding(.leading, 4)
                }
            }
            statRow("total plays", value: "\(stats?.totalPlays ?? 0)")
        }
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.witsBody(15, weight: .semibold))
                .foregroundStyle(Color.witsInk)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsMuted)
                .monospacedDigit()
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            if let onBack {
                Button(action: onBack) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .heavy))
                        Text("all games").font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color.witsWarm)
                }
                .buttonStyle(.plain)
            }
            Cta(title: primaryTitle, action: onPlay)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }
}

private extension Color {
    init(hexAny: UInt32) {
        self.init(
            red: Double((hexAny >> 16) & 0xFF) / 255,
            green: Double((hexAny >> 8) & 0xFF) / 255,
            blue: Double(hexAny & 0xFF) / 255
        )
    }
}
