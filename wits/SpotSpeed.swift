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

struct SpotSpeedScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private static let totalTrials = 14
    private static let slots = 8

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
    private let startedAt = Date()

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        _presentationMs = State(initialValue: max(120, 600 - cfg.difficulty.level * 40))
    }

    var body: some View {
        VStack(spacing: 12) {
            if !cfg.isSurvival {
                HStack(alignment: .firstTextBaseline) {
                    Text("spot \(Text("\(min(trial, Self.totalTrials))").foregroundStyle(Color.witsAccent)) of \(Self.totalTrials)")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                        .monospacedDigit()
                    Spacer()
                    Text("\(score) pts")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsMuted)
                        .monospacedDigit()
                }
                ProgressTrack(fraction: Double(trial - 1) / Double(Self.totalTrials), animated: true)
            }

            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let radius = side * 0.38
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                ZStack {
                    RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                        .fill(Color.witsCard)
                        .shadow(color: .witsShadow, radius: 10, y: 6)
                    centerView.position(center)
                    ForEach(0..<Self.slots, id: \.self) { i in
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
                .font(.system(size: 30, weight: .heavy))
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
        let angle = Double(i) / Double(Self.slots) * 2 * .pi - .pi / 2
        return CGPoint(x: center.x + radius * Darwin.cos(angle),
                       y: center.y + radius * Darwin.sin(angle))
    }

    @ViewBuilder private func slotView(_ i: Int) -> some View {
        switch step {
        case .stimulus:
            Circle()
                .fill(i == targetSlot ? Color.witsAccent : Color.witsLine)
                .frame(width: i == targetSlot ? 26 : 12, height: i == targetSlot ? 26 : 12)
                .shadow(color: i == targetSlot ? Color.witsAccent.opacity(0.6) : .clear, radius: 7)
        case .mask:
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.witsFaint.opacity(0.5))
                .frame(width: 24, height: 24)
        case .askPeriph:
            Button { pickSlot(i) } label: {
                Circle()
                    .strokeBorder(Color.witsAccent, lineWidth: 2)
                    .background(Circle().fill(Color.witsAccent.opacity(0.08)))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        case .feedback:
            Circle()
                .fill(i == targetSlot ? Color.witsAccent : Color.clear)
                .frame(width: 22, height: 22)
        default:
            Circle().fill(Color.witsLine).frame(width: 10, height: 10)
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
        targetSlot = Int.random(in: 0..<Self.slots)
        centerIsCar = Bool.random()
        centerAnswer = nil
        lastCorrect = nil
        step = .fixation
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard gen == generation else { return }
            step = .stimulus
            try? await Task.sleep(for: .milliseconds(Int(presentationMs)))
            guard gen == generation else { return }
            step = .mask
            try? await Task.sleep(for: .milliseconds(250))
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
        let bothRight = (centerAnswer == centerIsCar) && (i == targetSlot)
        lastCorrect = bothRight
        if bothRight {
            correct += 1
            score += 100 + max(0, Int((600 - presentationMs) / 4))
            presentationMs = max(80, presentationMs * 0.85)   // faster = harder
            cfg.report(.hit, points: 100, combo: correct)
        } else {
            presentationMs = min(700, presentationMs * 1.18)
            // peripheral landed one slot off the target → "so close"
            let ringNear = (centerAnswer == centerIsCar) && (abs(i - targetSlot) == 1 || abs(i - targetSlot) == Self.slots - 1)
            cfg.report(ringNear ? .nearMiss : .miss)
        }
        step = .feedback
        let gen = generation
        Task {
            try? await Task.sleep(for: .milliseconds(cfg.isSurvival ? 450 : 900))
            guard gen == generation else { return }
            if !cfg.isSurvival && trial >= Self.totalTrials {
                finish()
            } else {
                trial += 1
                startTrial()
            }
        }
    }

    private func finish() {
        let acc = Double(correct) / Double(Self.totalTrials)
        var r = GameResult(game: .spotSpeed, score: score, accuracy: acc)
        r.trials = Self.totalTrials
        r.threshold = presentationMs   // converged flash duration (ms)
        r.startedAt = startedAt
        r.raw = ["thresholdMs": presentationMs]
        onResult(r)
    }
}
