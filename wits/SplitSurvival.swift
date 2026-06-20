//
//  SplitSurvival.swift
//  wits
//
//  "split" — a survival-only divided-attention game. The screen splits LEFT /
//  RIGHT: left thumb keeps a flappy-style flyer alive; right thumb works a
//  go/no-go stream — tap the target, never the look-alike, don't let a target
//  slip by. One mistake of any kind ends the run. Levels are time-gated and
//  grow longer + harder; the level you reach is your score and feeds the
//  multitasking domain (AppModel.recordSplitRun) — never the staircase.
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
    private var rng = SystemRandomNumberGenerator()
    private var lastTick: Date?

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
        birdY = 0.42; birdV = 0
        pipes = []; emojis = []
        level = 1; levelElapsed = 0; totalElapsed = 0
        alive = true; started = false; deathReason = ""; trials = 0
        sincePipe = .greatestFiniteMagnitude
        sinceEmoji = 0.5
        nextID = 0
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

        // Faint zone tints + the vertical divider.
        ctx.fill(Path(CGRect(x: 0, y: 0, width: dividerX, height: size.height)),
                 with: .color(Color.witsAccent.opacity(0.04)))
        var div = Path()
        div.move(to: CGPoint(x: dividerX, y: 0))
        div.addLine(to: CGPoint(x: dividerX, y: size.height))
        ctx.stroke(div, with: .color(Color.witsLine.opacity(0.6)),
                   style: StrokeStyle(lineWidth: 1, dash: [4, 5]))

        // Right zone: the go/no-go emojis.
        for e in emojis {
            let pt = CGPoint(x: e.x * size.width, y: e.y * size.height)
            let remaining = e.ttl - e.age
            let alpha = min(1, min(e.age / 0.18, remaining / 0.35))
            ctx.opacity = max(0.15, alpha)
            ctx.draw(Text(e.isTarget ? target : lookAlike).font(.system(size: 36)),
                     at: pt, anchor: .center)
            ctx.opacity = 1
        }

        // Left zone: pipes.
        let pipeColor = Color.witsAccent.opacity(0.55)
        for p in pipes {
            let x = p.x * size.width
            let w = pipeW * size.width
            let gapTop = (p.gapY - p.gapH / 2) * size.height
            let gapBot = (p.gapY + p.gapH / 2) * size.height
            ctx.fill(Path(roundedRect: CGRect(x: x, y: 0, width: w, height: gapTop), cornerRadius: 5),
                     with: .color(pipeColor))
            ctx.fill(Path(roundedRect: CGRect(x: x, y: gapBot, width: w, height: size.height - gapBot), cornerRadius: 5),
                     with: .color(pipeColor))
        }

        // The flyer.
        let bx = birdX * size.width
        let by = birdY * size.height
        let r = birdRy * size.height
        ctx.fill(Path(ellipseIn: CGRect(x: bx - r, y: by - r, width: r * 2, height: r * 2)),
                 with: .color(Color.witsInk))
        ctx.fill(Path(ellipseIn: CGRect(x: bx + r * 0.05, y: by - r * 0.35, width: r * 0.5, height: r * 0.5)),
                 with: .color(Color.witsBg))
    }
}

// MARK: - Screen

struct SplitSurvivalScreen: View {
    let best: Int
    /// (level reached, depth into the next level 0…1, emoji trials) → persist.
    let onRunComplete: (Int, Double, Int) -> Void
    let onQuit: () -> Void

    @State private var model = SplitGame()
    @State private var phase: Phase = .intro
    @State private var endLevel = 1
    @State private var endReason = ""
    @State private var newBest = false
    @State private var tick = 0              // forces the playing view to observe model changes

    private enum Phase { case intro, playing, over }

    var body: some View {
        ZStack {
            Color.witsBg.ignoresSafeArea()
            switch phase {
            case .intro:   intro
            case .playing: playing
            case .over:    gameOver
            }
        }
        .overlay(alignment: .topLeading) {
            if phase == .playing {
                Button(action: onQuit) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Color.witsFaint)
                        .padding(12)
                }
                .padding(.top, 44)
            }
        }
        .onAppear { GameFeel.shared.warmUp() }
        .onDisappear { GameFeel.shared.teardown() }
    }

    // MARK: Intro

    private var intro: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: GameID.split.symbol)
                    .font(.system(size: 36, weight: .heavy))
                    .foregroundStyle(Color.witsAccent)
                Text("split")
                    .font(.witsDisplay(30))
                    .foregroundStyle(Color.witsInk)
                Text("two hands, two jobs. tap the LEFT side to keep the flyer up. on the RIGHT, tap every \(model.target) — but never the \(model.lookAlike).")
                    .font(.witsBody(15.5))
                    .foregroundStyle(Color.witsMuted)
                    .multilineTextAlignment(.center)
                Text("one slip — a crash, a wrong tap, or a missed \(model.target) — ends the run. levels get longer and faster. how far can you get?")
                    .font(.witsBody(14))
                    .foregroundStyle(Color.witsFaint)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .cardSurface()
            .rise()
            Spacer()
            Cta(title: "start", action: startRun)
                .rise(0.1)
            QuietButton(title: "back", action: onQuit)
                .padding(.top, 6)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 16)
    }

    // MARK: Playing

    private var playing: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("level \(model.level)")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsAccent)
                    .monospacedDigit()
                Spacer()
                HStack(spacing: 6) {
                    Text("tap").font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.witsMuted)
                    Text(model.target).font(.system(size: 17))
                    Text("avoid").font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.witsMuted)
                    Text(model.lookAlike).font(.system(size: 17))
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 44)

            GeometryReader { geo in
                ZStack {
                    TimelineView(.animation) { tl in
                        Canvas { ctx, size in
                            _ = tick                     // read so the closure re-evaluates each tick
                            model.draw(into: &ctx, size: size)
                        }
                        .onChange(of: tl.date) { _, _ in
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
                                .onEnded { v in model.handleTap(v.location, size: geo.size) }
                        )
                    if !model.started {
                        Text("tap the left side to fly")
                            .font(.witsBody(15, weight: .semibold))
                            .foregroundStyle(Color.witsMuted)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.witsCard, in: Capsule())
                            .allowsHitTesting(false)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }

    // MARK: Game over

    private var gameOver: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 8) {
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
                Text("best level \(max(best, endLevel))")
                    .font(.witsBody(15, weight: .semibold))
                    .foregroundStyle(Color.witsMuted)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .cardSurface()
            .rise()
            Spacer()
            Cta(title: "play again", action: startRun)
                .rise(0.1)
            QuietButton(title: "done", action: onQuit)
                .padding(.top, 6)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 16)
    }

    // MARK: Run lifecycle

    private func startRun() {
        model.reset()
        withAnimation(.easeOut(duration: 0.2)) { phase = .playing }
    }

    private func endRun() {
        guard phase == .playing else { return }
        endLevel = model.level
        endReason = model.deathReason
        newBest = endLevel > best
        GameFeel.shared.play(newBest ? .newBest : .gameOver)
        onRunComplete(model.level, model.depthIntoLevel, model.trials)
        withAnimation(.easeOut(duration: 0.25)) { phase = .over }
    }
}
