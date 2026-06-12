//
//  OnboardingScreens.swift
//  wits
//
//  Part one of the flow: hook, welcome, goals, calibration, likert quiz,
//  stat checkpoint, and about-you questions.
//

import SwiftUI

private let quizTotal = 8.0

// MARK: - 1. Hook

struct HookScreen: View {
    var onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                LogoBlob(size: 72, breathe: true)
                    .rise()
                Text("your attention span is \(Text("cooked").foregroundStyle(Color.witsAccent))")
                    .font(.witsDisplay(42))
                    .foregroundStyle(Color.witsInk)
                    .rise(0.1)
                Text("let's measure exactly how cooked.")
                    .font(.witsBody(17))
                    .foregroundStyle(Color.witsMuted)
                    .rise(0.19)
            }
            Spacer()
            VStack(spacing: 12) {
                Cta(title: "run the diagnostic", action: onNext)
                    .rise(0.28)
                Text("takes 3 minutes. less than one reel spiral.")
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
        (1, "your habits", "a short, honest interrogation"),
        (2, "your actual performance", "three tests. no studying allowed"),
        (3, "your recovery plan", "the comeback, mapped out"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
                .padding(.bottom, 30)
            Text("here's how this goes")
                .font(.witsDisplay(32))
                .foregroundStyle(Color.witsInk)
                .rise()
            Text("we build your attention profile in three parts.")
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
            Cta(title: "start part one", action: onNext)
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
        "doomscrolling",
        "can't finish shows",
        "reading feels impossible",
        "work focus",
        "i zone out mid-conversation",
        "just curious how bad it is",
    ]

    @State private var picked: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressTrack(fraction: 1 / quizTotal)
                .padding(.bottom, 30)
            Text("what are we fixing")
                .font(.witsDisplay(30))
                .foregroundStyle(Color.witsInk)
                .padding(.bottom, 16)
                .rise()
            Text("pick everything that applies. no judgment. some judgment.")
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
            Cta(title: picked.isEmpty ? "pick at least one" : "lock it in", dimmed: picked.isEmpty) {
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
                Text("help us calibrate the roast")
                    .font(.witsDisplay(32))
                    .foregroundStyle(Color.witsInk)
                    .rise(0.08)
                Text("four statements. tell us how hard they hit. honesty makes the diagnosis more accurate, and funnier.")
                    .font(.witsBody(16))
                    .foregroundStyle(Color.witsMuted)
                    .rise(0.16)
            }
            Spacer()
            Cta(title: "i'm ready", action: onNext)
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

    private static let statements = [
        "i open my phone to check one thing and resurface 40 minutes later.",
        "i rewind shows because i wasn't actually listening.",
        "i read the same paragraph three times and retain nothing.",
        "a movie without a second screen feels impossible.",
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
            ProgressTrack(fraction: Double(2 + index) / quizTotal)
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
    private let target = 144

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
                Text("times a day the average person checks their phone.")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                    .rise(0.12)
                Text("based on your answers so far, you're not average.")
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

// MARK: - 7. About you: age

struct AgeScreen: View {
    var onAnswer: (Int) -> Void

    private static let ages: [(label: String, mid: Int)] = [
        ("under 18", 16),
        ("18–24", 21),
        ("25–34", 29),
        ("35 and up", 42),
    ]

    @State private var picked: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressTrack(fraction: 6 / quizTotal)
                .padding(.bottom, 30)
            Text("about you")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.witsFaint)
                .padding(.bottom, 10)
                .rise()
            Text("how old are you actually")
                .font(.witsDisplay(30))
                .foregroundStyle(Color.witsInk)
                .padding(.bottom, 16)
                .rise(0.06)
            Text("we need a baseline to measure the damage against.")
                .font(.witsBody(16))
                .foregroundStyle(Color.witsMuted)
                .padding(.bottom, 24)
                .rise(0.1)
            VStack(spacing: 10) {
                ForEach(Array(Self.ages.enumerated()), id: \.offset) { i, age in
                    AnswerRow(label: age.label, picked: picked == i) {
                        guard picked == nil else { return }
                        picked = i
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onAnswer(age.mid)
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

// MARK: - 8. About you: screen time

struct ScreenTimeScreen: View {
    var onAnswer: (Int) -> Void

    private static let options: [(label: String, score: Int)] = [
        ("under 3 hours", 0),
        ("3–5 hours", 1),
        ("5–8 hours", 2),
        ("the weekly report scares me, so i turned it off", 3),
    ]

    @State private var picked: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressTrack(fraction: 7 / quizTotal)
                .padding(.bottom, 30)
            Text("about you")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.witsFaint)
                .padding(.bottom, 10)
                .rise()
            Text("honest daily screen time")
                .font(.witsDisplay(30))
                .foregroundStyle(Color.witsInk)
                .padding(.bottom, 16)
                .rise(0.06)
            Text("we said honest.")
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
