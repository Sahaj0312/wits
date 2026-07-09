//
//  ContentView.swift
//  wits
//
//  Created by Sahajdeep Chhabra on 2026-06-11.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(AppModel.self) private var app

    var body: some View {
        if let g = ProcessInfo.processInfo.environment["WITS_GAME"], let id = GameID(rawValue: g) {
            DebugGameHarness(id: id)            // dev-only: SIMCTL_CHILD_WITS_GAME=<id>
        } else if hasCompletedOnboarding {
            switch app.load {
            case .ready:
                RootShell()
                    .task {
                        AdManager.shared.adFreeProvider = { [weak app] in app?.entitlement.isAdFree ?? false }
                        await AdManager.shared.startIfNeeded()
                    }
            case .idle:
                SplashView()
                    .onAppear { app.bootstrap() }
            }
        } else {
            OnboardingView {
                hasCompletedOnboarding = true
                app.bootstrap()
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

/// Branded loader shown only while the cache hydrates (sub-second in practice).
struct SplashView: View {
    var body: some View {
        ZStack {
            Color.witsBg.ignoresSafeArea()
            LogoBlob(size: 64, breathe: true)
        }
    }
}

#Preview {
    ContentView()
        .environment(SupabaseManager.shared)
        .environment(AppModel(supa: .shared))
}
