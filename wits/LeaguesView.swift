//
//  LeaguesView.swift
//  wits
//
//  Weekly cohort league — ~30 pace-matched players, promotion/relegation. The
//  comparison is to similar others (cohort, not global) so it motivates rather
//  than crushes the bottom. Assignment + lazy weekly settlement run server-side.
//

import SwiftUI

private let tierNames = ["bronze", "silver", "gold", "sapphire", "ruby",
                         "emerald", "amethyst", "pearl", "obsidian", "diamond"]

struct LeaguesView: View {
    @Environment(AppModel.self) private var app

    private var tierName: String {
        guard let t = app.league?.tier, t < tierNames.count else { return "league" }
        return tierNames[t]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(tierName) league")
                    .font(.witsDisplay(30))
                    .foregroundStyle(Color.witsInk)
                    .padding(.top, 8)

                if let league = app.league {
                    Text("top \(league.promote) move up · bottom \(league.relegate) move down · resets weekly")
                        .font(.witsBody(13.5))
                        .foregroundStyle(Color.witsMuted)

                    VStack(spacing: 8) {
                        ForEach(league.standings) { s in
                            row(s, league: league)
                        }
                    }
                } else {
                    Text("finding your league…")
                        .font(.witsBody(15))
                        .foregroundStyle(Color.witsMuted)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface()
                }

                Text("you're matched with players training at a similar pace. play your daily workout to earn xp and climb.")
                    .font(.witsBody(12.5))
                    .foregroundStyle(Color.witsFaint)
                    .padding(.top, 4)
            }
            .padding(.horizontal, WitsMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .background(Color.witsBg.ignoresSafeArea())
        .task { await app.refreshLeague() }
    }

    @ViewBuilder
    private func row(_ s: LeagueStanding, league: LeagueResult) -> some View {
        let promo = s.rank <= league.promote
        let releg = s.rank > league.size - league.relegate
        let zoneColor: Color = promo ? .witsAccent : (releg ? .witsWarm : .witsFaint)
        HStack(spacing: 12) {
            Text("\(s.rank)")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(zoneColor)
                .frame(width: 28)
                .monospacedDigit()
            Image(systemName: promo ? "arrow.up.circle.fill" : releg ? "arrow.down.circle.fill" : "circle.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(zoneColor.opacity(promo || releg ? 1 : 0.3))
            Text(s.isMe ? "you" : "wits member")
                .font(.system(size: 15, weight: s.isMe ? .heavy : .semibold, design: .rounded))
                .foregroundStyle(s.isMe ? Color.witsInk : Color.witsMuted)
            Spacer()
            Text("\(s.xp) xp")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsInk)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(s.isMe ? Color.witsAccent.opacity(0.10) : Color.witsCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(s.isMe ? Color.witsAccent : .clear, lineWidth: 1.5)
        )
        .shadow(color: .witsShadow, radius: 6, y: 3)
    }
}
