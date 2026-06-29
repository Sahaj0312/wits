//
//  ArcadeSK.swift
//  wits
//
//  SpriteKit render/FX substrate. Runs the SAME game logic (ArcadeGame: spawn /
//  preStep / postStep / resolve, unit-space entities) but renders with SKNodes,
//  soft shadows, and particle bursts for a premium look. Hosted in SwiftUI via
//  SpriteView. The engine contract (cfg.report / GameResult / survival) is
//  unchanged. Textures are generated in code now; swap to provided art later.
//

import SwiftUI
import SpriteKit
import UIKit

// MARK: - Style + generated textures

struct ArcadeStyle {
    let size: CGSize
    let dab: SKTexture
    let ring: SKTexture
    let spark: SKTexture
    var unit: CGFloat { min(size.width, size.height) }
    /// unit-space (top-down) → scene point (bottom-up).
    func pt(_ u: CGPoint) -> CGPoint { CGPoint(x: u.x * size.width, y: (1 - u.y) * size.height) }
}

/// Provided art assets (white-on-transparent for tinting; bg is full colour).
enum ArcadeTextures {
    static let dab = SKTexture(imageNamed: "soft-dab")
    static let ring = SKTexture(imageNamed: "soft-ring")
    static let spark = SKTexture(imageNamed: "spark")
    static let bg = SKTexture(imageNamed: "field-bg")
}

extension SKNode {
    /// A soft drop shadow beneath the node (premium depth on a light field).
    func addSoftShadow(radius: CGFloat, style: ArcadeStyle, alpha: CGFloat = 0.16) {
        let s = SKSpriteNode(texture: style.dab)
        s.size = CGSize(width: radius * 3.6, height: radius * 3.6)
        s.color = UIColor(white: 0.05, alpha: 1); s.colorBlendFactor = 1
        s.alpha = alpha
        s.position = CGPoint(x: 0, y: -radius * 0.35)
        s.zPosition = -1
        addChild(s)
    }
}

func roundedUIFont(_ size: CGFloat, weight: UIFont.Weight = .heavy) -> UIFont {
    let base = UIFont.systemFont(ofSize: size, weight: weight)
    if let d = base.fontDescriptor.withDesign(.rounded) { return UIFont(descriptor: d, size: size) }
    return base
}

// MARK: - Scene

@MainActor
final class ArcadeSKScene: SKScene {
    private let cfg: GameConfig
    private let game: any ArcadeGame
    private let onResult: (GameResult) -> Void

    private let model = ArcadeScene()
    private var base = Spawner()
    private var style: ArcadeStyle!
    private var nodes: [Int: SKNode] = [:]
    private let fieldLayer = SKNode()

    private var lastT: TimeInterval = 0
    private var running = false
    private var finished = false
    private let startedAt = Date()

    private var hits = 0, misses = 0, near = 0, score = 0, combo = 0, bestCombo = 0
    private var timeLeft = 45.0
    private var multiplier: Int { min(6, 1 + combo / 3) }

    // input state
    private var startUnit: CGPoint?
    private var dragID: Int?
    private var traceIDs: [Int] = []

    // HUD
    private let scoreLabel = SKLabelNode()
    private let timerLabel = SKLabelNode()

    init(cfg: GameConfig, game: any ArcadeGame, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg; self.game = game; self.onResult = onResult
        super.init(size: CGSize(width: 390, height: 700))
        scaleMode = .resizeFill
        anchorPoint = .zero
    }
    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        guard style == nil else { return }
        style = ArcadeStyle(size: size, dab: ArcadeTextures.dab, ring: ArcadeTextures.ring, spark: ArcadeTextures.spark)
        model.bounds = size

        // Background: these games use the themed app background (matching arrow
        // storm's clean look); other arcade games use the provided light field art.
        let themedBackgroundGames: Set<GameID> = [.crowdControl, .echoGrid, .pathKeeper]
        if themedBackgroundGames.contains(game.id) {
            backgroundColor = UIColor(Color.witsBg)
        } else {
            // premium light background (provided asset, aspect-filled)
            let bg = SKSpriteNode(texture: ArcadeTextures.bg)
            bg.position = CGPoint(x: size.width/2, y: size.height/2)
            bg.zPosition = -10
            let tex = ArcadeTextures.bg.size()
            if tex.width > 0, tex.height > 0 {
                let scale = max(size.width / tex.width, size.height / tex.height)
                bg.size = CGSize(width: tex.width * scale, height: tex.height * scale)
            } else {
                bg.size = size
            }
            addChild(bg)
        }

        addChild(fieldLayer)
        game.setupScene(self, style: style)
        setupHUD()

        base = game.seed(level: cfg.difficulty.level, survival: cfg.isSurvival)
        model.spawner = base
        timeLeft = cfg.targetDurationSec

        showHowTo()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard let style, style.size != size else { return }
        self.style = ArcadeStyle(size: size, dab: ArcadeTextures.dab, ring: ArcadeTextures.ring, spark: ArcadeTextures.spark)
        model.bounds = size
    }

    // MARK: HUD + how-to

    private func setupHUD() {
        let topInset: CGFloat = 64   // clear the status bar / Dynamic Island
        scoreLabel.attributedText = scoreText()
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.verticalAlignmentMode = .top
        scoreLabel.position = CGPoint(x: 24, y: size.height - topInset)
        scoreLabel.zPosition = 50
        if !cfg.isSurvival { addChild(scoreLabel) }

        timerLabel.horizontalAlignmentMode = .right
        timerLabel.verticalAlignmentMode = .top
        timerLabel.position = CGPoint(x: size.width - 24, y: size.height - topInset)
        timerLabel.zPosition = 50
        if !cfg.isSurvival { addChild(timerLabel) }
        updateHUD()
    }

    private func scoreText() -> NSAttributedString {
        NSAttributedString(string: "\(score)", attributes: [
            .font: roundedUIFont(28), .foregroundColor: UIColor(Color.witsInk)])
    }

    private func updateHUD() {
        guard !cfg.isSurvival else { return }
        scoreLabel.attributedText = scoreText()
        timerLabel.attributedText = NSAttributedString(string: "\(Int(ceil(timeLeft)))s", attributes: [
            .font: roundedUIFont(22), .foregroundColor: UIColor(Color.witsMuted)])
    }

    private func showHowTo() {
        let label = SKLabelNode()
        label.attributedText = NSAttributedString(string: game.howTo, attributes: [
            .font: roundedUIFont(17, weight: .semibold), .foregroundColor: UIColor(Color.witsInk)])
        label.numberOfLines = 2
        label.preferredMaxLayoutWidth = size.width * 0.7
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: size.width/2, y: size.height/2)
        label.zPosition = 100

        let plate = SKShapeNode(rectOf: CGSize(width: size.width * 0.82, height: 90), cornerRadius: 18)
        plate.fillColor = UIColor(Color.witsCard)
        plate.strokeColor = UIColor(Color.witsLine)
        plate.lineWidth = 1
        plate.position = CGPoint(x: size.width/2, y: size.height/2)
        plate.zPosition = 99
        plate.addChild(label)
        label.position = .zero
        addChild(plate)

        plate.run(.sequence([.wait(forDuration: 1.6),
                             .fadeOut(withDuration: 0.25),
                             .removeFromParent()]))
        run(.wait(forDuration: 1.6)) { [weak self] in self?.running = true }
    }

    // MARK: Loop

    override func update(_ currentTime: TimeInterval) {
        defer { lastT = currentTime }
        guard running, !finished, style != nil, !cfg.isPaused else { return }
        let dt = min(max(currentTime - lastT, 0), 0.1)
        guard dt > 0 else { return }

        game.preStep(scene: model, dt: dt)
        Escalation.apply(&model.spawner, base: base, runTime: model.runTime, combo: combo, survival: cfg.isSurvival)
        model.spawner.acc += dt * model.spawner.rate
        while model.spawner.acc >= 1, model.aliveCount < model.spawner.maxAlive {
            model.spawner.acc -= 1
            game.spawn(into: model, params: model.spawner)
        }
        model.integrate(dt)
        for r in game.postStep(scene: model, dt: dt) { emit(r) }

        syncNodes()

        if !cfg.isSurvival {
            timeLeft -= dt
            updateHUD()
            if timeLeft <= 0 { finish() }
        }
    }

    private func syncNodes() {
        let alive = Set(model.entities.filter { !$0.dead }.map(\.id))
        for e in model.entities where !e.dead {
            if let n = nodes[e.id] {
                if !e.dragging { n.position = style.pt(e.pos) }
                game.refreshNode(n, e, style: style)
            } else {
                let n = game.makeNode(e, style: style)
                n.position = style.pt(e.pos)
                n.setScale(0.2)
                n.run(.scale(to: 1, duration: 0.18))
                fieldLayer.addChild(n)
                nodes[e.id] = n
            }
        }
        for (id, n) in nodes where !alive.contains(id) {
            nodes[id] = nil
            n.run(.sequence([.group([.scale(to: 1.3, duration: 0.12), .fadeOut(withDuration: 0.12)]),
                             .removeFromParent()]))
        }
        // drop entities removed from model entirely
        let present = Set(model.entities.map(\.id))
        for (id, n) in nodes where !present.contains(id) {
            nodes[id] = nil; n.removeFromParent()
        }
    }

    // MARK: Scoring

    private func emit(_ r: Resolution) {
        switch r.kind {
        case .hit:
            hits += 1; combo += 1; bestCombo = max(bestCombo, combo)
            score += r.points * multiplier
            if let id = r.entityID, let n = nodes[id] { fx(at: n.position, color: UIColor(Color.witsAccent)) }
        case .nearMiss:
            near += 1; combo = 0
        case .miss:
            misses += 1; combo = 0; shake()
        case .timeout:
            misses += 1; combo = 0
        }
        cfg.report(r.kind, points: r.points, combo: combo)
        updateHUD()
    }

    private func fx(at point: CGPoint, color: UIColor) {
        let ring = SKSpriteNode(texture: style.ring)
        ring.position = point; ring.size = CGSize(width: 60, height: 60)
        ring.color = color; ring.colorBlendFactor = 1; ring.zPosition = 30
        addChild(ring)
        ring.run(.sequence([.group([.scale(to: 2.4, duration: 0.35), .fadeOut(withDuration: 0.35)]), .removeFromParent()])
        )
        for _ in 0..<8 {
            let s = SKSpriteNode(texture: style.spark)
            s.position = point; s.size = CGSize(width: 14, height: 14)
            s.color = color; s.colorBlendFactor = 1; s.zPosition = 30
            let ang = Double.random(in: 0..<(2 * .pi))
            s.zRotation = ang - .pi / 2
            addChild(s)
            let dist = CGFloat.random(in: 34...80)
            s.run(.sequence([.group([
                .move(by: CGVector(dx: cos(ang)*dist, dy: sin(ang)*dist), duration: 0.45),
                .fadeOut(withDuration: 0.45),
                .scale(to: 0.3, duration: 0.45)]), .removeFromParent()]))
        }
    }

    private func shake() {
        let a = SKAction.sequence([.moveBy(x: -7, y: 0, duration: 0.04), .moveBy(x: 14, y: 0, duration: 0.06),
                                   .moveBy(x: -10, y: 0, duration: 0.05), .moveBy(x: 3, y: 0, duration: 0.04)])
        fieldLayer.run(a)
    }

    private func finish() {
        guard !finished, !cfg.isSurvival else { return }
        finished = true
        let total = hits + misses + near
        var res = GameResult(game: game.id, score: score,
                             accuracy: total > 0 ? Double(hits) / Double(total) : 0)
        res.trials = total
        res.threshold = model.spawner.speed
        res.startedAt = startedAt
        res.durationMs = Int(cfg.targetDurationSec * 1000)
        var metrics: [String: Double] = [
            "bestStreak": Double(bestCombo),
            "correct": Double(hits),
            "wrong": Double(misses),
            "nearMisses": Double(near),
            "timeOnTaskMs": cfg.targetDurationSec * 1000
        ]
        metrics.merge(game.resultMetrics(scene: model, hits: hits, misses: misses, nearMisses: near)) { _, new in new }
        res.raw = metrics
        onResult(res)
    }

    // MARK: Touch input → ArcadeAction

    private func unit(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x / size.width, y: 1 - p.y / size.height) }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard running, !cfg.isPaused, let t = touches.first else { return }
        let u = unit(t.location(in: self))
        startUnit = u
        if game.inputMode == .drag, let e = model.nearest(to: u, maxDist: 0.11) {
            dragID = e.id; model.setDragging(e.id, true)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard running, !cfg.isPaused, let t = touches.first else { return }
        let u = unit(t.location(in: self))
        switch game.inputMode {
        case .drag:
            if let id = dragID { model.setPos(id, u); nodes[id]?.position = style.pt(u) }
        case .trace:
            if let e = model.nearest(to: u, maxDist: 0.10, where: { $0.kind == 1 }), !traceIDs.contains(e.id) {
                traceIDs.append(e.id)
            }
        default: break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard running, !cfg.isPaused, let t = touches.first else { return }
        let u = unit(t.location(in: self))
        let start = startUnit ?? u
        let moved = hypot((u.x - start.x) * size.width, (u.y - start.y) * size.height)
        var action: ArcadeAction?
        switch game.inputMode {
        case .tap:
            if moved <= 16 { action = .tap(u) }
        case .swipe:
            if moved >= 24 { action = .swipe(swipeDir(from: start, to: u), at: start) }
        case .drag:
            if let id = dragID { model.setDragging(id, false); action = .drop(entityID: id, at: u) }
            else if moved <= 16, let e = model.nearest(to: u, maxDist: 0.11) { action = .drop(entityID: e.id, at: u) }
        case .trace:
            if !traceIDs.isEmpty { action = .trace(traceIDs) }
        }
        if let action, let r = game.resolve(action, scene: model) { emit(r) }
        startUnit = nil; dragID = nil; traceIDs = []
    }

    private func swipeDir(from a: CGPoint, to b: CGPoint) -> SwipeDir {
        let dx = b.x - a.x, dy = b.y - a.y   // unit, top-down
        if abs(dx) > abs(dy) { return dx > 0 ? .right : .left }
        return dy > 0 ? .down : .up
    }
}

// MARK: - SwiftUI host

struct ArcadeSpriteHost: View {
    @State private var scene: ArcadeSKScene

    init(cfg: GameConfig, game: any ArcadeGame, onResult: @escaping (GameResult) -> Void) {
        _scene = State(initialValue: ArcadeSKScene(cfg: cfg, game: game, onResult: onResult))
    }

    var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder])
            .ignoresSafeArea()
            .onAppear { GameFeel.shared.warmUp() }
            .onDisappear { GameFeel.shared.teardown() }
    }
}
