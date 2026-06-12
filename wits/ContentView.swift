//
//  ContentView.swift
//  wits
//
//  Created by Sahajdeep Chhabra on 2026-06-11.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            HomePlaceholder {
                hasCompletedOnboarding = false
            }
        } else {
            OnboardingView {
                hasCompletedOnboarding = true
            }
        }
    }
}

/// Stand-in for the main app until it exists.
private struct HomePlaceholder: View {
    var resetOnboarding: () -> Void

    var body: some View {
        ZStack {
            Color.witsBg.ignoresSafeArea()
            VStack(spacing: 20) {
                LogoBlob(size: 64, breathe: true)
                Text("welcome to wits")
                    .font(.witsDisplay(28))
                    .foregroundStyle(Color.witsInk)
                Text("the main app goes here.")
                    .font(.witsBody(16))
                    .foregroundStyle(Color.witsMuted)
                QuietButton(title: "replay onboarding", action: resetOnboarding)
            }
        }
    }
}

#Preview {
    ContentView()
}
