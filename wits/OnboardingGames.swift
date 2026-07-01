//
//  OnboardingGames.swift
//  wits
//
//  Part two of the flow — the gauntlet. Three tests built on classic
//  cognitive-psychology paradigms, each with an intro, a guided tutorial,
//  a "let's play" interstitial, and a real scored run:
//    Test 1: arrow storm   (Eriksen flanker task — interference control)
//    Test 2: crowd control (multiple object tracking — divided attention)
//    Test 3: echo grid     (backward spatial span — working memory)
//

import SwiftUI

@MainActor
private func reportGameFeel(_ cfg: GameConfig?, _ kind: TrialOutcome.Kind, points: Int = 0, combo: Int = 0) {
    if let cfg {
        cfg.report(kind, points: points, combo: combo)
        return
    }

    switch kind {
    case .hit:
        GameFeel.shared.play(.correct(combo: combo))
    case .miss:
        GameFeel.shared.play(.wrong)
    case .nearMiss:
        GameFeel.shared.play(.nearMiss)
    case .timeout:
        GameFeel.shared.play(.timeout)
    }
}

private extension View {
    func onboardingGameFeelLifecycle(enabled: Bool) -> some View {
        self
            .onAppear {
                if enabled { GameFeel.shared.warmUp() }
            }
            .onDisappear {
                if enabled { GameFeel.shared.teardown() }
            }
    }
}

// MARK: - Gauntlet overview

struct GauntletScreen: View {
    var onNext: () -> Void

    private let tests = [
        (1, "arrow storm", "ignore the crowd. answer only to the middle arrow."),
        (2, "crowd control", "mark the dots, watch them scatter. don't lose them."),
        (3, "echo grid", "a path lights up. play it back — backwards."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
                .padding(.bottom, 30)
            Text("take your fit test")
                .font(.witsDisplay(32))
                .foregroundStyle(Color.witsInk)
                .rise()
            Text("three quick games, about a minute each. we'll measure your baseline.")
                .font(.witsBody(16))
                .foregroundStyle(Color.witsMuted)
                .padding(.top, 12)
                .padding(.bottom, 26)
                .rise(0.08)
            VStack(spacing: 10) {
                ForEach(Array(tests.enumerated()), id: \.offset) { i, test in
                    PlanItem(number: test.0, title: test.1, sub: test.2)
                        .rise(0.16 + Double(i) * 0.09)
                }
            }
            Spacer()
            Cta(title: "start fit test", action: onNext)
                .rise(0.48)
                .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }
}

// MARK: - Test explainer (shared, shown after each test)

struct ExplainScreen: View {
    var test: String
    var score: String
    var blurb: String
    var last = false
    var onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Text(score)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsAccent)
                    .frame(width: 88, height: 88)
                    .background(Circle().fill(Color.witsAccent.opacity(0.14)))
                    .rise()
                Text(test)
                    .font(.witsDisplay(32))
                    .foregroundStyle(Color.witsInk)
                    .rise(0.09)
                Text(blurb)
                    .font(.witsBody(16))
                    .foregroundStyle(Color.witsMuted)
                    .rise(0.18)
            }
            Spacer()
            Cta(title: last ? "see the damage" : "next test", action: onNext)
                .rise(0.28)
                .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }
}

// MARK: - Test 1: arrow storm (flanker task)
// Five arrows. Only the middle one matters; the flankers usually disagree.
// An adaptive response deadline tightens as you streak — too slow counts
// as a miss. Based on the Eriksen flanker paradigm (1974).

struct FlankerScreen: View {
    /// nil → onboarding fit-test mode (intro + tutorial). non-nil → main-app
    /// workout mode: skip straight to a difficulty-seeded scored run.
    var cfg: GameConfig?
    var onResult: ((GameResult) -> Void)?
    var onComplete: ((FlankerStats) -> Void)?

    init(cfg: GameConfig? = nil,
         onResult: ((GameResult) -> Void)? = nil,
         onComplete: ((FlankerStats) -> Void)? = nil) {
        self.cfg = cfg
        self.onResult = onResult
        self.onComplete = onComplete
        _phase = State(initialValue: cfg == nil ? .intro : .playing)
        if let cfg {
            _window = State(initialValue: Self.seededWindow(cfg.difficulty.level))
            _trial = State(initialValue: Self.makeTrial())
        }
    }

    private static let gameSeconds = 45.0
    private static let maxWindow = 1.4
    private static let minWindow = 0.75

    /// Higher level → tighter starting deadline (harder).
    private static func seededWindow(_ level: Double) -> Double {
        max(minWindow, maxWindow - level * 0.08)
    }
    private var startedAt = Date()

    private struct Trial: Identifiable {
        let id = UUID()
        let right: Bool       // center arrow direction
        let congruent: Bool
        let yShift: CGFloat
    }

    private static func makeTrial() -> Trial {
        Trial(right: Bool.random(),
              congruent: Double.random(in: 0..<1) < 0.35,
              yShift: CGFloat.random(in: -34...34))
    }

    // Fixed tutorial trials: (right, congruent, hint)
    private static let tutorialTrials: [(right: Bool, congruent: Bool, hint: String)] = [
        (true, true, "five arrows. you answer for the middle one only. they all agree here — tap right."),
        (false, false, "now the crowd points right, but the middle arrow points left. tap left."),
        (true, false, "the flankers exist to fool you. middle arrow says right."),
    ]

    @State private var phase = GamePhase.intro
    @State private var tutorialIndex = 0
    @State private var tutorialError = false
    @State private var stats = FlankerStats()
    @State private var streak = 0
    @State private var trial: Trial?
    @State private var trialStart = Date()
    @State private var window = maxWindow
    @State private var windowFrac = 1.0
    @State private var timeLeft = gameSeconds
    @State private var feedback: Bool?
    @State private var finished = false

    private var multiplier: Int { min(5, 1 + streak / 3) }

    var body: some View {
        Group {
            switch phase {
            case .intro:
                GameExplainer(
                    tag: "test 1 of 3",
                    title: "arrow storm",
                    skill: "interference control",
                    how: "five arrows flash. you answer for the middle one while its neighbours point the other way and try to drag your answer with them. the clock per arrow shrinks as you get better.",
                    why: "this is the flanker task, a lab standard since 1974. it measures how well you act on the signal while the noise screams — the muscle that keeps you on one thing when everything on screen is flashing.",
                    onStart: { phase = .tutorial }
                ) {
                    VStack(spacing: 18) {
                        HStack(spacing: 14) {
                            ForEach(0..<5, id: \.self) { i in
                                Image(systemName: i == 2 ? "arrowtriangle.right.fill" : "arrowtriangle.left.fill")
                                    .font(.system(size: 30, weight: .heavy))
                                    .foregroundStyle(i == 2 ? Color.witsAccent : .white.opacity(0.4))
                            }
                        }
                        Capsule()
                            .fill(.white.opacity(0.16))
                            .frame(width: 120, height: 5)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color.witsWarm).frame(width: 42)
                            }
                    }
                }
            case .tutorial:
                tutorialView
            case .ready:
                GameReady {
                    stats = FlankerStats()
                    streak = 0
                    window = Self.maxWindow
                    trial = Self.makeTrial()
                    trialStart = Date()
                    phase = .playing
                }
            case .playing:
                playView
            }
        }
        .onboardingGameFeelLifecycle(enabled: cfg == nil)
    }

    private func arrowRow(right: Bool, congruent: Bool, size: CGFloat = 32) -> some View {
        HStack(spacing: 12) {
            ForEach(0..<5, id: \.self) { i in
                let isCenter = i == 2
                let pointsRight = isCenter ? right : (congruent ? right : !right)
                Image(systemName: pointsRight ? "arrowtriangle.right.fill" : "arrowtriangle.left.fill")
                    .font(.system(size: size, weight: .heavy))
                    .foregroundStyle(Color.witsInk)
            }
        }
    }

    private func trialCard(_ t: Trial) -> some View {
        VStack(spacing: 6) {
            arrowRow(right: t.right, congruent: t.congruent)
                .offset(y: t.yShift)
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .cardSurface()
            Text("THE MIDDLE ONE")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(0.7)
                .foregroundStyle(Color.witsFaint)
        }
    }

    private var tutorialView: some View {
        let t = Self.tutorialTrials[tutorialIndex]
        return VStack(spacing: 0) {
            GameTopTag(text: "tutorial · \(tutorialIndex + 1) of \(Self.tutorialTrials.count)")
            Spacer()
            VStack(spacing: 6) {
                arrowRow(right: t.right, congruent: t.congruent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .cardSurface()
                Text("THE MIDDLE ONE")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .kerning(0.7)
                    .foregroundStyle(Color.witsFaint)
            }
            Spacer()
            VStack(spacing: 14) {
                TutorialHint(text: tutorialError ? "not quite. \(t.hint)" : t.hint)
                answerButtons { saysRight in
                    let ok = saysRight == t.right
                    reportGameFeel(cfg, ok ? .hit : .miss, points: ok ? 100 : 0, combo: ok ? tutorialIndex + 1 : 0)
                    if ok {
                        tutorialError = false
                        if tutorialIndex < Self.tutorialTrials.count - 1 {
                            tutorialIndex += 1
                        } else {
                            phase = .ready
                        }
                    } else {
                        tutorialError = true
                    }
                }
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
        .animation(.easeOut(duration: 0.16), value: tutorialIndex)
        .animation(.easeOut(duration: 0.16), value: tutorialError)
    }

    private var playView: some View {
        VStack(spacing: 12) {
            if cfg?.isSurvival != true {
                HStack {
                    Spacer()
                    Text("\(Int(ceil(timeLeft)))s")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsMuted)
                        .monospacedDigit()
                }
                ProgressTrack(fraction: timeLeft / Self.gameSeconds, animated: false)
            }
            Spacer()
            if let trial {
                trialCard(trial)
                    .id(trial.id)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                            .strokeBorder(
                                feedback == true ? Color.witsAccent : feedback == false ? Color.witsWarm : .clear,
                                lineWidth: 2.5
                            )
                            .padding(-14)
                    )
                // per-trial deadline
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.witsLine)
                    GeometryReader { geo in
                        Capsule()
                            .fill(windowFrac < 0.35 ? Color.witsWarm : Color.witsMuted)
                            .frame(width: max(0, geo.size.width * windowFrac))
                    }
                }
                .frame(width: 130, height: 4)
                .padding(.top, 18)
            }
            Spacer()
            answerButtons { saysRight in
                answer(saysRight)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .task { await run() }
    }

    private func answerButtons(_ act: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 10) {
            Button { act(false) } label: {
                Image(systemName: "arrowtriangle.left.fill")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Color.witsInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Color.witsTint, in: Capsule())
            }
            .buttonStyle(.plain)
            Button { act(true) } label: {
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Color.witsAccent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func answer(_ saysRight: Bool) {
        guard let current = trial, !finished else { return }
        let ok = saysRight == current.right
        if ok {
            stats.right += 1
            streak += 1
            stats.bestStreak = max(stats.bestStreak, streak)
            stats.score += 100 * multiplier
            window = max(cfg?.isSurvival == true ? 0.6 : Self.minWindow, window - (cfg?.isSurvival == true ? 0.04 : 0.025))
            reportGameFeel(cfg, .hit, points: 100, combo: streak)
        } else {
            stats.wrong += 1
            streak = 0
            window = min(Self.maxWindow, window + 0.12)
            reportGameFeel(cfg, .miss)
        }
        feedback = ok
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { feedback = nil }
        nextTrial()
    }

    private func timeout() {
        guard !finished else { return }
        stats.wrong += 1
        streak = 0
        window = min(Self.maxWindow, window + 0.12)
        feedback = false
        reportGameFeel(cfg, .timeout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { feedback = nil }
        nextTrial()
    }

    private func nextTrial() {
        withAnimation(.easeOut(duration: 0.13)) {
            trial = Self.makeTrial()
        }
        trialStart = Date()
        windowFrac = 1
    }

    private func run() async {
        let start = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(30))
            timeLeft = max(0, Self.gameSeconds - Date().timeIntervalSince(start))
            let elapsed = Date().timeIntervalSince(trialStart)
            windowFrac = max(0, 1 - elapsed / window)
            if elapsed > window { timeout() }
            if cfg?.isSurvival != true && timeLeft <= 0 {
                guard !finished else { return }
                finished = true
                try? await Task.sleep(for: .milliseconds(350))
                finish()
                return
            }
        }
    }

    private func finish() {
        if let onResult {
            let total = stats.right + stats.wrong
            let acc = total > 0 ? Double(stats.right) / Double(total) : 0
            var r = GameResult(game: .arrowStorm, score: stats.score, accuracy: acc)
            r.trials = total
            r.threshold = window
            r.startedAt = startedAt
            r.durationMs = Int(Self.gameSeconds * 1000)
            r.raw = [
                "bestStreak": Double(stats.bestStreak),
                "correct": Double(stats.right),
                "wrong": Double(stats.wrong),
                "timeOnTaskMs": Self.gameSeconds * 1000
            ]
            onResult(r)
        } else {
            onComplete?(stats)
        }
    }
}

// MARK: - Test 2: crowd control (multiple object tracking)
// A few dots flash, then turn identical to the rest and everything starts
// drifting. Track the marked ones through the chaos and point them out when
// the dots freeze. Based on the multiple-object-tracking paradigm (1988).

struct TrackerScreen: View {
    var cfg: GameConfig?
    var onResult: ((GameResult) -> Void)?
    var onComplete: ((TrackStats) -> Void)?

    init(cfg: GameConfig? = nil,
         onResult: ((GameResult) -> Void)? = nil,
         onComplete: ((TrackStats) -> Void)? = nil) {
        self.cfg = cfg
        self.onResult = onResult
        self.onComplete = onComplete
        _phase = State(initialValue: cfg == nil ? .intro : .playing)
    }

    private var startedAt = Date()

    // (targets, dots, unit speed) per scored round
    private static let rounds: [(targets: Int, dots: Int, speed: Double)] = [
        (3, 9, 0.22), (4, 9, 0.26), (4, 9, 0.30), (5, 9, 0.34),
    ]
    private static let tutorialRound = (targets: 2, dots: 6, speed: 0.13)
    private static let markSeconds = 1.5
    private static let moveSeconds = 6.5
    private static let margin = 0.08
    private static let dotDiameter: CGFloat = 30
    private static let collisionIterations = 3

    private enum RoundPhase {
        case mark, move, pick, reveal
    }

    private struct Dot: Identifiable {
        let id: Int
        var pos: CGPoint
        var vel: CGVector
        var isTarget: Bool
        var picked = false
    }

    @State private var phase = GamePhase.intro
    @State private var roundPhase = RoundPhase.mark
    @State private var dots: [Dot] = []
    @State private var round = 0
    @State private var stats = TrackStats()
    @State private var pulse = false
    @State private var generation = 0
    @State private var boardSize: CGSize = .zero

    private var config: (targets: Int, dots: Int, speed: Double) {
        phase == .tutorial ? Self.tutorialRound : Self.rounds[min(round, Self.rounds.count - 1)]
    }

    var body: some View {
        Group {
            switch phase {
            case .intro:
                GameExplainer(
                    tag: "test 2 of 3",
                    title: "crowd control",
                    skill: "divided attention",
                    how: "a few dots glow, then go dark and scatter into an identical crowd. keep your eyes on all of them at once, and point them out when everything freezes. every round adds more to hold.",
                    why: "this is multiple object tracking, used in attention labs since the 80s. it measures how many moving things you can follow at once — the exact load your tabs, chats and second screen put on you together.",
                    onStart: {
                        phase = .tutorial
                        startRound()
                    }
                ) {
                    GeometryReader { geo in
                        let spots: [(x: Double, y: Double, target: Bool)] = [
                            (0.14, 0.30, true), (0.30, 0.68, false), (0.43, 0.22, false),
                            (0.56, 0.58, true), (0.70, 0.26, false), (0.84, 0.62, true),
                            (0.24, 0.46, false), (0.78, 0.42, false),
                        ]
                        ForEach(Array(spots.enumerated()), id: \.offset) { _, s in
                            Circle()
                                .fill(s.target ? Color.witsAccent : .white.opacity(0.30))
                                .frame(width: 24, height: 24)
                                .shadow(color: s.target ? Color.witsAccent.opacity(0.6) : .clear, radius: 7)
                                .position(x: s.x * geo.size.width, y: s.y * geo.size.height)
                        }
                    }
                    .padding(14)
                }
            case .tutorial, .playing:
                board
            case .ready:
                GameReady {
                    round = 0
                    stats = TrackStats()
                    phase = .playing
                    startRound()
                }
            }
        }
        .onboardingGameFeelLifecycle(enabled: cfg == nil)
    }

    private var statusLine: String {
        switch roundPhase {
        case .mark: return "memorize the glowing dots"
        case .move: return "don't lose them"
        case .pick: return "tap the \(config.targets) you were tracking"
        case .reveal: return dots.filter { $0.picked && $0.isTarget }.count == config.targets
            ? "all of them. nice." : "the rings show where they really went."
        }
    }

    private var board: some View {
        VStack(spacing: 12) {
            if phase == .tutorial {
                GameTopTag(text: "tutorial")
                TutorialHint(text: roundPhase == .pick
                    ? "the dots froze. tap the \(config.targets) that were glowing at the start."
                    : "two dots glow, then blend in and wander. follow them with your eyes.")
            } else if cfg?.isSurvival != true {
                HStack(alignment: .firstTextBaseline) {
                    Text("round \(Text("\(min(round + 1, Self.rounds.count))").foregroundStyle(Color.witsAccent)) of \(Self.rounds.count)")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                        .monospacedDigit()
                    Spacer()
                    Text("\(stats.correctPicks) of \(stats.totalTargets) held")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.witsMuted)
                        .monospacedDigit()
                }
                ProgressTrack(fraction: Double(round) / Double(Self.rounds.count), animated: true)
            }
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                        .fill(Color.witsCard)
                        .shadow(color: .witsShadow, radius: 10, y: 6)
                    ForEach(dots) { dot in
                        dotView(dot)
                            .position(x: dot.pos.x * size.width, y: dot.pos.y * size.height)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous))
                .onAppear {
                    boardSize = size
                }
                .onChange(of: size) { _, newSize in
                    boardSize = newSize
                }
                .onTapGesture { location in
                    tapBoard(location, in: size)
                }
            }
            Text(statusLine)
                .font(.witsBody(12.5))
                .foregroundStyle(Color.witsFaint)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .onAppear { if cfg != nil && dots.isEmpty { startRound() } }
    }

    private func dotView(_ dot: Dot) -> some View {
        let showTarget = roundPhase == .mark && dot.isTarget
        let missed = roundPhase == .reveal && dot.isTarget && !dot.picked
        let fill: Color = showTarget ? .witsAccent
            : dot.picked ? (roundPhase == .reveal && !dot.isTarget ? Color.witsWarm : Color.witsAccent.opacity(0.85))
            : Color.witsInk.opacity(0.32)
        return Circle()
            .fill(fill)
            .frame(width: Self.dotDiameter, height: Self.dotDiameter)
            .scaleEffect(showTarget && pulse ? 1.18 : 1)
            .overlay(
                Circle()
                    .strokeBorder(missed ? Color.witsAccent : .clear, lineWidth: 3)
                    .padding(-5)
            )
            .animation(.easeInOut(duration: 0.45), value: pulse)
            .animation(.easeOut(duration: 0.15), value: dot.picked)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    private func tapBoard(_ location: CGPoint, in size: CGSize) {
        guard roundPhase == .pick else { return }
        let unit = CGPoint(x: location.x / size.width, y: location.y / size.height)
        // nearest dot within ~22pt
        let hit = dots.indices.min { a, b in
            dist(dots[a].pos, unit, size) < dist(dots[b].pos, unit, size)
        }
        guard let hit, dist(dots[hit].pos, unit, size) < 26, !dots[hit].picked else { return }
        dots[hit].picked = true
        if dots.filter(\.picked).count == config.targets { finishPicks() }
    }

    private func dist(_ a: CGPoint, _ b: CGPoint, _ size: CGSize) -> Double {
        let dx = (a.x - b.x) * size.width, dy = (a.y - b.y) * size.height
        return (dx * dx + dy * dy).squareRoot()
    }

    private func finishPicks() {
        let correct = dots.filter { $0.picked && $0.isTarget }.count
        let isTutorial = phase == .tutorial
        let perfect = correct == config.targets
        if !isTutorial {
            stats.correctPicks += correct
            stats.totalTargets += config.targets
            stats.rounds += 1
            if perfect { stats.perfectRounds += 1 }
        }
        reportGameFeel(cfg, perfect ? .hit : .miss, points: correct * 80, combo: isTutorial ? (perfect ? 1 : 0) : stats.perfectRounds)
        roundPhase = .reveal
        let gen = generation
        Task {
            try? await Task.sleep(for: .milliseconds(1400))
            guard gen == generation else { return }
            if isTutorial {
                phase = .ready
            } else if cfg?.isSurvival != true && round + 1 >= Self.rounds.count {
                finish()
            } else {
                round = (round + 1) % Self.rounds.count   // cycle rounds endlessly in survival
                startRound()
            }
        }
    }

    private func finish() {
        if let onResult {
            let acc = stats.totalTargets > 0 ? Double(stats.correctPicks) / Double(stats.totalTargets) : 0
            var r = GameResult(game: .crowdControl, score: stats.correctPicks * 250, accuracy: acc)
            r.trials = stats.rounds
            r.threshold = Double(stats.perfectRounds)
            r.startedAt = startedAt
            r.durationMs = Int((cfg?.activeElapsed(since: startedAt) ?? Date().timeIntervalSince(startedAt)) * 1000)
            r.raw = [
                "perfectRounds": Double(stats.perfectRounds),
                "totalTargets": Double(stats.totalTargets),
                "correctPicks": Double(stats.correctPicks),
                // CrowdControlPolicy's contract: per-target hits and misses.
                "correct": Double(stats.correctPicks),
                "wrong": Double(max(0, stats.totalTargets - stats.correctPicks))
            ]
            onResult(r)
        } else {
            onComplete?(stats)
        }
    }

    private func startRound() {
        generation += 1
        let gen = generation
        let c = config
        var rng = SystemRandomNumberGenerator()
        var seeded: [Dot] = []
        for i in 0..<c.dots {
            // keep spawn points spread out
            var pos: CGPoint
            var attempts = 0
            repeat {
                pos = CGPoint(x: Double.random(in: Self.margin...(1 - Self.margin), using: &rng),
                              y: Double.random(in: Self.margin...(1 - Self.margin), using: &rng))
                attempts += 1
            } while attempts < 40 && seeded.contains(where: { hypot($0.pos.x - pos.x, $0.pos.y - pos.y) < 0.16 })
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
            seeded.append(Dot(
                id: gen * 100 + i,   // unique per round → dots fade in/out, never teleport
                pos: pos,
                vel: CGVector(dx: Darwin.cos(angle) * c.speed, dy: Darwin.sin(angle) * c.speed),
                isTarget: i < c.targets
            ))
        }
        let fresh = seeded.shuffled()

        Task {
            // fade the previous round's dots out, pause, then fade the new set in
            if !dots.isEmpty {
                withAnimation(.easeOut(duration: 0.25)) { dots = [] }
                try? await Task.sleep(for: .milliseconds(320))
                guard gen == generation else { return }
            }
            roundPhase = .mark
            pulse = false
            withAnimation(.easeOut(duration: 0.3)) { dots = fresh }

            // mark: pulse the targets
            var markLeft = Self.markSeconds
            while markLeft > 0 {
                pulse.toggle()
                try? await Task.sleep(for: .milliseconds(450))
                guard gen == generation else { return }
                markLeft -= 0.45
            }
            roundPhase = .move
            // move: drift, bounce, jitter
            var moveLeft = Self.moveSeconds
            let dt = 0.016
            while moveLeft > 0 {
                try? await Task.sleep(for: .milliseconds(16))
                guard gen == generation else { return }
                step(dt)
                moveLeft -= dt
            }
            roundPhase = .pick
        }
    }

    private func step(_ dt: Double) {
        for i in dots.indices {
            var d = dots[i]
            // occasional heading change so paths can't be extrapolated
            if Double.random(in: 0..<1) < 0.012 {
                let turn = Double.random(in: -0.9...0.9)
                let speed = hypot(d.vel.dx, d.vel.dy)
                let heading = atan2(d.vel.dy, d.vel.dx) + turn
                d.vel = CGVector(dx: Darwin.cos(heading) * speed, dy: Darwin.sin(heading) * speed)
            }
            d.pos.x += d.vel.dx * dt
            d.pos.y += d.vel.dy * dt
            keepDotInBounds(&d)
            dots[i] = d
        }
        resolveDotCollisions()
    }

    private func resolveDotCollisions() {
        guard dots.count > 1, boardSize.width > 0, boardSize.height > 0 else { return }
        for _ in 0..<Self.collisionIterations {
            for i in dots.indices {
                for j in dots.indices where j > i {
                    resolveCollision(i, j, in: boardSize)
                }
            }
            for i in dots.indices {
                keepDotInBounds(&dots[i])
            }
        }
    }

    private func resolveCollision(_ i: Int, _ j: Int, in size: CGSize) {
        var dx = (dots[j].pos.x - dots[i].pos.x) * size.width
        var dy = (dots[j].pos.y - dots[i].pos.y) * size.height
        var distance = hypot(dx, dy)
        if distance == 0 {
            let angle = Double((dots[i].id * 37 + dots[j].id * 19) % 360) * .pi / 180
            dx = CGFloat(Darwin.cos(angle)) * 0.001
            dy = CGFloat(Darwin.sin(angle)) * 0.001
            distance = hypot(dx, dy)
        }
        guard distance < Self.dotDiameter else { return }

        let nx = dx / distance
        let ny = dy / distance
        let push = (Self.dotDiameter - distance) / 2

        dots[i].pos.x -= nx * push / size.width
        dots[i].pos.y -= ny * push / size.height
        dots[j].pos.x += nx * push / size.width
        dots[j].pos.y += ny * push / size.height

        let ivx = dots[i].vel.dx * size.width
        let ivy = dots[i].vel.dy * size.height
        let jvx = dots[j].vel.dx * size.width
        let jvy = dots[j].vel.dy * size.height
        let rvx = jvx - ivx
        let rvy = jvy - ivy
        let closingSpeed = rvx * nx + rvy * ny
        if closingSpeed < 0 {
            dots[i].vel.dx = (ivx + closingSpeed * nx) / size.width
            dots[i].vel.dy = (ivy + closingSpeed * ny) / size.height
            dots[j].vel.dx = (jvx - closingSpeed * nx) / size.width
            dots[j].vel.dy = (jvy - closingSpeed * ny) / size.height
            normalizeSpeed(&dots[i], in: size)
            normalizeSpeed(&dots[j], in: size)
        }
    }

    private func keepDotInBounds(_ dot: inout Dot) {
        if dot.pos.x < Self.margin { dot.pos.x = Self.margin; dot.vel.dx = abs(dot.vel.dx) }
        if dot.pos.x > 1 - Self.margin { dot.pos.x = 1 - Self.margin; dot.vel.dx = -abs(dot.vel.dx) }
        if dot.pos.y < Self.margin { dot.pos.y = Self.margin; dot.vel.dy = abs(dot.vel.dy) }
        if dot.pos.y > 1 - Self.margin { dot.pos.y = 1 - Self.margin; dot.vel.dy = -abs(dot.vel.dy) }
    }

    private func normalizeSpeed(_ dot: inout Dot, in size: CGSize) {
        let vx = dot.vel.dx * size.width
        let vy = dot.vel.dy * size.height
        let speed = hypot(vx, vy)
        guard speed > 0 else { return }
        let targetSpeed = CGFloat(config.speed) * min(size.width, size.height)
        dot.vel.dx = vx / speed * targetSpeed / size.width
        dot.vel.dy = vy / speed * targetSpeed / size.height
    }
}

// MARK: - Test 3: echo grid (backward spatial span)
// Tiles light up one at a time. Tap them back in REVERSE order. Perfect
// recall lengthens the path, a slip shortens it. Based on the backward
// Corsi block-tapping task.

struct SpanScreen: View {
    var cfg: GameConfig?
    var onResult: ((GameResult) -> Void)?
    var onComplete: ((SpanStats) -> Void)?

    init(cfg: GameConfig? = nil,
         onResult: ((GameResult) -> Void)? = nil,
         onComplete: ((SpanStats) -> Void)? = nil) {
        self.cfg = cfg
        self.onResult = onResult
        self.onComplete = onComplete
        _phase = State(initialValue: cfg == nil ? .intro : .playing)
    }

    private var startedAt = Date()

    private static let totalTrials = 8
    private static let columns = 4
    private static let rows = 4

    private enum TrialPhase {
        case interstitial, show, recall, reveal
    }

    @State private var phase = GamePhase.intro
    @State private var trialPhase = TrialPhase.interstitial
    @State private var inTutorial = false
    @State private var trial = 0
    @State private var span = 3
    @State private var seq: [Int] = []
    @State private var litIndex: Int?
    @State private var tapIndex = 0
    @State private var rightTaps: Set<Int> = []
    @State private var wrongTap: Int?
    @State private var failed = false
    @State private var stats = SpanStats()
    @State private var generation = 0

    private var cellCount: Int { Self.rows * Self.columns }

    var body: some View {
        Group {
            switch phase {
            case .intro:
                GameExplainer(
                    tag: "test 3 of 3",
                    title: "echo grid",
                    skill: "working memory",
                    how: "tiles light up one at a time, then go dark. you play the path back in reverse — last tile first. perfect rounds make the path longer, slips make it shorter.",
                    why: "this is the backward corsi span, the test neuropsychologists reach for to measure working memory. holding a sequence in your head and flipping it around is the same load deep work puts on you.",
                    onStart: {
                        inTutorial = true
                        startTrial(reset: true)
                        phase = .tutorial
                    }
                ) {
                    HStack(spacing: 22) {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 5), count: 3), spacing: 5) {
                            ForEach(0..<9, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill([1, 5, 6].contains(i) ? Color.witsAccent : .white.opacity(0.12))
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if let n = [1, 5, 6].firstIndex(of: i) {
                                            Text("\(n + 1)")
                                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                        }
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 17, weight: .heavy))
                                .foregroundStyle(Color.witsAccent)
                            Text("3 → 2 → 1")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
            case .tutorial, .playing:
                board
            case .ready:
                GameReady {
                    inTutorial = false
                    startTrial(reset: true)
                    phase = .playing
                }
            }
        }
        .onboardingGameFeelLifecycle(enabled: cfg == nil)
    }

    private var board: some View {
        VStack(spacing: 12) {
            if inTutorial {
                GameTopTag(text: "tutorial")
                TutorialHint(text: trialPhase == .recall
                    ? "now play it back in reverse — tap the \(ordinal(seq.count)) tile first, the first tile last."
                    : "watch the order. you'll answer backwards.")
            } else if cfg?.isSurvival != true {
                HStack(alignment: .firstTextBaseline) {
                    Text("trial \(Text("\(min(trial, Self.totalTrials))").foregroundStyle(Color.witsAccent)) of \(Self.totalTrials)")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                        .monospacedDigit()
                    Spacer()
                    Text("\(stats.score) pts")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsMuted)
                        .monospacedDigit()
                }
                ProgressTrack(fraction: Double(trial - 1) / Double(Self.totalTrials), animated: true)
            }
            ZStack {
                gridView
                    .opacity(trialPhase == .interstitial ? 0.25 : 1)
                if trialPhase == .interstitial {
                    VStack(spacing: 2) {
                        Text("STEPS")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .kerning(1.5)
                            .foregroundStyle(Color.witsMuted)
                        Text("\(span)")
                            .font(.system(size: 54, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.witsInk)
                    }
                    .frame(width: 130, height: 130)
                    .background(Color.witsCard, in: Circle())
                    .shadow(color: .witsShadow, radius: 12, y: 6)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.18), value: trialPhase == .interstitial)
            Text(statusLine)
                .font(.witsBody(12.5))
                .foregroundStyle(Color.witsFaint)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .onAppear { if cfg != nil && seq.isEmpty { startTrial(reset: true) } }
    }

    private func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }

    private var statusLine: String {
        switch trialPhase {
        case .interstitial: return "get ready"
        case .show: return "\(span) steps. memorize the order."
        case .recall: return "tap them in reverse — \(seq.count - tapIndex) to go"
        case .reveal: return failed ? "the numbers show the reverse order. path shrinks." : "perfect echo. path grows."
        }
    }

    private var gridView: some View {
        GeometryReader { geo in
            let gap: CGFloat = 8
            let cellW = (geo.size.width - 28 - gap * CGFloat(Self.columns - 1)) / CGFloat(Self.columns)
            let cellH = (geo.size.height - 28 - gap * CGFloat(Self.rows - 1)) / CGFloat(Self.rows)
            let side = min(cellW, cellH)
            VStack(spacing: gap) {
                ForEach(0..<Self.rows, id: \.self) { r in
                    HStack(spacing: gap) {
                        ForEach(0..<Self.columns, id: \.self) { c in
                            cell(r * Self.columns + c)
                                .frame(width: side, height: side)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .cardSurface()
        }
    }

    private func cell(_ i: Int) -> some View {
        let isLit = trialPhase == .show && litIndex.map { seq[$0] == i } ?? false
        let isRight = rightTaps.contains(i)
        let isWrong = wrongTap == i
        let revealStep: Int? = trialPhase == .reveal && failed
            ? seq.lastIndex(of: i).map { seq.count - $0 } : nil
        let fill: Color = isLit ? .witsAccent
            : isRight ? Color.witsAccent.opacity(0.85)
            : isWrong ? Color.witsWarm.opacity(0.7)
            : revealStep != nil ? Color.witsAccent.opacity(0.30)
            : .witsTint
        return Button {
            tapCell(i)
        } label: {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(fill)
                .overlay {
                    if let revealStep {
                        Text("\(revealStep)")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.witsInk)
                    } else if isLit, inTutorial, let litIndex {
                        Text("\(litIndex + 1)")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.13), value: isLit)
        .animation(.easeOut(duration: 0.13), value: isRight)
        .animation(.easeOut(duration: 0.13), value: isWrong)
    }

    private func startTrial(reset: Bool) {
        if reset {
            stats = SpanStats()
            span = inTutorial ? 2 : min(6, 3 + Int((cfg?.difficulty.level ?? 0) / 2))
            trial = 1
        }
        generation += 1
        let gen = generation
        var cells: Set<Int> = []
        while cells.count < span {
            cells.insert(Int.random(in: 0..<cellCount))
        }
        seq = Array(cells).shuffled()
        litIndex = nil
        tapIndex = 0
        rightTaps = []
        wrongTap = nil
        failed = false
        trialPhase = .interstitial

        Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard gen == generation else { return }
            trialPhase = .show
            for i in seq.indices {
                litIndex = i
                try? await Task.sleep(for: .milliseconds(inTutorial ? 750 : 550))
                guard gen == generation else { return }
                litIndex = nil
                try? await Task.sleep(for: .milliseconds(140))
                guard gen == generation else { return }
            }
            trialPhase = .recall
        }
    }

    private func tapCell(_ i: Int) {
        guard trialPhase == .recall else { return }
        let expected = seq[seq.count - 1 - tapIndex]
        if i == expected {
            rightTaps.insert(i)
            tapIndex += 1
            reportGameFeel(cfg, .hit, points: 120, combo: tapIndex)
            if !inTutorial {
                stats.correctTaps += 1
                stats.score += 120
            }
            if tapIndex == seq.count { endTrial(perfect: true) }
        } else {
            wrongTap = i
            reportGameFeel(cfg, .miss)
            endTrial(perfect: false)
        }
    }

    private func endTrial(perfect: Bool) {
        failed = !perfect
        if !inTutorial {
            stats.totalTaps += seq.count
            stats.trials += 1
            if perfect {
                stats.perfectTrials += 1
                stats.maxSpan = max(stats.maxSpan, seq.count)
                stats.score += 360
            }
        }
        trialPhase = .reveal
        let gen = generation
        Task {
            try? await Task.sleep(for: .milliseconds(perfect ? 900 : 1700))
            guard gen == generation else { return }
            if inTutorial {
                phase = .ready
                return
            }
            span = perfect ? min(7, span + 1) : max(2, span - 1)
            if cfg?.isSurvival != true && trial >= Self.totalTrials {
                finish()
            } else {
                trial += 1
                startTrial(reset: false)
            }
        }
    }

    private func finish() {
        if let onResult {
            let acc = stats.totalTaps > 0 ? Double(stats.correctTaps) / Double(stats.totalTaps) : 0
            var r = GameResult(game: .echoGrid, score: stats.score, accuracy: acc)
            r.trials = stats.trials
            r.threshold = Double(stats.maxSpan)
            r.startedAt = startedAt
            r.raw = [
                "maxSpan": Double(stats.maxSpan),
                "perfectTrials": Double(stats.perfectTrials),
                "correctTaps": Double(stats.correctTaps),
                "totalTaps": Double(stats.totalTaps)
            ]
            onResult(r)
        } else {
            onComplete?(stats)
        }
    }
}
