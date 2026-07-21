//
//  TowerGame.swift
//  wits
//
//  Tower: the classic tap-timing stacker. No levels, three speed modes
//  (easy / medium / hard) each keep their own best score, and one all-time
//  best stands across every mode. A block glides across the top of the tower
//  on alternating axes; a tap drops it, the overhang is sliced away, and a
//  perfect drop keeps the block whole, chain perfects and the block slowly
//  grows back. The run ends when a block misses the stack completely.
//
//  Rendering is a single TimelineView-driven Canvas painting an isometric
//  tower: the engine is a plain class whose per-frame fields (slide position,
//  falling slices, ripples, camera) live outside observation and are advanced
//  by the painter each frame, so motion is continuous and taps land exactly
//  where the block is drawn.
//

import SwiftUI

// MARK: - Engine

/// One placed slab: footprint center/size in plan units (base block = 1×1).
struct TowerLayer {
    var cx: Double
    var cz: Double
    var w: Double
    var d: Double
    var hueIndex: Int
}

/// A sliced-off overhang (or a fully missed block) tumbling off the tower.
struct TowerCut {
    var cx: Double
    var cz: Double
    var w: Double
    var d: Double
    var y: Double           // top of the piece when it broke off
    var hueIndex: Int
    var bornAt: TimeInterval
    var vx: Double          // plan-velocity it keeps while falling
    var vz: Double
}

/// Expanding rings celebrating a perfect drop; more rings as the streak grows.
struct TowerRipple {
    var level: Int
    var w: Double
    var d: Double
    var at: TimeInterval
    var rings: Int
}

@Observable
final class TowerEngine {
    static let layerHeight = 0.28
    static let pedestalDepth = 2.6
    /// A slice thinner than this is treated as a clean miss.
    static let minOverlap = 0.02

    private(set) var score = 0
    private(set) var alive = true
    private(set) var perfects = 0
    private(set) var bestStreak = 0

    // Per-frame state, advanced by the painter and read ~60×/s: none of it
    // participates in observation.
    @ObservationIgnored private(set) var layers: [TowerLayer] = []
    @ObservationIgnored private(set) var cuts: [TowerCut] = []
    @ObservationIgnored private(set) var ripples: [TowerRipple] = []
    @ObservationIgnored private(set) var movingAxis = 0        // 0 slides along x, 1 along z
    @ObservationIgnored private(set) var movingPos = 0.0       // center on the active axis
    @ObservationIgnored private(set) var movingW = 1.0
    @ObservationIgnored private(set) var movingD = 1.0
    @ObservationIgnored private(set) var movingHueIndex = 1
    @ObservationIgnored private(set) var cameraY = 0.0         // smoothed world-y the view tracks
    @ObservationIgnored private(set) var gameOverAt: TimeInterval?
    @ObservationIgnored private(set) var lastPerfectAt: TimeInterval?
    @ObservationIgnored private(set) var baseHue: Double
    @ObservationIgnored private var direction = 1.0
    @ObservationIgnored private var streak = 0
    @ObservationIgnored private var lastUpdateAt: TimeInterval?
    /// Touch bookkeeping lives on the model: mutating it never invalidates SwiftUI.
    @ObservationIgnored var touchActive = false

    @ObservationIgnored private let baseSpeed: Double
    @ObservationIgnored private let tolerance: Double

    init(difficulty: ChallengeDifficulty) {
        switch difficulty {
        case .easy:
            baseSpeed = 1.1
            tolerance = 0.056
        case .medium:
            baseSpeed = 1.4
            tolerance = 0.042
        default:
            baseSpeed = 1.75
            tolerance = 0.032
        }
        baseHue = Double.random(in: 0..<1)
        layers = [TowerLayer(cx: 0, cz: 0, w: 1, d: 1, hueIndex: 0)]
        spawnNext()
    }

    enum DropOutcome: Equatable {
        case placed
        case perfect(streak: Int)
        case missed
    }

    var topLayer: TowerLayer { layers[layers.count - 1] }
    /// World-y of the tower's top surface: layer i's top sits at i·h, so with
    /// only the base (index 0) present this is 0.
    var towerTopY: Double { Double(layers.count - 1) * Self.layerHeight }

    /// Units/sec on the active axis; quickens gently as the tower grows,
    /// reaching full pace around fifty blocks.
    private var speed: Double {
        baseSpeed * (1 + min(0.35, Double(score) * 0.007))
    }

    /// How far the block's center travels before bouncing back.
    private var travelBound: Double {
        let size = movingAxis == 0 ? movingW : movingD
        return 0.55 + size / 2 + 0.22
    }

    /// Advance the slide, the falling slices, and the camera. Called every
    /// frame by the painter; safe while dead (slices keep tumbling).
    func update(now: TimeInterval) {
        let dt = min(0.05, max(0, now - (lastUpdateAt ?? now)))
        lastUpdateAt = now

        if alive {
            movingPos += direction * speed * dt
            let bound = travelBound
            if movingPos > bound { movingPos = bound; direction = -1 }
            if movingPos < -bound { movingPos = -bound; direction = 1 }
        }

        cuts.removeAll { now - $0.bornAt > 1.4 }
        ripples.removeAll { now - $0.at > 1.0 }

        let target = towerTopY
        cameraY += (target - cameraY) * min(1, dt * 4.5)
    }

    @discardableResult
    func drop(now: TimeInterval) -> DropOutcome {
        guard alive else { return .missed }

        let top = topLayer
        let topCenter = movingAxis == 0 ? top.cx : top.cz
        let topSize = movingAxis == 0 ? top.w : top.d
        let size = movingAxis == 0 ? movingW : movingD
        let lo = max(movingPos - size / 2, topCenter - topSize / 2)
        let hi = min(movingPos + size / 2, topCenter + topSize / 2)
        let overlap = hi - lo

        guard overlap > Self.minOverlap else {
            // Clean miss: the whole block falls and the run ends.
            cuts.append(cut(center: movingPos, size: size, now: now))
            alive = false
            gameOverAt = now
            return .missed
        }

        if abs(movingPos - topCenter) <= tolerance {
            // Perfect: snap to center at the block's own (possibly regrown)
            // size, no slice, ripple out, streak climbs.
            streak += 1
            perfects += 1
            bestStreak = max(bestStreak, streak)
            place(center: topCenter, size: size)
            ripples.append(TowerRipple(level: layers.count - 1,
                                       w: movingAxis == 0 ? size : movingW,
                                       d: movingAxis == 1 ? size : movingD,
                                       at: now,
                                       rings: min(4, 1 + streak / 2)))
            lastPerfectAt = now
            let result = DropOutcome.perfect(streak: streak)
            score += 1
            spawnNext()
            return result
        }

        // Partial: keep the overlap, shed the overhang.
        streak = 0
        let keptCenter = (lo + hi) / 2
        let shedSize = size - overlap
        let shedCenter = movingPos > topCenter ? hi + shedSize / 2 : lo - shedSize / 2
        cuts.append(cut(center: shedCenter, size: shedSize, now: now))
        place(center: keptCenter, size: overlap)
        score += 1
        spawnNext()
        return .placed
    }

    private func place(center: Double, size: Double) {
        let top = topLayer
        layers.append(TowerLayer(cx: movingAxis == 0 ? center : top.cx,
                                 cz: movingAxis == 1 ? center : top.cz,
                                 w: movingAxis == 0 ? size : movingW,
                                 d: movingAxis == 1 ? size : movingD,
                                 hueIndex: movingHueIndex))
    }

    private func cut(center: Double, size: Double, now: TimeInterval) -> TowerCut {
        let top = topLayer
        return TowerCut(cx: movingAxis == 0 ? center : top.cx,
                        cz: movingAxis == 1 ? center : top.cz,
                        w: movingAxis == 0 ? size : movingW,
                        d: movingAxis == 1 ? size : movingD,
                        y: towerTopY + Self.layerHeight,
                        hueIndex: movingHueIndex,
                        bornAt: now,
                        vx: movingAxis == 0 ? direction * speed * 0.35 : 0,
                        vz: movingAxis == 1 ? direction * speed * 0.35 : 0)
    }

    private func spawnNext() {
        let top = topLayer
        movingW = top.w
        movingD = top.d
        // Two straight perfects start feeding size back, up to the full base.
        if streak >= 2 {
            movingW = min(1, movingW + 0.035)
            movingD = min(1, movingD + 0.035)
        }
        movingAxis = layers.count % 2 == 0 ? 1 : 0
        movingHueIndex = layers.count
        direction = Bool.random() ? 1 : -1
        movingPos = -direction * (travelBound + 0.12)
    }

    /// One final chance replaces the missed moving slab and preserves the
    /// tower already built. A second miss ends the run normally.
    func revive() {
        guard !alive else { return }
        alive = true
        gameOverAt = nil
        lastUpdateAt = nil
        streak = 0
        spawnNext()
    }
}

// MARK: - Palette

/// Face colors walk the hue wheel as the tower rises, like dawn turning to
/// day: every layer nudges the hue, saturation breathing slowly underneath.
enum TowerShades {
    static func top(_ base: Double, _ index: Int) -> Color { face(base, index, brightness: 0.94) }
    static func left(_ base: Double, _ index: Int) -> Color { face(base, index, brightness: 0.74) }
    static func right(_ base: Double, _ index: Int) -> Color { face(base, index, brightness: 0.56) }

    private static func face(_ base: Double, _ index: Int, brightness: Double) -> Color {
        let hue = (base + Double(index) * 0.012).truncatingRemainder(dividingBy: 1)
        let sat = 0.46 + 0.12 * sin(Double(index) * 0.07)
        return Color(hue: hue, saturation: sat, brightness: brightness)
    }
}

// MARK: - Mode select

/// Tower's pre-game screen: no levels, just the three speed modes with their
/// own bests and the all-time best underneath.
struct TowerModeSelectView: View {
    var onPlay: (ChallengeDifficulty) -> Void
    var onClose: () -> Void
    var onHelp: (() -> Void)? = nil

    @Environment(AppModel.self) private var app

    private let game = GameID.tower
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

struct TowerScreen: View {
    let difficulty: ChallengeDifficulty
    let modeBest: Int
    let allTimeBest: Int
    let todayBest: Int
    let weekBest: Int
    /// (score, perfects, best streak) → persist.
    let onRunComplete: (Int, Int, Int) -> Void
    let onQuit: () -> Void

    @State private var model: TowerEngine
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

    private enum Phase { case playing, over }

    private var world: GameWorld { GameID.tower.world }

    init(difficulty: ChallengeDifficulty,
         modeBest: Int,
         allTimeBest: Int,
         todayBest: Int = 0,
         weekBest: Int = 0,
         onRunComplete: @escaping (Int, Int, Int) -> Void,
         onQuit: @escaping () -> Void) {
        self.difficulty = difficulty
        self.modeBest = modeBest
        self.allTimeBest = allTimeBest
        self.todayBest = todayBest
        self.weekBest = weekBest
        self.onRunComplete = onRunComplete
        self.onQuit = onQuit
        _model = State(initialValue: TowerEngine(difficulty: difficulty))
    }

    var body: some View {
        ZStack {
            GameWorldBackdrop(game: .tower, patternOpacity: 0.8)
            // The playing view stays mounted behind the game-over card so the
            // pulled-back tower sits dimmed under the scrim.
            playing
            if phase == .over {
                if canContinue {
                    RewardedReviveOffer(game: .tower,
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
                GamePausedOverlay(game: .tower,
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
        ZStack(alignment: .top) {
            towerView
            hud
                .padding(.horizontal, 16)
                .padding(.top, 10)
        }
        .allowsHitTesting(phase == .playing && !pauseController.isPaused)
    }

    private var hud: some View {
        EndlessRunHUD(game: .tower,
                      difficulty: difficulty,
                      score: model.score,
                      allTimeBest: allTimeBest,
                      onQuit: onQuit,
                      onPause: { pauseController.pause() })
    }

    // MARK: Tower

    private var towerView: some View {
        ZStack {
            TimelineView(.animation(paused: pauseController.isPaused)) { timeline in
                Canvas { context, size in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    model.update(now: now)
                    TowerPainter.draw(model: model, in: &context, size: size, now: now)
                }
            }
            Color.clear
                .contentShape(Rectangle())
                .gesture(dropGesture)
        }
        .ignoresSafeArea()
    }

    /// Fire on touch-down (not touch-up) so drops land exactly on the beat.
    private var dropGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !model.touchActive else { return }
                model.touchActive = true
                let outcome = model.drop(now: Date().timeIntervalSinceReferenceDate)
                react(to: outcome)
            }
            .onEnded { _ in model.touchActive = false }
    }

    private func react(to outcome: TowerEngine.DropOutcome) {
        switch outcome {
        case .placed:
            GameFeel.shared.play(.correct(combo: 1))
        case .perfect(let streak):
            GameFeel.shared.play(streak >= 3 ? .comboMilestone(streak) : .correct(combo: streak + 1))
        case .missed:
            endRun()
            return
        }
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
        // Let the camera pull back over the whole tower before the summary.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_500))
            withAnimation(.easeOut(duration: 0.3)) { phase = .over }
        }
    }

    private func finalizeRun() {
        guard !runRecorded else { return }
        runRecorded = true
        onRunComplete(model.score, model.perfects, model.bestStreak)
    }

    private var runOver: some View {
        GameRunOverView(game: .tower,
                        score: model.score,
                        caption: "\(model.perfects) perfect · best streak \(model.bestStreak)",
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
        model = TowerEngine(difficulty: difficulty)
        newAllTimeBest = false
        usedContinue = false
        canContinue = false
        pauseController.reset()
        withAnimation(.easeOut(duration: 0.2)) { phase = .playing }
    }
}

// MARK: - Painter

/// Isometric renderer: pedestal, placed slabs, falling slices, the sliding
/// block, and the perfect-drop ripples. The camera tracks the tower top while
/// alive and pulls back to frame the whole run after a miss.
private enum TowerPainter {

    static func draw(model: TowerEngine, in context: inout GraphicsContext, size: CGSize, now: TimeInterval) {
        let usable = min(size.width, 520.0)
        let baseScale = usable * 0.34
        let h = TowerEngine.layerHeight

        // Camera blend: gameplay framing → whole-tower framing after a miss.
        let zoom: Double
        if let overAt = model.gameOverAt {
            let t = min(1, max(0, (now - overAt) / 1.1))
            zoom = t * t * (3 - 2 * t)
        } else {
            zoom = 0
        }
        let towerHeight = (model.towerTopY + TowerEngine.pedestalDepth) * baseScale
        let fitScale = min(1, size.height * 0.72 / max(1, towerHeight))
        let scale = baseScale * (1 + (fitScale - 1) * zoom)
        let focusY = model.cameraY + ((model.towerTopY - TowerEngine.pedestalDepth) / 2 - model.cameraY) * zoom
        let anchorY = size.height * (0.62 + (0.52 - 0.62) * zoom)
        let cx = size.width / 2

        func project(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
            CGPoint(x: cx + (x - z) * 0.866 * scale,
                    y: anchorY - (y - focusY) * scale + (x + z) * 0.5 * scale)
        }

        func fillQuad(_ points: [CGPoint], _ color: Color, opacity: Double = 1) {
            var path = Path()
            path.move(to: points[0])
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
            context.fill(path, with: .color(color.opacity(opacity)))
        }

        /// One box: top face plus the two viewer-facing sides.
        func drawBox(cx bx: Double, cz bz: Double, w: Double, d: Double,
                     yBottom: Double, yTop: Double, hueIndex: Int, opacity: Double = 1) {
            let x0 = bx - w / 2, x1 = bx + w / 2
            let z0 = bz - d / 2, z1 = bz + d / 2
            let base = model.baseHue
            // Top face.
            fillQuad([project(x0, yTop, z0), project(x1, yTop, z0),
                      project(x1, yTop, z1), project(x0, yTop, z1)],
                     TowerShades.top(base, hueIndex), opacity: opacity)
            // +x face (viewer's lower right).
            fillQuad([project(x1, yTop, z0), project(x1, yTop, z1),
                      project(x1, yBottom, z1), project(x1, yBottom, z0)],
                     TowerShades.right(base, hueIndex), opacity: opacity)
            // +z face (viewer's lower left).
            fillQuad([project(x0, yTop, z1), project(x1, yTop, z1),
                      project(x1, yBottom, z1), project(x0, yBottom, z1)],
                     TowerShades.left(base, hueIndex), opacity: opacity)
        }

        // Pedestal: the base footprint extruded down past the bottom edge.
        let pedestal = model.layers[0]
        drawBox(cx: pedestal.cx, cz: pedestal.cz, w: pedestal.w, d: pedestal.d,
                yBottom: -TowerEngine.pedestalDepth, yTop: 0, hueIndex: 0)

        // Placed slabs, bottom to top. During play only the visible crown
        // matters; the pull-back reveal draws everything.
        let firstVisible = zoom > 0 ? 1 : max(1, model.layers.count - 18)
        for index in firstVisible..<model.layers.count {
            let layer = model.layers[index]
            drawBox(cx: layer.cx, cz: layer.cz, w: layer.w, d: layer.d,
                    yBottom: Double(index - 1) * h, yTop: Double(index) * h,
                    hueIndex: layer.hueIndex)
        }

        // Falling slices tumble away and fade.
        for cut in model.cuts {
            let age = now - cut.bornAt
            let fall = 4.5 * age * age
            let opacity = max(0, 1 - age / 1.1)
            drawBox(cx: cut.cx + cut.vx * age, cz: cut.cz + cut.vz * age,
                    w: cut.w, d: cut.d,
                    yBottom: cut.y - h - fall, yTop: cut.y - fall,
                    hueIndex: cut.hueIndex, opacity: opacity)
        }

        // The sliding block rides at the level it will land on.
        if model.alive {
            let top = model.topLayer
            let bx = model.movingAxis == 0 ? model.movingPos : top.cx
            let bz = model.movingAxis == 1 ? model.movingPos : top.cz
            drawBox(cx: bx, cz: bz, w: model.movingW, d: model.movingD,
                    yBottom: model.towerTopY, yTop: model.towerTopY + h,
                    hueIndex: model.movingHueIndex)
        }

        // Perfect-drop rings expanding around the landed slab.
        for ripple in model.ripples {
            let layerTop = Double(ripple.level) * h
            for ring in 0..<ripple.rings {
                let age = now - ripple.at - Double(ring) * 0.12
                guard age > 0, age < 0.62 else { continue }
                let progress = age / 0.62
                let grow = 1 + progress * 0.95
                let alpha = (1 - progress) * 0.85
                let w = ripple.w * grow, d = ripple.d * grow
                let layer = model.layers[min(ripple.level, model.layers.count - 1)]
                var path = Path()
                path.move(to: project(layer.cx - w / 2, layerTop, layer.cz - d / 2))
                path.addLine(to: project(layer.cx + w / 2, layerTop, layer.cz - d / 2))
                path.addLine(to: project(layer.cx + w / 2, layerTop, layer.cz + d / 2))
                path.addLine(to: project(layer.cx - w / 2, layerTop, layer.cz + d / 2))
                path.closeSubpath()
                context.stroke(path, with: .color(.white.opacity(alpha)),
                               lineWidth: 2.5 * (1 - progress) + 0.5)
            }
        }

        // A brief white glint on the top face right after a perfect.
        if let perfectAt = model.lastPerfectAt {
            let age = now - perfectAt
            if age < 0.22, model.layers.count > 1 {
                let layer = model.layers[model.layers.count - 1]
                let yTop = Double(model.layers.count - 1) * h
                fillQuad([project(layer.cx - layer.w / 2, yTop, layer.cz - layer.d / 2),
                          project(layer.cx + layer.w / 2, yTop, layer.cz - layer.d / 2),
                          project(layer.cx + layer.w / 2, yTop, layer.cz + layer.d / 2),
                          project(layer.cx - layer.w / 2, yTop, layer.cz + layer.d / 2)],
                         .white, opacity: 0.55 * (1 - age / 0.22))
            }
        }
    }
}
