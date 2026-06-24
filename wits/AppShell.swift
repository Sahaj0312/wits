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
    @State private var showScoringInfo = false

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
                        HStack(spacing: 8) {
                            Text("activity")
                                .font(.witsDisplay(30))
                                .foregroundStyle(Color.witsInk)
                            Button { showScoringInfo = true } label: {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 19, weight: .bold))
                                    .foregroundStyle(Color.witsFaint)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("how WPI scoring works")
                        }
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
        .sheet(isPresented: $showScoringInfo) {
            ScoringInfoSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
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

private struct ScoringInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        WitsBrandMark()
                        Text("how WPI works")
                            .font(.witsDisplay(28))
                            .foregroundStyle(Color.witsInk)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Color.witsMuted)
                            .frame(width: 34, height: 34)
                            .background(Color.witsTint, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("close")
                }

                VStack(alignment: .leading, spacing: 12) {
                    infoRow(icon: "bolt.fill",
                            title: "WPI is your training score",
                            body: "WPI is based on the mastery level you have earned in each skill area. It is separate from the points you see inside a game.")
                    divider
                    infoRow(icon: "number",
                            title: "Skill score = mastery × 500",
                            body: "Each game has a mastery level from 1 to 10. A level 4 skill is about 2000 WPI; level 10 is 5000.")
                    divider
                    infoRow(icon: "arrow.up.arrow.down",
                            title: "Scores can move down",
                            body: "Strong runs raise mastery. Weaker runs lower it gently, so WPI reflects current performance instead of only showing your best ever result.")
                    divider
                    infoRow(icon: "chart.bar.fill",
                            title: "Overall is an average",
                            body: "Your overall WPI is the average of trained skill scores. New skill areas appear after you play games in those areas.")
                }
                .padding(16)
                .cardSurface()

                Text("Raw points still matter for a single round, but WPI is the long-term progress system.")
                    .font(.witsBody(14))
                    .foregroundStyle(Color.witsMuted)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, WitsMetrics.screenPadding)
            .padding(.top, 22)
            .padding(.bottom, 28)
        }
        .background(Color.witsBg.ignoresSafeArea())
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.witsLine)
            .frame(height: 1)
    }

    private func infoRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Color.witsAccent)
                .frame(width: 32, height: 32)
                .background(Color.witsAccent.opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                Text(body)
                    .font(.witsBody(14))
                    .foregroundStyle(Color.witsMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
