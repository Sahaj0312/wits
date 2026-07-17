//
//  BlockFit.swift
//  wits
//
//  Block Fit: an endless block-packing survival. Three pieces at a time go
//  onto an 8×8 board; full rows and columns clear; the run ends the moment
//  nothing in the hand fits. No rotations, no clock, every placement is a
//  small spatial-planning decision and runs die suddenly, which is the hook.
//
//  The engine is pure logic and deterministic under a seed: the piece stream
//  never depends on where pieces are placed.
//

import SwiftUI

// MARK: - Pieces

struct BlockCell: Hashable, Sendable {
    var r: Int
    var c: Int
}

struct BlockPiece: Identifiable, Equatable {
    let id: Int
    let cells: [BlockCell]   // normalized: min row/col == 0
    let color: Int           // 1-based index into BlockFitPalette

    var rows: Int { (cells.map(\.r).max() ?? 0) + 1 }
    var cols: Int { (cells.map(\.c).max() ?? 0) + 1 }
}

enum BlockFitPalette {
    /// Fixed candy colors (hexAny) so blocks read identically in both modes.
    static let colors: [Color] = [
        Color(hexAny: 0xFFB13B),  // amber
        Color(hexAny: 0x4BE3A9),  // mint
        Color(hexAny: 0x58B4FF),  // sky
        Color(hexAny: 0xFF5E7A),  // pink
        Color(hexAny: 0xA78BFF),  // violet
        Color(hexAny: 0xFFE066),  // lemon
    ]

    static func color(_ index: Int) -> Color {
        colors[max(0, min(colors.count - 1, index - 1))]
    }
}

/// The dealable shape catalog. Weights preserve variety inside each size band;
/// `BlockFitGame` composes those bands into fair hands so a run cannot open on
/// a wall of board-breakers.
enum BlockFitShapes {
    struct Variant {
        let cells: [BlockCell]
        let weight: Double
    }

    static let all: [Variant] = {
        func v(_ weight: Double, _ pairs: [(Int, Int)]) -> Variant {
            Variant(cells: pairs.map { BlockCell(r: $0.0, c: $0.1) }, weight: weight)
        }
        func line(_ n: Int, weight: Double) -> [Variant] {
            [v(weight, (0..<n).map { (0, $0) }), v(weight, (0..<n).map { ($0, 0) })]
        }
        var shapes: [Variant] = [
            v(1.0, [(0, 0)]),                                    // 1×1
            v(0.9, [(0, 0), (0, 1), (1, 0), (1, 1)]),            // 2×2
            v(0.35, (0..<3).flatMap { r in (0..<3).map { (r, $0) } }),  // 3×3
            v(0.5, [(0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (1, 2)]),   // 2×3
            v(0.5, [(0, 0), (0, 1), (1, 0), (1, 1), (2, 0), (2, 1)]),   // 3×2
        ]
        shapes += line(2, weight: 1.0)
        shapes += line(3, weight: 0.9)
        shapes += line(4, weight: 0.6)
        shapes += line(5, weight: 0.4)
        // Small corners (3 cells, all four bends).
        shapes += [
            v(0.6, [(0, 0), (0, 1), (1, 0)]),
            v(0.6, [(0, 0), (0, 1), (1, 1)]),
            v(0.6, [(0, 0), (1, 0), (1, 1)]),
            v(0.6, [(0, 1), (1, 0), (1, 1)]),
        ]
        // Big Ls (5 cells, all four bends).
        shapes += [
            v(0.3, [(0, 0), (1, 0), (2, 0), (2, 1), (2, 2)]),
            v(0.3, [(0, 0), (0, 1), (0, 2), (1, 0), (2, 0)]),
            v(0.3, [(0, 0), (0, 1), (0, 2), (1, 2), (2, 2)]),
            v(0.3, [(0, 2), (1, 2), (2, 0), (2, 1), (2, 2)]),
        ]
        // Ts and skews.
        shapes += [
            v(0.45, [(0, 0), (0, 1), (0, 2), (1, 1)]),
            v(0.45, [(1, 0), (1, 1), (1, 2), (0, 1)]),
            v(0.45, [(0, 0), (1, 0), (2, 0), (1, 1)]),
            v(0.45, [(0, 1), (1, 0), (1, 1), (2, 1)]),
            v(0.35, [(0, 1), (0, 2), (1, 0), (1, 1)]),
            v(0.35, [(0, 0), (0, 1), (1, 1), (1, 2)]),
            v(0.35, [(0, 0), (1, 0), (1, 1), (2, 1)]),
            v(0.35, [(0, 1), (1, 0), (1, 1), (2, 0)]),
        ]
        return shapes
    }()

    /// Flexible pieces that still have useful homes on a crowded board.
    static let compact = all.filter { $0.cells.count <= 3 }
    /// The gentler pool excludes large-area board-breakers.
    static let nonBulky = all.filter { $0.cells.count < 5 }

    static func isCompact(_ piece: BlockPiece) -> Bool { piece.cells.count <= 3 }
    static func isBulky(_ piece: BlockPiece) -> Bool { piece.cells.count >= 5 }
}

// MARK: - Engine

@Observable
final class BlockFitGame {
    static let side = 8
    static let handSize = 3

    private(set) var board: [Int]           // side*side; 0 empty, else color
    private(set) var hand: [BlockPiece?]
    /// The hand that will be dealt once the current one is used up. Shown in
    /// the UI so deep planning is information, not a gamble.
    private(set) var nextHand: [BlockPiece] = []
    private(set) var score = 0
    private(set) var linesCleared = 0
    private(set) var combo = 0              // consecutive clearing placements
    private(set) var bestCombo = 0
    private(set) var piecesPlaced = 0
    private(set) var alive = true

    private var rng: SeededRandomNumberGenerator
    private var nextPieceID = 0
    private var handsGenerated = 0

    struct Placement {
        let placedCells: [BlockCell]
        let clearedCells: [BlockCell]
        let lines: Int
        let points: Int
        let comboAfter: Int
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
        board = Array(repeating: 0, count: Self.side * Self.side)
        hand = Array(repeating: nil, count: Self.handSize)
        deal()
    }

    // MARK: Queries

    func color(atRow r: Int, col c: Int) -> Int {
        board[r * Self.side + c]
    }

    func canPlace(_ piece: BlockPiece, atRow r: Int, col c: Int) -> Bool {
        for cell in piece.cells {
            let row = r + cell.r, col = c + cell.c
            guard row >= 0, row < Self.side, col >= 0, col < Self.side,
                  board[row * Self.side + col] == 0 else { return false }
        }
        return true
    }

    func fitsSomewhere(_ piece: BlockPiece) -> Bool {
        for r in 0...(Self.side - piece.rows) {
            for c in 0...(Self.side - piece.cols) where canPlace(piece, atRow: r, col: c) {
                return true
            }
        }
        return false
    }

    var anyMoveAvailable: Bool {
        hand.contains { $0.map(fitsSomewhere) ?? false }
    }

    /// Which rows/columns a hypothetical placement would complete, the view
    /// tints them in the ghost preview so clears feel telegraphed, not lucky.
    func linesCompleted(byPlacing piece: BlockPiece, atRow r: Int, col c: Int) -> (rows: [Int], cols: [Int]) {
        var filled = Set<Int>()
        for cell in piece.cells { filled.insert((r + cell.r) * Self.side + (c + cell.c)) }
        func full(row: Int) -> Bool {
            (0..<Self.side).allSatisfy { board[row * Self.side + $0] != 0 || filled.contains(row * Self.side + $0) }
        }
        func full(col: Int) -> Bool {
            (0..<Self.side).allSatisfy { board[$0 * Self.side + col] != 0 || filled.contains($0 * Self.side + col) }
        }
        return ((0..<Self.side).filter(full(row:)), (0..<Self.side).filter(full(col:)))
    }

    // MARK: Mutations

    @discardableResult
    func place(handIndex: Int, atRow r: Int, col c: Int) -> Placement? {
        guard alive, hand.indices.contains(handIndex), let piece = hand[handIndex],
              canPlace(piece, atRow: r, col: c) else { return nil }

        var placed: [BlockCell] = []
        for cell in piece.cells {
            let row = r + cell.r, col = c + cell.c
            board[row * Self.side + col] = piece.color
            placed.append(BlockCell(r: row, c: col))
        }
        piecesPlaced += 1
        hand[handIndex] = nil

        let fullRows = (0..<Self.side).filter { row in
            (0..<Self.side).allSatisfy { board[row * Self.side + $0] != 0 }
        }
        let fullCols = (0..<Self.side).filter { col in
            (0..<Self.side).allSatisfy { board[$0 * Self.side + col] != 0 }
        }

        var cleared: [BlockCell] = []
        for row in fullRows {
            for col in 0..<Self.side { cleared.append(BlockCell(r: row, c: col)) }
        }
        for col in fullCols {
            for row in 0..<Self.side where !fullRows.contains(row) {
                cleared.append(BlockCell(r: row, c: col))
            }
        }
        for cell in cleared { board[cell.r * Self.side + cell.c] = 0 }

        let lines = fullRows.count + fullCols.count
        var points = piece.cells.count
        if lines > 0 {
            combo += 1
            bestCombo = max(bestCombo, combo)
            // 1 line = 10, 2 = 40, 3 = 90 … then the streak multiplies it.
            points += 10 * lines * lines * combo
            linesCleared += lines
        } else {
            combo = 0
        }
        score += points

        if hand.allSatisfy({ $0 == nil }) { deal() }
        if !anyMoveAvailable { alive = false }

        return Placement(placedCells: placed,
                         clearedCells: cleared,
                         lines: lines,
                         points: points,
                         comboAfter: combo)
    }

    /// Hands come off one deterministic stream: the preview is always drawn
    /// ahead, so what the player sees as "next" is exactly what they'll get.
    private func deal() {
        if nextHand.isEmpty {
            nextHand = drawHand()
        }
        for index in 0..<Self.handSize {
            hand[index] = nextHand[index]
        }
        nextHand = drawHand()
    }

    /// Every hand includes a compact piece, which gives the player a way to
    /// repair tight boards instead of losing to three awkward rolls. The first
    /// two hands are extra gentle so a new run has time to develop; after that,
    /// bulky pieces return but never appear more than once in the same hand.
    /// The recipe depends only on the seeded RNG and hand count.
    private func drawHand() -> [BlockPiece] {
        let openingHand = handsGenerated < 2
        var pieces = [draw(from: BlockFitShapes.compact)]

        if openingHand {
            pieces.append(draw(from: BlockFitShapes.compact))
            pieces.append(draw(from: BlockFitShapes.nonBulky))
        } else {
            pieces.append(draw(from: BlockFitShapes.all))
            pieces.append(draw(from: BlockFitShapes.all))
            let bulkySlots = pieces.indices.filter { BlockFitShapes.isBulky(pieces[$0]) }
            for slot in bulkySlots.dropFirst() {
                pieces[slot] = draw(from: BlockFitShapes.nonBulky)
            }
        }

        pieces.shuffle(using: &rng)
        handsGenerated += 1
        return pieces
    }

    private func draw(from candidates: [BlockFitShapes.Variant]) -> BlockPiece {
        precondition(!candidates.isEmpty)
        let totalWeight = candidates.reduce(0) { $0 + $1.weight }
        var pick = Double.random(in: 0..<totalWeight, using: &rng)
        var variant = candidates[0]
        for candidate in candidates {
            if pick < candidate.weight { variant = candidate; break }
            pick -= candidate.weight
        }
        nextPieceID += 1
        return BlockPiece(id: nextPieceID,
                          cells: variant.cells,
                          color: Int.random(in: 1...BlockFitPalette.colors.count, using: &rng))
    }

    /// Test seam: install an exact board and hand.
    func load(board: [Int], hand: [BlockPiece?]) {
        precondition(board.count == Self.side * Self.side)
        self.board = board
        self.hand = hand
        alive = anyMoveAvailable
    }

    /// One final chance keeps the run's score and hand, but clears the packed
    /// board so every remaining piece has somewhere legal to land.
    func revive() {
        guard !alive else { return }
        board = Array(repeating: 0, count: Self.side * Self.side)
        combo = 0
        if hand.allSatisfy({ $0 == nil }) { deal() }
        alive = true
    }
}

// MARK: - Screen

struct BlockFitScreen: View {
    let best: Int
    let todayBest: Int
    let weekBest: Int
    /// (score, lines cleared, pieces placed) → persist.
    let onRunComplete: (Int, Int, Int) -> Void
    let onQuit: () -> Void

    @State private var model: BlockFitGame
    @State private var phase: Phase = .playing
    @State private var pauseController = GamePauseController()
    @State private var usedContinue = false
    @State private var canContinue = false
    @State private var adBusy = false
    @State private var runRecorded = true
    @State private var boardFrame: CGRect = .zero
    @State private var dragSlot: Int?
    @State private var dragLocation: CGPoint = .zero
    @State private var newBest = false
    /// Best across every run since this screen opened, so the bests rows stay
    /// honest through PLAY AGAIN loops.
    @State private var sessionBest = 0

    private enum Phase { case playing, over }
    private static let space = "blockfit.play"
    /// The dragged piece floats above the finger so it stays visible.
    private static let lift: CGFloat = 76

    private var world: GameWorld { GameID.blockFit.world }

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
        _model = State(initialValue: BlockFitGame())
    }

    var body: some View {
        ZStack {
            GameWorldBackdrop(game: .blockFit, patternOpacity: 0.45)
            // The playing view stays mounted behind the game-over card so the
            // final board sits dimmed under the scrim.
            playing
            if phase == .over {
                if canContinue {
                    RewardedReviveOffer(game: .blockFit,
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
                GamePauseButtonLayer(game: .blockFit) { pauseController.pause() }
            }
        }
        .overlay {
            if phase == .playing, pauseController.isPaused {
                GamePausedOverlay(game: .blockFit,
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

            nextRow
                .padding(.horizontal, 22)
                .padding(.top, 12)

            Spacer(minLength: 10)

            boardView
                .padding(.horizontal, 18)

            Spacer(minLength: 8)

            tray
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 14)
        }
        .coordinateSpace(name: Self.space)
        .overlay {
            if let piece = draggedPiece {
                draggedPieceView(piece)
            }
        }
        .allowsHitTesting(phase == .playing && !pauseController.isPaused)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("SCORE")
                    .font(.system(size: 10, weight: .black, design: world.bodyDesign))
                    .foregroundStyle(world.muted)
                Text("\(model.score)")
                    .font(.system(size: 34, weight: .black, design: world.titleDesign))
                    .foregroundStyle(world.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: model.score)
            }

            if model.combo >= 2 {
                Text("COMBO ×\(model.combo)")
                    .font(.system(size: 11, weight: .black, design: world.bodyDesign))
                    .foregroundStyle(world.background)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(world.secondary, in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(newBest ? "NEW BEST" : "BEST")
                    .font(.system(size: 10, weight: .black, design: world.bodyDesign))
                    .foregroundStyle(newBest ? world.accent : world.muted)
                Text("\(max(referenceBest, model.score))")
                    .font(.system(size: 20, weight: .black, design: world.titleDesign))
                    .foregroundStyle(newBest ? world.accent : world.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.combo >= 2)
    }

    private var referenceBest: Int { best }

    // MARK: Board

    private var boardView: some View {
        GeometryReader { geo in
            let cell = geo.size.width / CGFloat(BlockFitGame.side)
            let ghost = ghostPlacement
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(world.surface.opacity(0.72))

                ForEach(0..<BlockFitGame.side * BlockFitGame.side, id: \.self) { index in
                    let r = index / BlockFitGame.side
                    let c = index % BlockFitGame.side
                    boardCell(row: r, col: c, ghost: ghost)
                        .frame(width: cell, height: cell)
                        .offset(x: CGFloat(c) * cell, y: CGFloat(r) * cell)
                }
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(Self.space))
            } action: { frame in
                boardFrame = frame
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 460)
    }

    private struct GhostPlacement {
        let cells: Set<BlockCell>
        let clearRows: Set<Int>
        let clearCols: Set<Int>
        let color: Int
    }

    private var ghostPlacement: GhostPlacement? {
        guard let piece = draggedPiece,
              let origin = dropOrigin(for: piece),
              model.canPlace(piece, atRow: origin.r, col: origin.c) else { return nil }
        let cells = Set(piece.cells.map { BlockCell(r: origin.r + $0.r, c: origin.c + $0.c) })
        let lines = model.linesCompleted(byPlacing: piece, atRow: origin.r, col: origin.c)
        return GhostPlacement(cells: cells,
                              clearRows: Set(lines.rows),
                              clearCols: Set(lines.cols),
                              color: piece.color)
    }

    @ViewBuilder
    private func boardCell(row: Int, col: Int, ghost: GhostPlacement?) -> some View {
        let value = model.color(atRow: row, col: col)
        let cellID = BlockCell(r: row, c: col)
        let isGhost = ghost?.cells.contains(cellID) == true
        let inClearLine = value != 0 &&
            (ghost?.clearRows.contains(row) == true || ghost?.clearCols.contains(col) == true)

        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(cellFill(value: value, ghost: ghost, isGhost: isGhost))
            .overlay {
                if inClearLine {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(world.ink.opacity(0.85), lineWidth: 2)
                }
            }
            .padding(1.5)
            .animation(.easeOut(duration: 0.16), value: value)
    }

    private func cellFill(value: Int, ghost: GhostPlacement?, isGhost: Bool) -> Color {
        if value != 0 { return BlockFitPalette.color(value) }
        if isGhost, let ghost { return BlockFitPalette.color(ghost.color).opacity(0.42) }
        return world.raised.opacity(0.5)
    }

    // MARK: Next preview

    /// The upcoming hand, dimmed and small: information for planners without
    /// competing visually with the live tray.
    private var nextRow: some View {
        HStack(spacing: 14) {
            Text("NEXT")
                .font(.system(size: 9.5, weight: .black, design: world.bodyDesign))
                .foregroundStyle(world.muted)
            ForEach(model.nextHand) { piece in
                pieceView(piece, cellSize: min(8, 30 / CGFloat(max(piece.rows, piece.cols))))
                    .opacity(0.5)
                    .saturation(0.7)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 30)
        .animation(.easeOut(duration: 0.2), value: model.nextHand.map(\.id))
    }

    // MARK: Tray

    private var tray: some View {
        HStack(spacing: 12) {
            ForEach(0..<BlockFitGame.handSize, id: \.self) { slot in
                traySlot(slot)
            }
        }
        .frame(height: 104)
    }

    @ViewBuilder
    private func traySlot(_ slot: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(world.surface.opacity(0.6))
            if let piece = model.hand[slot], dragSlot != slot {
                let unplaceable = !model.fitsSomewhere(piece)
                pieceView(piece, cellSize: trayCellSize(for: piece))
                    .opacity(unplaceable ? 0.28 : 1)
                    .saturation(unplaceable ? 0.3 : 1)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(dragGesture(slot: slot))
    }

    private func trayCellSize(for piece: BlockPiece) -> CGFloat {
        min(19, 78 / CGFloat(max(piece.rows, piece.cols)))
    }

    private func dragGesture(slot: Int) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { gesture in
                guard !pauseController.isPaused, model.hand[slot] != nil else { return }
                dragSlot = slot
                dragLocation = gesture.location
            }
            .onEnded { _ in
                defer { withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { dragSlot = nil } }
                guard let slot = dragSlot, let piece = model.hand[slot],
                      let origin = dropOrigin(for: piece) else { return }
                attemptPlace(slot: slot, piece: piece, origin: origin)
            }
    }

    private var draggedPiece: BlockPiece? {
        dragSlot.flatMap { model.hand[$0] }
    }

    private func draggedPieceView(_ piece: BlockPiece) -> some View {
        let cell = boardCellSize
        return pieceView(piece, cellSize: cell)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 8)
            .position(x: dragLocation.x, y: dragLocation.y - Self.lift)
            .allowsHitTesting(false)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    private var boardCellSize: CGFloat {
        boardFrame.width > 0 ? boardFrame.width / CGFloat(BlockFitGame.side) : 24
    }

    private func pieceView(_ piece: BlockPiece, cellSize: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(piece.cells, id: \.self) { cell in
                RoundedRectangle(cornerRadius: cellSize * 0.18, style: .continuous)
                    .fill(BlockFitPalette.color(piece.color))
                    .overlay {
                        RoundedRectangle(cornerRadius: cellSize * 0.18, style: .continuous)
                            .fill(.white.opacity(0.22))
                            .padding(cellSize * 0.16)
                            .offset(x: -cellSize * 0.05, y: -cellSize * 0.05)
                            .blendMode(.plusLighter)
                    }
                    .frame(width: cellSize - 2, height: cellSize - 2)
                    .offset(x: CGFloat(cell.c) * cellSize, y: CGFloat(cell.r) * cellSize)
            }
        }
        .frame(width: CGFloat(piece.cols) * cellSize,
               height: CGFloat(piece.rows) * cellSize,
               alignment: .topLeading)
    }

    /// Board origin cell for the current drag, anchored on the floating
    /// piece's center so the drop lands exactly where the ghost shows.
    private func dropOrigin(for piece: BlockPiece) -> (r: Int, c: Int)? {
        guard boardFrame.width > 0 else { return nil }
        let cell = boardCellSize
        let center = CGPoint(x: dragLocation.x, y: dragLocation.y - Self.lift)
        let originX = center.x - CGFloat(piece.cols) * cell / 2
        let originY = center.y - CGFloat(piece.rows) * cell / 2
        let c = Int(((originX - boardFrame.minX) / cell).rounded())
        let r = Int(((originY - boardFrame.minY) / cell).rounded())
        return (r, c)
    }

    private func attemptPlace(slot: Int, piece: BlockPiece, origin: (r: Int, c: Int)) {
        var placement: BlockFitGame.Placement?
        withAnimation(.easeOut(duration: 0.18)) {
            placement = model.place(handIndex: slot, atRow: origin.r, col: origin.c)
        }
        guard let placement else {
            GameFeel.shared.uiTick(0.35)
            return
        }

        if placement.lines > 0 {
            GameFeel.shared.play(.correct(combo: placement.comboAfter))
        } else {
            GameFeel.shared.uiMove(0.46)
        }
        if placement.lines >= 2 {
            GameFeel.shared.play(.comboMilestone(placement.lines))
        }
        if !newBest, referenceBest > 0, model.score > referenceBest {
            newBest = true
            GameFeel.shared.play(.newBest)
        }
        if !model.alive { endRun() }
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
        onRunComplete(model.score, model.linesCleared, model.piecesPlaced)
    }

    private var runOver: some View {
        GameRunOverView(game: .blockFit,
                        score: model.score,
                        caption: "\(model.linesCleared) lines · combo ×\(model.bestCombo)",
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
        model = BlockFitGame()
        newBest = false
        usedContinue = false
        canContinue = false
        pauseController.reset()
        withAnimation(.easeOut(duration: 0.2)) { phase = .playing }
    }
}
