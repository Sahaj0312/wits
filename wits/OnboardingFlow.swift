//
//  OnboardingFlow.swift
//  wits
//
//  Flow order, collected data, scoring, and Supabase persistence.
//  Step order mirrors Lumosity's onboarding, in wits' voice, keeping the
//  three wits games (arrow storm / crowd control / echo grid).
//

import SwiftUI

/// Number of progress-bearing question screens (goals + 6 likert + gender +
/// education + attribution + screen time) — used to fill the progress bar.
let onboardingQuizTotal = 11.0

enum OnboardingStep: Hashable {
    // 1 — account creation
    case hook, auth, birthdate
    // 2 — goals & personalization
    case welcome, goals, calibrate
    // 3 — self-assessment
    case likert(Int)
    case stat
    // 4 — demographics
    case aboutYou, gender, education, attribution, screenTime
    // 5 — fit test
    case meetYou, gauntlet
    case flanker, explainFlanker
    case tracker, explainTracker
    case span, explainSpan
    // 6 — results & engagement
    case calc, result, breakdown
    case streak, reminder
    // 7 — program builder
    case planIntro, difficulty, coach, exercise, sleep, trainingDays, planBuild
    // 8 — reveal & paywall
    case projection, paywall

    static let flow: [OnboardingStep] = [
        .hook,
        .auth, .birthdate,
        .welcome, .goals, .calibrate,
        .likert(0), .likert(1), .likert(2), .stat, .likert(3), .likert(4), .likert(5),
        .aboutYou, .gender, .education, .attribution, .screenTime,
        .meetYou, .gauntlet,
        .flanker, .explainFlanker,
        .tracker, .explainTracker,
        .span, .explainSpan,
        .calc, .result, .breakdown,
        .streak, .reminder,
        .planIntro, .difficulty, .coach, .exercise, .sleep, .trainingDays, .planBuild,
        .projection, .paywall,
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
    // account / demographics
    var birthdate: Date?
    var gender: String?
    var education: String?
    var heardAbout: String?
    var screenTime = 1              // 0–3
    // goals & self-assessment
    var goals: [String] = []
    var likertAnswers: [Int: Int] = [:]   // statement index → 0–3
    // program builder
    var difficulty: String?
    var encouragement: String?
    var exerciseFreq: String?
    var sleepHours: String?
    var trainingDays: Int?
    // fit test
    var flanker: FlankerStats?
    var tracker: TrackStats?
    var span: SpanStats?

    /// Total self-assessment score (0–18 across six statements).
    var likert: Int { likertAnswers.values.reduce(0, +) }

    /// Age in years derived from the account birthdate (defaults to 21).
    var ageMid: Int {
        guard let birthdate else { return 21 }
        let years = Calendar.current.dateComponents([.year], from: birthdate, to: Date()).year ?? 21
        return max(13, min(100, years))
    }
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
        + Double(d.likert) * 1.5
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

    @Environment(SupabaseManager.self) private var supa
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
        case .auth:
            AuthScreen(onAuthed: next)
        case .birthdate:
            BirthdateScreen { date in
                data.birthdate = date
                push(["birthdate": Self.dateString(date)])
                next()
            }
        case .welcome:
            WelcomeScreen(onNext: next)
        case .goals:
            GoalsScreen { picked in
                data.goals = picked
                push(["goals": picked])
                next()
            }
        case .calibrate:
            CalibrateScreen(onNext: next)
        case .likert(let index):
            LikertScreen(index: index) { score in
                data.likertAnswers[index] = score
                if index == LikertScreen.statements.count - 1 { pushAssessment() }
                next()
            }
        case .stat:
            StatScreen(onNext: next)
        case .aboutYou:
            AboutYouScreen(onNext: next)
        case .gender:
            GenderScreen { value in
                data.gender = value
                push(["gender": value])
                next()
            }
        case .education:
            EducationScreen { value in
                data.education = value
                push(["education": value])
                next()
            }
        case .attribution:
            AttributionScreen { value in
                data.heardAbout = value
                push(["heard_about": value])
                next()
            }
        case .screenTime:
            ScreenTimeScreen { score in
                data.screenTime = score
                push(["screen_time": score])
                next()
            }
        case .meetYou:
            MeetYouScreen(onNext: next)
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
                blurb: "that was the flanker task — a measure of response inhibition that researchers have used since 1974. it reflects how well you focus on what matters while tuning out distractions.",
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
                blurb: "that was multiple object tracking — how researchers have measured divided attention since the 1980s. it's the same skill you use to keep track of several things happening at once.",
                onNext: next
            )
        case .span:
            SpanScreen { stats in
                data.span = stats
                pushScores()
                next()
            }
        case .explainSpan:
            ExplainScreen(
                test: "echo grid",
                score: "\(spanPct)%",
                blurb: "that was a backward spatial span — the reverse corsi test neuropsychologists use to measure working memory. holding a sequence in mind and reordering it is a skill you rely on every day.",
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
        case .planIntro:
            PlanIntroScreen(onNext: next)
        case .difficulty:
            DifficultyScreen { value in
                data.difficulty = value
                push(["difficulty": value])
                next()
            }
        case .coach:
            CoachScreen(onNext: next)
        case .exercise:
            ExerciseScreen { value in
                data.exerciseFreq = value
                push(["exercise_freq": value])
                next()
            }
        case .sleep:
            SleepScreen { value in
                data.sleepHours = value
                push(["sleep_hours": value])
                next()
            }
        case .trainingDays:
            TrainingDaysScreen { value in
                data.trainingDays = value
                push(["training_days": value])
                next()
            }
        case .planBuild:
            PlanBuildScreen(onNext: next)
        case .projection:
            ProjectionScreen(result: computeResult(data), onNext: next)
        case .paywall:
            PaywallScreen(onClose: complete)
        }
    }

    // MARK: - Persistence (best-effort; RLS-guarded)

    private func push(_ fields: [String: Any]) {
        guard supa.isSignedIn else { return }
        Task { try? await supa.upsertProfile(fields) }
    }

    private func pushAssessment() {
        guard supa.isSignedIn else { return }
        let rows = data.likertAnswers.sorted { $0.key < $1.key }.map { idx, score -> (idx: Int, statement: String, score: Int) in
            let text = LikertScreen.statements.indices.contains(idx) ? LikertScreen.statements[idx] : ""
            return (idx: idx, statement: text, score: score)
        }
        Task { try? await supa.saveAssessment(rows) }
    }

    private func pushScores() {
        guard supa.isSignedIn else { return }
        let result = computeResult(data)
        var rows: [[String: Any]] = []
        if let f = data.flanker {
            rows.append(["game": "arrow storm", "score": f.score, "percentile": result.tests[0].pct,
                         "accuracy": accuracy(f.right, f.right + f.wrong)])
        }
        if let t = data.tracker {
            rows.append(["game": "crowd control", "percentile": result.tests[1].pct,
                         "accuracy": accuracy(t.correctPicks, t.totalTargets)])
        }
        if let s = data.span {
            rows.append(["game": "echo grid", "score": s.score, "percentile": result.tests[2].pct,
                         "accuracy": accuracy(s.correctTaps, s.totalTaps)])
        }
        Task { try? await supa.saveGameScores(rows) }
    }

    private func complete() {
        if supa.isSignedIn {
            Task { try? await supa.upsertProfile(["onboarding_completed": true]) }
        }
        onFinished()
    }

    private func accuracy(_ n: Int, _ d: Int) -> Double {
        d > 0 ? (Double(n) / Double(d) * 1000).rounded() / 1000 : 0
    }

    private static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

#Preview {
    OnboardingView {}
        .environment(SupabaseManager.shared)
}
