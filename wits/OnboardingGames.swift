//
//  OnboardingGames.swift
//  wits
//
//  Part two of the flow — the gauntlet. Three Lumosity-style tests, each with
//  an intro, a guided tutorial, a "let's play" interstitial, and a real
//  scored run:
//    Test 1: color match   (response inhibition / focus)
//    Test 2: train of thought (divided attention / multitasking)
//    Test 3: memory matrix (spatial recall / working memory)
//

import SwiftUI

// MARK: - Gauntlet overview

struct GauntletScreen: View {
    var onNext: () -> Void

    private let tests = [
        (1, "color match", "say no to the answer your brain shouts first."),
        (2, "train of thought", "route every train home. they keep coming."),
        (3, "memory matrix", "tiles flash, then vanish. hold the picture."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
                .padding(.bottom, 30)
            Text("part two: the gauntlet")
                .font(.witsDisplay(32))
                .foregroundStyle(Color.witsInk)
                .rise()
            Text("three tests, about a minute each. this is the part you can't fake.")
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
            Cta(title: "start test one", action: onNext)
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

// MARK: - Shared game scaffolding

private enum GamePhase {
    case intro, tutorial, ready, playing
}

private struct GameTopTag: View {
    var text: String
    var body: some View {
        HStack {
            Wordmark()
            Spacer()
            Text(text)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.witsFaint)
        }
    }
}

/// Intro card: game number, name, skill line, demo slot, "start tutorial".
private struct GameIntro<Demo: View>: View {
    var tag: String
    var title: String
    var skillLine: String
    var onStart: () -> Void
    @ViewBuilder var demo: Demo

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GameTopTag(text: tag)
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.witsDisplay(36))
                    .foregroundStyle(Color.witsInk)
                    .rise()
                Text(skillLine)
                    .font(.witsBody(17))
                    .foregroundStyle(Color.witsMuted)
                    .rise(0.08)
                demo
                    .rise(0.18)
            }
            Spacer()
            Cta(title: "start tutorial", action: onStart)
                .rise(0.3)
                .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }
}

/// "Nice work" interstitial between tutorial and the scored run.
private struct GameReady: View {
    var onPlay: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                Text("you've got it")
                    .font(.witsDisplay(28))
                    .foregroundStyle(Color.witsInk)
                Text("now it counts. respond as quickly as possible while avoiding mistakes.")
                    .font(.witsBody(16))
                    .foregroundStyle(Color.witsMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .cardSurface()
            .rise()
            Spacer()
            Cta(title: "let's play", action: onPlay)
                .rise(0.15)
                .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 12)
    }
}

private struct TutorialHint: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.witsBody(14, weight: .semibold))
            .foregroundStyle(Color.witsMuted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.witsTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private let gameInks: [(name: String, color: Color)] = [
    ("green", Color(light: 0x2FAE6E, dark: 0x2FAE6E)),
    ("blue", Color(light: 0x4E7CF6, dark: 0x4E7CF6)),
    ("orange", Color(light: 0xF0853F, dark: 0xF0853F)),
    ("pink", Color(light: 0xE0569E, dark: 0xE0569E)),
]

// MARK: - Test 1: color match
// Top card shows a word (its MEANING matters). Bottom card shows a word
// printed in a color (its INK matters). Match = top word's meaning equals
// the bottom word's ink color. 45 seconds, streak multiplier scoring.

struct ColorMatchScreen: View {
    var onComplete: (ColorMatchStats) -> Void

    private static let gameSeconds = 45.0

    private struct Trial: Identifiable {
        let id = UUID()
        let topWord: String
        let bottomWord: String
        let inkName: String
        let ink: Color
        var match: Bool { topWord == inkName }
    }

    private static func makeTrial() -> Trial {
        let top = gameInks.randomElement()!
        let bottomWord = gameInks.randomElement()!.name
        let ink = Bool.random() ? top : gameInks.filter { $0.name != top.name }.randomElement()!
        return Trial(topWord: top.name, bottomWord: bottomWord, inkName: ink.name, ink: ink.color)
    }

    // Fixed tutorial trials: (top, bottomWord, inkIndex, hint)
    private static let tutorialTrials: [(top: String, bottom: String, ink: Int, hint: String)] = [
        ("blue", "blue", 1, "the top word means blue. the bottom text is printed in blue. that's a match — tap yes."),
        ("orange", "pink", 0, "ignore what the bottom word says. it's printed in green, and the top word means orange. no match."),
        ("pink", "green", 3, "the word says green, but it's printed in pink — and the top word means pink. match."),
    ]

    @State private var phase = GamePhase.intro
    @State private var tutorialIndex = 0
    @State private var tutorialError = false
    @State private var stats = ColorMatchStats()
    @State private var streak = 0
    @State private var trial: Trial?
    @State private var timeLeft = gameSeconds
    @State private var feedback: Bool?
    @State private var finished = false

    private var multiplier: Int { min(5, 1 + streak / 3) }

    var body: some View {
        switch phase {
        case .intro:
            GameIntro(
                tag: "test 1 of 3",
                title: "color match",
                skillLine: "does the top word's meaning match the color the bottom word is printed in? your brain will lie to you. answer fast anyway.",
                onStart: { phase = .tutorial }
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    wordCard(text: "blue", color: Color.witsInk, label: "meaning", labelAbove: true, compact: true)
                    wordCard(text: "green", color: gameInks[1].color, label: "text color", labelAbove: false, compact: true)
                    Text("this one's a \(Text("yes").foregroundStyle(Color.witsAccent)) — it says green, but it's printed in blue")
                        .font(.witsBody(12.5))
                        .foregroundStyle(Color.witsFaint)
                }
            }
        case .tutorial:
            tutorialView
        case .ready:
            GameReady {
                stats = ColorMatchStats()
                streak = 0
                trial = Self.makeTrial()
                phase = .playing
            }
        case .playing:
            playView
        }
    }

    private func wordCard(text: String, color: Color, label: String, labelAbove: Bool, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if labelAbove { cardLabel(label) }
            Text(text)
                .font(.system(size: compact ? 26 : 38, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .frame(maxWidth: compact ? nil : .infinity)
                .padding(.horizontal, compact ? 26 : 20)
                .padding(.vertical, compact ? 12 : 22)
                .cardSurface()
            if !labelAbove { cardLabel(label) }
        }
    }

    private func cardLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .kerning(0.7)
            .foregroundStyle(Color.witsFaint)
            .padding(.leading, 4)
    }

    private var tutorialView: some View {
        let t = Self.tutorialTrials[tutorialIndex]
        return VStack(spacing: 0) {
            GameTopTag(text: "tutorial · \(tutorialIndex + 1) of \(Self.tutorialTrials.count)")
            Spacer()
            trialCards(top: t.top, bottom: t.bottom, ink: gameInks[t.ink].color)
            Spacer()
            VStack(spacing: 14) {
                TutorialHint(text: tutorialError ? "not quite. \(t.hint)" : t.hint)
                answerButtons { saysMatch in
                    let isMatch = t.top == gameInks[t.ink].name
                    if saysMatch == isMatch {
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
            HStack(alignment: .firstTextBaseline) {
                Text("\(Text("\(stats.score)").foregroundStyle(Color.witsAccent)) pts")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                    .monospacedDigit()
                if multiplier > 1 {
                    Text("×\(multiplier)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.witsAccent.opacity(0.14), in: Capsule())
                }
                Spacer()
                Text("\(Int(ceil(timeLeft)))s")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsMuted)
                    .monospacedDigit()
            }
            ProgressTrack(fraction: timeLeft / Self.gameSeconds, animated: false)
            Spacer()
            if let trial {
                trialCards(top: trial.topWord, bottom: trial.bottomWord, ink: trial.ink)
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
            }
            Spacer()
            answerButtons { saysMatch in
                answer(saysMatch)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .task { await run() }
    }

    private func trialCards(top: String, bottom: String, ink: Color) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                cardLabel("meaning")
                Text(top)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .cardSurface()
            }
            VStack(spacing: 6) {
                Text(bottom)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .cardSurface()
                cardLabel("text color")
            }
        }
    }

    private func answerButtons(_ act: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 10) {
            Button { act(false) } label: {
                Text("no")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Color.witsTint, in: Capsule())
            }
            .buttonStyle(.plain)
            Button { act(true) } label: {
                Text("yes")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Color.witsAccent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func answer(_ saysMatch: Bool) {
        guard let current = trial, !finished else { return }
        let ok = saysMatch == current.match
        if ok {
            stats.right += 1
            streak += 1
            stats.bestStreak = max(stats.bestStreak, streak)
            stats.score += 100 * multiplier
        } else {
            stats.wrong += 1
            streak = 0
        }
        feedback = ok
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { feedback = nil }
        withAnimation(.easeOut(duration: 0.13)) {
            trial = Self.makeTrial()
        }
    }

    private func run() async {
        let start = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
            timeLeft = max(0, Self.gameSeconds - Date().timeIntervalSince(start))
            if timeLeft <= 0 {
                guard !finished else { return }
                finished = true
                try? await Task.sleep(for: .milliseconds(350))
                onComplete(stats)
                return
            }
        }
    }
}

// MARK: - Test 2: train of thought
// Colored trains leave the depot and roll through junctions toward colored
// stations. Tapping a junction flips which branch it sends trains down.
// Route each train to the station of its color.

struct TrainGameScreen: View {
    var onComplete: (TrainStats) -> Void

    private static let totalTrains = 14

    // ── track graph (unit coordinates) ──
    fileprivate struct Edge {
        let p0: CGPoint, c0: CGPoint, c1: CGPoint, p1: CGPoint
        let endJunction: Int?
        let endStation: Int?

        func point(_ t: Double) -> CGPoint {
            let u = 1 - t
            let x = u*u*u*p0.x + 3*u*u*t*c0.x + 3*u*t*t*c1.x + t*t*t*p1.x
            let y = u*u*u*p0.y + 3*u*u*t*c0.y + 3*u*t*t*c1.y + t*t*t*p1.y
            return CGPoint(x: x, y: y)
        }
    }

    fileprivate enum Track {
        static let src = CGPoint(x: 0.5, y: 0.05)
        static let j = [CGPoint(x: 0.5, y: 0.3), CGPoint(x: 0.26, y: 0.56), CGPoint(x: 0.74, y: 0.56)]
        static let stations = [
            CGPoint(x: 0.13, y: 0.88), CGPoint(x: 0.385, y: 0.88),
            CGPoint(x: 0.615, y: 0.88), CGPoint(x: 0.87, y: 0.88),
        ]
        static let edges: [Edge] = [
            // 0: depot → J0
            Edge(p0: src, c0: CGPoint(x: 0.5, y: 0.14), c1: CGPoint(x: 0.5, y: 0.21), p1: j[0], endJunction: 0, endStation: nil),
            // 1: J0 → J1 (left), 2: J0 → J2 (right)
            Edge(p0: j[0], c0: CGPoint(x: 0.5, y: 0.43), c1: CGPoint(x: 0.26, y: 0.43), p1: j[1], endJunction: 1, endStation: nil),
            Edge(p0: j[0], c0: CGPoint(x: 0.5, y: 0.43), c1: CGPoint(x: 0.74, y: 0.43), p1: j[2], endJunction: 2, endStation: nil),
            // 3: J1 → station 0, 4: J1 → station 1
            Edge(p0: j[1], c0: CGPoint(x: 0.26, y: 0.7), c1: CGPoint(x: 0.13, y: 0.72), p1: stations[0], endJunction: nil, endStation: 0),
            Edge(p0: j[1], c0: CGPoint(x: 0.26, y: 0.7), c1: CGPoint(x: 0.385, y: 0.72), p1: stations[1], endJunction: nil, endStation: 1),
            // 5: J2 → station 2, 6: J2 → station 3
            Edge(p0: j[2], c0: CGPoint(x: 0.74, y: 0.7), c1: CGPoint(x: 0.615, y: 0.72), p1: stations[2], endJunction: nil, endStation: 2),
            Edge(p0: j[2], c0: CGPoint(x: 0.74, y: 0.7), c1: CGPoint(x: 0.87, y: 0.72), p1: stations[3], endJunction: nil, endStation: 3),
        ]
        /// Outgoing edge indices per junction: [first branch, second branch].
        static let branches = [[1, 2], [3, 4], [5, 6]]
    }

    fileprivate struct TrainRun: Identifiable {
        let id = UUID()
        let target: Int
        var edge = 0
        var progress = 0.0
        var arrived = false
        var correct = false
    }

    @State private var phase = GamePhase.intro
    @State private var switches = [true, true, true]   // true = first branch
    @State private var trains: [TrainRun] = []
    @State private var stats = TrainStats()
    @State private var spawned = 0
    @State private var stationFlash: [Int: Bool] = [:]  // station -> correct?
    @State private var tutorialDone = false
    @State private var tutorialMessage = "tap a switch to bend the track. get the train to the station that matches its color."
    @State private var finished = false

    var body: some View {
        switch phase {
        case .intro:
            GameIntro(
                tag: "test 2 of 3",
                title: "train of thought",
                skillLine: "trains roll out one after another. flip the switches so every train reaches the station of its color. they will not wait for you.",
                onStart: { phase = .tutorial }
            ) {
                HStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(gameInks[i].color)
                            .frame(width: 40, height: 34)
                            .overlay(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(.white.opacity(0.85))
                                    .frame(width: 10, height: 12)
                                    .padding(.bottom, 3)
                            }
                    }
                }
            }
        case .tutorial:
            boardView(isTutorial: true)
        case .ready:
            GameReady {
                trains = []
                stats = TrainStats()
                spawned = 0
                finished = false
                phase = .playing
            }
        case .playing:
            boardView(isTutorial: false)
        }
    }

    private func boardView(isTutorial: Bool) -> some View {
        VStack(spacing: 12) {
            if isTutorial {
                GameTopTag(text: "tutorial")
                TutorialHint(text: tutorialMessage)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Text("\(stats.correct)").foregroundStyle(Color.witsAccent)) of \(Self.totalTrains) routed")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                        .monospacedDigit()
                    Spacer()
                    Text("\(stats.total) done")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.witsMuted)
                        .monospacedDigit()
                }
                ProgressTrack(fraction: Double(stats.total) / Double(Self.totalTrains), animated: true)
            }
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                        .fill(Color.witsCard)
                        .shadow(color: .witsShadow, radius: 10, y: 6)

                    // tracks
                    ForEach(0..<TrainGameScreen.Track.edges.count, id: \.self) { i in
                        trackPath(TrainGameScreen.Track.edges[i], in: size)
                            .stroke(
                                Color.witsLine.opacity(isActiveEdge(i) ? 1 : 0.45),
                                style: StrokeStyle(lineWidth: isActiveEdge(i) ? 7 : 5, lineCap: .round)
                            )
                    }

                    // depot
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.witsInk.opacity(0.75))
                        .frame(width: 44, height: 26)
                        .position(scaled(TrainGameScreen.Track.src, size))

                    // stations
                    ForEach(0..<4, id: \.self) { s in
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(gameInks[s].color)
                            .frame(width: 46, height: 38)
                            .overlay(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(.white.opacity(0.85))
                                    .frame(width: 11, height: 14)
                                    .padding(.bottom, 3)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(
                                        stationFlash[s] == true ? Color.witsAccent
                                            : stationFlash[s] == false ? Color.witsWarm : .clear,
                                        lineWidth: 3
                                    )
                                    .padding(-5)
                            )
                            .position(scaled(TrainGameScreen.Track.stations[s], size))
                    }

                    // junction switches
                    ForEach(0..<3, id: \.self) { jIdx in
                        Button {
                            switches[jIdx].toggle()
                        } label: {
                            Image(systemName: switches[jIdx] ? "arrow.turn.down.left" : "arrow.turn.down.right")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.witsAccent, in: Circle())
                                .shadow(color: .witsAccent.opacity(0.4), radius: 6, y: 3)
                        }
                        .buttonStyle(.plain)
                        .position(scaled(TrainGameScreen.Track.j[jIdx], size))
                        .animation(.easeOut(duration: 0.12), value: switches[jIdx])
                    }

                    // trains
                    ForEach(trains) { train in
                        if !train.arrived {
                            let edge = TrainGameScreen.Track.edges[train.edge]
                            Circle()
                                .fill(gameInks[train.target].color)
                                .frame(width: 24, height: 24)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                                .shadow(color: .witsShadow, radius: 4, y: 2)
                                .position(scaled(edge.point(train.progress), size))
                        }
                    }
                }
            }
            Text(isTutorial ? "trains check the switch when they reach it" : "every train to its own color")
                .font(.witsBody(12.5))
                .foregroundStyle(Color.witsFaint)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .task(id: phase == .tutorial) { await run(isTutorial: isTutorial) }
    }

    private func scaled(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: p.x * size.width, y: p.y * size.height)
    }

    private func trackPath(_ edge: TrainGameScreen.Edge, in size: CGSize) -> Path {
        Path { p in
            p.move(to: scaled(edge.p0, size))
            p.addCurve(to: scaled(edge.p1, size),
                       control1: scaled(edge.c0, size),
                       control2: scaled(edge.c1, size))
        }
    }

    /// Edge 0 is always active; branch edges are active when their junction points at them.
    private func isActiveEdge(_ i: Int) -> Bool {
        switch i {
        case 0: return true
        case 1: return switches[0]
        case 2: return !switches[0]
        case 3: return switches[1]
        case 4: return !switches[1]
        case 5: return switches[2]
        default: return !switches[2]
        }
    }

    private func spawnTrain() {
        trains.append(TrainRun(target: Int.random(in: 0..<4)))
        spawned += 1
    }

    private func arrival(_ index: Int, station: Int) {
        trains[index].arrived = true
        let correct = trains[index].target == station
        trains[index].correct = correct
        stationFlash[station] = correct
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            stationFlash[station] = nil
        }
    }

    private func run(isTutorial: Bool) async {
        let tick = 0.016
        var sinceSpawn = 10.0
        var elapsed = 0.0

        if isTutorial {
            tutorialDone = false
            trains = []
        }

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            elapsed += tick
            sinceSpawn += tick

            // spawning
            if isTutorial {
                if trains.allSatisfy(\.arrived) && sinceSpawn > 1.0 && !tutorialDone {
                    spawnTrain()
                    sinceSpawn = 0
                }
            } else if spawned < Self.totalTrains && sinceSpawn >= 2.3 {
                spawnTrain()
                sinceSpawn = 0
            }

            // movement
            let edgeDuration = isTutorial ? 2.2 : max(1.1, 1.6 - elapsed * 0.012)
            for i in trains.indices where !trains[i].arrived {
                trains[i].progress += tick / edgeDuration
                while trains[i].progress >= 1, !trains[i].arrived {
                    let edge = TrainGameScreen.Track.edges[trains[i].edge]
                    if let jIdx = edge.endJunction {
                        let nextEdge = TrainGameScreen.Track.branches[jIdx][switches[jIdx] ? 0 : 1]
                        trains[i].edge = nextEdge
                        trains[i].progress -= 1
                    } else if let station = edge.endStation {
                        let wasCorrectTarget = trains[i].target == station
                        arrival(i, station: station)
                        if isTutorial {
                            if wasCorrectTarget {
                                tutorialDone = true
                                tutorialMessage = "that's it. now they come faster, and they don't stop."
                            } else {
                                tutorialMessage = "missed it — flip the switches before the train reaches them. here comes another."
                            }
                        } else {
                            stats.total += 1
                            if wasCorrectTarget { stats.correct += 1 }
                        }
                    }
                }
            }

            // end conditions
            if isTutorial {
                if tutorialDone, trains.allSatisfy(\.arrived) {
                    try? await Task.sleep(for: .milliseconds(900))
                    phase = .ready
                    return
                }
            } else if stats.total >= Self.totalTrains {
                guard !finished else { return }
                finished = true
                try? await Task.sleep(for: .milliseconds(400))
                onComplete(stats)
                return
            }
        }
    }
}

// MARK: - Test 3: memory matrix
// Tiles flash, then vanish; tap where they were. Difficulty adapts —
// perfect recall adds a tile, a miss removes one. 10 trials.

struct MemoryMatrixScreen: View {
    var onComplete: (MatrixStats) -> Void

    private static let totalTrials = 10
    private static let columns = 4

    private enum MatrixPhase {
        case interstitial, show, recall, reveal
    }

    @State private var phase = GamePhase.intro
    @State private var trialPhase = MatrixPhase.interstitial
    @State private var inTutorial = false
    @State private var trial = 0
    @State private var tiles = 3
    @State private var lit: Set<Int> = []
    @State private var taps: [Int] = []
    @State private var stats = MatrixStats()
    @State private var generation = 0

    private var rows: Int { tiles <= 3 ? 3 : tiles <= 5 ? 4 : 5 }
    private var cellCount: Int { rows * Self.columns }

    var body: some View {
        switch phase {
        case .intro:
            GameIntro(
                tag: "test 3 of 3",
                title: "memory matrix",
                skillLine: "tiles light up, then vanish. tap where they were. get them all and the board grows. miss and it shrinks. ten rounds.",
                onStart: {
                    inTutorial = true
                    startTrial(reset: true)
                    phase = .tutorial
                }
            ) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 6), count: 4), spacing: 6) {
                    ForEach(0..<12, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill([1, 4, 6, 11].contains(i) ? Color.witsAccent : Color.witsTint)
                            .frame(width: 40, height: 40)
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

    private var board: some View {
        VStack(spacing: 12) {
            if inTutorial {
                GameTopTag(text: "tutorial")
                TutorialHint(text: trialPhase == .recall
                    ? "now tap the \(lit.count) tiles that were lit."
                    : "watch closely — the tiles only flash once.")
            } else {
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
                        Text("TILES")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .kerning(1.5)
                            .foregroundStyle(Color.witsMuted)
                        Text("\(tiles)")
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
    }

    private var statusLine: String {
        switch trialPhase {
        case .interstitial: return "get ready"
        case .show: return "\(tiles) tiles. watch."
        case .recall: return "tap \(lit.count) tiles from memory"
        case .reveal: return taps.filter { lit.contains($0) }.count == lit.count ? "perfect. board grows." : "missed some. board shrinks."
        }
    }

    private var gridView: some View {
        GeometryReader { geo in
            let gap: CGFloat = 8
            let cellW = (geo.size.width - 28 - gap * CGFloat(Self.columns - 1)) / CGFloat(Self.columns)
            let cellH = (geo.size.height - 28 - gap * CGFloat(rows - 1)) / CGFloat(rows)
            let side = min(cellW, cellH)
            VStack(spacing: gap) {
                ForEach(0..<rows, id: \.self) { r in
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
        let isLitShown = trialPhase == .show && lit.contains(i)
        let tapped = taps.contains(i)
        let wasRight = tapped && lit.contains(i)
        let missed = trialPhase == .reveal && lit.contains(i) && !taps.contains(i)
        let fill: Color = isLitShown ? .witsAccent
            : tapped ? (wasRight ? Color.witsAccent.opacity(0.85) : Color.witsWarm.opacity(0.7))
            : .witsTint
        return Button {
            tapCell(i)
        } label: {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(missed ? Color.witsAccent : .clear, lineWidth: 2.5)
                )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.13), value: isLitShown)
        .animation(.easeOut(duration: 0.13), value: tapped)
        .animation(.easeOut(duration: 0.13), value: missed)
    }

    private func startTrial(reset: Bool) {
        if reset {
            stats = MatrixStats()
            tiles = 3
            trial = 1
        }
        generation += 1
        let gen = generation
        var cells: Set<Int> = []
        while cells.count < tiles {
            cells.insert(Int.random(in: 0..<cellCount))
        }
        lit = cells
        taps = []
        trialPhase = .interstitial
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard generation == gen else { return }
            trialPhase = .show
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
                guard generation == gen else { return }
                trialPhase = .recall
            }
        }
    }

    private func tapCell(_ i: Int) {
        guard trialPhase == .recall, !taps.contains(i) else { return }
        taps.append(i)
        guard taps.count == lit.count else { return }

        let correct = taps.filter { lit.contains($0) }.count
        let perfect = correct == lit.count
        if !inTutorial {
            stats.correctTiles += correct
            stats.totalTiles += lit.count
            stats.trials += 1
            if perfect { stats.perfectTrials += 1 }
            stats.maxTiles = max(stats.maxTiles, tiles)
            stats.score += correct * 150 + (perfect ? 450 : 0)
        }
        trialPhase = .reveal

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            if inTutorial {
                phase = .ready
                return
            }
            tiles = perfect ? min(7, tiles + 1) : max(2, tiles - 1)
            if trial >= Self.totalTrials {
                onComplete(stats)
            } else {
                trial += 1
                startTrial(reset: false)
            }
        }
    }
}
