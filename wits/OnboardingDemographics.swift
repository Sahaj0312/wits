//
//  OnboardingDemographics.swift
//  wits
//
//  Section four: demographics. A bit-about-you intro, then gender, education,
//  and attribution — Lumosity's baseline questions in wits' voice.
//

import SwiftUI

// MARK: - Intro

struct AboutYouScreen: View {
    var onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                ConcentricMark()
                    .rise()
                Text("now, a bit about you")
                    .font(.witsDisplay(32))
                    .foregroundStyle(Color.witsInk)
                    .rise(0.08)
                Text("cognitive performance varies by age, background, and lifestyle. these details help us set the right baseline for you.")
                    .font(.witsBody(16))
                    .foregroundStyle(Color.witsMuted)
                    .rise(0.16)
            }
            Spacer()
            Cta(title: "continue", action: onNext)
                .rise(0.26)
                .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }
}

private struct ConcentricMark: View {
    var body: some View {
        ZStack {
            Circle().strokeBorder(Color.witsAccent.opacity(0.18), lineWidth: 2).frame(width: 72, height: 72)
            Circle().strokeBorder(Color.witsAccent.opacity(0.32), lineWidth: 2).frame(width: 50, height: 50)
            Image(systemName: "person.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.witsAccent)
        }
    }
}

// MARK: - Gender

struct GenderScreen: View {
    var onAnswer: (String) -> Void

    private static let options = ["male", "female", "non-binary"]

    var body: some View {
        PickerScreen(
            position: 8,
            eyebrow: "about you",
            title: "what's your gender?",
            sub: "this helps us compare you with similar members.",
            options: Self.options,
            onAnswer: onAnswer
        )
    }
}

// MARK: - Education

struct EducationScreen: View {
    var onAnswer: (String) -> Void

    private static let options = [
        "some high school",
        "high school",
        "some college",
        "associate degree",
        "college degree (ba/bs)",
        "master's degree",
        "professional degree",
    ]

    var body: some View {
        PickerScreen(
            position: 9,
            eyebrow: "about you",
            title: "what's the highest level of education you've completed?",
            sub: nil,
            options: Self.options,
            onAnswer: onAnswer
        )
    }
}

// MARK: - Attribution

struct AttributionScreen: View {
    var onAnswer: (String) -> Void

    private static let options = [
        "doctor or healthcare provider",
        "friend or family",
        "app store",
        "social media",
        "search (e.g. google)",
        "other",
    ]

    var body: some View {
        PickerScreen(
            position: 10,
            eyebrow: "about you",
            title: "how did you hear about wits?",
            sub: nil,
            options: Self.options,
            onAnswer: onAnswer
        )
    }
}

// MARK: - Attention history

struct AttentionHistoryScreen: View {
    var onAnswer: (String) -> Void

    private static let options = [
        "yes",
        "i think i do",
        "no",
        "i prefer not to share",
        "not sure",
    ]

    var body: some View {
        PickerScreen(
            position: 12,
            eyebrow: "about you",
            title: "do you have ADD/ADHD?",
            sub: "this can affect how you focus and learn.",
            options: Self.options,
            onAnswer: onAnswer
        )
    }
}

// MARK: - Shared single-select picker (auto-advances)

struct PickerScreen: View {
    var position: Int
    var eyebrow: String?
    var title: String
    var sub: String?
    var options: [String]
    var onAnswer: (String) -> Void

    @State private var picked: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressTrack(fraction: Double(position) / onboardingQuizTotal)
                .padding(.bottom, 30)
            if let eyebrow {
                Text(eyebrow)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.witsFaint)
                    .padding(.bottom, 10)
                    .rise()
            }
            Text(title)
                .font(.witsDisplay(28))
                .foregroundStyle(Color.witsInk)
                .padding(.bottom, sub == nil ? 22 : 14)
                .rise(0.06)
            if let sub {
                Text(sub)
                    .font(.witsBody(16))
                    .foregroundStyle(Color.witsMuted)
                    .padding(.bottom, 22)
                    .rise(0.1)
            }
            VStack(spacing: 10) {
                ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                    AnswerRow(label: option, picked: picked == i) {
                        guard picked == nil else { return }
                        picked = i
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onAnswer(option)
                        }
                    }
                    .rise(0.14 + Double(i) * 0.05)
                }
            }
            Spacer(minLength: 12)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }
}
