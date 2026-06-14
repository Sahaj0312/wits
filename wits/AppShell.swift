//
//  AppShell.swift
//  wits
//
//  The post-onboarding chrome: a four-tab shell with Today as the default. The
//  Today tab is the retention surface; the others are depth the user reaches for.
//

import SwiftUI

struct RootShell: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("today", systemImage: "bolt.fill") }
            ProgressTab()
                .tabItem { Label("progress", systemImage: "chart.line.uptrend.xyaxis") }
            GamesLibraryView()
                .tabItem { Label("games", systemImage: "square.grid.2x2.fill") }
            ProfileView()
                .tabItem { Label("you", systemImage: "person.fill") }
        }
        .tint(.witsAccent)
    }
}

// MARK: - Progress tab (Phase-1 baseline; Swift Charts hero arrives in Phase 2)

struct ProgressTab: View {
    @Environment(AppModel.self) private var app

    private var completedDays: [DailyProgressRow] {
        app.progressDays.filter { $0.workout_done == true }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("your progress")
                    .font(.witsDisplay(30))
                    .foregroundStyle(Color.witsInk)
                    .padding(.top, 8)

                HStack(spacing: 12) {
                    metric(value: "\(app.streak.current)", label: "day streak")
                    metric(value: "\(completedDays.count)", label: "workouts")
                    metric(value: app.headlineIndex.map { "\(Int($0))" } ?? "—", label: "wits score")
                }

                Text("recent days")
                    .font(.witsBody(15, weight: .bold))
                    .foregroundStyle(Color.witsMuted)
                    .padding(.top, 4)

                if completedDays.isEmpty {
                    Text("finish a workout to start your improvement chart. with a few days of data, you'll see how your scores trend.")
                        .font(.witsBody(15))
                        .foregroundStyle(Color.witsMuted)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface()
                } else {
                    miniChart
                }

                Text("wits measures how you do on these games over time. it doesn't claim to raise your iq — it shows you getting sharper at the skills you train.")
                    .font(.witsBody(12.5))
                    .foregroundStyle(Color.witsFaint)
                    .padding(.top, 6)
            }
            .padding(.horizontal, WitsMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .background(Color.witsBg.ignoresSafeArea())
    }

    private var miniChart: some View {
        let days = completedDays.suffix(14)
        let maxV = max(1, days.compactMap { $0.headline_index }.max() ?? 1)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                let v = d.headline_index ?? 0
                VStack {
                    Capsule()
                        .fill(Color.witsAccent)
                        .frame(height: max(6, CGFloat(v / maxV) * 120))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 130)
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsAccent)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.witsMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .cardSurface()
    }
}
