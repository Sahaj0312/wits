//
//  OnboardingResults.swift
//  wits
//
//  Part three of the flow: calculating, result, breakdown, streak,
//  reminder, coaching style, plan build, 30-day projection, paywall.
//

import SwiftUI

// MARK: - Calculating

struct CalcScreen: View {
    var onNext: () -> Void

    private static let roasts = [
        "analyzing your damage",
        "cross-referencing your screen time confession",
        "comparing you to a goldfish",
        "the goldfish won",
        "factoring in the dots you lost track of",
        "compiling the diagnosis",
    ]

    @State private var pct = 0
    @State private var lineIndex = 0

    var body: some View {
        VStack(spacing: 26) {
            ZStack {
                Circle()
                    .stroke(Color.witsLine, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: Double(pct) / 100)
                    .stroke(Color.witsAccent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.12), value: pct)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(pct)")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                    Text("%")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.witsFaint)
                }
                .monospacedDigit()
            }
            .frame(width: 150, height: 150)
            Text(Self.roasts[lineIndex])
                .font(.witsBody(16, weight: .semibold))
                .foregroundStyle(Color.witsMuted)
                .multilineTextAlignment(.center)
                .frame(minHeight: 24)
                .id(lineIndex)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.22), value: lineIndex)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, WitsMetrics.screenPadding)
        .task {
            let total = 5.2
            let start = Date()
            var nextLine = 0.85
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                let elapsed = Date().timeIntervalSince(start)
                let t = min(1, elapsed / total)
                let eased = t < 0.7 ? t * 1.1 : 0.77 + (t - 0.7) * 0.77
                pct = min(100, Int((eased * 100).rounded()))
                if elapsed >= nextLine {
                    lineIndex = min(lineIndex + 1, Self.roasts.count - 1)
                    nextLine += 0.85
                }
                if t >= 1 {
                    try? await Task.sleep(for: .milliseconds(450))
                    onNext()
                    return
                }
            }
        }
    }
}

// MARK: - Result

struct ResultScreen: View {
    var result: AttentionResult
    var onNext: () -> Void

    @State private var progress = 0.0

    private var shownAge: Int { Int((Double(result.age) * progress).rounded()) }
    private var gaugeFraction: Double { min(1, Double(result.age - 16) / 78) * progress }

    var body: some View {
        VStack(spacing: 0) {
            Text("YOUR RESULT")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .kerning(1.2)
                .foregroundStyle(Color.witsFaint)
                .padding(.bottom, 8)
            ZStack {
                Circle()
                    .stroke(Color.witsLine, lineWidth: 14)
                Circle()
                    .trim(from: 0, to: gaugeFraction)
                    .stroke(Color.witsWarm, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Text("\(shownAge)")
                        .font(.system(size: 60, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsWarm)
                        .monospacedDigit()
                    Text("attention age")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.witsMuted)
                }
            }
            .frame(width: 172, height: 172)
            .padding(.bottom, 20)
            VStack(spacing: 12) {
                HStack {
                    Text("outwitted by")
                        .font(.witsBody(14))
                        .foregroundStyle(Color.witsMuted)
                    Spacer()
                    Text("\(result.percentile)% of users")
                        .font(.system(size: 14.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsWarm)
                }
                HStack {
                    Text("gap vs your real age")
                        .font(.witsBody(14))
                        .foregroundStyle(Color.witsMuted)
                    Spacer()
                    Text(result.gap > 0 ? "+\(result.gap) years" : "you're fine. suspicious.")
                        .font(.system(size: 14.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                }
                Rectangle()
                    .fill(Color.witsLine)
                    .frame(height: 1)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color.witsAccent)
                        .frame(width: 20, height: 20)
                        .background(Color.witsAccent.opacity(0.16), in: Circle())
                    Text("bright spot: \(result.best.skill). you beat \(result.best.pct)% of the curve on \(result.best.name).")
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.witsMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
            .cardSurface()
            .rise(0.5)
            Spacer()
            Cta(title: "see the breakdown", action: onNext)
                .rise(0.9)
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

// MARK: - Breakdown

struct BreakdownScreen: View {
    var result: AttentionResult
    var onNext: () -> Void

    @State private var barsShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
                .padding(.bottom, 30)
            Text("the breakdown")
                .font(.witsDisplay(32))
                .foregroundStyle(Color.witsInk)
                .rise()
            Text("where you beat the curve, and where the curve beat you.")
                .font(.witsBody(16))
                .foregroundStyle(Color.witsMuted)
                .padding(.top, 12)
                .padding(.bottom, 26)
                .rise(0.08)
            VStack(spacing: 10) {
                ForEach(Array(result.tests.enumerated()), id: \.element.name) { i, test in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(test.name)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.witsInk)
                            Spacer()
                            Text("\(test.pct)%")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.witsAccent)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.witsTint)
                                Capsule()
                                    .fill(Color.witsAccent)
                                    .frame(width: barsShown ? geo.size.width * Double(test.pct) / 100 : 0)
                                    .animation(
                                        .timingCurve(0.2, 0.8, 0.3, 1, duration: 0.7).delay(0.3 + Double(i) * 0.1),
                                        value: barsShown
                                    )
                            }
                        }
                        .frame(height: 8)
                        Text("\(test.skill) — better than \(test.pct)% of users")
                            .font(.witsBody(12.5))
                            .foregroundStyle(Color.witsMuted)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
                    .cardSurface()
                    .rise(0.16 + Double(i) * 0.1)
                }
            }
            Spacer()
            Cta(title: "fix it", action: onNext)
                .rise(0.56)
                .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
        .onAppear { barsShown = true }
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
                Text("congrats. you just did the longest focused stretch of your day.")
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
                Text("one test a day keeps the streak alive.")
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
    var onNext: () -> Void

    private static let times: [(label: String, time: String, sub: String)] = [
        ("morning", "8:00", "before the scroll starts"),
        ("lunch", "12:30", "a break with a purpose"),
        ("night", "21:00", "instead of episode four"),
    ]

    @State private var picked = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
                .padding(.bottom, 30)
            Text("when should we check on you")
                .font(.witsDisplay(32))
                .foregroundStyle(Color.witsInk)
                .rise()
            Text("one reminder a day. that's the whole notification strategy.")
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
                            Text(option.time)
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
                Cta(title: "set the reminder", action: onNext)
                    .rise(0.42)
                QuietButton(title: "skip for now", action: onNext)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
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
    var onNext: () -> Void

    private static let styles: [(label: String, sub: String)] = [
        ("gentle encouragement", "soft praise. we'll be nice about it."),
        ("tough love", "we'll say what your friends won't."),
        ("full roast", "you've seen the app. you know what this means."),
    ]

    @State private var picked: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
                .padding(.bottom, 30)
            Text("how should we talk to you")
                .font(.witsDisplay(32))
                .foregroundStyle(Color.witsInk)
                .rise()
            Text("this only changes the tone. the math stays brutal.")
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
                            onNext()
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
            Text("building your 30-day recovery arc")
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

    private struct Row {
        let name: String
        let now: Int
        let soon: Int
        var delta: Int { soon - now }
    }

    private var rows: [Row] {
        result.tests.map { test in
            Row(name: test.skill, now: test.pct,
                soon: min(99, test.pct + 18 + Int((Double(100 - test.pct) * 0.2).rounded())))
        }
    }

    private var futureAge: Int {
        max(18, result.age - max(6, Int((Double(result.gap) * 0.6).rounded())))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
                .padding(.bottom, 30)
            Text("your 30-day arc")
                .font(.witsDisplay(32))
                .foregroundStyle(Color.witsInk)
                .rise()
            Text("5 minutes a day. attention age \(Text("\(result.age)").foregroundStyle(Color.witsWarm).bold()) → \(Text("\(futureAge)").foregroundStyle(Color.witsAccent).bold()) by day 30.")
                .font(.witsBody(16))
                .foregroundStyle(Color.witsMuted)
                .padding(.top, 12)
                .padding(.bottom, 26)
                .rise(0.08)
            VStack(spacing: 0) {
                HStack {
                    Text("SKILL").frame(maxWidth: .infinity, alignment: .leading)
                    Text("TODAY").frame(width: 60, alignment: .leading)
                    Text("DAY 30").frame(width: 90, alignment: .leading)
                }
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .kerning(0.8)
                .foregroundStyle(Color.witsFaint)
                .padding(.vertical, 11)
                .overlay(Rectangle().fill(Color.witsLine).frame(height: 1), alignment: .bottom)
                ForEach(Array(rows.enumerated()), id: \.element.name) { i, row in
                    HStack {
                        Text(row.name)
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.witsInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(row.now)%")
                            .font(.witsBody(14, weight: .semibold))
                            .foregroundStyle(Color.witsMuted)
                            .frame(width: 60, alignment: .leading)
                        HStack(spacing: 4) {
                            Text("\(row.soon)%")
                                .font(.system(size: 14.5, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.witsAccent)
                            if row.delta > 0 {
                                Text("+\(row.delta)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.witsAccent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.witsAccent.opacity(0.14), in: Capsule())
                            }
                        }
                        .frame(width: 90, alignment: .leading)
                    }
                    .padding(.vertical, 11)
                    .overlay(
                        i > 0 ? Rectangle().fill(Color.witsLine).frame(height: 1) : nil,
                        alignment: .top
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .cardSurface()
            .padding(.bottom, 14)
            .rise(0.18)
            Text("projection based on members who trained 5 days a week. results vary. effort doesn't.")
                .font(.witsBody(12.5))
                .foregroundStyle(Color.witsFaint)
                .rise(0.3)
            Spacer()
            Cta(title: "start the arc", action: onNext)
                .rise(0.38)
                .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }
}

// MARK: - Paywall

struct PaywallScreen: View {
    var onClose: () -> Void

    private enum Plan {
        case weekly, annual
    }

    private let timeline: [(day: String, text: String)] = [
        ("today", "full access. every game, every read."),
        ("day 2", "we remind you the trial is ending. once."),
        ("day 3", "trial ends. $4.99/week. cancel before, no hard feelings."),
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
            Text("fund the recovery")
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
                    price: "$39.99/year. for the committed."
                ) { plan = .annual }
                    .rise(0.46)
            }
            Text("★ 4.8 · \u{201C}this app called me out and i paid it\u{201D}")
                .font(.witsBody(13))
                .foregroundStyle(Color.witsMuted)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
            Spacer()
            VStack(spacing: 12) {
                Cta(title: plan == .weekly ? "start free trial" : "go annual") {}
                Text("cancel anytime. we'll still know.")
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
