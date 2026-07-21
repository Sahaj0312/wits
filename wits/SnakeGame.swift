//
//  SnakeGame.swift
//  wits
//
//  Snake: the classic endless steering run. No levels, three speed modes
//  (easy / medium / hard) each keep their own best score, and one all-time
//  best stands across every mode. The snake never stops; every apple adds a
//  segment and quietly raises the tempo, and one clip of a wall or your own
//  body ends the run.
//
//  Rendering follows the Split playbook: the engine is a plain class stepped
//  by an async loop, and a TimelineView-driven Canvas interpolates segment
//  positions between ticks so the snake glides instead of hopping cells.
//  Steering works mid-drag, every ~22pt of travel in a new direction queues
//  a turn, so a held finger can whip through corners without lifting.
//

import SwiftUI

// MARK: - Engine

enum SnakeDir {
    case up, down, left, right

    var dx: Int {
        switch self {
        case .left: -1
        case .right: 1
        default: 0
        }
    }

    var dy: Int {
        switch self {
        case .up: -1
        case .down: 1
        default: 0
        }
    }

    var opposite: SnakeDir {
        switch self {
        case .up: .down
        case .down: .up
        case .left: .right
        case .right: .left
        }
    }
}

struct SnakeCell: Hashable {
    var x: Int
    var y: Int
}

struct SnakeSparkle {
    let cell: SnakeCell
    let at: TimeInterval
}

@Observable
final class SnakeEngine {
    static let cols = 15
    static let rows = 22
    static let foodCount = 2

    /// A board-spanning cycle used to respawn any snake length without
    /// overlapping itself. The cycle leaves the cell to the right of the
    /// revival head free until the board is completely full.
    private static let revivalRoute: [SnakeCell] = {
        var route = (0..<cols).map { SnakeCell(x: $0, y: 0) }
        for y in 1..<rows {
            let xs: [Int] = y.isMultiple(of: 2)
                ? Array(1..<cols)
                : Array(stride(from: cols - 1, through: 1, by: -1))
            route.append(contentsOf: xs.map { SnakeCell(x: $0, y: y) })
        }
        route.append(SnakeCell(x: 0, y: rows - 1))
        route.append(contentsOf: stride(from: rows - 2, through: 1, by: -1)
            .map { SnakeCell(x: 0, y: $0) })
        return route
    }()

    /// Head first.
    private(set) var body: [SnakeCell] = []
    private(set) var foods: [SnakeCell] = []
    private(set) var score = 0
    private(set) var alive = true
    private(set) var direction: SnakeDir = .up

    // Interpolation state for the renderer: where every segment was last
    // tick and when that tick landed. Read ~60×/s by the Canvas, so none of
    // it participates in observation.
    @ObservationIgnored private(set) var prevBody: [SnakeCell] = []
    @ObservationIgnored private(set) var lastStepAt: TimeInterval = 0
    @ObservationIgnored private(set) var tickDuration: Double = 0.15
    @ObservationIgnored private(set) var sparkles: [SnakeSparkle] = []

    /// Queued turns (max two) so a fast double-swipe lands both corners.
    @ObservationIgnored private var pending: [SnakeDir] = []
    /// Drag bookkeeping lives on the model: mutating it never invalidates SwiftUI.
    @ObservationIgnored var dragAnchor: CGPoint?
    @ObservationIgnored private var rng = SystemRandomNumberGenerator()

    init() {
        let x = Self.cols / 2
        let y = Self.rows * 2 / 3
        body = (0..<4).map { SnakeCell(x: x, y: y + $0) }
        prevBody = body
        for _ in 0..<Self.foodCount { spawnFood() }
    }

    enum StepOutcome { case moved, ate, died }

    @discardableResult
    func steer(_ dir: SnakeDir) -> Bool {
        guard alive else { return false }
        let reference = pending.last ?? direction
        guard dir != reference, dir != reference.opposite, pending.count < 2 else { return false }
        pending.append(dir)
        return true
    }

    @discardableResult
    func step(tick: Double, now: TimeInterval = Date().timeIntervalSinceReferenceDate) -> StepOutcome {
        guard alive else { return .died }
        prevBody = body
        lastStepAt = now
        tickDuration = tick
        sparkles.removeAll { now - $0.at > 0.6 }

        if !pending.isEmpty { direction = pending.removeFirst() }
        let head = body[0]
        let next = SnakeCell(x: head.x + direction.dx, y: head.y + direction.dy)
        let ate = foods.contains(next)

        // The tail cell vacates this tick, so moving into it is legal ,
        // unless this move grows the snake and the tail stays put.
        var occupied = body
        if !ate { occupied.removeLast() }
        guard (0..<Self.cols).contains(next.x), (0..<Self.rows).contains(next.y),
              !occupied.contains(next) else {
            alive = false
            return .died
        }

        body.insert(next, at: 0)
        if ate {
            score += 1
            foods.removeAll { $0 == next }
            sparkles.append(SnakeSparkle(cell: next, at: now))
            spawnFood()
            return .ate
        }
        body.removeLast()
        return .moved
    }

    @discardableResult
    private func spawnFood() -> Bool {
        var empty: [SnakeCell] = []
        for x in 0..<Self.cols {
            for y in 0..<Self.rows {
                let cell = SnakeCell(x: x, y: y)
                if !body.contains(cell), !foods.contains(cell) { empty.append(cell) }
            }
        }
        guard let cell = empty.randomElement(using: &rng) else { return false }
        foods.append(cell)
        return true
    }

    /// Test seam: install an exact run state before exercising death/revive.
    func load(body: [SnakeCell], foods: [SnakeCell], score: Int,
              direction: SnakeDir, alive: Bool) {
        precondition(!body.isEmpty && body.count <= Self.cols * Self.rows)
        precondition(Set(body).count == body.count)
        self.body = body
        prevBody = body
        self.foods = foods
        self.score = score
        self.direction = direction
        pending.removeAll()
        dragAnchor = nil
        sparkles.removeAll()
        self.alive = alive
    }

    private static func revivalBody(length: Int) -> [SnakeCell] {
        precondition((1...revivalRoute.count).contains(length))
        let head = SnakeCell(x: cols / 2, y: rows * 2 / 3)
        let headIndex = revivalRoute.firstIndex(of: head)!
        return (0..<length).map { offset in
            revivalRoute[(headIndex - offset + revivalRoute.count) % revivalRoute.count]
        }
    }

    /// One final chance respawns the complete snake on a safe contiguous path,
    /// preserving both the run's score and its earned length.
    func revive() {
        guard !alive else { return }
        body = Self.revivalBody(length: body.count)
        prevBody = body
        foods.removeAll { body.contains($0) }
        while foods.count < Self.foodCount, spawnFood() {}
        direction = .right
        pending.removeAll()
        dragAnchor = nil
        sparkles.removeAll()
        lastStepAt = Date().timeIntervalSinceReferenceDate
        alive = true
    }
}

// MARK: - Mode select

/// Snake's pre-game screen: no levels, just the three speed modes with their
/// own bests and the all-time best underneath.
struct SnakeModeSelectView: View {
    var onPlay: (ChallengeDifficulty) -> Void
    var onClose: () -> Void
    var onHelp: (() -> Void)? = nil

    @Environment(AppModel.self) private var app

    private let game = GameID.snake
    private var world: GameWorld { game.world }
    private let modes: [ChallengeDifficulty] = [.easy, .medium, .hard]

    var body: some View {
        ZStack {
            GameWorldBackdrop(game: game)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack {
                        iconButton("chevron.left", label: "Close", action: onClose)
                        Spacer()
                        Text(game.subskill.uppercased())
                            .font(.system(size: 10.5, weight: .black, design: world.bodyDesign))
                            .foregroundStyle(world.muted)
                        Spacer()
                        if let onHelp {
                            iconButton("questionmark", label: "How to play", action: onHelp)
                        } else {
                            Color.clear.frame(width: 44, height: 44)
                        }
                    }
                    .padding(.top, 10)

                    GamePosterArt(game: game)
                        .frame(height: 250)
                        .frame(maxWidth: 440)

                    Text(game.worldTitle())
                        .font(.system(size: 44, weight: .black, design: world.titleDesign))
                        .foregroundStyle(world.ink)
                    Text(game.tagline)
                        .font(.system(size: 14.5, weight: .semibold, design: world.bodyDesign))
                        .foregroundStyle(world.muted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 7)

                    VStack(spacing: 11) {
                        ForEach(modes) { mode in
                            modeButton(mode)
                        }
                    }
                    .padding(.top, 28)

                    if allTimeBest > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 11, weight: .black))
                                .foregroundStyle(world.accent)
                            Text("ALL TIME BEST · \(allTimeBest)")
                                .font(.system(size: 12, weight: .black, design: world.bodyDesign))
                                .foregroundStyle(world.ink)
                                .monospacedDigit()
                        }
                        .padding(.top, 18)
                    }
                }
                .padding(.bottom, 30)
                .padding(.horizontal, 22)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var allTimeBest: Int {
        app.levels.marathonBest(for: game)?.score ?? 0
    }

    private func modeButton(_ mode: ChallengeDifficulty) -> some View {
        let color = world.difficultyColor(mode)
        let best = app.levels.modeBest(for: game, difficulty: mode)
        return Button { onPlay(mode) } label: {
            HStack(spacing: 14) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 24, weight: .black))
                    .frame(width: 45)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(mode.shortTitle.uppercased()) MODE")
                        .font(.system(size: 18, weight: .black, design: world.titleDesign))
                    Text(best > 0 ? "best · \(best)" : "no runs yet")
                        .font(.system(size: 11.5, weight: .bold, design: world.bodyDesign))
                        .opacity(0.72)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .black))
                    .opacity(0.7)
            }
            .foregroundStyle(world.background)
            .padding(.horizontal, 17)
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(TactilePressScale(feedback: .primary))
        .shadow(color: color.opacity(0.22), radius: 10, y: 5)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(world.ink)
                .frame(width: 44, height: 44)
                .background(world.surface, in: Circle())
                .overlay(Circle().strokeBorder(world.accent.opacity(0.42), lineWidth: 1))
        }
        .buttonStyle(TactilePressScale())
        .accessibilityLabel(label)
    }
}

// MARK: - Screen

struct SnakeScreen: View {
    let difficulty: ChallengeDifficulty
    let modeBest: Int
    let allTimeBest: Int
    var todayBest: Int = 0
    var weekBest: Int = 0
    /// (score, final length) → persist.
    let onRunComplete: (Int, Int) -> Void
    let onQuit: () -> Void

    @State private var model = SnakeEngine()
    @State private var phase: Phase = .playing
    @State private var pauseController = GamePauseController()
    @State private var usedContinue = false
    @State private var canContinue = false
    @State private var adBusy = false
    @State private var runRecorded = true
    @State private var newAllTimeBest = false
    /// Best across every run since this screen opened, so the bests rows stay
    /// honest through PLAY AGAIN loops.
    @State private var sessionBest = 0
    /// Bumped on PLAY AGAIN so the run loop restarts for the fresh engine.
    @State private var runID = 0

    private enum Phase { case playing, over }

    private var world: GameWorld { GameID.snake.world }

    var body: some View {
        ZStack {
            GameWorldBackdrop(game: .snake, patternOpacity: 0.35)
            // The playing view stays mounted behind the game-over card so the
            // final board sits dimmed under the scrim.
            playing
            if phase == .over {
                if canContinue {
                    RewardedReviveOffer(game: .snake,
                                        busy: adBusy,
                                        onDecline: declineContinue,
                                        onSave: continueRun)
                } else {
                    runOver
                }
            }
        }
        .overlay {
            if phase == .playing, pauseController.isPaused {
                GamePausedOverlay(game: .snake,
                                  controller: pauseController,
                                  onQuit: {
                                      pauseController.reset()
                                      onQuit()
                                  })
            }
        }
        .onAppear { GameFeel.shared.warmUp() }
        .onDisappear {
            finalizeRun()
            pauseController.reset()
            GameFeel.shared.teardown()
        }
    }

    // MARK: Playing

    private var playing: some View {
        VStack(spacing: 0) {
            hud
                .padding(.horizontal, 16)
                .padding(.top, 10)

            boardView
                .padding(.horizontal, 30)
                .padding(.top, 14)
                .padding(.bottom, 16)
        }
        .allowsHitTesting(phase == .playing && !pauseController.isPaused)
        .task(id: runID) { await runLoop() }
    }

    private var hud: some View {
        EndlessRunHUD(game: .snake,
                      difficulty: difficulty,
                      score: model.score,
                      allTimeBest: allTimeBest,
                      onQuit: onQuit,
                      onPause: { pauseController.pause() })
    }

    // MARK: Board

    private var boardView: some View {
        GeometryReader { geo in
            let cell = min(geo.size.width / CGFloat(SnakeEngine.cols),
                           geo.size.height / CGFloat(SnakeEngine.rows))
            let boardW = cell * CGFloat(SnakeEngine.cols)
            let boardH = cell * CGFloat(SnakeEngine.rows)

            ZStack {
                // Per-frame drawing lives in its own TimelineView so nothing
                // else invalidates; the gesture rides a stable sibling layer.
                TimelineView(.animation(paused: pauseController.isPaused || !model.alive)) { timeline in
                    Canvas { context, size in
                        SnakeBoardPainter.draw(model: model,
                                               in: &context,
                                               size: size,
                                               cell: cell,
                                               now: timeline.date.timeIntervalSinceReferenceDate,
                                               world: world)
                    }
                }
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(steerGesture)
            }
            .frame(width: boardW, height: boardH)
            .background(world.surface.opacity(0.55),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(world.ink.opacity(0.10), lineWidth: 1)
            )
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    // MARK: Input

    /// Continuous steering: every ~22pt of drag in a fresh direction queues a
    /// turn and re-anchors, so a held finger can chain corners without lifting.
    private var steerGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { gesture in
                let anchor = model.dragAnchor ?? gesture.startLocation
                let dx = gesture.location.x - anchor.x
                let dy = gesture.location.y - anchor.y
                guard max(abs(dx), abs(dy)) >= 22 else { return }
                let dir: SnakeDir = abs(dx) > abs(dy)
                    ? (dx > 0 ? .right : .left)
                    : (dy > 0 ? .down : .up)
                if model.steer(dir) {
                    GameFeel.shared.uiSelection()
                }
                model.dragAnchor = gesture.location
            }
            .onEnded { _ in model.dragAnchor = nil }
    }

    // MARK: Loop

    /// Milliseconds per step: each mode sets the base tempo, and every apple
    /// quickens the run toward a floor.
    private var tickMS: Int {
        let base: Double = switch difficulty {
        case .easy: 200
        case .medium: 150
        default: 112
        }
        let ramp = min(0.34, Double(model.score) * 0.012)
        return Int(base * (1 - ramp))
    }

    private func runLoop() async {
        while !Task.isCancelled {
            let tick = tickMS
            try? await Task.sleep(for: .milliseconds(tick))
            guard phase == .playing, model.alive, !pauseController.isPaused else { continue }
            let outcome = model.step(tick: Double(tick) / 1_000)
            react(to: outcome)
            if outcome == .died {
                endRun()
                return
            }
        }
    }

    private func react(to outcome: SnakeEngine.StepOutcome) {
        guard outcome == .ate else { return }
        GameFeel.shared.play(.correct(combo: 1))
        if !newAllTimeBest, model.score > allTimeBest, allTimeBest > 0 {
            newAllTimeBest = true
            GameFeel.shared.play(.newBest)
        }
    }

    // MARK: Game over

    private func endRun() {
        if model.score > 0, allTimeBest == 0 || model.score > allTimeBest {
            newAllTimeBest = true
        }
        sessionBest = max(sessionBest, model.score)
        canContinue = !usedContinue && AdManager.shared.rewardedReady
        runRecorded = false
        if !canContinue { finalizeRun() }
        GameFeel.shared.play(.gameOver)
        withAnimation(.easeOut(duration: 0.3)) { phase = .over }
    }

    private func finalizeRun() {
        guard !runRecorded else { return }
        runRecorded = true
        onRunComplete(model.score, model.body.count)
    }

    private var runOver: some View {
        GameRunOverView(game: .snake,
                        score: model.score,
                        caption: "length \(model.body.count)",
                        bests: RunBestLine.standard(today: max(todayBest, sessionBest),
                                                    week: max(weekBest, sessionBest),
                                                    allTime: max(allTimeBest, sessionBest)),
                        celebrate: newAllTimeBest,
                        onHome: {
                            finalizeRun()
                            onQuit()
                        },
                        onPlayAgain: playAgain)
    }

    private func continueRun() {
        guard !adBusy, canContinue else { return }
        adBusy = true
        AdManager.shared.showRewarded { earned in
            adBusy = false
            guard earned else { return }
            usedContinue = true
            canContinue = false
            model.revive()
            runID += 1
            pauseController.reset()
            withAnimation(.easeOut(duration: 0.2)) { phase = .playing }
            pauseController.pause()
            pauseController.beginResumeCountdown()
        }
    }

    private func declineContinue() {
        withAnimation(.easeOut(duration: 0.2)) { canContinue = false }
        finalizeRun()
    }

    private func playAgain() {
        finalizeRun()
        model = SnakeEngine()
        newAllTimeBest = false
        usedContinue = false
        canContinue = false
        runID += 1
        pauseController.reset()
        withAnimation(.easeOut(duration: 0.2)) { phase = .playing }
    }
}

// MARK: - Painter

/// Draws the whole playfield each frame: checkerboard, apples, sparkles, and
/// the snake with tick-interpolated segment positions so motion is continuous.
private enum SnakeBoardPainter {

    static func draw(model: SnakeEngine,
                     in context: inout GraphicsContext,
                     size: CGSize,
                     cell: CGFloat,
                     now: TimeInterval,
                     world: GameWorld) {
        drawChecker(in: &context, cell: cell, world: world)

        // Interpolation fraction through the current tick.
        let t = model.tickDuration > 0
            ? CGFloat(min(1, max(0, (now - model.lastStepAt) / model.tickDuration)))
            : 1

        func point(_ c: SnakeCell) -> CGPoint {
            CGPoint(x: (CGFloat(c.x) + 0.5) * cell, y: (CGFloat(c.y) + 0.5) * cell)
        }

        /// Rendered position of segment `i`: glide from last tick's cell.
        func position(_ i: Int) -> CGPoint {
            let target = point(model.body[i])
            guard i < model.prevBody.count else { return target }
            let from = point(model.prevBody[i])
            return CGPoint(x: from.x + (target.x - from.x) * t,
                           y: from.y + (target.y - from.y) * t)
        }

        for food in model.foods {
            drawApple(in: &context, at: point(food), cell: cell, now: now)
        }
        drawSparkles(in: &context, model: model, cell: cell, now: now, point: point)

        let count = model.body.count
        guard count > 0 else { return }
        let positions = (0..<count).map(position)

        /// Travel direction at segment `i`, from its rendered neighbours.
        func heading(_ i: Int) -> CGVector {
            let ahead = positions[max(0, i - 1)]
            let behind = positions[min(count - 1, i + 1)]
            let dx = ahead.x - behind.x
            let dy = ahead.y - behind.y
            let len = max(0.001, sqrt(dx * dx + dy * dy))
            return CGVector(dx: dx / len, dy: dy / len)
        }

        drawTail(in: &context, positions: positions, cell: cell)

        // Body back-to-front so the head lands on top.
        for i in stride(from: count - 1, through: 1, by: -1) {
            drawSegment(in: &context, at: positions[i], heading: heading(i),
                        index: i, cell: cell)
        }
        drawHead(in: &context, model: model, at: positions[0], heading: heading(0),
                 cell: cell, point: point)
    }

    // MARK: Layers

    private static func drawChecker(in context: inout GraphicsContext,
                                    cell: CGFloat,
                                    world: GameWorld) {
        for x in 0..<SnakeEngine.cols {
            for y in 0..<SnakeEngine.rows where (x + y).isMultiple(of: 2) {
                context.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell,
                                         width: cell, height: cell)),
                             with: .color(world.ink.opacity(0.035)))
            }
        }
    }

    private static func drawApple(in context: inout GraphicsContext,
                                  at center: CGPoint,
                                  cell: CGFloat,
                                  now: TimeInterval) {
        let pulse = 1 + 0.05 * sin(now * 3.2 + Double(center.x))
        let radius = cell * 0.46 * pulse
        let rect = CGRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .color(SnakePalette.apple))
        context.stroke(Path(ellipseIn: rect.insetBy(dx: radius * 0.14, dy: radius * 0.14)),
                       with: .color(SnakePalette.appleRim),
                       lineWidth: radius * 0.22)
        // The leaf.
        var leaf = Path()
        leaf.move(to: CGPoint(x: center.x - radius * 0.1, y: center.y))
        leaf.addQuadCurve(to: CGPoint(x: center.x + radius * 0.62, y: center.y - radius * 0.18),
                          control: CGPoint(x: center.x + radius * 0.3, y: center.y - radius * 0.5))
        leaf.addQuadCurve(to: CGPoint(x: center.x - radius * 0.1, y: center.y),
                          control: CGPoint(x: center.x + radius * 0.3, y: center.y + radius * 0.14))
        context.fill(leaf, with: .color(SnakePalette.leaf))
    }

    private static func drawSparkles(in context: inout GraphicsContext,
                                     model: SnakeEngine,
                                     cell: CGFloat,
                                     now: TimeInterval,
                                     point: (SnakeCell) -> CGPoint) {
        let offsets: [(CGFloat, CGFloat, CGFloat)] = [   // (dx, dy, spin)
            (0.55, -0.55, 0), (-0.6, 0.15, 45), (0.35, 0.6, 20)
        ]
        for sparkle in model.sparkles {
            let age = now - sparkle.at
            guard age >= 0, age < 0.45 else { continue }
            let progress = CGFloat(age / 0.45)
            let alpha = 1 - progress
            let center = point(sparkle.cell)
            for (dx, dy, spin) in offsets {
                let p = CGPoint(x: center.x + dx * cell * (0.7 + progress * 0.5),
                                y: center.y + dy * cell * (0.7 + progress * 0.5))
                let arm = cell * (0.14 + 0.1 * progress)
                var star = Path()
                for angle in [0.0, 90.0] {
                    let rad = (angle + Double(spin)) * .pi / 180
                    let vx = CGFloat(cos(rad)) * arm
                    let vy = CGFloat(sin(rad)) * arm
                    star.move(to: CGPoint(x: p.x - vx, y: p.y - vy))
                    star.addLine(to: CGPoint(x: p.x + vx, y: p.y + vy))
                }
                context.stroke(star,
                               with: .color(.white.opacity(0.85 * alpha)),
                               style: StrokeStyle(lineWidth: cell * 0.08, lineCap: .round))
            }
        }
    }

    private static func drawTail(in context: inout GraphicsContext,
                                 positions: [CGPoint],
                                 cell: CGFloat) {
        guard positions.count >= 2 else { return }
        let tip = positions[positions.count - 1]
        let prev = positions[positions.count - 2]
        var dx = tip.x - prev.x
        var dy = tip.y - prev.y
        let len = max(0.001, sqrt(dx * dx + dy * dy))
        dx /= len; dy /= len
        let radius = cell * 0.42
        // A cone from the last disc out to a point, so the tail tapers.
        var cone = Path()
        cone.move(to: CGPoint(x: tip.x - dy * radius, y: tip.y + dx * radius))
        cone.addLine(to: CGPoint(x: tip.x + dy * radius, y: tip.y - dx * radius))
        cone.addLine(to: CGPoint(x: tip.x + dx * cell * 1.05, y: tip.y + dy * cell * 1.05))
        cone.closeSubpath()
        context.fill(cone, with: .color(SnakePalette.body))
    }

    private static func drawSegment(in context: inout GraphicsContext,
                                    at center: CGPoint,
                                    heading: CGVector,
                                    index: Int,
                                    cell: CGFloat) {
        let radius = cell * 0.55
        let rect = CGRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect),
                     with: .color(index.isMultiple(of: 2) ? SnakePalette.body : SnakePalette.bodyAlt))
        context.stroke(Path(ellipseIn: rect.insetBy(dx: radius * 0.08, dy: radius * 0.08)),
                       with: .color(SnakePalette.rim.opacity(0.45)),
                       lineWidth: radius * 0.12)

        // Two dashed stripes across the disc, perpendicular to travel.
        let perp = CGVector(dx: -heading.dy, dy: heading.dx)
        var stripes = Path()
        for offset in [-0.22, 0.22] {
            let ox = heading.dx * radius * offset
            let oy = heading.dy * radius * offset
            stripes.move(to: CGPoint(x: center.x + ox - perp.dx * radius * 0.58,
                                     y: center.y + oy - perp.dy * radius * 0.58))
            stripes.addLine(to: CGPoint(x: center.x + ox + perp.dx * radius * 0.58,
                                        y: center.y + oy + perp.dy * radius * 0.58))
        }
        context.stroke(stripes,
                       with: .color(SnakePalette.rim.opacity(0.7)),
                       style: StrokeStyle(lineWidth: radius * 0.16,
                                          lineCap: .round,
                                          dash: [radius * 0.34, radius * 0.3]))
    }

    private static func drawHead(in context: inout GraphicsContext,
                                 model: SnakeEngine,
                                 at center: CGPoint,
                                 heading: CGVector,
                                 cell: CGFloat,
                                 point: (SnakeCell) -> CGPoint) {
        let radius = cell * 0.62
        let rect = CGRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .color(SnakePalette.head))

        // Open the mouth when an apple sits within a cell and a half ahead.
        let mouthOpen = model.foods.contains { food in
            let p = point(food)
            let dx = p.x - center.x
            let dy = p.y - center.y
            let along = dx * heading.dx + dy * heading.dy
            let across = abs(dx * heading.dy - dy * heading.dx)
            return along > 0 && along < cell * 1.6 && across < cell * 0.75
        }
        if mouthOpen {
            var mouth = Path()
            mouth.move(to: center)
            let spread = 0.55
            for sign in [-1.0, 1.0] {
                let angle = atan2(heading.dy, heading.dx) + sign * spread
                mouth.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * radius * 1.08,
                                          y: center.y + CGFloat(sin(angle)) * radius * 1.08))
            }
            mouth.closeSubpath()
            context.fill(mouth, with: .color(SnakePalette.mouth))
        }

        // Googly eyes riding the front of the head, pupils chasing the food.
        let perp = CGVector(dx: -heading.dy, dy: heading.dx)
        let nearestFood = model.foods.map(point).min {
            hypot($0.x - center.x, $0.y - center.y) < hypot($1.x - center.x, $1.y - center.y)
        }
        var look = heading
        if let nearestFood {
            let dx = nearestFood.x - center.x
            let dy = nearestFood.y - center.y
            let len = max(0.001, sqrt(dx * dx + dy * dy))
            look = CGVector(dx: dx / len, dy: dy / len)
        }
        for sign in [-1.0, 1.0] {
            let eyeCenter = CGPoint(
                x: center.x + heading.dx * radius * 0.28 + perp.dx * radius * 0.5 * sign,
                y: center.y + heading.dy * radius * 0.28 + perp.dy * radius * 0.5 * sign
            )
            let eyeR = radius * 0.42
            context.fill(Path(ellipseIn: CGRect(x: eyeCenter.x - eyeR, y: eyeCenter.y - eyeR,
                                                width: eyeR * 2, height: eyeR * 2)),
                         with: .color(.white))
            let pupilR = eyeR * 0.52
            let pupil = CGPoint(x: eyeCenter.x + look.dx * eyeR * 0.42,
                                y: eyeCenter.y + look.dy * eyeR * 0.42)
            context.fill(Path(ellipseIn: CGRect(x: pupil.x - pupilR, y: pupil.y - pupilR,
                                                width: pupilR * 2, height: pupilR * 2)),
                         with: .color(.black))
        }
    }
}

// MARK: - Pieces

enum SnakePalette {
    static let body = Color(hexAny: 0x58C452)
    static let bodyAlt = Color(hexAny: 0x6ED95F)
    static let head = Color(hexAny: 0x63D957)
    static let rim = Color(hexAny: 0x2F7A33)
    static let mouth = Color(hexAny: 0x143017)
    static let apple = Color(hexAny: 0xF05B4C)
    static let appleRim = Color(hexAny: 0xC23F35)
    static let leaf = Color(hexAny: 0x1F4A22)
}
