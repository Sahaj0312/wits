//
//  CrowdControlGame.swift
//  wits
//
//  Crowd control (multiple object tracking — divided attention).
//  A few dots flash, then turn identical to the rest and everything starts
//  drifting. Track the marked ones through the chaos and point them out when
//  the dots freeze. Based on the multiple-object-tracking paradigm (1988).
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
    }

    private var startedAt = Date()

    private static let roundCount = 4
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

    @State private var roundPhase = RoundPhase.mark
    @State private var dots: [Dot] = []
    @State private var round = 0
    @State private var stats = TrackStats()
    @State private var pulse = false
    @State private var generation = 0
    @State private var boardSize: CGSize = .zero

    private var config: (targets: Int, dots: Int, speed: Double) {
        let level = cfg.difficulty.level
        let baseTargets = 2 + Int(ceil(level / 2.5))
        let targets = min(6, baseTargets + round / 2)
        let dots = min(12, max(targets + 4, 8 + Int(level / 3)))
        let speed = min(0.44, 0.18 + level * 0.018 + Double(round) * 0.016)
        return (targets, dots, speed)
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

    var body: some View {
        VStack(spacing: 12) {
            if !cfg.isSurvival {
                HStack(alignment: .firstTextBaseline) {
                    Text("round \(Text("\(min(round + 1, Self.roundCount))").foregroundStyle(Color.witsAccent)) of \(Self.roundCount)")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                        .monospacedDigit()
                    Spacer()
                    Text("\(stats.correctPicks) of \(stats.totalTargets) held")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.witsMuted)
                        .monospacedDigit()
                }
                ProgressTrack(fraction: Double(round) / Double(Self.roundCount), animated: true)
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
        .onAppear { if dots.isEmpty { startRound() } }
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
