//
//  ContentView.swift
//  wits
//
//  Created by Sahajdeep Chhabra on 2026-06-11.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let g = ProcessInfo.processInfo.environment["WITS_GAME"], let id = GameID(rawValue: g) {
            DebugGameHarness(id: id)            // dev-only: SIMCTL_CHILD_WITS_GAME=<id>
        } else {
            GamesLibraryView()
                .task {
                    GameCenterManager.shared.onAuthenticated = { [weak app] in
                        guard let app else { return }
                        GameCenterManager.shared.syncLocalBests(levels: app.levels, streak: app.streak)
                    }
                    GameCenterManager.shared.authenticate()
                    AdManager.shared.adFreeProvider = { PurchasesManager.shared.isAdFree }
                    await AdManager.shared.startIfNeeded()
                }
        }
    }
}

/// Dev-only: launch straight into one game for screenshots/feel testing.
struct DebugGameHarness: View {
    let id: GameID

    private var debugDifficulty: DifficultyState {
        if let raw = ProcessInfo.processInfo.environment["WITS_LEVEL"],
           let level = Double(raw) {
            return DifficultyState(level: level,
                                   mastery: level,
                                   variance: 1.2,
                                   scoringVersion: id.difficultyScoringVersion)
        }
        return .seed(for: id)
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                GameStageBackground(game: id)
                makeGameView(id, config: .standard(id, difficulty: debugDifficulty, freePlay: true)) { _ in }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, id.ownsSafeAreaSurface ? 0 : 36)
                    .padding(.bottom, id.ownsSafeAreaSurface ? 0 : 8)
                    .clipped()
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
