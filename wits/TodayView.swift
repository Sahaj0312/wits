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
    @State private var challengeGame: GameID?
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if app.isWorkoutDoneToday {
                    doneCard.padding(.top, 22)
                } else {
                    workoutCard.padding(.top, 22)
                }
                if let g = app.dailyChallengeGame, !app.dailyChallengeDone {
                    challengeCard(g).padding(.top, 14)
                }
            }
            .padding(.horizontal, WitsMetrics.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(Color.witsBg.ignoresSafeArea())
        .fullScreenCover(isPresented: $playing) {
            GameHost(
                workout: app.today,
                difficultyFor: app.difficultyFor,
                onGameResult: { app.recordGameResult($0) },
                onWorkoutDone: { results in
                    app.finishWorkout(results)
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
        .sheet(isPresented: $showPrimer) {
            NotificationPrimer()
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
                    Text("one round of \(g.displayName) · earns a streak freeze")
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
                Wordmark()
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
            if app.streak.freezes > 0 {
                Image(systemName: "snowflake")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color.witsAccent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.witsCard, in: Capsule())
        .shadow(color: .witsShadow, radius: 8, y: 4)
    }

    private var workoutCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("today's workout")
                .font(.witsDisplay(30))
                .foregroundStyle(Color.witsInk)
                .rise()
            Text("\(app.today.games.count) games · about three minutes")
                .font(.witsBody(15.5))
                .foregroundStyle(Color.witsMuted)
                .padding(.top, 8)
                .rise(0.06)

            VStack(spacing: 10) {
                ForEach(Array(app.today.games.enumerated()), id: \.offset) { i, g in
                    gameRow(g).rise(0.14 + Double(i) * 0.07)
                }
            }
            .padding(.top, 20)

            Cta(title: "start workout") { playing = true }
                .padding(.top, 22)
                .rise(0.4)

            if case let .trial(_) = app.entitlement {
                Text("\(app.entitlement.trialDaysLeft) days left in your free trial")
                    .font(.witsBody(12.5))
                    .foregroundStyle(Color.witsFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .rise(0.46)
            }
        }
    }

    private func gameRow(_ g: GameID) -> some View {
        HStack(spacing: 14) {
            Image(systemName: g.symbol)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Color.witsAccent)
                .frame(width: 42, height: 42)
                .background(Color.witsAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(g.displayName)
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                Text(g.tagline)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.witsMuted)
            }
            Spacer(minLength: 0)
            Text(g.domain.label)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.witsFaint)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var doneCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 46, weight: .heavy))
                .foregroundStyle(Color.witsAccent)
            Text("done for today")
                .font(.witsDisplay(28))
                .foregroundStyle(Color.witsInk)
            Text("you trained today and your streak is safe. come back tomorrow for a fresh workout — no need to grind.")
                .font(.witsBody(15.5))
                .foregroundStyle(Color.witsMuted)
                .multilineTextAlignment(.center)
            QuietButton(title: "play again anyway") { playing = true }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .cardSurface()
        .rise()
    }
}
