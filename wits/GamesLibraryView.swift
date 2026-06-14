//
//  GamesLibraryView.swift
//  wits
//
//  Free play: the full library. Live games launch a single-game session (which
//  still calibrates difficulty); roadmap games show as coming soon.
//

import SwiftUI

struct GamesLibraryView: View {
    @Environment(AppModel.self) private var app
    @State private var freePlay: GameID?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("games")
                    .font(.witsDisplay(30))
                    .foregroundStyle(Color.witsInk)
                    .padding(.top, 8)
                Text("train any skill on its own. your daily workout mixes these for you.")
                    .font(.witsBody(15))
                    .foregroundStyle(Color.witsMuted)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(GameID.allCases) { g in
                        card(g)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, WitsMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .background(Color.witsBg.ignoresSafeArea())
        .fullScreenCover(item: $freePlay) { g in
            GameHost(
                workout: DailyWorkout(day: app.today.day, games: [g]),
                difficultyFor: app.difficultyFor,
                onGameResult: { app.recordGameResult($0, source: "free_play") },
                onWorkoutDone: { _ in freePlay = nil },
                onQuit: { freePlay = nil }
            )
        }
    }

    private func card(_ g: GameID) -> some View {
        Button {
            if g.isLive { freePlay = g }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: g.symbol)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(g.isLive ? Color.witsAccent : Color.witsFaint)
                    .frame(width: 46, height: 46)
                    .background((g.isLive ? Color.witsAccent : Color.witsFaint).opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(g.displayName)
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                Text(g.isLive ? g.domain.label : "coming soon")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(g.isLive ? Color.witsMuted : Color.witsFaint)
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .padding(16)
            .cardSurface()
            .opacity(g.isLive ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!g.isLive)
    }
}
