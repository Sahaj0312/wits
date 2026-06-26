//
//  GameCard.swift
//  wits
//
//  The pre-game detail card shown before every game (workout + free play):
//  themed hero, title, DOMAIN › SUBSKILL breadcrumb, what-it-trains copy, and a
//  stats block (level, best score, best stat, total plays). Modelled on the
//  Lumosity game card, in wits' voice and design language.
//

import SwiftUI

struct GameCard: View {
    let game: GameID
    var stats: GameStats?
    var difficulty: DifficultyState? = nil
    var primaryTitle: String = "play"
    var onPlay: () -> Void
    var onBack: (() -> Void)? = nil
    /// When set, shows a second "survival" action.
    var onSurvival: (() -> Void)? = nil
    /// Optional content above the hero (e.g. workout progress dots).
    var accessory: AnyView? = nil

    private var masteryLevel: Double {
        min(10, max(1, difficulty?.level ?? game.seedLevel))
    }

    private var masteryLevelLabel: String {
        let rounded = (masteryLevel * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", rounded)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let accessory {
                accessory.padding(.horizontal, WitsMetrics.screenPadding).padding(.top, 8)
            }
            hero
                .ignoresSafeArea(edges: .top)
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
                    masteryBlock
                    statsBlock
                }
                .padding(.horizontal, WitsMetrics.screenPadding)
                .padding(.top, 2)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .background(Color.witsBg.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            if let onBack {
                closeButton(action: onBack)
                    .padding(.top, 8)
                    .padding(.trailing, 12)
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        let (a, b) = game.heroColors
        return ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(hexAny: a), Color(hexAny: b)],
                           startPoint: .top, endPoint: .bottom)
            Circle().fill(Color.witsAccent.opacity(0.13)).frame(width: 230, height: 230).offset(x: 110, y: -85)
            Circle().fill(Color.white.opacity(0.05)).frame(width: 110, height: 110).offset(x: -60, y: 20)
            Image(systemName: game.symbol)
                .font(.system(size: 118, weight: .heavy))
                .foregroundStyle(.white.opacity(0.08))
                .offset(x: 154, y: 12)
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: game.symbol)
                    .font(.system(size: 21, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(game.displayName)
                        .font(.witsDisplay(34))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                    Text(game.tagline)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, WitsMetrics.screenPadding)
            .padding(.bottom, 20)
        }
        .frame(height: 238)
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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
            statTile("best score", value: (stats?.bestScore).flatMap { $0 > 0 ? "\($0)" : nil } ?? "—")
            statTile("best stat", value: stats?.bestStat.map { game.statLabel($0) } ?? "—")
            statTile("plays", value: "\(stats?.totalPlays ?? 0)")
            if let sv = stats?.survivalBest, sv > 0 {
                statTile("survival best", value: "\(sv)")
            } else {
                statTile("mode", value: onSurvival == nil ? "train" : "train + survival")
            }
        }
    }

    private var masteryBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("level")
                    .font(.witsBody(15, weight: .heavy))
                    .foregroundStyle(Color.witsInk)
                Spacer(minLength: 8)
                Text("level \(masteryLevelLabel) of 10")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsAccent)
                    .monospacedDigit()
            }
            HStack(spacing: 5) {
                ForEach(1...10, id: \.self) { step in
                    masterySegment(fill: masteryFill(for: step))
                }
            }
            Text("your starting difficulty for this game")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.witsMuted)
        }
        .padding(15)
        .background(Color.witsTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("level \(masteryLevelLabel) of 10")
    }

    private func masteryFill(for step: Int) -> Double {
        min(1, max(0, masteryLevel - Double(step - 1)))
    }

    private func masterySegment(fill: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.witsLine)
                Capsule()
                    .fill(Color.witsAccent)
                    .frame(width: geo.size.width * fill)
            }
        }
        .frame(height: 8)
    }

    private func statTile(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsFaint)
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsInk)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.witsCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.witsLine, lineWidth: 1)
        )
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 11) {
            Cta(title: primaryTitle, action: onPlay)
            if let onSurvival {
                Button(action: onSurvival) {
                    HStack(spacing: 10) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 14, weight: .heavy))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("survival mode")
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                            Text("3 lives, no mercy")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.witsWarm.opacity(0.72))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .heavy))
                    }
                    .foregroundStyle(Color.witsWarm)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Color.witsWarm.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    private func closeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .accessibilityLabel("close")
        }
        .buttonStyle(.plain)
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
