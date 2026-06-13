//
//  OnboardingScreens.swift
//  wits
//
//  Part one of the flow: hook, welcome, goals, calibration, likert quiz,
//  stat checkpoint, and about-you questions.
//

import SwiftUI

// MARK: - 1. Hook

struct HookScreen: View {
    var onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                LogoBlob(size: 72, breathe: true)
                    .rise()
                Text("sharpen your \(Text("wits").foregroundStyle(Color.witsAccent))")
                    .font(.witsDisplay(42))
                    .foregroundStyle(Color.witsInk)
                    .rise(0.1)
                Text("discover what your mind can do, and train it to do more.")
                    .font(.witsBody(17))
                    .foregroundStyle(Color.witsMuted)
                    .rise(0.19)
            }
            Spacer()
            VStack(spacing: 12) {
                Cta(title: "get started", action: onNext)
                    .rise(0.28)
                Text("takes about 3 minutes. no studying required.")
                    .font(.witsBody(12.5))
                    .foregroundStyle(Color.witsFaint)
                    .rise(0.36)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.bottom, 12)
    }
}

// MARK: - 2. Welcome overview

struct WelcomeScreen: View {
    var onNext: () -> Void

    private let steps = [
        (1, "your goals", "tell us what you'd like to improve"),
        (2, "your brain performance", "three quick games measure your baseline"),
        (3, "your training plan", "a personalized program, built for you"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
                .padding(.bottom, 30)
            Text("here's how it works")
                .font(.witsDisplay(32))
                .foregroundStyle(Color.witsInk)
                .rise()
            Text("we'll build your personalized plan in three parts.")
                .font(.witsBody(16))
                .foregroundStyle(Color.witsMuted)
                .padding(.top, 12)
                .padding(.bottom, 26)
                .rise(0.08)
            VStack(spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    PlanItem(number: step.0, title: step.1, sub: step.2)
                        .rise(0.16 + Double(i) * 0.09)
                }
            }
            Spacer()
            Cta(title: "continue", action: onNext)
                .rise(0.48)
                .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }
}

// MARK: - 3. Goals

struct GoalsScreen: View {
    var onNext: ([String]) -> Void

    private static let goals = [
        "sharpen my focus",
        "improve my memory",
        "boost my attention",
        "think faster",
        "keep my mind active",
        "just exploring",
    ]

    @State private var picked: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressTrack(fraction: 1 / onboardingQuizTotal)
                .padding(.bottom, 30)
            Text("what would you like to improve?")
                .font(.witsDisplay(30))
                .foregroundStyle(Color.witsInk)
                .padding(.bottom, 16)
                .rise()
            Text("select all that apply.")
                .font(.witsBody(16))
                .foregroundStyle(Color.witsMuted)
                .padding(.bottom, 24)
                .rise(0.08)
            FlowLayout(spacing: 10) {
                ForEach(Array(Self.goals.enumerated()), id: \.element) { i, goal in
                    GoalChip(label: goal, picked: picked.contains(goal)) {
                        if let idx = picked.firstIndex(of: goal) {
                            picked.remove(at: idx)
                        } else {
                            picked.append(goal)
                        }
                    }
                    .rise(0.14 + Double(i) * 0.06)
                }
            }
            Spacer()
            Cta(title: picked.isEmpty ? "select at least one" : "continue", dimmed: picked.isEmpty) {
                if !picked.isEmpty { onNext(picked) }
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }
}

private struct GoalChip: View {
    var label: String
    var picked: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                .foregroundStyle(picked ? Color.witsAccent : Color.witsInk)
                .padding(.horizontal, 17)
                .padding(.vertical, 13)
                .background(Color.witsCard, in: Capsule())
                .overlay(Capsule().strokeBorder(picked ? Color.witsAccent : .clear, lineWidth: 1.5))
                .shadow(color: .witsShadow, radius: 10, y: 6)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: picked)
    }
}

// MARK: - 4. Calibration interstitial

struct CalibrateScreen: View {
    var onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                LogoBlob(size: 56, breathe: true)
                    .rise()
                Text("let's personalize your plan")
                    .font(.witsDisplay(32))
                    .foregroundStyle(Color.witsInk)
                    .rise(0.08)
                Text("a few quick statements. tell us how much each one sounds like you — it helps us tailor your program.")
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

// MARK: - 5. Likert quiz

struct LikertScreen: View {
    var index: Int
    var onAnswer: (Int) -> Void

    static let statements = [
        "i misplace everyday things like my keys, phone, or glasses.",
        "some days my thinking feels foggy for no clear reason.",
        "i read or hear something and forget it moments later.",
        "names slip away right after i'm introduced to someone.",
        "i find it hard to stay focused on one task.",
        "i lose the thread during longer conversations.",
    ]
    private static let options: [(label: String, score: Int)] = [
        ("strongly disagree", 0),
        ("disagree", 1),
        ("agree", 2),
        ("strongly agree", 3),
    ]

    @State private var picked: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressTrack(fraction: Double(2 + index) / onboardingQuizTotal)
                .padding(.bottom, 30)
            Text("statement \(index + 1) of \(Self.statements.count)")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.witsFaint)
                .padding(.bottom, 10)
                .rise()
            Text(Self.statements[index])
                .font(.witsDisplay(26))
                .foregroundStyle(Color.witsInk)
                .padding(.bottom, 28)
                .rise(0.06)
            VStack(spacing: 10) {
                ForEach(Array(Self.options.enumerated()), id: \.offset) { i, option in
                    AnswerRow(label: option.label, picked: picked == i) {
                        guard picked == nil else { return }
                        picked = i
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onAnswer(option.score)
                        }
                    }
                    .rise(0.14 + Double(i) * 0.07)
                }
            }
            Spacer()
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }
}

// MARK: - 6. Stat checkpoint

struct StatScreen: View {
    var onNext: () -> Void

    @State private var value = 0
    private let target = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Text("\(value)")
                    .font(.system(size: 92, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsAccent)
                    .monospacedDigit()
                    .rise()
                Text("minutes a day is all it takes to start training your brain.")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                    .rise(0.12)
                Text("small sessions, done consistently, add up over time.")
                    .font(.witsBody(15))
                    .foregroundStyle(Color.witsMuted)
                    .rise(0.22)
            }
            Spacer()
            Cta(title: "keep going", action: onNext)
                .rise(0.32)
                .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
        .task {
            let start = Date()
            let duration = 1.1
            while !Task.isCancelled {
                let t = min(1, Date().timeIntervalSince(start) / duration)
                value = Int((1 - pow(1 - t, 3)) * Double(target))
                if t >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }
}

// MARK: - About you: screen time

struct ScreenTimeScreen: View {
    var onAnswer: (Int) -> Void

    private static let options: [(label: String, score: Int)] = [
        ("under 3 hours", 0),
        ("3–5 hours", 1),
        ("5–8 hours", 2),
        ("more than 8 hours", 3),
    ]

    @State private var picked: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressTrack(fraction: 11 / onboardingQuizTotal)
                .padding(.bottom, 30)
            Text("about you")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.witsFaint)
                .padding(.bottom, 10)
                .rise()
            Text("how much screen time on a typical day?")
                .font(.witsDisplay(30))
                .foregroundStyle(Color.witsInk)
                .padding(.bottom, 16)
                .rise(0.06)
            Text("a rough estimate is fine.")
                .font(.witsBody(16))
                .foregroundStyle(Color.witsMuted)
                .padding(.bottom, 24)
                .rise(0.1)
            VStack(spacing: 10) {
                ForEach(Array(Self.options.enumerated()), id: \.offset) { i, option in
                    AnswerRow(label: option.label, picked: picked == i) {
                        guard picked == nil else { return }
                        picked = i
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onAnswer(option.score)
                        }
                    }
                    .rise(0.14 + Double(i) * 0.07)
                }
            }
            Spacer()
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }
}
