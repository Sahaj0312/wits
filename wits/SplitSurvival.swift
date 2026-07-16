//
//  SplitSurvival.swift
//  wits
//
//  "split" — a survival-only divided-attention game. The screen splits LEFT /
//  RIGHT: left thumb keeps a flappy-style flyer alive; right thumb works a
//  go/no-go stream — tap the target, never the look-alike, don't let a target
//  slip by. One mistake of any kind ends the run. Levels are time-gated and
//  grow longer + harder. This mode is standalone: it records its own best run,
//  but it does not feed WPI, mastery, or adaptive difficulty.
//

import SwiftUI

// MARK: - Model

private struct Pipe { var x: CGFloat; var gapY: CGFloat; var gapH: CGFloat }

private struct Emoji {
    var id: Int
    var x: CGFloat        // unit of full width (0…1), lives in the right zone
    var y: CGFloat        // unit of full height (0…1)
    var isTarget: Bool
    var age: Double = 0
    var ttl: Double
    var tapped: Bool = false
}

/// All the live game state + the per-frame step. Plain class (not Observable):
/// the TimelineView redraws every frame and reads these fields directly.
@MainActor
final class SplitGame {
    // The fixed look-alike pair for the run (similar, but resolvable with a look).
    let target = "🍎"
    let lookAlike = "🍅"

    // Geometry (unit of the play area). The screen splits at `splitX`.
    let splitX: CGFloat = 0.5          // vertical divider; left = fly, right = pick
    let birdX: CGFloat = 0.14          // flyer x within the left zone
    let birdRx: CGFloat = 0.03         // collision radius, width units
    let birdRy: CGFloat = 0.032        // collision radius, height units
    let pipeW: CGFloat = 0.085         // pipe width, width units

    // Flight feel — CONSTANT across levels (only the course gets harder).
    let gravity: CGFloat = 2.2
    let flapV: CGFloat = -0.86

    // State
    private(set) var birdY: CGFloat = 0.42
    private(set) var birdV: CGFloat = 0
    /// Smoothed nose angle (radians) the renderer draws. Chases the
    /// velocity-derived target so a flap swoops the nose up instead of
    /// snapping it in a single frame.
    private(set) var displayPitch: Double = 0
    private var pipes: [Pipe] = []
    private var emojis: [Emoji] = []
    private(set) var level = 1
    private(set) var levelElapsed: Double = 0
    private(set) var totalElapsed: Double = 0
    private(set) var alive = true
    private(set) var started = false        // bird hovers until the first flap
    private(set) var deathReason = ""
    private(set) var trials = 0

    private var sincePipe: CGFloat = .greatestFiniteMagnitude  // force an early first pipe
    private var sinceEmoji: Double = 0.5
    private var nextID = 0
    private let fixedSeed: UInt64?
    private var rng: SeededRandomNumberGenerator
    private var lastTick: Date?

    init(seed: UInt64? = nil) {
        fixedSeed = seed
        if let seed {
            rng = SeededRandomNumberGenerator(seed: seed)
        } else {
            var system = SystemRandomNumberGenerator()
            rng = SeededRandomNumberGenerator(seed: system.next())
        }
    }

    // Escalation: difficulty saturates around level 13 (k caps at 12).
    private func k() -> CGFloat { CGFloat(min(level - 1, 12)) }
    private var scrollSpeed: CGFloat { 0.22 + 0.020 * k() }            // 0.22 → 0.46 /s
    private var gapH: CGFloat { 0.42 - 0.018 * k() }                  // 0.42 → 0.20
    private var pipeSpacing: CGFloat { 0.46 - 0.015 * k() }           // width units between pipes
    private var emojiInterval: Double { 2.9 - 0.13 * Double(k()) }    // 2.9 → 1.34 s
    private var emojiTTL: Double { 2.7 - 0.12 * Double(k()) }         // 2.7 → 1.26 s
    private var forbiddenProb: Double { 0.16 + 0.013 * Double(k()) }  // 0.16 → 0.32
    /// Seconds to clear the current level — short early, growing each level.
    func timeForLevel(_ l: Int) -> Double { 12 + 3 * Double(l - 1) }

    /// How far into the current level the run ended (0…1) — the secondary signal
    /// the domain score uses to break ties between equal levels reached.
    var depthIntoLevel: Double { min(1, levelElapsed / timeForLevel(level)) }

    func reset() {
        birdY = 0.42; birdV = 0; displayPitch = 0
        pipes = []; emojis = []
        level = 1; levelElapsed = 0; totalElapsed = 0
        alive = true; started = false; deathReason = ""; trials = 0
        sincePipe = .greatestFiniteMagnitude
        sinceEmoji = 0.5
        nextID = 0
        lastTick = nil
        if let fixedSeed {
            rng = SeededRandomNumberGenerator(seed: fixedSeed)
        } else {
            var system = SystemRandomNumberGenerator()
            rng = SeededRandomNumberGenerator(seed: system.next())
        }
    }

    /// Rewarded-ad continue: restart the current level with a clear field.
    /// Run totals (level, trials) survive; one slip still ends the run.
    /// `sincePipe = 0` grants a full spacing of clear air, unlike reset's
    /// forced early first pipe.
    func revive() {
        birdY = 0.42; birdV = 0; displayPitch = 0
        pipes = []; emojis = []
        levelElapsed = 0
        alive = true; started = false; deathReason = ""
        sincePipe = 0
        sinceEmoji = 0.5
        lastTick = nil
    }

    func flap() {
        guard alive else { return }
        started = true
        birdV = flapV
    }

    private func die(_ reason: String) {
        guard alive else { return }
        alive = false
        deathReason = reason
    }

    // MARK: Step

    func tick(_ now: Date) {
        guard alive else { return }
        let dt = min(1.0 / 30.0, max(0, lastTick.map { now.timeIntervalSince($0) } ?? 0))
        lastTick = now
        guard dt > 0, started else { return }   // hover (no physics) until first flap

        totalElapsed += dt
        levelElapsed += dt
        if levelElapsed >= timeForLevel(level) { levelElapsed -= timeForLevel(level); level += 1 }

        stepFlyer(dt)
        stepEmojis(dt)
    }

    private func stepFlyer(_ dt: Double) {
        birdV += gravity * CGFloat(dt)
        birdY += birdV * CGFloat(dt)

        // Nose follows the motion, eased: quick (but not instant) up on a
        // flap, a lazier settle back down as the fall builds. birdV is in
        // play-area units per second (flap −0.86 … falling ≈ +1.3).
        let targetPitch = max(-0.55, min(0.75, Double(birdV) * 0.55))
        let rate = targetPitch < displayPitch ? 14.0 : 6.0
        displayPitch += (targetPitch - displayPitch) * min(1, dt * rate)

        if birdY - birdRy <= 0 { birdY = birdRy; birdV = max(birdV, 0) }   // ceiling clamps
        if birdY + birdRy >= 1 { die("you hit the floor"); return }        // floor kills

        for i in pipes.indices { pipes[i].x -= scrollSpeed * CGFloat(dt) }
        pipes.removeAll { $0.x + pipeW < -0.05 }

        sincePipe += scrollSpeed * CGFloat(dt)
        if sincePipe >= pipeSpacing {
            sincePipe = 0
            let g = gapH
            let center = CGFloat.random(in: (g / 2 + 0.08)...(1 - g / 2 - 0.08), using: &rng)
            pipes.append(Pipe(x: splitX, gapY: center, gapH: g))   // enters at the divider
        }

        for p in pipes {
            let xOverlap = (birdX + birdRx > p.x) && (birdX - birdRx < p.x + pipeW)
            if xOverlap {
                let top = p.gapY - p.gapH / 2, bottom = p.gapY + p.gapH / 2
                if birdY - birdRy < top || birdY + birdRy > bottom { die("you clipped a pipe"); return }
            }
        }
    }

    private func stepEmojis(_ dt: Double) {
        for i in emojis.indices { emojis[i].age += dt }
        var survivors: [Emoji] = []
        for e in emojis {
            if e.age >= e.ttl {
                if e.isTarget && !e.tapped { die("you missed a \(target)"); return }
                trials += 1                       // a look-alike correctly let go
            } else {
                survivors.append(e)
            }
        }
        emojis = survivors

        sinceEmoji += dt
        if sinceEmoji >= emojiInterval {
            sinceEmoji = 0
            let forbidden = Double.random(in: 0...1, using: &rng) < forbiddenProb
            nextID += 1
            emojis.append(Emoji(id: nextID,
                                x: CGFloat.random(in: (splitX + 0.06)...0.94, using: &rng),
                                y: CGFloat.random(in: 0.14...0.86, using: &rng),
                                isTarget: !forbidden,
                                ttl: emojiTTL))
        }
    }

    // MARK: Input

    /// Left of the divider = flap; right = resolve the nearest target under the
    /// finger (empty taps on the right are ignored).
    func handleTap(_ p: CGPoint, size: CGSize) {
        guard alive else { return }
        if p.x < splitX * size.width { flap(); return }

        var hitIndex: Int? = nil
        var best = CGFloat.greatestFiniteMagnitude
        for (i, e) in emojis.enumerated() {
            let center = CGPoint(x: e.x * size.width, y: e.y * size.height)
            let d = hypot(p.x - center.x, p.y - center.y)
            if d < 46, d < best { best = d; hitIndex = i }
        }
        guard let i = hitIndex else { return }
        if emojis[i].isTarget {
            emojis[i].tapped = true
            trials += 1
            emojis.remove(at: i)
            GameFeel.shared.play(.correct(combo: trials))
        } else {
            die("you tapped the \(lookAlike)")
        }
    }

    // MARK: Draw

    func draw(into ctx: inout GraphicsContext, size: CGSize) {
        let dividerX = splitX * size.width

        drawStage(into: &ctx, size: size, dividerX: dividerX)

        drawGates(into: &ctx, size: size, dividerX: dividerX)

        // Right zone: go/no-go emojis.
        for e in emojis { drawEmoji(e, into: &ctx, size: size) }

        // The flyer.
        drawFlyer(into: &ctx, size: size)
    }

    private func drawStage(into ctx: inout GraphicsContext, size: CGSize, dividerX: CGFloat) {
        let inset: CGFloat = 9
        let left = CGRect(x: inset, y: inset, width: dividerX - inset * 1.5, height: size.height - inset * 2)
        let right = CGRect(x: dividerX + inset * 0.5, y: inset, width: size.width - dividerX - inset * 1.5, height: size.height - inset * 2)
        ctx.fill(Path(roundedRect: left, cornerRadius: 14), with: .color(.white.opacity(0.035)))
        ctx.fill(Path(roundedRect: right, cornerRadius: 14), with: .color(Color.witsWarm.opacity(0.035)))
        ctx.stroke(Path(roundedRect: left, cornerRadius: 14), with: .color(.white.opacity(0.055)), lineWidth: 1)
        ctx.stroke(Path(roundedRect: right, cornerRadius: 14), with: .color(.white.opacity(0.055)), lineWidth: 1)

        for i in 1..<5 {
            let y = CGFloat(i) * size.height / 5
            var line = Path()
            line.move(to: CGPoint(x: 14, y: y))
            line.addLine(to: CGPoint(x: size.width - 14, y: y))
            ctx.stroke(line, with: .color(.white.opacity(0.035)), lineWidth: 1)
        }

        var div = Path()
        div.move(to: CGPoint(x: dividerX, y: 14))
        div.addLine(to: CGPoint(x: dividerX, y: size.height - 14))
        var glow = ctx
        glow.addFilter(.shadow(color: Color.witsAccent.opacity(0.55), radius: 8))
        glow.stroke(div, with: .color(Color.witsAccent.opacity(0.72)),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [7, 7]))

        ctx.draw(Text("FLY").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(ArcadeInk.onDarkDim),
                 at: CGPoint(x: 30, y: 28), anchor: .leading)
        ctx.draw(Text("PICK").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(ArcadeInk.onDarkDim),
                 at: CGPoint(x: dividerX + 18, y: 28), anchor: .leading)
    }

    private func drawEmoji(_ e: Emoji, into ctx: inout GraphicsContext, size: CGSize) {
        let pt = CGPoint(x: e.x * size.width, y: e.y * size.height)
        let remaining = e.ttl - e.age
        let alpha = min(1, min(e.age / 0.16, remaining / 0.32))
        let fontSize = min(43, max(34, size.width * 0.10))
        let scale = 0.88 + 0.12 * alpha

        ctx.opacity = max(0.18, alpha)
        var glow = ctx
        glow.addFilter(.shadow(color: (e.isTarget ? Color.witsAccent : Color.witsWarm).opacity(0.34), radius: 10))
        glow.draw(Text(e.isTarget ? target : lookAlike).font(.system(size: fontSize * scale)),
                  at: pt, anchor: .center)
        ctx.opacity = 1
    }

    private func drawGates(into ctx: inout GraphicsContext, size: CGSize, dividerX: CGFloat) {
        var gateCtx = ctx
        gateCtx.clip(to: Path(CGRect(x: 0, y: 0, width: dividerX, height: size.height)))

        for p in pipes {
            let x = p.x * size.width
            let w = pipeW * size.width
            let gapTop = (p.gapY - p.gapH / 2) * size.height
            let gapBot = (p.gapY + p.gapH / 2) * size.height
            gateCtx.chip(CGRect(x: x, y: -2, width: w, height: gapTop + 2),
                         fill: Color.witsAccent.opacity(0.70),
                         corner: 8,
                         glow: Color.witsAccent)
            gateCtx.chip(CGRect(x: x, y: gapBot, width: w, height: size.height - gapBot + 2),
                         fill: Color.witsAccent.opacity(0.70),
                         corner: 8,
                         glow: Color.witsAccent)
        }
    }

    private func drawFlyer(into ctx: inout GraphicsContext, size: CGSize) {
        let bx = birdX * size.width
        let by = birdY * size.height
        let r = max(12, birdRy * size.height)

        var plane = ctx
        plane.translateBy(x: bx, y: by)
        // The SF glyph points up-right; +45° levels it out to fly right.
        plane.rotate(by: .degrees(45) + .radians(displayPitch))
        plane.addFilter(.shadow(color: Color.witsAccent.opacity(0.85), radius: 9))
        var icon = plane.resolve(Image(systemName: "paperplane.fill"))
        icon.shading = .color(.white)
        let d = r * 2.5
        plane.draw(icon, in: CGRect(x: -d / 2, y: -d / 2, width: d, height: d))
    }
}

// MARK: - Screen

struct SplitSurvivalScreen: View {
    let best: Int
    let bestDepthFraction: Double
    /// (level reached, depth into the next level 0…1, emoji trials) → persist.
    let onRunComplete: (Int, Double, Int) -> Void
    let onQuit: () -> Void

    @State private var model: SplitGame
    @State private var phase: Phase
    @State private var endLevel = 1
    @State private var endReason = ""
    @State private var newBest = false
    @State private var tick = 0              // forces the playing view to observe model changes
    @State private var pauseController = GamePauseController()
    /// 3…2…1 pre-launch count (0 = "go!", nil = live). Taps are ignored while
    /// it runs; at "go!" the flyer auto-launches with a flap kick.
    @State private var countdown: Int?
    /// One rewarded-ad continue per run. `canContinue` is snapshotted at death
    /// so the offer doesn't pop in while the game-over card is already up.
    @State private var usedContinue = false
    @State private var canContinue = false
    @State private var adBusy = false
    /// False while a death sits unrecorded behind a pending continue offer.
    @State private var runRecorded = true

    private enum Phase { case playing, over }

    init(best: Int,
         bestDepthFraction: Double = 0,
         onRunComplete: @escaping (Int, Double, Int) -> Void,
         onQuit: @escaping () -> Void) {
        self.best = best
        self.bestDepthFraction = bestDepthFraction
        self.onRunComplete = onRunComplete
        self.onQuit = onQuit
        _model = State(initialValue: SplitGame())
        _phase = State(initialValue: .playing)
    }

    var body: some View {
        ZStack {
            Color.witsBg.ignoresSafeArea()
            switch phase {
            case .playing: playing
            case .over:    gameOver
            }
        }
        .overlay {
            if phase == .playing, !pauseController.isPaused {
                GamePauseButtonLayer(game: .split) {
                    pauseController.pause()
                }
            }
        }
        .overlay {
            if phase == .playing, pauseController.isPaused {
                GamePausedOverlay(game: .split,
                                  controller: pauseController,
                                  onQuit: {
                                      pauseController.reset()
                                      onQuit()
                                  })
            }
        }
        .onAppear {
            GameFeel.shared.warmUp()
            AdManager.shared.loadRewardedIfNeeded()
        }
        .onDisappear {
            finalizeRun()   // no-op unless a death sat behind a continue offer
            pauseController.reset()
            GameFeel.shared.teardown()
        }
    }

    // MARK: Playing

    private var playing: some View {
        VStack(spacing: 10) {
            SplitRunHUD(level: model.level,
                        progress: model.depthIntoLevel,
                        best: best,
                        target: model.target,
                        lookAlike: model.lookAlike)
                .padding(.leading, 48)
                .padding(.trailing, 16)

            GeometryReader { geo in
                ZStack {
                    ArcadeArena()

                    TimelineView(.animation(paused: pauseController.isPaused)) { tl in
                        Canvas { ctx, size in
                            _ = tick                     // read so the closure re-evaluates each tick
                            model.draw(into: &ctx, size: size)
                        }
                        .onChange(of: tl.date) { _, _ in
                            guard !pauseController.isPaused else { return }
                            model.tick(Date())
                            tick &+= 1
                            if !model.alive { endRun() }
                        }
                    }

                    // Stable tap layer (NOT rebuilt each frame, so taps track reliably).
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { v in
                                    guard !pauseController.isPaused, countdown == nil else { return }
                                    model.handleTap(v.location, size: geo.size)
                                }
                        )

                    if let countdown {
                        Text(countdown == 0 ? "go!" : "\(countdown)")
                            .font(.system(size: 84, weight: .heavy, design: .rounded))
                            .foregroundStyle(countdown == 0 ? Color.witsAccent : Color.witsInk)
                            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                            .id(countdown)
                            .transition(.scale(scale: 1.5).combined(with: .opacity))
                            .allowsHitTesting(false)
                    }
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.7), value: countdown)
                .clipShape(RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .witsShadow, radius: 12, y: 8)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 42)
        .padding(.bottom, 10)
        .task { await runCountdown() }
    }

    /// 3…2…1…go — then launch. Pause freezes the count; a rerun (fresh model)
    /// counts again, while re-appearing mid-run does not.
    private func runCountdown() async {
        guard !model.started, countdown == nil else { return }
        for n in [3, 2, 1] {
            countdown = n
            await activeSleep(0.8)
            guard !Task.isCancelled else { countdown = nil; return }
        }
        countdown = 0
        model.flap()
        await activeSleep(0.5)
        countdown = nil
    }

    private func activeSleep(_ seconds: Double) async {
        var remaining = seconds
        while remaining > 0, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(40))
            if !pauseController.isPaused { remaining -= 0.04 }
        }
    }

    // MARK: Game over

    private var gameOver: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: GameID.split.symbol)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(Color.witsAccent)
                Text(endReason)
                    .font(.witsBody(15, weight: .semibold))
                    .foregroundStyle(Color.witsMuted)
                    .multilineTextAlignment(.center)
                if newBest {
                    Text("NEW BEST")
                        .font(.system(size: 12, weight: .heavy, design: .rounded)).kerning(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.witsWarm, in: Capsule())
                        .padding(.top, 2)
                }
                Text("level \(endLevel)")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                    .monospacedDigit()
                HStack(spacing: 10) {
                    SplitStatPill(title: "best", value: splitBestLabel)
                    SplitStatPill(title: "picks", value: "\(model.trials)")
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .cardSurface()
            .rise()
            Spacer()
            if canContinue {
                Cta(title: "continue · watch ad", action: continueRun)
                    .rise(0.1)
                Text("pick back up at level \(endLevel) — once per run")
                    .font(.witsLabel(11.5))
                    .foregroundStyle(Color.witsFaint)
                    .padding(.top, 8)
                QuietButton(title: "play again", action: playAgain)
                    .padding(.top, 10)
            } else {
                Cta(title: "play again", action: playAgain)
                    .rise(0.1)
            }
            QuietButton(title: "done", action: finishAndQuit)
                .padding(.top, 6)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 16)
        .disabled(adBusy)
    }

    // MARK: Run lifecycle

    private func startRun() {
        pauseController.reset()
        model.reset()
        usedContinue = false
        canContinue = false
        withAnimation(.easeOut(duration: 0.2)) { phase = .playing }
    }

    private func endRun() {
        guard phase == .playing else { return }
        pauseController.reset()
        endLevel = model.level
        endReason = model.deathReason
        newBest = currentProgressValue > comparisonBestValue
        GameFeel.shared.play(newBest ? .newBest : .gameOver)
        // A continue offer defers recording — the run isn't over until the
        // player passes on it. No offer → record right away, as before.
        canContinue = !usedContinue && AdManager.shared.rewardedReady
        if canContinue {
            runRecorded = false
        } else {
            runRecorded = true
            onRunComplete(model.level, model.depthIntoLevel, model.trials)
        }
        withAnimation(.easeOut(duration: 0.25)) { phase = .over }
    }

    private func finalizeRun() {
        guard !runRecorded else { return }
        runRecorded = true
        onRunComplete(model.level, model.depthIntoLevel, model.trials)
    }

    private var splitBestLabel: String {
        SplitProgress.label(value: max(comparisonBestValue, currentProgressValue))
    }

    private var currentProgressValue: Int {
        SplitProgress.value(level: endLevel, depth: model.depthIntoLevel)
    }

    private var comparisonBestValue: Int {
        guard best > 0 else { return 0 }
        return SplitProgress.value(level: best, depth: bestDepthFraction)
    }

    private func playAgain() {
        finalizeRun()
        startRun()
    }

    private func finishAndQuit() {
        finalizeRun()
        onQuit()
    }

    private func continueRun() {
        guard !adBusy else { return }
        adBusy = true
        AdManager.shared.showRewarded { earned in
            adBusy = false
            guard earned else { return }   // closed early — offer stays on the table
            usedContinue = true
            canContinue = false
            pauseController.reset()
            model.revive()
            withAnimation(.easeOut(duration: 0.2)) { phase = .playing }
        }
    }
}

private struct SplitRunHUD: View {
    var level: Int
    var progress: Double
    var best: Int
    var target: String
    var lookAlike: String

    var body: some View {
        VStack(spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("level \(level)")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsAccent)
                    .monospacedDigit()
                Spacer(minLength: 8)
                Text("best \(best)")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.witsFaint)
                    .monospacedDigit()
            }

            ProgressTrack(fraction: progress, animated: false)

            HStack(spacing: 8) {
                SplitTargetChip(label: "tap", symbol: target, color: .witsAccent)
                SplitTargetChip(label: "avoid", symbol: lookAlike, color: .witsWarm)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.witsCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .witsShadow, radius: 9, y: 5)
    }
}

private struct SplitTargetChip: View {
    var label: String
    var symbol: String
    var color: Color

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
            Text(symbol)
                .font(.system(size: 16))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
    }
}

private struct SplitStatPill: View {
    var title: String
    var value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsFaint)
            Text(value)
                .font(.system(size: 14.5, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsInk)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.witsTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
