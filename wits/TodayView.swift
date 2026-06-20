//
//  TodayView.swift
//  wits
//
//  The retention surface. One job: get a returning user into today's workout in
//  one tap. Shows the streak (loss aversion), the day's games, and a single big
//  start button — or, once done, a finite "come back tomorrow" stop point.
//

import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var app
    @State private var playing = false
    @State private var showPrimer = false
    @State private var showPaywall = false
    @State private var showCheckIn = false
    @State private var pendingStart = false
    @State private var challengeGame: GameID?
    @State private var didCenterLiveNode = false
    @AppStorage("notifPrimerAsked") private var notifPrimerAsked = false

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "good morning"
        case 12..<17: return "good afternoon"
        case 17..<22: return "good evening"
        default: return "still up?"
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Text(app.isWorkoutDoneToday ? "done for today — see you tomorrow"
                                                : "your journey")
                        .font(.witsBody(13.5, weight: .semibold))
                        .foregroundStyle(Color.witsMuted)
                        .padding(.top, 20)

                    WorkoutPathView(onStart: beginWorkout)
                        .padding(.top, 6)

                    if case .trial = app.entitlement {
                        Text("\(app.entitlement.trialDaysLeft) days left in your free trial")
                            .font(.witsBody(12.5))
                            .foregroundStyle(Color.witsFaint)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }

                    if let g = app.dailyChallengeGame, !app.dailyChallengeDone {
                        challengeCard(g).padding(.top, 14)
                    }
                }
                .padding(.horizontal, WitsMetrics.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .onAppear { centerLiveNode(proxy, animated: false) }
                .onChange(of: app.today.results.count) { _, _ in centerLiveNode(proxy, animated: true) }
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.witsBg.ignoresSafeArea())
        .fullScreenCover(isPresented: $playing) {
            GameHost(
                workout: app.today,
                difficultyFor: app.difficultyFor,
                onGameResult: { app.recordWorkoutGame($0) },
                onWorkoutDone: { _ in
                    // rollup already happened as the final game completed; just close.
                    playing = false
                    // first value moment → offer reminders (once)
                    if !notifPrimerAsked && !app.profile.notificationsEnabled {
                        notifPrimerAsked = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showPrimer = true }
                    }
                },
                onQuit: { playing = false }
            )
        }
        .fullScreenCover(isPresented: $showCheckIn, onDismiss: {
            if pendingStart { pendingStart = false; playing = true }
        }) {
            DailyCheckInView(
                onFinish: { mood, sleep in
                    if mood != nil || sleep != nil {
                        app.recordCheckIn(mood: mood ?? 3, sleep: sleep ?? 2)
                    } else {
                        app.skipCheckInToday()
                    }
                    pendingStart = true
                    showCheckIn = false
                },
                onStop: {
                    app.checkinsDisabled = true
                    app.skipCheckInToday()
                    pendingStart = true
                    showCheckIn = false
                }
            )
        }
        .sheet(isPresented: $showPrimer) {
            NotificationPrimer()
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView()
        }
        .fullScreenCover(item: $challengeGame) { g in
            GameHost(
                workout: DailyWorkout(day: app.today.day, games: [g]),
                difficultyFor: app.difficultyFor,
                onGameResult: { _ in },
                onWorkoutDone: { results in
                    if let r = results.first { app.completeDailyChallenge(r) }
                    challengeGame = nil
                },
                onQuit: { challengeGame = nil }
            )
        }
    }

    private func challengeCard(_ g: GameID) -> some View {
        Button { challengeGame = g } label: {
            HStack(spacing: 14) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Color.witsWarm)
                    .frame(width: 44, height: 44)
                    .background(Color.witsWarm.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("surprise challenge")
                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                    Text("one round of \(g.displayName) · a quick bonus")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.witsMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color.witsFaint)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
        .buttonStyle(.plain)
        .rise(0.1)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.witsBody(15, weight: .semibold))
                    .foregroundStyle(Color.witsMuted)
                Text("wits")
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsAccent)
            }
            Spacer()
            streakPill
        }
    }

    private var streakPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(app.streak.current > 0 ? Color.witsWarm : Color.witsFaint)
            Text("\(app.streak.current)")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsInk)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.witsCard, in: Capsule())
        .shadow(color: .witsShadow, radius: 8, y: 4)
    }

    /// Tapped the live node on the path → start / resume today's workout.
    private func beginWorkout() {
        if app.entitlement.isExpired { showPaywall = true }
        else if app.needsCheckIn { showCheckIn = true }
        else { playing = true }
    }

    private func centerLiveNode(_ proxy: ScrollViewProxy, animated: Bool) {
        guard !didCenterLiveNode || animated else { return }
        didCenterLiveNode = true
        let scroll = {
            if animated {
                withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.38)) {
                    proxy.scrollTo(WorkoutPathView.liveScrollID, anchor: .center)
                }
            } else {
                proxy.scrollTo(WorkoutPathView.liveScrollID, anchor: .center)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: scroll)
        if !animated {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: scroll)
        }
    }
}
