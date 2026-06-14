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
            LeaguesView()
                .tabItem { Label("league", systemImage: "trophy.fill") }
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
    private var headlinePoints: [SeriesPoint] { ProgressMath.headlineSeries(app.progressDays) }
    private var domainScores: [CognitiveDomain: Double] { ProgressMath.latestDomainScores(app.progressDays) }
    private var heroScore: Double? { ProgressMath.headline(app.progressDays) }

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
                    metric(value: heroScore.map { "\(Int($0))" } ?? "—", label: "wits score")
                }

                section("your brain is improving")
                if headlinePoints.count >= 2 {
                    HeadlineChart(points: headlinePoints)
                } else {
                    emptyCard("finish a couple of workouts to start your improvement chart. with a few days of data, you'll see how your scores trend.")
                }

                if !domainScores.isEmpty {
                    section("by skill")
                    DomainBars(scores: domainScores)
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

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.witsBody(15, weight: .bold))
            .foregroundStyle(Color.witsMuted)
            .padding(.top, 4)
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.witsBody(15))
            .foregroundStyle(Color.witsMuted)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
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
