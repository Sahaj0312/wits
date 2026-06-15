//
//  GameScaffold.swift
//  wits
//
//  Shared chrome for every game (onboarding fit test + the main-app library):
//  the phase machine, the top tag, the pre-game hero/explainer, the "you've got
//  it" interstitial, and the tutorial hint. Extracted from OnboardingGames so
//  the new adaptive games reuse exactly the same look and feel.
//

import SwiftUI

enum GamePhase {
    case intro, tutorial, ready, playing
}

struct GameTopTag: View {
    var text: String
    var body: some View {
        HStack {
            Wordmark()
            Spacer()
            Text(text)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.witsFaint)
        }
    }
}

/// Hero panel for the pre-game explainer: fixed navy stage with soft accent
/// glows, so the teal illustration reads the same in light and dark mode.
struct HeroPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(light: 0x243155, dark: 0x232E55), Color(light: 0x161F3A, dark: 0x141B33)],
                startPoint: .top, endPoint: .bottom
            )
            Circle()
                .fill(Color.witsAccent.opacity(0.10))
                .frame(width: 220, height: 220)
                .offset(x: -110, y: -80)
            Circle()
                .fill(Color.witsAccent.opacity(0.08))
                .frame(width: 180, height: 180)
                .offset(x: 130, y: 90)
            content
        }
        .frame(height: 195)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous))
        .shadow(color: .witsShadow, radius: 10, y: 6)
    }
}

/// Pre-game explainer card: hero illustration, "X tests your Y" headline,
/// how it plays, and what it measures.
struct GameExplainer<Hero: View>: View {
    var tag: String
    var title: String
    var skill: String
    var how: String
    var why: String
    var ctaTitle: String = "start tutorial"
    var onStart: () -> Void
    @ViewBuilder var hero: Hero

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GameTopTag(text: tag)
                .padding(.bottom, 18)
            HeroPanel { hero }
                .rise()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(title) tests your \(Text(skill).foregroundStyle(Color.witsAccent)).")
                        .font(.witsDisplay(27))
                        .foregroundStyle(Color.witsInk)
                        .rise(0.08)
                    Text(how)
                        .font(.witsBody(15.5))
                        .foregroundStyle(Color.witsMuted)
                        .rise(0.16)
                    Text(why)
                        .font(.witsBody(15.5))
                        .foregroundStyle(Color.witsMuted)
                        .rise(0.22)
                }
                .padding(.top, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Cta(title: ctaTitle, action: onStart)
                .rise(0.3)
                .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }
}

/// "Nice work" interstitial between tutorial and the scored run.
struct GameReady: View {
    var onPlay: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                Text("you've got it")
                    .font(.witsDisplay(28))
                    .foregroundStyle(Color.witsInk)
                Text("now it counts. respond as quickly as possible while avoiding mistakes.")
                    .font(.witsBody(16))
                    .foregroundStyle(Color.witsMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .cardSurface()
            .rise()
            Spacer()
            Cta(title: "let's play", action: onPlay)
                .rise(0.15)
                .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }
}

struct TutorialHint: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.witsBody(14, weight: .semibold))
            .foregroundStyle(Color.witsMuted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.witsTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
