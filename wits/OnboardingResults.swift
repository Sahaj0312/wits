//
//  OnboardingResults.swift
//  wits
//
//  Part three of the flow: calculating, breakdown, result, streak,
//  reminder, coaching style, plan build, 30-day projection, paywall.
//

import SwiftUI

// MARK: - Calculating

struct CalcScreen: View {
    var onNext: () -> Void

    private struct Step {
        let label: String
        var doneLabel: String?
        let at: Double          // progress fraction when this step completes
    }

    private static let steps: [Step] = [
        Step(label: "scoring your focus", at: 0.16),
        Step(label: "factoring in your daily habits", at: 0.34),
        Step(label: "measuring your attention", at: 0.52),
        Step(label: "reviewing your working memory", at: 0.72),
        Step(label: "preparing your results", at: 0.94),
    ]

    @State private var t = 0.0

    private var pct: Int { min(100, Int((t * 100).rounded())) }

    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(Color.witsLine, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: t)
                    .stroke(Color.witsAccent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 8) {
                    LogoBlob(size: 46, breathe: true)
                    Text("\(pct)%")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                        .monospacedDigit()
                }
            }
            .frame(width: 156, height: 156)
            .rise()

            VStack(spacing: 0) {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { i, step in
                    let done = t >= step.at
                    let active = !done && (i == 0 || t >= Self.steps[i - 1].at)
                    HStack(spacing: 12) {
                        ZStack {
                            if done {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(Color.witsAccent, in: Circle())
                                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                            } else if active {
                                MiniSpinner()
                            } else {
                                Circle()
                                    .strokeBorder(Color.witsLine, lineWidth: 2)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        .frame(width: 20, height: 20)
                        Text(done ? (step.doneLabel ?? step.label) : step.label)
                            .font(.witsBody(14, weight: .semibold))
                            .foregroundStyle(done ? Color.witsInk : active ? Color.witsMuted : Color.witsFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(done)
                            .transition(.opacity)
                    }
                    .padding(.vertical, 10)
                    .animation(.easeOut(duration: 0.22), value: done)
                    .animation(.easeOut(duration: 0.22), value: active)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .cardSurface()
            .rise(0.12)

            Text("this will only take a few seconds.")
                .font(.witsBody(12.5))
                .foregroundStyle(Color.witsFaint)
                .multilineTextAlignment(.center)
                .rise(0.22)
            Spacer()
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .task {
            let total = 5.6
            let start = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(40))
                let raw = min(1, Date().timeIntervalSince(start) / total)
                t = raw * raw * (3 - 2 * raw)   // smoothstep: lingers at the ends
                if raw >= 1 {
                    try? await Task.sleep(for: .milliseconds(550))
                    onNext()
                    return
                }
            }
        }
    }
}

private struct MiniSpinner: View {
    @State private var on = false
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.72)
            .stroke(Color.witsAccent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 15, height: 15)
            .rotationEffect(.degrees(on ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: on)
            .onAppear { on = true }
    }
}

// MARK: - Result

struct ResultScreen: View {
    var result: AttentionResult
    var onNext: () -> Void

    @State private var progress = 0.0

    private var baselineScore: Int {
        guard !result.tests.isEmpty else { return 50 }
        let total = result.tests.reduce(0) { $0 + $1.pct }
        return min(99, max(4, Int((Double(total) / Double(result.tests.count)).rounded())))
    }
    private var shownScore: Int { Int((Double(baselineScore) * progress).rounded()) }
    private var gaugeFraction: Double { Double(baselineScore) / 100 * progress }
    private var weakest: TestScore {
        result.tests.min { $0.pct < $1.pct } ?? result.best
    }
    private var statusTitle: String {
        if result.gap > 8 {
            "we found the pressure points"
        } else if baselineScore >= 78 {
            "you've got a strong starting point"
        } else {
            "we found your starting point"
        }
    }
    private var statusCopy: String {
        if result.gap > 8 {
            "your test showed where attention held steady and where it slipped under pressure. wits will start there."
        } else if baselineScore >= 78 {
            "your test showed a solid baseline. wits will raise the challenge as your scores move."
        } else {
            "this is not a grade. it's the starting map wits uses to tune your first week."
        }
    }
    private var scoreColor: Color {
        baselineScore < 55 ? .witsWarm : .witsAccent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("FIT TEST COMPLETE")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .kerning(1.1)
                .foregroundStyle(Color.witsFaint)
                .rise()
            Text(statusTitle)
                .font(.witsDisplay(34))
                .foregroundStyle(Color.witsInk)
                .padding(.top, 10)
                .fixedSize(horizontal: false, vertical: true)
                .rise(0.08)
            Text(statusCopy)
                .font(.witsBody(16))
                .foregroundStyle(Color.witsMuted)
                .padding(.top, 10)
                .fixedSize(horizontal: false, vertical: true)
                .rise(0.16)

            VStack(spacing: 12) {
                HStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .stroke(Color.witsLine, lineWidth: 12)
                        Circle()
                            .trim(from: 0, to: gaugeFraction)
                            .stroke(scoreColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 1) {
                                Text("\(shownScore)")
                                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                                    .foregroundStyle(scoreColor)
                                    .monospacedDigit()
                                Text("/100")
                                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color.witsFaint)
                            }
                            Text("starting score")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.witsMuted)
                        }
                    }
                    .frame(width: 142, height: 142)

                    VStack(alignment: .leading, spacing: 10) {
                        ResultPill(text: "adaptive baseline", color: scoreColor)
                        Text("we'll use it to set your first drills.")
                            .font(.witsBody(17, weight: .heavy))
                            .foregroundStyle(Color.witsInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("your first sessions will adjust from here.")
                            .font(.witsBody(13.5))
                            .foregroundStyle(Color.witsMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
            .cardSurface()
            .padding(.top, 20)
            .rise(0.28)

            VStack(spacing: 10) {
                ResultSignalRow(
                    icon: "bolt.fill",
                    title: "strongest signal",
                    value: "\(result.best.skill) · \(result.best.pct)%",
                    detail: "\(result.best.name) came through as your clearest strength today.",
                    tint: .witsAccent
                )
                ResultSignalRow(
                    icon: "target",
                    title: "training target",
                    value: "\(weakest.skill) · \(weakest.pct)%",
                    detail: "we'll put extra early work into the area that showed the most friction.",
                    tint: .witsWarm
                )
            }
            .padding(.top, 12)
            .rise(0.42)

            Spacer()
            Cta(title: "continue", action: onNext)
                .rise(0.62)
                .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
        .task {
            let start = Date()
            let duration = 1.4
            while !Task.isCancelled {
                let t = min(1, Date().timeIntervalSince(start) / duration)
                progress = 1 - pow(1 - t, 3)
                if t >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }
}

private struct ResultPill: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
    }
}

private struct ResultSignalRow: View {
    var icon: String
    var title: String
    var value: String
    var detail: String
    var tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsFaint)
                        .textCase(.uppercase)
                    Spacer(minLength: 8)
                    Text(value)
                        .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                Text(detail)
                    .font(.witsBody(13.5))
                    .foregroundStyle(Color.witsMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.witsTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Breakdown

/// Normal-distribution silhouette, filled from the left edge.
private struct BellShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mu = 0.5, sigma = 0.17
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        let samples = 60
        for i in 0...samples {
            let u = Double(i) / Double(samples)
            let g = exp(-pow((u - mu) / sigma, 2) / 2)
            p.addLine(to: CGPoint(x: rect.minX + u * rect.width,
                                  y: rect.maxY - g * rect.height * 0.94))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct BellCurveView: View {
    var fraction: Double    // 0...1 — how much of the population you beat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                BellShape()
                    .fill(Color.witsInk.opacity(0.10))
                BellShape()
                    .fill(Color.witsAccent)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: geo.size.width * fraction)
                            .frame(maxHeight: .infinity)
                    }
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.witsLine)
                    .frame(height: 1.5)
            }
        }
    }
}

struct BreakdownScreen: View {
    var result: AttentionResult
    var onNext: () -> Void

    @State private var curvesShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
                .padding(.bottom, 30)
            Text("your results")
                .font(.witsDisplay(32))
                .foregroundStyle(Color.witsInk)
                .rise()
            Text("here's your starting baseline for each fit-test game.")
                .font(.witsBody(16))
                .foregroundStyle(Color.witsMuted)
                .padding(.top, 12)
                .padding(.bottom, 26)
                .rise(0.08)
            VStack(spacing: 10) {
                ForEach(Array(result.tests.enumerated()), id: \.element.name) { i, test in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(test.name)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.witsInk)
                            Spacer()
                            Text(test.skill)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.witsFaint)
                        }
                        HStack(spacing: 18) {
                            BellCurveView(fraction: curvesShown ? Double(test.pct) / 100 : 0)
                                .frame(height: 62)
                                .animation(
                                    .timingCurve(0.2, 0.8, 0.3, 1, duration: 0.9).delay(0.3 + Double(i) * 0.12),
                                    value: curvesShown
                                )
                            VStack(alignment: .leading, spacing: 1) {
                                Text("fit score")
                                    .font(.witsBody(12.5))
                                    .foregroundStyle(Color.witsMuted)
                                Text("\(test.pct)%")
                                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color.witsAccent)
                                    .monospacedDigit()
                                Text("baseline")
                                    .font(.witsBody(12.5))
                                    .foregroundStyle(Color.witsMuted)
                            }
                            .frame(width: 92, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
                    .cardSurface()
                    .rise(0.16 + Double(i) * 0.1)
                }
            }
            Spacer()
            Cta(title: "see my baseline", action: onNext)
                .rise(0.56)
                .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
        .onAppear { curvesShown = true }
    }
}

// MARK: - Streak

struct StreakScreen: View {
    var onNext: () -> Void

    private let days = ["s", "m", "t", "w", "t", "f", "s"]
    private var today: Int { Calendar.current.component(.weekday, from: .now) - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Text("day 1")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsAccent)
                    .rise()
                Text("you've started a daily streak. nice work!")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                    .rise(0.1)
                HStack(spacing: 8) {
                    ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                        VStack(spacing: 7) {
                            Circle()
                                .fill(i == today ? Color.witsAccent : Color.witsTint)
                                .frame(width: 13, height: 13)
                                .background(
                                    Circle()
                                        .fill(Color.witsAccent.opacity(i == today ? 0.18 : 0))
                                        .frame(width: 21, height: 21)
                                )
                            Text(day)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(i == today ? Color.witsInk : Color.witsFaint)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                        .padding(.bottom, 10)
                        .cardSurface(radius: 12)
                    }
                }
                .rise(0.2)
                Text("train a little every day to keep it going.")
                    .font(.witsBody(15))
                    .foregroundStyle(Color.witsMuted)
                    .rise(0.3)
            }
            Spacer()
            Cta(title: "keep it going", action: onNext)
                .rise(0.4)
                .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }
}

// MARK: - Reminder

struct ReminderScreen: View {
    var onEnable: (Int, Int) -> Void
    var onSkip: () -> Void

    private static let times: [(label: String, hour: Int, minute: Int, sub: String)] = [
        ("morning", 8, 0, "start your day sharp"),
        ("lunch", 12, 30, "a midday brain break"),
        ("night", 21, 0, "wind down with a quick session"),
    ]

    @State private var picked = 0
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
                .padding(.bottom, 30)
            Text("set up a daily reminder")
                .font(.witsDisplay(32))
                .foregroundStyle(Color.witsInk)
                .rise()
            Text("a gentle nudge to help you build a healthy training habit.")
                .font(.witsBody(16))
                .foregroundStyle(Color.witsMuted)
                .padding(.top, 12)
                .padding(.bottom, 26)
                .rise(0.08)
            VStack(spacing: 10) {
                ForEach(Array(Self.times.enumerated()), id: \.offset) { i, option in
                    Button {
                        picked = i
                    } label: {
                        HStack(spacing: 14) {
                            Text(timeLabel(hour: option.hour, minute: option.minute))
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.witsInk)
                                .monospacedDigit()
                                .frame(minWidth: 54, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label)
                                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.witsInk)
                                Text(option.sub)
                                    .font(.witsBody(12.5))
                                    .foregroundStyle(Color.witsMuted)
                            }
                            Spacer()
                            RadioDot(on: picked == i)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                                .fill(Color.witsCard)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                                .strokeBorder(picked == i ? Color.witsAccent : .clear, lineWidth: 1.5)
                        )
                        .shadow(color: .witsShadow, radius: 10, y: 6)
                    }
                    .buttonStyle(.plain)
                    .animation(.easeOut(duration: 0.12), value: picked)
                    .rise(0.16 + Double(i) * 0.08)
                }
            }
            Spacer()
            VStack(spacing: 12) {
                Cta(title: working ? "..." : "set the reminder") {
                    guard !working else { return }
                    working = true
                    Task {
                        let granted = await WitsNotifications.requestAuthorization()
                        let choice = Self.times[picked]
                        working = false
                        if granted {
                            onEnable(choice.hour, choice.minute)
                        } else {
                            onSkip()
                        }
                    }
                }
                    .rise(0.42)
                QuietButton(title: "skip for now", action: onSkip)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }

    private func timeLabel(hour: Int, minute: Int) -> String {
        String(format: "%d:%02d", hour, minute)
    }
}

private struct RadioDot: View {
    var on: Bool
    var body: some View {
        Circle()
            .strokeBorder(on ? Color.witsAccent : Color.witsLine, lineWidth: on ? 6 : 2)
            .frame(width: 20, height: 20)
    }
}

// MARK: - Coaching style

struct CoachScreen: View {
    var onAnswer: (String) -> Void

    private static let styles: [(label: String, sub: String)] = [
        ("high fives", "celebrate my progress and my wins."),
        ("tough love", "push me to stay on track and keep improving."),
    ]

    @State private var picked: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
                .padding(.bottom, 30)
            Text("what keeps you motivated?")
                .font(.witsDisplay(32))
                .foregroundStyle(Color.witsInk)
                .rise()
            Text("this just sets the tone of your encouragement.")
                .font(.witsBody(16))
                .foregroundStyle(Color.witsMuted)
                .padding(.top, 12)
                .padding(.bottom, 26)
                .rise(0.08)
            VStack(spacing: 10) {
                ForEach(Array(Self.styles.enumerated()), id: \.offset) { i, style in
                    AnswerRow(label: style.label, sub: style.sub, picked: picked == i) {
                        guard picked == nil else { return }
                        picked = i
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                            onAnswer(style.label)
                        }
                    }
                    .rise(0.16 + Double(i) * 0.08)
                }
            }
            Spacer()
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }
}

// MARK: - Plan build spinner

struct PlanBuildScreen: View {
    var onNext: () -> Void

    @State private var spinning = false

    var body: some View {
        VStack(spacing: 24) {
            Circle()
                .trim(from: 0.12, to: 1)
                .stroke(Color.witsLine, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .overlay(
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(Color.witsAccent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                )
                .frame(width: 54, height: 54)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spinning)
            Text("creating your personalized 30-day plan")
                .font(.witsBody(16, weight: .semibold))
                .foregroundStyle(Color.witsMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { spinning = true }
        .task {
            try? await Task.sleep(for: .seconds(2.6))
            if !Task.isCancelled { onNext() }
        }
    }
}

// MARK: - 30-day projection

struct ProjectionScreen: View {
    var result: AttentionResult
    var onNext: () -> Void

    struct Row: Identifiable {
        let name: String
        let now: Int
        let soon: Int
        var id: String { name }
        var delta: Int { soon - now }
    }

    @State private var shown = false

    private var rows: [Row] {
        result.tests.map { test in
            Row(name: test.skill, now: test.pct,
                soon: min(99, test.pct + 18 + Int((Double(100 - test.pct) * 0.2).rounded())))
        }
    }

    private var averageLift: Int {
        guard !rows.isEmpty else { return 0 }
        let total = rows.reduce(0) { $0 + $1.delta }
        return Int((Double(total) / Double(rows.count)).rounded())
    }

    private var focusSkill: String {
        rows.min { $0.now < $1.now }?.name ?? "focus"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
                .padding(.bottom, 24)

            Text("your first 30 days")
                .font(.witsDisplay(34))
                .foregroundStyle(Color.witsInk)
                .rise()

            Text("we'll start with \(focusSkill), then raise the challenge as your scores move.")
                .font(.witsBody(16, weight: .semibold))
                .foregroundStyle(Color.witsMuted)
                .padding(.top, 12)
                .rise(0.08)

            ProjectionHeroCard(
                averageLift: averageLift,
                focusSkill: focusSkill,
                progress: shown ? 1 : 0
            )
            .padding(.top, 20)
            .rise(0.18)

            VStack(spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    ProjectionSkillRow(row: row, progress: shown ? 1 : 0)
                        .rise(0.28 + Double(i) * 0.08)
                }
            }
            .padding(.top, 12)

            Text("projection uses your fit-test baseline and training frequency. results vary.")
                .font(.witsBody(12.5))
                .foregroundStyle(Color.witsFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .rise(0.58)

            Spacer()
            Cta(title: "start my plan", action: onNext)
                .rise(0.66)
                .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
        .onAppear {
            withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.95).delay(0.25)) {
                shown = true
            }
        }
    }
}

private struct ProjectionHeroCard: View {
    var averageLift: Int
    var focusSkill: String
    var progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("projected lift")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .kerning(0.8)
                        .foregroundStyle(Color.witsFaint)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("+\(Int((Double(averageLift) * progress).rounded()))")
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.witsAccent)
                            .monospacedDigit()
                        Text("pts")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.witsMuted)
                    }
                    Text("\(focusSkill) gets the first push.")
                        .font(.witsBody(14, weight: .semibold))
                        .foregroundStyle(Color.witsMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 118, alignment: .leading)

                ProjectionCurve(progress: progress)
                    .frame(maxWidth: .infinity)
                    .frame(height: 92)
            }

            HStack(spacing: 8) {
                ProjectionMilestone(title: "today", subtitle: "baseline")
                ProjectionMilestone(title: "week 2", subtitle: "adjust")
                ProjectionMilestone(title: "day 30", subtitle: "harder")
            }
        }
        .padding(16)
        .cardSurface()
    }
}

private struct ProjectionCurve: View {
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let start = CGPoint(x: 4, y: h * 0.78)
            let end = CGPoint(x: w - 4, y: h * 0.26)
            let c1 = CGPoint(x: w * 0.34, y: h * 0.86)
            let c2 = CGPoint(x: w * 0.58, y: h * 0.20)

            ZStack {
                Path { path in
                    path.move(to: start)
                    path.addCurve(to: end, control1: c1, control2: c2)
                }
                .stroke(Color.witsLine, style: StrokeStyle(lineWidth: 8, lineCap: .round))

                Path { path in
                    path.move(to: start)
                    path.addCurve(to: end, control1: c1, control2: c2)
                }
                .trim(from: 0, to: progress)
                .stroke(Color.witsAccent, style: StrokeStyle(lineWidth: 8, lineCap: .round))

                ProjectionNode(point: start, active: true, delay: 0)
                ProjectionNode(point: CGPoint(x: w * 0.52, y: h * 0.48), active: progress > 0.45, delay: 0.1)
                ProjectionNode(point: end, active: progress > 0.9, delay: 0.2)
            }
        }
    }
}

private struct ProjectionNode: View {
    var point: CGPoint
    var active: Bool
    var delay: Double

    var body: some View {
        Circle()
            .fill(active ? Color.witsAccent : Color.witsCard)
            .frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(active ? Color.witsAccent.opacity(0.28) : Color.witsLine, lineWidth: 5))
            .position(point)
            .scaleEffect(active ? 1 : 0.82)
            .animation(.spring(response: 0.42, dampingFraction: 0.72).delay(delay), value: active)
    }
}

private struct ProjectionMilestone: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subtitle)
                .font(.witsBody(11.5, weight: .semibold))
                .foregroundStyle(Color.witsFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

private struct ProjectionSkillRow: View {
    var row: ProjectionScreen.Row
    var progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.name)
                    .font(.system(size: 15.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                Text("\(row.now)%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.witsMuted)
                    .monospacedDigit()
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.witsFaint)
                Text("\(row.soon)%")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsAccent)
                    .monospacedDigit()
            }

            ProjectionBar(now: Double(row.now) / 100, soon: Double(row.soon) / 100, progress: progress)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .background(Color.witsTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ProjectionBar: View {
    var now: Double
    var soon: Double
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let currentX = width * now
            let targetX = width * (now + (soon - now) * progress)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.witsLine)
                    .frame(height: 7)
                Capsule()
                    .fill(Color.witsAccent.opacity(0.28))
                    .frame(width: max(0, currentX), height: 7)
                Capsule()
                    .fill(Color.witsAccent)
                    .frame(width: max(0, targetX), height: 7)
                Circle()
                    .fill(Color.witsCard)
                    .frame(width: 13, height: 13)
                    .overlay(Circle().strokeBorder(Color.witsMuted.opacity(0.55), lineWidth: 2))
                    .position(x: currentX, y: 7)
                Circle()
                    .fill(Color.witsAccent)
                    .frame(width: 15, height: 15)
                    .shadow(color: Color.witsAccent.opacity(0.35), radius: 5)
                    .position(x: targetX, y: 7)
            }
        }
        .frame(height: 12)
    }
}

// MARK: - Paywall

struct PaywallScreen: View {
    var onClose: () -> Void

    private enum Plan {
        case weekly, annual
    }

    private let timeline: [(day: String, text: String)] = [
        ("today", "get full access to every game and workout."),
        ("day 2", "we'll send a reminder before your trial ends."),
        ("day 3", "your trial ends. cancel anytime before then."),
    ]

    @State private var plan = Plan.weekly

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.witsFaint)
                }
                Spacer()
                QuietButton(title: "restore") {}
            }
            .padding(.bottom, 14)
            Text("choose your plan")
                .font(.witsDisplay(30))
                .foregroundStyle(Color.witsInk)
                .padding(.bottom, 20)
                .rise()
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(timeline.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(i == 0 ? Color.witsAccent : Color.witsLine)
                                .frame(width: 11, height: 11)
                                .background(
                                    Circle()
                                        .fill(Color.witsAccent.opacity(i == 0 ? 0.18 : 0))
                                        .frame(width: 19, height: 19)
                                )
                                .padding(.top, 4)
                            if i < timeline.count - 1 {
                                Rectangle()
                                    .fill(Color.witsLine)
                                    .frame(width: 2)
                                    .frame(minHeight: 12)
                                    .padding(.vertical, 5)
                            }
                        }
                        .frame(width: 14)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.day)
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.witsInk)
                            Text(item.text)
                                .font(.witsBody(13))
                                .foregroundStyle(Color.witsMuted)
                        }
                        .padding(.bottom, 13)
                    }
                    .rise(0.1 + Double(i) * 0.09)
                }
            }
            .padding(.bottom, 18)
            VStack(spacing: 10) {
                planCard(
                    selected: plan == .weekly,
                    name: "weekly",
                    badge: "3-day free trial",
                    price: "then $4.99/week"
                ) { plan = .weekly }
                    .rise(0.38)
                planCard(
                    selected: plan == .annual,
                    name: "annual",
                    badge: nil,
                    save: "save 84%",
                    price: "$39.99/year — best value."
                ) { plan = .annual }
                    .rise(0.46)
            }
            Text("★ 4.8 · \u{201C}i feel sharper after just a few weeks\u{201D}")
                .font(.witsBody(13))
                .foregroundStyle(Color.witsMuted)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
            Spacer()
            VStack(spacing: 12) {
                Cta(title: plan == .weekly ? "start free trial" : "go annual") {}
                Text("cancel anytime.")
                    .font(.witsBody(12.5))
                    .foregroundStyle(Color.witsFaint)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }

    private func planCard(selected: Bool, name: String, badge: String?, save: String? = nil, price: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RadioDot(on: selected)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(name)
                            .font(.system(size: 15.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.witsInk)
                        Spacer()
                        if let badge {
                            Text(badge)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.witsAccent)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Color.witsAccent.opacity(0.16), in: Capsule())
                        } else if let save {
                            Text(save)
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.witsMuted)
                        }
                    }
                    Text(price)
                        .font(.witsBody(13))
                        .foregroundStyle(Color.witsMuted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                    .fill(Color.witsCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                    .strokeBorder(selected ? Color.witsAccent : .clear, lineWidth: 1.5)
            )
            .shadow(color: .witsShadow, radius: 10, y: 6)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: selected)
    }
}
