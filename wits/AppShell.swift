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
                .tabItem { Label("train", systemImage: "brain.head.profile") }
                .tag(0)
            GamesLibraryView()
                .tabItem { Label("games", systemImage: "square.grid.2x2.fill") }
                .tag(1)
            ActivityTab()
                .tabItem { Label("activity", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(2)
            ProfileView()
                .tabItem { Label("profile", systemImage: "person.fill") }
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
    private var latestProgress: DailyProgressRow? {
        app.progressDays.filter { $0.workout_done == true }.sorted { ($0.dayDate ?? .distantPast) < ($1.dayDate ?? .distantPast) }.last
    }
    private var coverageCount: Int {
        latestProgress?.coverage_count ?? domainScores.count
    }
    private var wpiStateLabel: String {
        guard heroScore != nil else { return "WPI" }
        if coverageCount <= 2 { return "calibrating" }
        if coverageCount <= 4 { return "early estimate" }
        return "WPI"
    }
    /// Single headline number, top-right.
    private var wpiBadge: some View {
        VStack(spacing: 1) {
            Text(heroScore.map { "\(Int($0))" } ?? "—")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsAccent)
                .monospacedDigit()
            Text(wpiStateLabel)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.witsMuted)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .padding(.trailing, 6)
        .background(Color.witsAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Button { showScoringInfo = true } label: {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.witsFaint)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("how WPI scoring works")
            .padding(3)
        }
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
                                  series: headlinePoints, emphasized: true,
                                  norm: app.statNorms["overall"])
                        ForEach(CognitiveDomain.allCases) { domain in
                            if let value = domainScores[domain] {
                                MetricBar(label: domain.label, value: value,
                                          series: ProgressMath.domainSeries(app.progressDays, domain),
                                          tint: domain.color,
                                          norm: app.statNorms[domain.rawValue])
                            } else {
                                untrainedDomainRow(domain)
                            }
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

    private func untrainedDomainRow(_ domain: CognitiveDomain) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(domain.color.opacity(0.45))
                .frame(width: 8, height: 8)
            Text(domain.label)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color.witsInk)
            Spacer()
            Text("not trained yet")
                .font(.witsLabel(12))
                .foregroundStyle(Color.witsFaint)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }
}

private struct ScoringInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var contentHeight: CGFloat = 560

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        WitsBrandMark()
                        Text("how WPI works")
                            .font(.witsDisplay(26))
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

                VStack(alignment: .leading, spacing: 10) {
                    infoRow(icon: "bolt.fill",
                            title: "WPI is your training score",
                            body: "WPI estimates your current skill from recent performance, measured against each game's own difficulty.")
                    divider
                    infoRow(icon: "number",
                            title: "points and WPI are separate",
                            body: "points reward one round. WPI moves more slowly from accuracy, speed, challenge, and confidence.")
                    divider
                    infoRow(icon: "arrow.up.arrow.down",
                            title: "scores can move both ways",
                            body: "strong runs raise your estimate. weaker or stale areas become less certain, so WPI reflects current training.")
                    divider
                    infoRow(icon: "chart.bar.fill",
                            title: "overall is an average",
                            body: "each skill area has its own score out of 5000. new areas calibrate as you train them.")
                }
                .padding(14)
                .cardSurface()

                Text("raw points still matter for a single round, but WPI is the long-term progress system.")
                    .font(.witsBody(13.5))
                    .foregroundStyle(Color.witsMuted)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, WitsMetrics.screenPadding)
            .padding(.top, 20)
            .padding(.bottom, 20)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: ScoringInfoSheetHeightKey.self, value: proxy.size.height)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onPreferenceChange(ScoringInfoSheetHeightKey.self) { contentHeight = ceil($0) }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.hidden)
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
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color.witsAccent)
                .frame(width: 30, height: 30)
                .background(Color.witsAccent.opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                Text(body)
                    .font(.witsBody(13.5))
                    .foregroundStyle(Color.witsMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ScoringInfoSheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 560
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
