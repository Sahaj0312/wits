//
//  ArcadeGameView.swift
//  wits
//
//  The shared host for every arcade game: owns the display-synced loop, spawning
//  + escalation, the field Canvas, gesture overlay, juice, and ALL engine
//  plumbing. Each decision flows through cfg.report (juice in workout, outcome
//  stream to SurvivalHost in survival). On a workout timeout it builds the
//  GameResult; in survival it loops forever and never self-ends.
//

import SwiftUI

struct ArcadeGameView: View {
    let cfg: GameConfig
    let game: any ArcadeGame
    let onResult: (GameResult) -> Void

    @State private var scene = ArcadeScene()
    @State private var base = Spawner()
    @State private var started = false
    @State private var finished = false

    @State private var hits = 0
    @State private var misses = 0
    @State private var near = 0
    @State private var score = 0
    @State private var combo = 0
    @State private var bestCombo = 0
    @State private var timeLeft = 45.0

    @State private var shakeTick = 0
    @State private var flashTick = 0
    @State private var burstTick = 0
    @State private var showHowTo = true

    private let startedAt = Date()

    private var multiplier: Int { min(6, 1 + combo / 3) }

    var body: some View {
        VStack(spacing: 10) {
            if !cfg.isSurvival {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Text("\(score)").foregroundStyle(Color.witsAccent)) pts")
                        .font(.system(size: 17, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Color.witsInk)
                    if multiplier > 1 {
                        Text("×\(multiplier)")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.witsAccent)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.witsAccent.opacity(0.14), in: Capsule())
                    }
                    Spacer()
                    Text("\(Int(ceil(timeLeft)))s")
                        .font(.system(size: 17, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Color.witsMuted)
                }
                .padding(.horizontal, WitsMetrics.screenPadding)
                ProgressTrack(fraction: max(0, timeLeft / cfg.targetDurationSec), animated: false)
                    .padding(.horizontal, WitsMetrics.screenPadding)
            }

            GeometryReader { geo in
                ZStack {
                    ArcadeArena()
                        .clipShape(RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous))
                        .shadow(color: .witsShadow, radius: 10, y: 6)

                    field(size: geo.size)

                    game.overlay(scene: scene)

                    ArcadeInputLayer(mode: game.inputMode, scene: scene, onAction: handle)

                    if showHowTo {
                        Text(game.howTo)
                            .font(.witsBody(15, weight: .semibold))
                            .foregroundStyle(Color.witsInk)
                            .multilineTextAlignment(.center)
                            .padding(18)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal, 30)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous))
                .onAppear {
                    scene.bounds = geo.size
                    if !started { started = true; bootstrap() }
                }
            }
            .padding(.horizontal, cfg.isSurvival ? 0 : WitsMetrics.screenPadding)
        }
        .padding(.bottom, 12)
        .padding(.top, cfg.isSurvival ? 0 : 18)
        .witsShake(trigger: shakeTick)
        .witsFlash(.witsWarm, trigger: flashTick)
    }

    @ViewBuilder
    private func field(size: CGSize) -> some View {
        TimelineView(.animation(paused: finished || showHowTo)) { tl in
            Canvas { ctx, sz in
                let m = min(sz.width, sz.height)
                for e in scene.entities where !e.dead {
                    let c = CGPoint(x: e.pos.x * sz.width, y: e.pos.y * sz.height)
                    let r = e.radius * m
                    let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                    game.draw(e, into: &ctx, rect: rect, scene: scene)
                }
            }
            .onChange(of: tl.date) { old, new in
                tick(new.timeIntervalSince(old))
            }
        }
    }

    // MARK: Loop

    private func bootstrap() {
        base = game.seed(level: cfg.difficulty.level, survival: cfg.isSurvival)
        scene.spawner = base
        timeLeft = cfg.targetDurationSec
        // brief how-to, then go
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { showHowTo = false }
    }

    private func tick(_ rawDt: Double) {
        guard !finished, !showHowTo else { return }
        let dt = min(max(rawDt, 0), 0.1)         // clamp first-frame / background spikes
        guard dt > 0 else { return }

        game.preStep(scene: scene, dt: dt)

        // escalate, then spawn
        Escalation.apply(&scene.spawner, base: base, runTime: scene.runTime, combo: combo, survival: cfg.isSurvival)
        scene.spawner.acc += dt * scene.spawner.rate
        while scene.spawner.acc >= 1, scene.aliveCount < scene.spawner.maxAlive {
            scene.spawner.acc -= 1
            game.spawn(into: scene, params: scene.spawner)
        }

        scene.integrate(dt)

        for r in game.postStep(scene: scene, dt: dt) { emit(r) }
        scene.entities.removeAll { $0.dead }

        if !cfg.isSurvival {
            timeLeft -= dt
            if timeLeft <= 0 { finish() }
        }
    }

    private func handle(_ action: ArcadeAction) {
        guard !finished, !showHowTo, let r = game.resolve(action, scene: scene) else { return }
        emit(r)
    }

    private func emit(_ r: Resolution) {
        switch r.kind {
        case .hit:
            hits += 1; combo += 1; bestCombo = max(bestCombo, combo)
            score += r.points * multiplier
            burstTick += 1
        case .nearMiss:
            near += 1; combo = 0; flashTick += 1
        case .miss:
            misses += 1; combo = 0; shakeTick += 1; flashTick += 1
        case .timeout:
            misses += 1; combo = 0; shakeTick += 1
        }
        cfg.report(r.kind, points: r.points, combo: combo)
    }

    private func finish() {
        guard !finished, !cfg.isSurvival else { return }
        finished = true
        let total = hits + misses + near
        var res = GameResult(game: game.id, score: score,
                             accuracy: total > 0 ? Double(hits) / Double(total) : 0)
        res.trials = total
        res.threshold = scene.spawner.speed
        res.startedAt = startedAt
        res.durationMs = Int(cfg.targetDurationSec * 1000)
        res.raw = ["bestStreak": Double(bestCombo)]
        onResult(res)
    }
}
