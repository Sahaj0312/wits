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
    @State private var launch: GameID?
    @State private var showPaywall = false

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
        .fullScreenCover(item: $launch) { g in
            GameLauncher(game: g)
        }
        .fullScreenCover(isPresented: $showPaywall) { PaywallView() }
    }

    private func card(_ g: GameID) -> some View {
        Button {
            guard g.isLive else { return }
            if app.entitlement.isExpired { showPaywall = true } else { launch = g }
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

/// Pre-game chooser: the card with Train vs Survival, then runs the chosen mode
/// in a single full-screen cover (no double card).
private struct GameLauncher: View {
    let game: GameID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .card

    private enum Phase { case card, train, survival }

    var body: some View {
        switch phase {
        case .card:
            GameCard(
                game: game,
                stats: app.gameStats[game],
                primaryTitle: "train",
                onPlay: { phase = .train },
                onBack: { dismiss() },
                onSurvival: { phase = .survival }
            )
            .overlay(alignment: .topLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.28), in: Circle())
                }
                .padding(.top, 44)
                .padding(.leading, 12)
            }
        case .train:
            ZStack {
                Color.witsBg.ignoresSafeArea()
                makeGameView(game, config: .standard(game, difficulty: app.difficultyFor(game), freePlay: true)) { r in
                    app.recordGameResult(r, source: "free_play")
                    dismiss()
                }
            }
            .overlay(alignment: .topLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Color.witsFaint)
                        .padding(12)
                }
                .padding(.top, 44)
            }
            .onAppear { GameFeel.shared.warmUp() }
            .onDisappear { GameFeel.shared.teardown() }
        case .survival:
            SurvivalHost(
                game: game,
                seedDifficulty: app.difficultyFor(game),
                stats: app.gameStats[game],
                onRunComplete: { score, trials in app.recordSurvivalRun(game: game, score: score, trials: trials) },
                onQuit: { dismiss() },
                startImmediately: true
            )
        }
    }
}
