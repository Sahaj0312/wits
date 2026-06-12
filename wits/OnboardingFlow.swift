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
    case colorMatch, explainColorMatch
    case trains, explainTrains
    case matrix, explainMatrix
    case calc, result, breakdown
    case streak, reminder, coach, planBuild, projection, paywall

    static let flow: [OnboardingStep] = [
        .hook, .welcome, .goals, .calibrate,
        .likert(0), .likert(1), .stat, .likert(2), .likert(3),
        .age, .screenTime,
        .gauntlet,
        .colorMatch, .explainColorMatch,
        .trains, .explainTrains,
        .matrix, .explainMatrix,
        .calc, .result, .breakdown,
        .streak, .reminder, .coach, .planBuild, .projection, .paywall,
    ]
}

struct ColorMatchStats {
    var right = 0
    var wrong = 0
    var bestStreak = 0
    var score = 0
}

struct TrainStats {
    var correct = 0
    var total = 0
}

struct MatrixStats {
    var correctTiles = 0
    var totalTiles = 0
    var perfectTrials = 0
    var trials = 0
    var maxTiles = 0
    var score = 0
}

struct OnboardingData {
    var goals: [String] = []
    var likert = 0          // 0–12 across four statements
    var ageMid = 21
    var screenTime = 1      // 0–3
    var colorMatch: ColorMatchStats?
    var trains: TrainStats?
    var matrix: MatrixStats?
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
    let cmTotal = (d.colorMatch?.right ?? 0) + (d.colorMatch?.wrong ?? 0)
    let cmAcc = cmTotal > 0 ? Double(d.colorMatch!.right) / Double(cmTotal) : 0.5
    let trainAcc = d.trains.map { Double($0.correct) / Double(max(1, $0.total)) } ?? 0.5
    let mmAcc = d.matrix.map { Double($0.correctTiles) / Double(max(1, $0.totalTiles)) } ?? 0.5

    var age = Double(d.ageMid)
        + Double(d.likert) * 2.2
        + Double(d.screenTime) * 3
        + (1 - cmAcc) * 12
        + (1 - trainAcc) * 14
        + (1 - mmAcc) * 12
        - 6
    age = min(94, max((Double(d.ageMid) * 0.8).rounded(), age)).rounded()

    let gap = Int(age) - d.ageMid
    let percentile = min(97, max(6, Int((40 + Double(gap) * 1.6).rounded())))

    let clamp = { (p: Int) in min(99, max(4, p)) }
    let tests = [
        TestScore(name: "color match", skill: "focus",
                  pct: clamp(Int((cmAcc * 100).rounded()))),
        TestScore(name: "train of thought", skill: "multitasking",
                  pct: clamp(Int((trainAcc * 100).rounded()))),
        TestScore(name: "memory matrix", skill: "memory",
                  pct: clamp(Int((mmAcc * 100).rounded()))),
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

    private var colorMatchPct: Int {
        guard let s = data.colorMatch, s.right + s.wrong > 0 else { return 0 }
        return min(99, max(4, Int((Double(s.right) / Double(s.right + s.wrong) * 100).rounded())))
    }

    private var trainPct: Int {
        guard let s = data.trains, s.total > 0 else { return 0 }
        return min(99, max(4, Int((Double(s.correct) / Double(s.total) * 100).rounded())))
    }

    private var matrixPct: Int {
        guard let s = data.matrix, s.totalTiles > 0 else { return 0 }
        return min(99, max(4, Int((Double(s.correctTiles) / Double(s.totalTiles) * 100).rounded())))
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
        case .colorMatch:
            ColorMatchScreen { stats in
                data.colorMatch = stats
                next()
            }
        case .explainColorMatch:
            ExplainScreen(
                test: "color match",
                score: "\(colorMatchPct)%",
                blurb: "that measured response inhibition — overriding the answer your brain shouts first. it's the same muscle that decides whether you open the app or finish the sentence.",
                onNext: next
            )
        case .trains:
            TrainGameScreen { stats in
                data.trains = stats
                next()
            }
        case .explainTrains:
            ExplainScreen(
                test: "train of thought",
                score: "\(trainPct)%",
                blurb: "that measured divided attention — tracking several moving things at once without dropping one. it's the skill your seventeen open tabs have been quietly taxing.",
                onNext: next
            )
        case .matrix:
            MemoryMatrixScreen { stats in
                data.matrix = stats
                next()
            }
        case .explainMatrix:
            ExplainScreen(
                test: "memory matrix",
                score: "\(matrixPct)%",
                blurb: "that measured working memory — holding a picture in your head after it's gone. it's what melts first when everything is a 15-second clip.",
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
