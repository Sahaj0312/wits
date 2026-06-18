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
            ActivityTab()
                .tabItem { Label("activity", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(1)
            GamesLibraryView()
                .tabItem { Label("games", systemImage: "square.grid.2x2.fill") }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    WitsBrandMark()
                    Text("activity")
                        .font(.witsDisplay(30))
                        .foregroundStyle(Color.witsInk)
                }
                .padding(.top, 8)

                HStack(spacing: 12) {
                    metric(value: "\(app.streak.current)", label: "day streak")
                    metric(value: "\(app.xp)", label: "xp")
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
                    DomainRadarChart(scores: domainScores)
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
        .task { await app.refreshFriends() }
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
