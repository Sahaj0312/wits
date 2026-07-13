//
//  CrowdControlGame.swift
//  wits
//
//  Crowd control (multiple object tracking — divided attention).
//  A few dots flash, then turn identical to the rest and everything starts
//  drifting. Track the marked ones through the chaos and point them out when
//  the dots freeze. Based on the multiple-object-tracking paradigm (1988).
//
//  The crowd simulates in board points on a display-synced TimelineView:
//  constant-speed dots steer along smooth wander curves, exchange velocity on
//  contact (equal-mass elastic), and bounce off walls at their true radius.
//  Picks run against a deadline so a round can't be parked mid-answer.
//

import SwiftUI

private struct TrackStats {
    var correctPicks = 0
    var totalTargets = 0
    var rounds = 0
    var perfectRounds = 0
}

struct TrackerScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        _rng = State(initialValue: cfg.makeRandomGenerator())
    }

    private var startedAt = Date()
    private var world: GameWorld { GameID.crowdControl.world }

    private static let roundCount = 4
    private static let markSeconds = 1.5
    private static let moveSeconds = 6.5
    private static let pickSeconds = 9.0
    private static let dotDiameter: CGFloat = 32
    private static let wallInset: CGFloat = 10
    private static let collisionIterations = 3

    private enum RoundPhase {
        case mark, move, pick, reveal
    }

    private struct Dot: Identifiable {
        let id: Int
        var pos: CGPoint        // board points
        var vel: CGVector       // board points / second
        var turn = 0.0          // wander steering, radians / second
        var retarget = 0.0      // seconds until the wander turn resamples
        var isTarget: Bool
        var picked = false
    }

    @State private var roundPhase = RoundPhase.mark
    @State private var dots: [Dot] = []
    @State private var round = 0
    @State private var stats = TrackStats()
    @State private var pulse = false
    @State private var generation = 0
    @State private var rng: SeededRandomNumberGenerator
    @State private var boardSize = CGSize.zero
    @State private var moveLeft = 0.0
    @State private var pickLeft = 0.0
    @State private var lastTick: Date?

    private var config: (targets: Int, dots: Int, speed: Double) {
        let level = cfg.difficulty.level
        let baseTargets = 2 + Int(ceil(level / 2.5))
        let targets = min(6, baseTargets + round / 2)
        let dots = min(12, max(targets + 4, 8 + Int(level / 3)))
        let speed = min(0.44, 0.18 + level * 0.018 + Double(round) * 0.016)
        return (targets, dots, speed)
    }

    /// Constant dot speed in points/sec, scaled off the short board side so a
    /// diagonal drift covers the same ground as a horizontal one.
    private var dotSpeed: Double {
        config.speed * Double(min(boardSize.width, boardSize.height))
    }

    private var picksLeft: Int {
        max(0, config.targets - dots.filter(\.picked).count)
    }

    private var statusLine: String {
        switch roundPhase {
        case .mark: return "memorize the glowing dots"
        case .move: return "don't lose them"
        case .pick: return picksLeft == 1 ? "tap 1 more" : "tap the \(picksLeft) you were tracking"
        case .reveal: return dots.filter { $0.picked && $0.isTarget }.count == config.targets
            ? "all of them. nice." : "the rings show where they really went."
        }
    }

    /// Draining fraction for the phase countdown under the board.
    private var phaseFraction: Double {
        switch roundPhase {
        case .move: return max(0, moveLeft / Self.moveSeconds)
        case .pick: return max(0, pickLeft / Self.pickSeconds)
        case .mark, .reveal: return 0
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            if !cfg.isSurvival {
                HStack(alignment: .firstTextBaseline) {
                    Text("round \(Text("\(min(round + 1, Self.roundCount))").foregroundStyle(world.accent)) of \(Self.roundCount)")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(world.ink)
                        .monospacedDigit()
                    Spacer()
                    Text("\(stats.correctPicks) of \(stats.totalTargets) held")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(world.muted)
                        .monospacedDigit()
                }
                ProgressTrack(fraction: Double(round) / Double(Self.roundCount), animated: true,
                              tint: world.accent, track: world.surface)
            }

            TimelineView(.animation(paused: !(roundPhase == .move || roundPhase == .pick) || cfg.isPaused)) { tl in
                boardView
                    .onChange(of: tl.date) { _, now in
                        tick(now)
                    }
            }

            // phase countdown: teal while the crowd drifts, red while picks drain
            ProgressTrack(fraction: phaseFraction, animated: false,
                          tint: roundPhase == .pick ? world.secondary : world.accent,
                          track: world.surface)
                .opacity(roundPhase == .move || roundPhase == .pick ? 1 : 0)

            Text(statusLine)
                .font(.system(size: 15, weight: .heavy, design: world.bodyDesign))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.22), in: Capsule())
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    private var boardView: some View {
        GeometryReader { geo in
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            ZStack {
                shape.fill(world.surface)
                RadialGradient(colors: [world.accent.opacity(0.10), .clear],
                               center: .center, startRadius: 0,
                               endRadius: max(geo.size.width, geo.size.height) * 0.65)
                    .clipShape(shape)
                shape.strokeBorder(world.accent.opacity(0.28), lineWidth: 1.5)

                ForEach(dots) { dot in
                    dotView(dot)
                        .position(dot.pos)
                }
            }
            .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
            .contentShape(shape)
            .onTapGesture { location in
                tapBoard(location)
            }
            .onChange(of: geo.size, initial: true) { _, size in
                boardResized(to: size)
            }
        }
    }

    private func dotView(_ dot: Dot) -> some View {
        let showTarget = roundPhase == .mark && dot.isTarget
        let wrongPick = roundPhase == .reveal && dot.picked && !dot.isTarget
        let missed = roundPhase == .reveal && dot.isTarget && !dot.picked
        let lit = showTarget || (dot.picked && !wrongPick)

        let fill: Color = showTarget ? world.accent
            : wrongPick ? world.secondary
            : dot.picked ? world.accent.opacity(0.9)
            : world.ink.opacity(0.30)
        let glow: Color = lit ? world.accent.opacity(0.75)
            : wrongPick ? world.secondary.opacity(0.7)
            : .clear

        return Circle()
            .fill(fill)
            .overlay(Circle().strokeBorder(.white.opacity(lit ? 0.9 : 0.12), lineWidth: lit ? 2 : 1))
            .frame(width: Self.dotDiameter, height: Self.dotDiameter)
            .scaleEffect(showTarget && pulse ? 1.16 : 1)
            .shadow(color: glow, radius: 7)
            .overlay(
                Circle()
                    .strokeBorder(missed ? world.secondary : .clear, lineWidth: 3)
                    .padding(-5)
            )
            .animation(.easeInOut(duration: 0.45), value: pulse)
            .animation(.easeOut(duration: 0.15), value: dot.picked)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    // MARK: Interaction

    private func tapBoard(_ location: CGPoint) {
        guard roundPhase == .pick else { return }
        let hit = dots.indices.min { a, b in
            dist(dots[a].pos, location) < dist(dots[b].pos, location)
        }
        guard let hit, dist(dots[hit].pos, location) < 28, !dots[hit].picked else { return }
        dots[hit].picked = true
        if dots.filter(\.picked).count == config.targets { finishPicks() }
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func finishPicks() {
        guard roundPhase == .pick else { return }
        let correct = dots.filter { $0.picked && $0.isTarget }.count
        let perfect = correct == config.targets
        stats.correctPicks += correct
        stats.totalTargets += config.targets
        stats.rounds += 1
        if perfect { stats.perfectRounds += 1 }
        cfg.report(perfect ? .hit : .miss, points: correct * 80, combo: stats.perfectRounds)
        roundPhase = .reveal
        let gen = generation
        Task {
            try? await Task.sleep(for: .milliseconds(1400))
            guard gen == generation else { return }
            if !cfg.isSurvival && round + 1 >= Self.roundCount {
                finish()
            } else {
                round = (round + 1) % Self.roundCount   // cycle rounds endlessly in survival
                startRound()
            }
        }
    }

    private func finish() {
        let acc = stats.totalTargets > 0 ? Double(stats.correctPicks) / Double(stats.totalTargets) : 0
        var r = GameResult(game: .crowdControl, score: stats.correctPicks * 250, accuracy: acc)
        r.trials = stats.rounds
        r.threshold = Double(stats.perfectRounds)
        r.startedAt = startedAt
        r.durationMs = Int(cfg.activeElapsed(since: startedAt) * 1000)
        r.raw = [
            "perfectRounds": Double(stats.perfectRounds),
            "totalTargets": Double(stats.totalTargets),
            "correctPicks": Double(stats.correctPicks),
            // CrowdControlPolicy's contract: per-target hits and misses.
            "correct": Double(stats.correctPicks),
            "wrong": Double(max(0, stats.totalTargets - stats.correctPicks))
        ]
        onResult(r)
    }

    // MARK: Round flow

    private func boardResized(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        if boardSize == .zero {
            boardSize = size
            startRound()
        } else if boardSize != size {
            let sx = size.width / boardSize.width
            let sy = size.height / boardSize.height
            for i in dots.indices {
                dots[i].pos.x *= sx
                dots[i].pos.y *= sy
            }
            boardSize = size
        }
    }

    private func startRound() {
        guard boardSize != .zero else { return }
        generation += 1
        let gen = generation
        let c = config
        let inset = Self.dotDiameter / 2 + Self.wallInset
        var seeded: [Dot] = []
        for i in 0..<c.dots {
            // keep spawn points spread out
            var pos: CGPoint
            var attempts = 0
            repeat {
                pos = CGPoint(x: Double.random(in: inset...(boardSize.width - inset), using: &rng),
                              y: Double.random(in: inset...(boardSize.height - inset), using: &rng))
                attempts += 1
            } while attempts < 60 && seeded.contains(where: { dist($0.pos, pos) < Self.dotDiameter * 2 })
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
            seeded.append(Dot(
                id: gen * 100 + i,   // unique per round → dots fade in/out, never teleport
                pos: pos,
                vel: CGVector(dx: Darwin.cos(angle) * dotSpeed, dy: Darwin.sin(angle) * dotSpeed),
                retarget: Double.random(in: 0...0.8, using: &rng),
                isTarget: i < c.targets
            ))
        }
        let fresh = seeded.shuffled(using: &rng)

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
            moveLeft = Self.moveSeconds
            lastTick = nil
            roundPhase = .move
        }
    }

    /// One display frame: advance the crowd during move, drain the deadline
    /// during pick. dt is measured and clamped so hitches slow the crowd
    /// instead of teleporting it.
    private func tick(_ now: Date) {
        guard !cfg.isPaused else { return }
        let dt = min(1.0 / 30, now.timeIntervalSince(lastTick ?? now))
        lastTick = now
        guard dt > 0 else { return }

        switch roundPhase {
        case .move:
            step(dt)
            moveLeft -= dt
            if moveLeft <= 0 {
                pickLeft = Self.pickSeconds
                roundPhase = .pick
            }
        case .pick:
            pickLeft -= dt
            if pickLeft <= 0 { finishPicks() }
        case .mark, .reveal:
            break
        }
    }

    // MARK: Physics

    private func step(_ dt: Double) {
        let speed = dotSpeed
        for i in dots.indices {
            var d = dots[i]
            // smooth wander: hold a turn rate for a while, then re-roll it,
            // so paths curve unpredictably instead of snapping
            d.retarget -= dt
            if d.retarget <= 0 {
                d.turn = Double.random(in: -1.7...1.7, using: &rng)
                d.retarget = Double.random(in: 0.5...1.4, using: &rng)
            }
            let heading = atan2(d.vel.dy, d.vel.dx) + d.turn * dt
            d.vel = CGVector(dx: Darwin.cos(heading) * speed, dy: Darwin.sin(heading) * speed)
            d.pos.x += d.vel.dx * dt
            d.pos.y += d.vel.dy * dt
            keepDotInBounds(&d)
            dots[i] = d
        }
        resolveDotCollisions()
    }

    private func resolveDotCollisions() {
        guard dots.count > 1 else { return }
        for _ in 0..<Self.collisionIterations {
            for i in dots.indices {
                for j in dots.indices where j > i {
                    resolveCollision(i, j)
                }
            }
            for i in dots.indices {
                keepDotInBounds(&dots[i])
            }
        }
    }

    private func resolveCollision(_ i: Int, _ j: Int) {
        var dx = dots[j].pos.x - dots[i].pos.x
        var dy = dots[j].pos.y - dots[i].pos.y
        var distance = hypot(dx, dy)
        if distance == 0 {
            let angle = Double((dots[i].id * 37 + dots[j].id * 19) % 360) * .pi / 180
            dx = Darwin.cos(angle) * 0.1
            dy = Darwin.sin(angle) * 0.1
            distance = hypot(dx, dy)
        }
        guard distance < Self.dotDiameter else { return }

        let nx = dx / distance
        let ny = dy / distance
        let push = (Self.dotDiameter - distance) / 2

        dots[i].pos.x -= nx * push
        dots[i].pos.y -= ny * push
        dots[j].pos.x += nx * push
        dots[j].pos.y += ny * push

        // equal-mass elastic: swap the velocity components along the contact
        // normal, then restore constant speed
        let rvx = dots[j].vel.dx - dots[i].vel.dx
        let rvy = dots[j].vel.dy - dots[i].vel.dy
        let closingSpeed = rvx * nx + rvy * ny
        if closingSpeed < 0 {
            dots[i].vel.dx += closingSpeed * nx
            dots[i].vel.dy += closingSpeed * ny
            dots[j].vel.dx -= closingSpeed * nx
            dots[j].vel.dy -= closingSpeed * ny
            normalizeSpeed(&dots[i])
            normalizeSpeed(&dots[j])
        }
    }

    private func keepDotInBounds(_ dot: inout Dot) {
        let inset = Self.dotDiameter / 2 + Self.wallInset
        let maxX = boardSize.width - inset
        let maxY = boardSize.height - inset
        if dot.pos.x < inset { dot.pos.x = inset; dot.vel.dx = abs(dot.vel.dx) }
        if dot.pos.x > maxX { dot.pos.x = maxX; dot.vel.dx = -abs(dot.vel.dx) }
        if dot.pos.y < inset { dot.pos.y = inset; dot.vel.dy = abs(dot.vel.dy) }
        if dot.pos.y > maxY { dot.pos.y = maxY; dot.vel.dy = -abs(dot.vel.dy) }
    }

    private func normalizeSpeed(_ dot: inout Dot) {
        let speed = hypot(dot.vel.dx, dot.vel.dy)
        guard speed > 0 else { return }
        dot.vel.dx = dot.vel.dx / speed * dotSpeed
        dot.vel.dy = dot.vel.dy / speed * dotSpeed
    }
}
