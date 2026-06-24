//
//  AppShell.swift
//  wits
//
//  The post-onboarding chrome: a four-tab shell with Today as the default. The
//  Today tab is the retention surface; the others are depth the user reaches for.
//

import SwiftUI

struct RootShell: View {
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("today", systemImage: "bolt.fill") }
                .tag(0)
            GamesLibraryView()
                .tabItem { Label("games", systemImage: "square.grid.2x2.fill") }
                .tag(1)
            ActivityTab()
                .tabItem { Label("activity", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(2)
            ProfileView()
                .tabItem { Label("you", systemImage: "person.fill") }
                .tag(3)
        }
        .tint(.witsAccent)
        .sensoryFeedback(.selection, trigger: tab)
    }
}

// MARK: - Activity tab

struct ActivityTab: View {
    @Environment(AppModel.self) private var app

    private var headlinePoints: [SeriesPoint] { ProgressMath.headlineSeries(app.progressDays) }
    private var domainScores: [CognitiveDomain: Double] { ProgressMath.latestDomainScores(app.progressDays) }
    private var heroScore: Double? { ProgressMath.headline(app.progressDays) }
    private var domainRows: [(domain: CognitiveDomain, value: Double)] {
        CognitiveDomain.allCases.compactMap { d in domainScores[d].map { (d, $0) } }
    }

    /// Single headline number, top-right.
    private var wpiBadge: some View {
        VStack(spacing: 1) {
            Text(heroScore.map { "\(Int($0))" } ?? "—")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsAccent)
                .monospacedDigit()
            Text("WPI")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.witsMuted)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.witsAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    var body: some View {
        NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        WitsBrandMark()
                        Text("activity")
                            .font(.witsDisplay(30))
                            .foregroundStyle(Color.witsInk)
                    }
                    Spacer()
                    wpiBadge
                }
                .padding(.top, 8)

                if domainScores.isEmpty {
                    emptyCard("finish a workout to see your WPI and skill breakdown.")
                } else {
                    DomainRadarChart(scores: domainScores)

                    section("skill scores")
                    VStack(spacing: 10) {
                        MetricBar(label: "overall", value: heroScore ?? 0,
                                  series: headlinePoints, emphasized: true)
                        ForEach(domainRows, id: \.domain) { row in
                            MetricBar(label: row.domain.label, value: row.value,
                                      series: ProgressMath.domainSeries(app.progressDays, row.domain))
                        }
                    }
                }
            }
            .padding(.horizontal, WitsMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .background(Color.witsBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        }
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
}
