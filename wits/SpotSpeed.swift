//
//  SpotSpeed.swift
//  wits
//
//  Useful-Field-of-View (UFOV) — the speed-of-processing paradigm with the
//  strongest real-world transfer evidence (the ACTIVE trial). A central target
//  to identify AND a peripheral target to locate are flashed together, then
//  masked. Adaptive: the flash duration (ms) staircases toward threshold.
//

import SwiftUI

enum SpotSpeedTuning {
    static let totalTrials = 18
    static let minPresentationMs = 60.0
    static let maxPresentationMs = 420.0
    static let thresholdSampleWindow = 6

    private static let startingMsByLevel: [Double] = [380, 330, 285, 245, 210, 180, 150, 125, 105, 90]

    static func initialPresentationMs(for level: Double) -> Double {
        let clamped = clampedLevel(level)
        let lowerIndex = Int(floor(clamped)) - 1
        let upperIndex = min(startingMsByLevel.count - 1, lowerIndex + 1)
        let fraction = clamped - floor(clamped)
        let lower = startingMsByLevel[max(0, lowerIndex)]
        let upper = startingMsByLevel[upperIndex]
        return max(minPresentationMs, lower + (upper - lower) * fraction)
    }

    static func stimulationLevel(for level: Double) -> Int {
        min(10, max(1, Int(clampedLevel(level).rounded(.toNearestOrAwayFromZero))))
    }

    static func slotCount(for level: Double) -> Int {
        min(14, max(8, 7 + stimulationLevel(for: level)))
    }

    static func intensity(for level: Double) -> Double {
        (clampedLevel(level) - 1) / 9
    }

    private static func clampedLevel(_ level: Double) -> Double {
        min(10, max(1, level.isFinite ? level : 1))
    }
}

struct SpotSpeedScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private enum Step { case fixation, stimulus, mask, askCenter, askPeriph, feedback }

    @State private var step: Step = .fixation
    @State private var presentationMs: Double
    @State private var targetSlot = 0
    @State private var centerIsCar = true
    @State private var centerAnswer: Bool?
    @State private var lastCorrect: Bool?
    @State private var trial = 1
    @State private var correct = 0
    @State private var score = 0
    @State private var generation = 0
    @State private var thresholdSamples: [Double] = []
    private let initialPresentationMs: Double
    private let stimulationLevel: Int
    private let difficultyIntensity: Double
    private let slotCount: Int
    private let startedAt = Date()

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        let level = cfg.difficulty.level
        let initialMs = SpotSpeedTuning.initialPresentationMs(for: level)
        let stimulation = SpotSpeedTuning.stimulationLevel(for: level)
        self.initialPresentationMs = initialMs
        self.stimulationLevel = stimulation
        self.difficultyIntensity = SpotSpeedTuning.intensity(for: level)
        self.slotCount = SpotSpeedTuning.slotCount(for: level)
        _presentationMs = State(initialValue: initialMs)
    }

    var body: some View {
        VStack(spacing: 12) {
            if !cfg.isSurvival {
                HStack(alignment: .firstTextBaseline) {
                    Text("spot \(Text("\(min(trial, SpotSpeedTuning.totalTrials))").foregroundStyle(Color.witsAccent)) of \(SpotSpeedTuning.totalTrials)")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                        .monospacedDigit()
                    Spacer()
                    Text("\(score) pts")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsMuted)
                        .monospacedDigit()
                }
                ProgressTrack(fraction: Double(trial - 1) / Double(SpotSpeedTuning.totalTrials), animated: true)
            }

            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let radius = side * 0.38
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                ZStack {
                    RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                        .fill(Color.witsCard)
                        .shadow(color: .witsShadow, radius: 10, y: 6)
                    if showsClutter {
                        ForEach(0..<clutterCount, id: \.self) { i in
                            clutterView(i)
                                .position(clutterPosition(i, center: center, radius: radius))
                        }
                    }
                    centerView.position(center)
                    ForEach(0..<slotCount, id: \.self) { i in
                        slotView(i)
                            .position(slotPosition(i, center: center, radius: radius))
                    }
                }
            }

            statusBar
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .onAppear { if step == .fixation { startTrial() } }
    }

    // MARK: Center

    @ViewBuilder private var centerView: some View {
        switch step {
        case .fixation:
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Color.witsFaint)
        case .stimulus:
            Image(systemName: centerIsCar ? "car.fill" : "bus.fill")
                .font(.system(size: centerSymbolSize, weight: .heavy))
                .foregroundStyle(Color.witsInk)
        case .mask:
            Image(systemName: "number.square.fill")
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(Color.witsFaint)
        default:
            EmptyView()
        }
    }

    // MARK: Slots

    private func slotPosition(_ i: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = Double(i) / Double(slotCount) * 2 * .pi - .pi / 2
        return CGPoint(x: center.x + radius * Darwin.cos(angle),
                       y: center.y + radius * Darwin.sin(angle))
    }

    @ViewBuilder private func slotView(_ i: Int) -> some View {
        switch step {
        case .stimulus:
            let isTarget = i == targetSlot
            let size = isTarget ? targetDotSize : distractorDotSize(for: i)
            Circle()
                .fill(stimulusColor(forSlot: i))
                .frame(width: size, height: size)
                .overlay {
                    Circle()
                        .strokeBorder(isTarget ? Color.witsInk.opacity(0.18) : Color.clear, lineWidth: 1)
                }
                .shadow(color: isTarget ? Color.witsAccent.opacity(targetGlowOpacity) : .clear, radius: targetGlowRadius)
        case .mask:
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.witsFaint.opacity(0.5))
                .frame(width: maskSize, height: maskSize)
        case .askPeriph:
            Button { pickSlot(i) } label: {
                Circle()
                    .strokeBorder(Color.witsAccent, lineWidth: 2)
                    .background(Circle().fill(Color.witsAccent.opacity(0.08)))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("slot \(i + 1)")
        case .feedback:
            Circle()
                .fill(i == targetSlot ? Color.witsAccent : Color.clear)
                .frame(width: 22, height: 22)
        default:
            Circle().fill(Color.witsLine).frame(width: 10, height: 10)
        }
    }

    @ViewBuilder private func clutterView(_ i: Int) -> some View {
        if step == .mask {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.witsFaint.opacity(0.36 + Double(i % 3) * 0.08))
                .frame(width: maskClutterSize(for: i), height: maskClutterSize(for: i))
        } else if i % 3 == 0 {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(clutterColor(for: i))
                .frame(width: clutterSize(for: i), height: clutterSize(for: i))
        } else {
            Circle()
                .fill(clutterColor(for: i))
                .frame(width: clutterSize(for: i), height: clutterSize(for: i))
        }
    }

    // MARK: Status / answer UI

    @ViewBuilder private var statusBar: some View {
        switch step {
        case .askCenter:
            VStack(spacing: 10) {
                Text("which was in the middle?")
                    .font(.witsBody(14, weight: .semibold))
                    .foregroundStyle(Color.witsMuted)
                HStack(spacing: 10) {
                    vehicleButton(isCar: true)
                    vehicleButton(isCar: false)
                }
            }
        case .askPeriph:
            Text("now tap where the dot flashed")
                .font(.witsBody(13))
                .foregroundStyle(Color.witsFaint)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
        case .feedback:
            Text(lastCorrect == true ? "nice — both right" : "close. watch the edges")
                .font(.witsBody(14, weight: .semibold))
                .foregroundStyle(lastCorrect == true ? Color.witsAccent : Color.witsWarm)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
        default:
            Text("watch the middle and the edges")
                .font(.witsBody(13))
                .foregroundStyle(Color.witsFaint)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
        }
    }

    private func vehicleButton(isCar: Bool) -> some View {
        Button { answerCenter(isCar) } label: {
            Image(systemName: isCar ? "car.fill" : "bus.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Color.witsInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.witsTint, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Flow

    private func startTrial() {
        generation += 1
        let gen = generation
        targetSlot = Int.random(in: 0..<slotCount)
        centerIsCar = Bool.random()
        centerAnswer = nil
        lastCorrect = nil
        step = .fixation
        Task {
            await cfg.sleepActive(milliseconds: 450)
            guard gen == generation else { return }
            step = .stimulus
            await cfg.sleepActive(milliseconds: Int(presentationMs))
            guard gen == generation else { return }
            step = .mask
            await cfg.sleepActive(milliseconds: 250)
            guard gen == generation else { return }
            step = .askCenter
        }
    }

    private func answerCenter(_ isCar: Bool) {
        guard step == .askCenter else { return }
        centerAnswer = isCar
        step = .askPeriph
    }

    private func pickSlot(_ i: Int) {
        guard step == .askPeriph else { return }
        let trialPresentationMs = presentationMs
        thresholdSamples.append(trialPresentationMs)
        if thresholdSamples.count > SpotSpeedTuning.thresholdSampleWindow {
            thresholdSamples.removeFirst(thresholdSamples.count - SpotSpeedTuning.thresholdSampleWindow)
        }

        let bothRight = (centerAnswer == centerIsCar) && (i == targetSlot)
        lastCorrect = bothRight
        if bothRight {
            correct += 1
            score += 100 + max(0, Int((SpotSpeedTuning.maxPresentationMs - trialPresentationMs) / 2.6))
            presentationMs = max(SpotSpeedTuning.minPresentationMs, trialPresentationMs * 0.84)   // faster = harder
            cfg.report(.hit, points: 100, combo: correct)
        } else {
            presentationMs = min(SpotSpeedTuning.maxPresentationMs, trialPresentationMs * 1.08)
            // peripheral landed one slot off the target → "so close"
            let ringNear = (centerAnswer == centerIsCar) && (abs(i - targetSlot) == 1 || abs(i - targetSlot) == slotCount - 1)
            cfg.report(ringNear ? .nearMiss : .miss)
        }
        step = .feedback
        let gen = generation
        Task {
            await cfg.sleepActive(milliseconds: cfg.isSurvival ? 450 : 900)
            guard gen == generation else { return }
            if !cfg.isSurvival && trial >= SpotSpeedTuning.totalTrials {
                finish()
            } else {
                trial += 1
                startTrial()
            }
        }
    }

    private func finish() {
        let acc = Double(correct) / Double(SpotSpeedTuning.totalTrials)
        let thresholdMs = estimatedThresholdMs
        var r = GameResult(game: .spotSpeed, score: score, accuracy: acc)
        r.trials = SpotSpeedTuning.totalTrials
        r.threshold = thresholdMs   // recent median flash duration (ms)
        r.startedAt = startedAt
        r.raw = [
            "thresholdMs": thresholdMs,
            "finalPresentationMs": presentationMs,
            "initialPresentationMs": initialPresentationMs,
            "stimulationLevel": Double(stimulationLevel),
            "difficultyIntensity": difficultyIntensity,
            "slotCount": Double(slotCount)
        ]
        onResult(r)
    }

    private var showsClutter: Bool {
        step == .stimulus || step == .mask
    }

    private var clutterCount: Int {
        6 + stimulationLevel * 4 + max(0, slotCount - 8) * 2
    }

    private var centerSymbolSize: CGFloat {
        CGFloat(max(20, 34 - difficultyIntensity * 13))
    }

    private var targetDotSize: CGFloat {
        CGFloat(max(13, 22 - difficultyIntensity * 8))
    }

    private func distractorDotSize(for i: Int) -> CGFloat {
        CGFloat(16 + difficultyIntensity * 5 + Double((i + trial) % 3))
    }

    private var targetGlowOpacity: Double {
        max(0, 0.24 - difficultyIntensity * 0.28)
    }

    private var targetGlowRadius: CGFloat {
        CGFloat(max(0, 4 - difficultyIntensity * 5))
    }

    private var maskSize: CGFloat {
        CGFloat(22 + difficultyIntensity * 10)
    }

    private func stimulusColor(forSlot i: Int) -> Color {
        if i == targetSlot {
            return Color.witsAccent.opacity(0.72 - difficultyIntensity * 0.16)
        }
        if stimulationLevel >= 3 && (i + trial) % 3 == 0 {
            return Color.witsAccent.opacity(0.24 + difficultyIntensity * 0.18)
        }
        return Color.witsFaint.opacity(0.38 + difficultyIntensity * 0.18 + Double((i + trial) % 3) * 0.04)
    }

    private func clutterColor(for i: Int) -> Color {
        if stimulationLevel >= 2 && (i + trial) % 4 == 0 {
            return Color.witsAccent.opacity(0.18 + difficultyIntensity * 0.20)
        }
        return Color.witsFaint.opacity(0.24 + difficultyIntensity * 0.16 + Double(i % 4) * 0.035)
    }

    private func clutterSize(for i: Int) -> CGFloat {
        CGFloat(6 + difficultyIntensity * 7 + Double((i % 3) * 2))
    }

    private func maskClutterSize(for i: Int) -> CGFloat {
        CGFloat(14 + difficultyIntensity * 12 + Double((i % 3) * 3))
    }

    private func clutterPosition(_ i: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = (Double(i) * 0.61803398875 + Double(trial) * 0.11) * 2 * .pi
        let band = [0.45, 0.66, 0.88, 1.16][i % 4]
        let distance = radius * CGFloat(band)
        return CGPoint(x: center.x + distance * CGFloat(Darwin.cos(angle)),
                       y: center.y + distance * CGFloat(Darwin.sin(angle)))
    }

    private var estimatedThresholdMs: Double {
        let samples = Array(thresholdSamples.suffix(SpotSpeedTuning.thresholdSampleWindow))
        guard !samples.isEmpty else { return presentationMs }
        let sorted = samples.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
