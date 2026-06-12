//
//  OnboardingFlow.swift
//  wits
//
//  Flow order, collected data, and the attention-age scoring.
//

import SwiftUI

enum OnboardingStep: Hashable {
    case hook, welcome, goals, calibrate
    case likert(Int)
    case stat, age, screenTime
    case gauntlet
    case flanker, explainFlanker
    case tracker, explainTracker
    case span, explainSpan
    case calc, result, breakdown
    case streak, reminder, coach, planBuild, projection, paywall

    static let flow: [OnboardingStep] = [
        .hook, .welcome, .goals, .calibrate,
        .likert(0), .likert(1), .stat, .likert(2), .likert(3),
        .age, .screenTime,
        .gauntlet,
        .flanker, .explainFlanker,
        .tracker, .explainTracker,
        .span, .explainSpan,
        .calc, .result, .breakdown,
        .streak, .reminder, .coach, .planBuild, .projection, .paywall,
    ]
}

struct FlankerStats {
    var right = 0
    var wrong = 0
    var bestStreak = 0
    var score = 0
}

struct TrackStats {
    var correctPicks = 0
    var totalTargets = 0
    var perfectRounds = 0
    var rounds = 0
}

struct SpanStats {
    var correctTaps = 0
    var totalTaps = 0
    var perfectTrials = 0
    var trials = 0
    var maxSpan = 0
    var score = 0
}

struct OnboardingData {
    var goals: [String] = []
    var likert = 0          // 0–12 across four statements
    var ageMid = 21
    var screenTime = 1      // 0–3
    var flanker: FlankerStats?
    var tracker: TrackStats?
    var span: SpanStats?
}

struct TestScore {
    let name: String
    let skill: String
    let pct: Int
}

struct AttentionResult {
    let age: Int
    let gap: Int
    let percentile: Int
    let tests: [TestScore]
    let best: TestScore
}

func computeResult(_ d: OnboardingData) -> AttentionResult {
    let flankerTotal = (d.flanker?.right ?? 0) + (d.flanker?.wrong ?? 0)
    let flankerAcc = flankerTotal > 0 ? Double(d.flanker!.right) / Double(flankerTotal) : 0.5
    let trackAcc = d.tracker.map { Double($0.correctPicks) / Double(max(1, $0.totalTargets)) } ?? 0.5
    let spanAcc = d.span.map { Double($0.correctTaps) / Double(max(1, $0.totalTaps)) } ?? 0.5

    var age = Double(d.ageMid)
        + Double(d.likert) * 2.2
        + Double(d.screenTime) * 3
        + (1 - flankerAcc) * 12
        + (1 - trackAcc) * 14
        + (1 - spanAcc) * 12
        - 6
    age = min(94, max((Double(d.ageMid) * 0.8).rounded(), age)).rounded()

    let gap = Int(age) - d.ageMid
    let percentile = min(97, max(6, Int((40 + Double(gap) * 1.6).rounded())))

    let clamp = { (p: Int) in min(99, max(4, p)) }
    let tests = [
        TestScore(name: "arrow storm", skill: "focus",
                  pct: clamp(Int((flankerAcc * 100).rounded()))),
        TestScore(name: "crowd control", skill: "multitasking",
                  pct: clamp(Int((trackAcc * 100).rounded()))),
        TestScore(name: "echo grid", skill: "memory",
                  pct: clamp(Int((spanAcc * 100).rounded()))),
    ]
    let best = tests.max { $0.pct < $1.pct } ?? tests[0]
    return AttentionResult(age: Int(age), gap: gap, percentile: percentile, tests: tests, best: best)
}

// MARK: - Root flow view

struct OnboardingView: View {
    var onFinished: () -> Void

    @State private var stepIndex = 0
    @State private var data = OnboardingData()

    private var step: OnboardingStep { OnboardingStep.flow[stepIndex] }

    private func next() {
        stepIndex = min(stepIndex + 1, OnboardingStep.flow.count - 1)
    }

    private var flankerPct: Int {
        guard let s = data.flanker, s.right + s.wrong > 0 else { return 0 }
        return min(99, max(4, Int((Double(s.right) / Double(s.right + s.wrong) * 100).rounded())))
    }

    private var trackerPct: Int {
        guard let s = data.tracker, s.totalTargets > 0 else { return 0 }
        return min(99, max(4, Int((Double(s.correctPicks) / Double(s.totalTargets) * 100).rounded())))
    }

    private var spanPct: Int {
        guard let s = data.span, s.totalTaps > 0 else { return 0 }
        return min(99, max(4, Int((Double(s.correctTaps) / Double(s.totalTaps) * 100).rounded())))
    }

    var body: some View {
        ZStack {
            Color.witsBg.ignoresSafeArea()
            screen
                .id(stepIndex)
                .transition(.asymmetric(
                    insertion: .offset(y: 12).combined(with: .opacity),
                    removal: .opacity
                ))
        }
        .animation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.28), value: stepIndex)
    }

    @ViewBuilder
    private var screen: some View {
        switch step {
        case .hook:
            HookScreen(onNext: next)
        case .welcome:
            WelcomeScreen(onNext: next)
        case .goals:
            GoalsScreen { picked in
                data.goals = picked
                next()
            }
        case .calibrate:
            CalibrateScreen(onNext: next)
        case .likert(let index):
            LikertScreen(index: index) { score in
                data.likert += score
                next()
            }
        case .stat:
            StatScreen(onNext: next)
        case .age:
            AgeScreen { mid in
                data.ageMid = mid
                next()
            }
        case .screenTime:
            ScreenTimeScreen { score in
                data.screenTime = score
                next()
            }
        case .gauntlet:
            GauntletScreen(onNext: next)
        case .flanker:
            FlankerScreen { stats in
                data.flanker = stats
                next()
            }
        case .explainFlanker:
            ExplainScreen(
                test: "arrow storm",
                score: "\(flankerPct)%",
                blurb: "that was the flanker task — the lab standard for interference control since 1974. acting on the signal while the noise screams is the exact muscle a feed full of thumbnails grinds down.",
                onNext: next
            )
        case .tracker:
            TrackerScreen { stats in
                data.tracker = stats
                next()
            }
        case .explainTracker:
            ExplainScreen(
                test: "crowd control",
                score: "\(trackerPct)%",
                blurb: "that was multiple object tracking — how labs have measured divided attention since the 80s. your tabs, your chats, your second screen: same juggling act, fewer dots.",
                onNext: next
            )
        case .span:
            SpanScreen { stats in
                data.span = stats
                next()
            }
        case .explainSpan:
            ExplainScreen(
                test: "echo grid",
                score: "\(spanPct)%",
                blurb: "that was a backward spatial span — the reverse corsi test neuropsychologists use for working memory. holding a sequence and flipping it is what deep work feels like.",
                last: true,
                onNext: next
            )
        case .calc:
            CalcScreen(onNext: next)
        case .result:
            ResultScreen(result: computeResult(data), onNext: next)
        case .breakdown:
            BreakdownScreen(result: computeResult(data), onNext: next)
        case .streak:
            StreakScreen(onNext: next)
        case .reminder:
            ReminderScreen(onNext: next)
        case .coach:
            CoachScreen(onNext: next)
        case .planBuild:
            PlanBuildScreen(onNext: next)
        case .projection:
            ProjectionScreen(result: computeResult(data), onNext: next)
        case .paywall:
            PaywallScreen(onClose: onFinished)
        }
    }
}

#Preview {
    OnboardingView {}
}
