//
//  OnboardingProgram.swift
//  wits
//
//  Sections five & seven interstitials + the program-builder questionnaire:
//  meet-you, plan intro, difficulty, exercise, sleep, training days.
//

import SwiftUI

// MARK: - "Great to meet you" (before the fit test)

struct MeetYouScreen: View {
    var onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Color.witsAccent)
                    .frame(width: 88, height: 88)
                    .background(Color.witsAccent.opacity(0.14), in: Circle())
                    .rise()
                Text("great to meet you")
                    .font(.witsDisplay(32))
                    .foregroundStyle(Color.witsInk)
                    .rise(0.08)
                Text("next, we'll calibrate your program to your current level so you can improve over time.")
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

// MARK: - Plan intro (after results, before builder)

struct PlanIntroScreen: View {
    var onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Color.witsWarm)
                    .frame(width: 88, height: 88)
                    .background(Color.witsWarm.opacity(0.14), in: Circle())
                    .rise()
                Text("now that we have your baseline")
                    .font(.witsDisplay(32))
                    .foregroundStyle(Color.witsInk)
                    .rise(0.08)
                Text("let's build a plan to help you strengthen your memory, attention, and reasoning.")
                    .font(.witsBody(16))
                    .foregroundStyle(Color.witsMuted)
                    .rise(0.16)
            }
            Spacer()
            Cta(title: "build my program", action: onNext)
                .rise(0.26)
                .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }
}

// MARK: - Difficulty

struct DifficultyScreen: View {
    var onAnswer: (String) -> Void

    private static let options: [(label: String, sub: String)] = [
        ("standard", "i like to balance fun with steady improvement. (recommended)"),
        ("advanced", "i want to push myself and improve faster."),
    ]

    var body: some View {
        BuilderPicker(
            title: "what difficulty do you want",
            sub: nil,
            options: Self.options,
            onAnswer: onAnswer
        )
    }
}

// MARK: - Exercise frequency

struct ExerciseScreen: View {
    var onAnswer: (String) -> Void

    private static let options: [(label: String, sub: String)] = [
        ("daily or almost daily", ""),
        ("a few times per week", ""),
        ("once a week or less", ""),
        ("rarely or never", ""),
    ]

    var body: some View {
        BuilderPicker(
            title: "how often do you exercise",
            sub: "physical activity supports brain health.",
            options: Self.options,
            onAnswer: onAnswer
        )
    }
}

// MARK: - Sleep

struct SleepScreen: View {
    var onAnswer: (String) -> Void

    private static let options: [(label: String, sub: String)] = [
        ("4 hours or less", ""),
        ("5–6 hours", ""),
        ("7–8 hours", ""),
        ("9 hours or more", ""),
    ]

    var body: some View {
        BuilderPicker(
            title: "how much sleep do you get",
            sub: "on a typical night.",
            options: Self.options,
            onAnswer: onAnswer
        )
    }
}

// MARK: - Training days per week

struct TrainingDaysScreen: View {
    var onAnswer: (Int) -> Void

    private static let options = [3, 4, 5, 6, 7]

    var body: some View {
        BuilderPicker(
            title: "how many days a week can you train",
            sub: "research shows that more training leads to bigger improvements.",
            options: Self.options.map { (label: "\($0) days a week", sub: "") },
            onAnswer: { label in
                let n = Int(label.prefix { $0.isNumber }) ?? 5
                onAnswer(n)
            }
        )
    }
}

// MARK: - Shared builder picker (single-select, auto-advance, no progress bar)

struct BuilderPicker: View {
    var title: String
    var sub: String?
    var options: [(label: String, sub: String)]
    var onAnswer: (String) -> Void

    @State private var picked: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
                .padding(.bottom, 30)
            Text(title)
                .font(.witsDisplay(28))
                .foregroundStyle(Color.witsInk)
                .padding(.bottom, sub == nil ? 22 : 14)
                .rise()
            if let sub {
                Text(sub)
                    .font(.witsBody(16))
                    .foregroundStyle(Color.witsMuted)
                    .padding(.bottom, 22)
                    .rise(0.08)
            }
            VStack(spacing: 10) {
                ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                    AnswerRow(label: option.label, sub: option.sub.isEmpty ? nil : option.sub, picked: picked == i) {
                        guard picked == nil else { return }
                        picked = i
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onAnswer(option.label)
                        }
                    }
                    .rise(0.14 + Double(i) * 0.06)
                }
            }
            Spacer(minLength: 12)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }
}
