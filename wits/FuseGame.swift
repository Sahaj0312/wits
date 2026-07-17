//
//  FuseGame.swift
//  wits
//
//  Fuse: an endless sliding-merge survival. Every swipe slides the whole 4×4
//  board; matching cells fuse and double, and each fusion pays its new value.
//  No clock, every swipe is a lookahead-planning decision and a jammed board
//  dies suddenly.
//
//  The engine is pure logic and deterministic under a seed: spawn cells and
//  values come off one seeded stream.
//

import SwiftUI

// MARK: - Engine

struct FuseTile: Identifiable, Equatable {
    let id: Int
    var value: Int
    var row: Int
    var col: Int
    /// Transient animation flags: spawned/fused this settle, cleared by calm().
    var justSpawned = false
    var justFused = false
}

enum FuseSwipe {
    case up, down, left, right
}

@Observable
final class FuseEngine {
    static let side = 4

    private(set) var tiles: [FuseTile] = []
    private(set) var score = 0
    private(set) var bestTile = 0
    private(set) var moves = 0
    private(set) var alive = true

    private var rng: SeededRandomNumberGenerator
    private var nextID = 0
    /// Bookkeeping between slide() and settle(): tiles that slid onto a partner
    /// and vanish, and the partners that double.
    private var doomedIDs: Set<Int> = []
    private var growingIDs: Set<Int> = []

    struct MoveOutcome {
        let points: Int
        let fusions: Int
        let biggestFusion: Int
    }

    init(seed: UInt64? = nil) {
        let resolved: UInt64
        if let seed {
            resolved = seed
        } else {
            var system = SystemRandomNumberGenerator()
            resolved = system.next()
        }
        rng = SeededRandomNumberGenerator(seed: resolved)
        spawn()
        spawn()
        bestTile = tiles.map(\.value).max() ?? 0
    }

    // MARK: Queries

    func tile(atRow r: Int, col c: Int) -> FuseTile? {
        tiles.first { $0.row == r && $0.col == c }
    }

    var anyMoveAvailable: Bool {
        if tiles.count < Self.side * Self.side { return true }
        for t in tiles {
            if let right = tile(atRow: t.row, col: t.col + 1), right.value == t.value { return true }
            if let below = tile(atRow: t.row + 1, col: t.col), below.value == t.value { return true }
        }
        return false
    }

    // MARK: Move (two phases so the view can slide, then pop)

    /// Phase 1: move every tile to its destination cell. A cell that fuses
    /// slides onto its partner's cell and is marked doomed; the partner is
    /// marked to double at settle. Returns false if nothing moved.
    func slide(_ dir: FuseSwipe) -> Bool {
        guard alive, doomedIDs.isEmpty else { return false }
        for i in tiles.indices {
            tiles[i].justSpawned = false
            tiles[i].justFused = false
        }

        var moved = false
        for line in 0..<Self.side {
            var indices = tiles.indices.filter {
                (dir == .left || dir == .right) ? tiles[$0].row == line : tiles[$0].col == line
            }
            indices.sort {
                switch dir {
                case .left:  tiles[$0].col < tiles[$1].col
                case .right: tiles[$0].col > tiles[$1].col
                case .up:    tiles[$0].row < tiles[$1].row
                case .down:  tiles[$0].row > tiles[$1].row
                }
            }

            var slot = 0
            var open: Int? = nil    // last placed cell still open to a fusion
            for idx in indices {
                if let last = open, tiles[last].value == tiles[idx].value {
                    let r = tiles[last].row, c = tiles[last].col
                    if tiles[idx].row != r || tiles[idx].col != c { moved = true }
                    tiles[idx].row = r
                    tiles[idx].col = c
                    doomedIDs.insert(tiles[idx].id)
                    growingIDs.insert(tiles[last].id)
                    open = nil      // a doubled cell can't fuse again this move
                } else {
                    let (r, c) = cell(line: line, slot: slot, dir: dir)
                    if tiles[idx].row != r || tiles[idx].col != c { moved = true }
                    tiles[idx].row = r
                    tiles[idx].col = c
                    open = idx
                    slot += 1
                }
            }
        }

        if !moved {
            doomedIDs.removeAll()
            growingIDs.removeAll()
        }
        return moved
    }

    /// Phase 2: remove the doomed tiles, double the survivors, pay the score,
    /// drop a fresh tile, and check for a jammed board.
    @discardableResult
    func settle() -> MoveOutcome {
        tiles.removeAll { doomedIDs.contains($0.id) }

        var points = 0
        var fusions = 0
        var biggest = 0
        for i in tiles.indices where growingIDs.contains(tiles[i].id) {
            tiles[i].value *= 2
            tiles[i].justFused = true
            points += tiles[i].value
            fusions += 1
            biggest = max(biggest, tiles[i].value)
            bestTile = max(bestTile, tiles[i].value)
        }
        doomedIDs.removeAll()
        growingIDs.removeAll()

        score += points
        moves += 1
        spawn()
        if !anyMoveAvailable { alive = false }
        return MoveOutcome(points: points, fusions: fusions, biggestFusion: biggest)
    }

    /// Clear the transient pop flags once the view has shown them.
    func calm() {
        for i in tiles.indices {
            tiles[i].justSpawned = false
            tiles[i].justFused = false
        }
    }

    /// One final chance removes the four weakest cells from a jammed board,
    /// preserving the score and strongest merges while restoring movement.
    func revive() {
        guard !alive else { return }
        let removed = Set(tiles.sorted {
            if $0.value == $1.value { return $0.id < $1.id }
            return $0.value < $1.value
        }.prefix(4).map(\.id))
        tiles.removeAll { removed.contains($0.id) }
        doomedIDs.removeAll()
        growingIDs.removeAll()
        calm()
        alive = true
    }

    private func cell(line: Int, slot: Int, dir: FuseSwipe) -> (Int, Int) {
        switch dir {
        case .left:  (line, slot)
        case .right: (line, Self.side - 1 - slot)
        case .up:    (slot, line)
        case .down:  (Self.side - 1 - slot, line)
        }
    }

    private func spawn() {
        var empty: [(Int, Int)] = []
        for r in 0..<Self.side {
            for c in 0..<Self.side where tile(atRow: r, col: c) == nil {
                empty.append((r, c))
            }
        }
        guard let (r, c) = empty.randomElement(using: &rng) else { return }
        nextID += 1
        tiles.append(FuseTile(id: nextID,
                              value: Double.random(in: 0...1, using: &rng) < 0.9 ? 2 : 4,
                              row: r, col: c, justSpawned: true))
    }

    /// Test seam: install an exact board (row-major values, 0 = empty).
    func load(values: [Int]) {
        precondition(values.count == Self.side * Self.side)
        tiles.removeAll()
        for (index, value) in values.enumerated() where value > 0 {
            nextID += 1
            tiles.append(FuseTile(id: nextID,
                                  value: value,
                                  row: index / Self.side,
                                  col: index % Self.side))
        }
        bestTile = max(bestTile, values.max() ?? 0)
        alive = anyMoveAvailable
    }
}

// MARK: - Tile palette (a charged-gem ramp of our own)

enum FusePalette {
    static func fill(_ value: Int) -> Color {
        switch value {
        case 2: Color(hexAny: 0x35586B)
        case 4: Color(hexAny: 0x2E6E7E)
        case 8: Color(hexAny: 0x1F8F86)
        case 16: Color(hexAny: 0x2FB07F)
        case 32: Color(hexAny: 0x63A83C)
        case 64: Color(hexAny: 0xB0A32B)
        case 128: Color(hexAny: 0xE0902F)
        case 256: Color(hexAny: 0xE86A3C)
        case 512: Color(hexAny: 0xE84A6F)
        case 1024: Color(hexAny: 0xC44BD1)
        case 2048: Color(hexAny: 0x7A5CFF)
        default: Color(hexAny: 0x4C7DFF)
        }
    }

    static func ink(_ value: Int) -> Color {
        Color(hexAny: 0xF4F9FF)
    }

    /// The big cells hum.
    static func glow(_ value: Int) -> Color {
        value >= 128 ? fill(value).opacity(0.6) : .clear
    }
}

// MARK: - Screen

struct FuseScreen: View {
    let best: Int
    let todayBest: Int
    let weekBest: Int
    /// (score, best tile, moves) → persist.
    let onRunComplete: (Int, Int, Int) -> Void
    let onQuit: () -> Void

    @State private var model: FuseEngine
    @State private var phase: Phase = .playing
    @State private var pauseController = GamePauseController()
    @State private var usedContinue = false
    @State private var canContinue = false
    @State private var adBusy = false
    @State private var runRecorded = true
    @State private var newBest = false
    /// Best across every run since this screen opened, so the bests rows stay
    /// honest through PLAY AGAIN loops.
    @State private var sessionBest = 0
    /// True from a swipe landing until its settle applies; input is ignored so
    /// two-phase animations never interleave.
    @State private var resolving = false

    private enum Phase { case playing, over }

    private var world: GameWorld { GameID.fuse.world }

    init(best: Int,
         todayBest: Int = 0,
         weekBest: Int = 0,
         onRunComplete: @escaping (Int, Int, Int) -> Void,
         onQuit: @escaping () -> Void) {
        self.best = best
        self.todayBest = todayBest
        self.weekBest = weekBest
        self.onRunComplete = onRunComplete
        self.onQuit = onQuit
        _model = State(initialValue: FuseEngine())
    }

    var body: some View {
        ZStack {
            GameWorldBackdrop(game: .fuse, patternOpacity: 0.4)
            // The playing view stays mounted behind the game-over card so the
            // final board sits dimmed under the scrim.
            playing
            if phase == .over {
                if canContinue {
                    RewardedReviveOffer(game: .fuse,
                                        busy: adBusy,
                                        onDecline: declineContinue,
                                        onSave: continueRun)
                } else {
                    runOver
                }
            }
        }
        .overlay {
            if phase == .playing, !pauseController.isPaused {
                GamePauseButtonLayer(game: .fuse) { pauseController.pause() }
            }
        }
        .overlay {
            if phase == .playing, pauseController.isPaused {
                GamePausedOverlay(game: .fuse,
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
            header
                .padding(.leading, 48)
                .padding(.trailing, 16)
                .padding(.top, 44)

            Spacer(minLength: 12)

            boardView
                .padding(.horizontal, 18)

            Text("SWIPE TO SLIDE · MATCHING CELLS FUSE")
                .font(.system(size: 10, weight: .black, design: world.bodyDesign))
                .foregroundStyle(world.muted)
                .padding(.top, 16)

            Spacer(minLength: 24)
        }
        .allowsHitTesting(phase == .playing && !pauseController.isPaused)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("SCORE")
                    .font(.system(size: 10, weight: .black, design: world.bodyDesign))
                    .foregroundStyle(world.muted)
                Text(String(model.score))
                    .font(.system(size: 34, weight: .black, design: world.titleDesign))
                    .foregroundStyle(world.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: model.score)
            }

            if model.bestTile >= 128 {
                Text("CELL \(String(model.bestTile))")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .font(.system(size: 11, weight: .black, design: world.bodyDesign))
                    .foregroundStyle(FusePalette.ink(model.bestTile))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(FusePalette.fill(model.bestTile), in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(newBest ? "NEW BEST" : "BEST")
                    .font(.system(size: 10, weight: .black, design: world.bodyDesign))
                    .foregroundStyle(newBest ? world.accent : world.muted)
                Text(String(max(referenceBest, model.score)))
                    .font(.system(size: 20, weight: .black, design: world.titleDesign))
                    .foregroundStyle(newBest ? world.accent : world.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.bestTile)
    }

    private var referenceBest: Int { best }

    // MARK: Board

    private var boardView: some View {
        GeometryReader { geo in
            boardContent(side: geo.size.width)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 440)
    }

    private func boardContent(side: CGFloat) -> some View {
        let gap = side * 0.022
        let cell = (side - gap * CGFloat(FuseEngine.side + 1)) / CGFloat(FuseEngine.side)

        func center(_ row: Int, _ col: Int) -> CGPoint {
            CGPoint(x: gap + (cell + gap) * CGFloat(col) + cell / 2,
                    y: gap + (cell + gap) * CGFloat(row) + cell / 2)
        }

        return ZStack {
            RoundedRectangle(cornerRadius: side * 0.03, style: .continuous)
                .fill(world.surface)

            ForEach(0..<FuseEngine.side * FuseEngine.side, id: \.self) { index in
                RoundedRectangle(cornerRadius: cell * 0.13, style: .continuous)
                    .fill(world.raised.opacity(0.55))
                    .frame(width: cell, height: cell)
                    .position(center(index / FuseEngine.side, index % FuseEngine.side))
            }

            ForEach(model.tiles) { tile in
                tileView(tile, cell: cell)
                    .position(center(tile.row, tile.col))
            }
        }
        .contentShape(Rectangle())
        .gesture(swipeGesture)
    }

    private func tileView(_ tile: FuseTile, cell: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cell * 0.13, style: .continuous)
            .fill(FusePalette.fill(tile.value))
            .overlay {
                Text(String(tile.value))
                    .font(.system(size: cell * fontScale(tile.value),
                                  weight: .black,
                                  design: world.titleDesign))
                    .foregroundStyle(FusePalette.ink(tile.value))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(cell * 0.08)
            }
            .shadow(color: FusePalette.glow(tile.value), radius: cell * 0.16)
            .frame(width: cell, height: cell)
            .scaleEffect(tile.justFused ? 1.12 : (tile.justSpawned ? 0.99 : 1))
            .transition(.scale(scale: 0.35).combined(with: .opacity))
    }

    private func fontScale(_ value: Int) -> CGFloat {
        switch value {
        case ..<100: 0.46
        case ..<1_000: 0.38
        case ..<10_000: 0.3
        default: 0.25
        }
    }

    // MARK: Input

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 22)
            .onEnded { gesture in
                let dx = gesture.translation.width
                let dy = gesture.translation.height
                let dir: FuseSwipe = abs(dx) > abs(dy)
                    ? (dx > 0 ? .right : .left)
                    : (dy > 0 ? .down : .up)
                perform(dir)
            }
    }

    private func perform(_ dir: FuseSwipe) {
        guard phase == .playing, !pauseController.isPaused, !resolving else { return }
        let moved = withAnimation(.easeOut(duration: 0.10)) { model.slide(dir) }
        guard moved else { return }

        resolving = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(95))
            var outcome = FuseEngine.MoveOutcome(points: 0, fusions: 0, biggestFusion: 0)
            withAnimation(.spring(response: 0.22, dampingFraction: 0.62)) {
                outcome = model.settle()
            }
            resolving = false
            react(to: outcome)
            if !model.alive { endRun() }

            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(.easeOut(duration: 0.12)) { model.calm() }
        }
    }

    private func react(to outcome: FuseEngine.MoveOutcome) {
        if outcome.fusions > 0 {
            GameFeel.shared.play(.correct(combo: outcome.fusions))
        } else {
            GameFeel.shared.uiMove(0.42)
        }
        if outcome.biggestFusion >= 128, outcome.biggestFusion == model.bestTile {
            GameFeel.shared.play(.comboMilestone(outcome.fusions))
        }
        if !newBest, referenceBest > 0, model.score > referenceBest {
            newBest = true
            GameFeel.shared.play(.newBest)
        }
    }

    // MARK: Game over

    private func endRun() {
        if referenceBest == 0 && model.score > 0 { newBest = true }
        sessionBest = max(sessionBest, model.score)
        canContinue = !usedContinue
        runRecorded = false
        if !canContinue { finalizeRun() }
        GameFeel.shared.play(.gameOver)
        withAnimation(.easeOut(duration: 0.3)) { phase = .over }
    }

    private func finalizeRun() {
        guard !runRecorded else { return }
        runRecorded = true
        onRunComplete(model.score, model.bestTile, model.moves)
    }

    private var runOver: some View {
        GameRunOverView(game: .fuse,
                        score: model.score,
                        caption: "best cell \(model.bestTile) · \(model.moves) moves",
                        bests: RunBestLine.standard(today: max(todayBest, sessionBest),
                                                   week: max(weekBest, sessionBest),
                                                   allTime: max(best, sessionBest)),
                        celebrate: newBest,
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
            resolving = false
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
        model = FuseEngine()
        newBest = false
        resolving = false
        usedContinue = false
        canContinue = false
        pauseController.reset()
        withAnimation(.easeOut(duration: 0.2)) { phase = .playing }
    }
}
