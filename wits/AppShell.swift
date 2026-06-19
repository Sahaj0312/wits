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

// MARK: - Activity tab (progress + friends ranking)

/// A single row in the friends ranking: you or a friend, ranked by lifetime XP.
private struct RankedPlayer {
    let name: String
    let xp: Int
    let trainedToday: Bool?
    let isMe: Bool
}

struct ActivityTab: View {
    @Environment(AppModel.self) private var app

    private var headlinePoints: [SeriesPoint] { ProgressMath.headlineSeries(app.progressDays) }
    private var domainScores: [CognitiveDomain: Double] { ProgressMath.latestDomainScores(app.progressDays) }
    private var heroScore: Double? { ProgressMath.headline(app.progressDays) }
    private var domainRows: [(domain: CognitiveDomain, value: Double)] {
        CognitiveDomain.allCases.compactMap { d in domainScores[d].map { (d, $0) } }
    }

    /// Single headline number, top-right.
    private var brainScoreBadge: some View {
        VStack(spacing: 1) {
            Text(heroScore.map { "\(Int($0))" } ?? "—")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsAccent)
                .monospacedDigit()
            Text("brain score")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.witsMuted)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.witsAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// You + your friends, ranked by lifetime XP. Highest first; you're
    /// highlighted in place so you can see where you stand.
    private var friendRanking: [RankedPlayer] {
        guard !app.friends.isEmpty else { return [] }
        var players = [RankedPlayer(name: "you", xp: app.xp, trainedToday: nil, isMe: true)]
        players += app.friends.map {
            RankedPlayer(name: $0.name, xp: $0.xp, trainedToday: $0.trainedToday, isMe: false)
        }
        return players.sorted { $0.xp > $1.xp }
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
                    brainScoreBadge
                }
                .padding(.top, 8)

                if domainScores.isEmpty {
                    emptyCard("finish a workout to see your brain score and skill breakdown.")
                } else {
                    DomainRadarChart(scores: domainScores)

                    section("your scores")
                    VStack(spacing: 10) {
                        MetricBar(label: "overall", value: heroScore ?? 0,
                                  series: headlinePoints, emphasized: true)
                        ForEach(domainRows, id: \.domain) { row in
                            MetricBar(label: row.domain.label, value: row.value,
                                      series: ProgressMath.domainSeries(app.progressDays, row.domain))
                        }
                    }
                }

                if !app.checkins.isEmpty {
                    section("lifestyle")
                    LifestyleCard(checkins: app.checkins)
                }

                if let msg = app.percentileMessage {
                    HStack(spacing: 12) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(Color.witsAccent)
                        Text(msg)
                            .font(.witsBody(14, weight: .semibold))
                            .foregroundStyle(Color.witsInk)
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()
                }

                if !friendRanking.isEmpty {
                    section("friends")
                    VStack(spacing: 8) {
                        ForEach(Array(friendRanking.enumerated()), id: \.offset) { idx, p in
                            friendRankRow(rank: idx + 1, player: p)
                        }
                    }
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
        .toolbar(.hidden, for: .navigationBar)
        .task { await app.refreshFriends() }
        }
    }

    @ViewBuilder
    private func friendRankRow(rank: Int, player p: RankedPlayer) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(p.isMe ? Color.witsAccent : Color.witsFaint)
                .frame(width: 28)
                .monospacedDigit()
            Image(systemName: "person.fill")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color.witsAccent)
                .frame(width: 34, height: 34)
                .background(Color.witsAccent.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name)
                    .font(.system(size: 15, weight: p.isMe ? .heavy : .semibold, design: .rounded))
                    .foregroundStyle(p.isMe ? Color.witsInk : Color.witsInk)
                    .lineLimit(1)
                if let trained = p.trainedToday {
                    Text(trained ? "trained today" : "hasn't trained today")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(trained ? Color.witsAccent : Color.witsMuted)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                Text("\(p.xp)")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                    .monospacedDigit()
                Text("xp")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsFaint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(p.isMe ? Color.witsAccent.opacity(0.10) : Color.witsCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(p.isMe ? Color.witsAccent : .clear, lineWidth: 1.5)
        )
        .shadow(color: .witsShadow, radius: 6, y: 3)
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
