//
//  Leaderboard.swift
//  wits
//
//  Global per-game leaderboard panel for post-game screens. The data arrives
//  in a single RPC snapshot (top players + my rank + total) that AppModel
//  prefetches the moment a run persists, so this view usually renders from
//  cache with zero wait; while a fetch is in flight it holds a fixed-height
//  placeholder to avoid layout jumps.
//

import SwiftUI

struct LeaderboardPanel: View {
    let game: GameID
    let snapshot: LeaderboardSnapshot?

    private var meInTop: Bool {
        snapshot?.top.contains(where: \.me) ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("global leaderboard")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .kerning(0.6)
                    .foregroundStyle(Color.witsFaint)
                Spacer()
                if let total = snapshot?.total {
                    Text("\(total) players")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.witsFaint)
                        .monospacedDigit()
                }
            }

            if let snapshot {
                VStack(spacing: 6) {
                    ForEach(Array(snapshot.top.enumerated()), id: \.offset) { i, entry in
                        row(rank: i + 1, name: entry.me ? "you" : entry.name,
                            score: entry.score, highlighted: entry.me)
                    }
                    if !meInTop, let rank = snapshot.rank, let score = snapshot.score {
                        Rectangle()
                            .fill(Color.witsLine)
                            .frame(height: 1)
                            .padding(.vertical, 2)
                        row(rank: rank, name: "you", score: score, highlighted: true)
                    }
                }
            } else {
                Text("ranking your run…")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.witsFaint)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(14)
        .background(Color.witsTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeOut(duration: 0.2), value: snapshot)
    }

    private func rankColor(_ rank: Int, highlighted: Bool) -> Color {
        switch rank {
        case 1: .witsGold
        case 2: .witsSky
        case 3: .witsWarm
        default: highlighted ? .witsAccent : .witsFaint
        }
    }

    private func row(rank: Int, name: String, score: Int, highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Text("#\(rank)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(rankColor(rank, highlighted: highlighted))
                .monospacedDigit()
                .frame(width: 36, alignment: .leading)
            Text(name)
                .font(.system(size: 13.5, weight: highlighted ? .heavy : .semibold, design: .rounded))
                .foregroundStyle(highlighted ? Color.witsAccent : Color.witsInk)
                .lineLimit(1)
            Spacer()
            Text("\(score)")
                .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                .foregroundStyle(highlighted ? Color.witsAccent : Color.witsMuted)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            highlighted ? Color.witsAccent.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }
}
