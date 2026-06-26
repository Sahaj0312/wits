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
    /// Optional content above the hero (e.g. workout progress dots).
    var accessory: AnyView? = nil

    private var masteryLevel: Double {
        min(10, max(1, difficulty?.level ?? game.seedLevel))
    }

    private var currentLevelNumber: Int {
        min(10, max(1, Int(floor(masteryLevel))))
    }

    private var nextLevelNumber: Int {
        min(10, currentLevelNumber + 1)
    }

    private var levelProgress: Double {
        guard masteryLevel < 10 else { return 1 }
        return min(1, max(0, masteryLevel - Double(currentLevelNumber)))
    }

    private var levelProgressPercent: Int {
        Int((levelProgress * 100).rounded())
    }

    private var levelProgressSummary: String {
        currentLevelNumber >= 10 ? "max level" : "\(levelProgressPercent)%"
    }

    private var currentLevelLabel: String {
        "level \(currentLevelNumber)"
    }

    private var nextLevelLabel: String {
        currentLevelNumber >= 10 ? "max" : "level \(nextLevelNumber)"
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
            statTile("mode", value: "train")
        }
    }

    private var masteryBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("level progress")
                    .font(.witsBody(15, weight: .heavy))
                    .foregroundStyle(Color.witsInk)
                Spacer(minLength: 8)
                Text(levelProgressSummary)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsAccent)
                    .monospacedDigit()
            }
            ProgressTrack(fraction: levelProgress, animated: false)
                .frame(height: 8)
            HStack {
                Text(currentLevelLabel)
                Spacer(minLength: 8)
                Text(nextLevelLabel)
            }
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.witsMuted)
            .monospacedDigit()
            Text("your starting difficulty for this game")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.witsMuted)
        }
        .padding(15)
        .background(Color.witsTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(levelAccessibilityLabel)
    }

    private var levelAccessibilityLabel: String {
        if currentLevelNumber >= 10 {
            return "level 10, max level"
        }
        return "\(currentLevelLabel), \(levelProgressPercent) percent toward \(nextLevelLabel)"
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
