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
        if hasCompletedOnboarding {
            switch app.load {
            case .ready:
                RootShell()
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
