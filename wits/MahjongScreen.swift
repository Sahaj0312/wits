//
//  MahjongScreen.swift
//  wits
//
//  The playable mahjong screen, Vita-style rack mechanic: tap any free tile
//  to lift it into the rack at the top; the moment its twin lands there the
//  pair flashes and clears. The rack holds only a few tiles — fill it with
//  unmatched singles and the run is out of space. Strategy is deciding which
//  singles are worth banking and which pairs are actually reachable.
//
//  Every deal is reverse-play generated (Mahjong.swift) so a full clear is
//  always reachable, and undo rewinds one pick at a time. Tile faces are
//  drawn in SwiftUI — original renditions of the traditional public-domain
//  iconography — so the game reads instantly as mahjong without image assets.
//

import SwiftUI

struct MahjongScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    @State private var tiles: [MahjongTile]?
    @State private var spec: MahjongSpec?
    /// Tile ids still standing on the board.
    @State private var boardIDs: Set<Int> = []
    /// Tile ids waiting in the rack, in slot order.
    @State private var rack: [Int] = []
    /// Tile ids matched away.
    @State private var clearedIDs: Set<Int> = []
    /// Pair mid-flight/flash: input locks until it lands.
    @State private var popping: Set<Int> = []
    /// Drives the staggered deal-in cascade at load and on restart.
    @State private var dealt = false
    /// Per-tile jiggle trigger: bumped when a blocked tile is tapped.
    @State private var shakes: [Int: Int] = [:]
    /// Drag-to-peek: slide any tile aside to see what's underneath; it snaps
    /// home on release and never counts as a move.
    @State private var peekID: Int?
    @State private var peekOffset: CGSize = .zero
    /// One-deep undo: only the immediately previous move can be taken back,
    /// and taking it back consumes it until the next move.
    @State private var lastMove: Move?
    /// One rewarded-ad revive per attempt: empties the rack back onto the
    /// board. Spent it? The next out-of-space ends the run.
    @State private var reviveUsed = false
    @State private var adBusy = false
    @State private var revives = 0
    @State private var undos = 0
    @State private var restarts = 0
    @State private var blockedTaps = 0
    @State private var elapsed = 0.0
    @State private var timerStartedAt = Date()
    @State private var hint = "tap a free tile to lift it into the rack"
    @State private var finished = false
    @State private var outOfSpace = false

    @Namespace private var rackSpace

    private enum Move {
        case pick(Int)
        case match(picked: Int, partner: Int)
    }

    private let startedAt = Date()
    private let level: Double
    private let mapLevel: Int
    private var world: GameWorld { GameID.mahjong.world }

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        self.level = cfg.difficulty.level
        self.mapLevel = cfg.mapLevel ?? DifficultyScale.contentLevel(for: .mahjong,
                                                                     legacyDifficulty: cfg.difficulty.level)
    }

    private var pairs: Int { (tiles?.count ?? 0) / 2 }
    private var traySlots: Int { spec?.traySlots ?? 4 }
    private var canRevive: Bool { !reviveUsed && AdManager.shared.rewardedReady }

    /// Time budget prices in scanning and rack planning, not reflexes.
    private var parSeconds: Double { Double(pairs) * 6.0 + 25 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                GameStageBackground(game: .mahjong)
                if let tiles {
                    VStack(spacing: 0) {
                        topBar
                            .padding(.top, 8)
                            .padding(.horizontal, WitsMetrics.screenPadding)

                        rackView(tiles, in: geo.size)
                            .padding(.top, 14)
                            .padding(.horizontal, WitsMetrics.screenPadding)

                        Text(hint)
                            .font(.system(size: 14.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.horizontal, WitsMetrics.screenPadding)
                            .padding(.top, 10)
                            .opacity(hint.isEmpty ? 0 : 1)

                        Spacer(minLength: 8)

                        boardView(tiles, in: geo.size)

                        Spacer(minLength: 12)
                    }

                    if outOfSpace {
                        outOfSpaceCard
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
            }
        }
        .task { await setUpAndRun() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mahjong")
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 6) {
            // clears the pause button the host overlays at top-leading
            Spacer()
                .frame(width: 38)

            HStack {
                Spacer(minLength: 0)
                Text(Self.clock(elapsed))
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Color.black.opacity(0.35), in: Capsule())

            Button {
                undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white.opacity(lastMove == nil ? 0.35 : 1))
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(lastMove == nil || finished || outOfSpace)
            .accessibilityLabel("Undo the last move")

            Button {
                showHelp()
            } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show rule reminder")
        }
    }

    // MARK: Rack

    private func rackView(_ tiles: [MahjongTile], in size: CGSize) -> some View {
        let slots = traySlots
        let gap: CGFloat = 8
        let maxW = size.width - WitsMetrics.screenPadding * 2 - 20
        let slotW = min(58, (maxW - gap * CGFloat(slots - 1)) / CGFloat(slots))
        let slotH = slotW * 1.24

        return HStack(spacing: gap) {
            ForEach(0..<slots, id: \.self) { index in
                ZStack {
                    RoundedRectangle(cornerRadius: slotW * 0.14, style: .continuous)
                        .fill(.black.opacity(0.30))
                        .overlay {
                            RoundedRectangle(cornerRadius: slotW * 0.14, style: .continuous)
                                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                        }
                    if index < rack.count {
                        let id = rack[index]
                        let popped = popping.contains(id)
                        MahjongTileView(face: tiles[id].face,
                                        width: slotW,
                                        height: slotH,
                                        depth: slotW * 0.10)
                            .matchedGeometryEffect(id: id, in: rackSpace)
                            .scaleEffect(popped ? 1.18 : 1)
                            .shadow(color: popped ? Color(hexAny: 0xF2C14E).opacity(0.85) : .clear,
                                    radius: popped ? 10 : 0)
                            .accessibilityLabel("\(tiles[id].face.accessibilityName), in the rack")
                    }
                }
                .frame(width: slotW, height: slotH + slotW * 0.10)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color(hexAny: 0x241014).opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(rack.count >= slots - 1 && !rack.isEmpty
                              ? Color(hexAny: 0xE05563).opacity(0.8)
                              : world.accent.opacity(0.25),
                              lineWidth: rack.count >= slots - 1 && !rack.isEmpty ? 2 : 1)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: rack.count)
    }

    private var outOfSpaceCard: some View {
        VStack(spacing: 14) {
            Text("out of space")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text(canRevive
                 ? "the rack is full — revive to clear it and keep this run going"
                 : "the rack is full and the revive is spent — this run is over")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            if canRevive {
                Button {
                    revive()
                } label: {
                    Label("revive · watch ad", systemImage: "play.rectangle.fill")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black.opacity(0.85))
                        .padding(.horizontal, 18)
                        .frame(height: 46)
                        .frame(maxWidth: .infinity)
                        .background(world.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(adBusy)

                Button {
                    restart()
                } label: {
                    Label("restart board", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(.white.opacity(0.18), in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    restart()
                } label: {
                    Label("replay level", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black.opacity(0.85))
                        .padding(.horizontal, 18)
                        .frame(height: 46)
                        .frame(maxWidth: .infinity)
                        .background(world.accent, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    finishFailed()
                } label: {
                    Label("end run", systemImage: "flag.checkered")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(.white.opacity(0.18), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .frame(maxWidth: 320)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
        .padding(.horizontal, WitsMetrics.screenPadding)
        .disabled(adBusy)
    }

    // MARK: Board

    private func boardView(_ tiles: [MahjongTile], in size: CGSize) -> some View {
        let slots = tiles.map(\.slot)
        let widthUnits = CGFloat((slots.map(\.x).max() ?? 0) + 2)
        let heightUnits = CGFloat((slots.map(\.y).max() ?? 0) + 2)
        let maxZ = CGFloat(slots.map(\.z).max() ?? 0)

        let vAspect: CGFloat = 1.24                    // tiles run taller than wide
        let availW = size.width - WitsMetrics.screenPadding * 2
        let availH = size.height * 0.72
        let u = min(availW / widthUnits,
                    availH / (heightUnits * vAspect + maxZ * 0.4 + 0.6),
                    62)
        let tileW = u * 2
        let tileH = u * 2 * vAspect
        let depth = u * 0.24
        let boardW = widthUnits * u
        let boardH = heightUnits * u * vAspect + depth * 2

        let ordered = tiles
            .filter { boardIDs.contains($0.id) }
            .sorted { a, b in
                if a.slot.z != b.slot.z { return a.slot.z < b.slot.z }
                if a.slot.y != b.slot.y { return a.slot.y < b.slot.y }
                return a.slot.x < b.slot.x
            }
        let present = boardIDs
        // Training wheels: only the first band spotlights what's playable —
        // after that, reading the stack (and peeking under it) is the skill.
        let covered = mapLevel <= 4 ? coveredIDs(tiles, present: present) : []

        return ZStack(alignment: .topLeading) {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, tile in
                let lift = CGFloat(tile.slot.z)
                let peeking = peekID == tile.id
                MahjongTileView(face: tile.face,
                                width: tileW,
                                height: tileH,
                                depth: depth,
                                dimmed: covered.contains(tile.id))
                    .matchedGeometryEffect(id: tile.id, in: rackSpace)
                    .modifier(TileShake(shakes: CGFloat(shakes[tile.id] ?? 0)))
                    .scaleEffect(peeking ? 1.06 : 1)
                    .shadow(color: .black.opacity(peeking ? 0.4 : 0), radius: 10, y: 6)
                    .offset(x: CGFloat(tile.slot.x) * u - lift * depth * 0.6 + (peeking ? peekOffset.width : 0),
                            y: CGFloat(tile.slot.y) * u * vAspect - lift * depth + (peeking ? peekOffset.height : 0))
                    .zIndex(peeking ? 1_000 : Double(index))
                    // the deal rains in: each tile springs on with a tiny stagger
                    .scaleEffect(dealt ? 1 : 0.2, anchor: .center)
                    .opacity(dealt ? 1 : 0)
                    .animation(.spring(response: 0.42, dampingFraction: 0.72)
                        .delay(dealt ? Double(tile.id) * 0.016 : 0), value: dealt)
                    .onTapGesture { tap(tile, present: present) }
                    .gesture(peekGesture(tile))
                    .accessibilityLabel(tileLabel(tile, present: present))
                    .accessibilityAddTraits(.isButton)
            }
        }
        .frame(width: boardW, height: boardH, alignment: .topLeading)
        .frame(maxWidth: .infinity)
    }

    /// Slide a tile aside to inspect the layers beneath it; on release it
    /// springs back. Pure reconnaissance — the engine never hears about it.
    private func peekGesture(_ tile: MahjongTile) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !finished, !outOfSpace, popping.isEmpty else { return }
                if peekID == nil { peekID = tile.id }
                guard peekID == tile.id else { return }
                peekOffset = value.translation
            }
            .onEnded { _ in
                guard peekID == tile.id else { return }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.66)) {
                    peekOffset = .zero
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(340))
                    if peekOffset == .zero { peekID = nil }
                }
            }
    }

    /// Tiles with anything resting on them render dimmed — the depth cue that
    /// makes free tiles pop (side-blocking stays for the player to read).
    private func coveredIDs(_ tiles: [MahjongTile], present: Set<Int>) -> Set<Int> {
        var covered: Set<Int> = []
        for index in present {
            let slot = tiles[index].slot
            for other in present
            where tiles[other].slot.z > slot.z
                && abs(tiles[other].slot.x - slot.x) < 2
                && abs(tiles[other].slot.y - slot.y) < 2 {
                covered.insert(index)
                break
            }
        }
        return covered
    }

    private func tileLabel(_ tile: MahjongTile, present: Set<Int>) -> String {
        guard let tiles else { return tile.face.accessibilityName }
        let free = MahjongEngine.isFree(tile.id, slots: tiles.map(\.slot), present: present)
        return "\(tile.face.accessibilityName), \(free ? "free" : "blocked")"
    }

    // MARK: Interaction

    private func tap(_ tile: MahjongTile, present: Set<Int>) {
        guard !finished, popping.isEmpty, !outOfSpace, let tiles else { return }
        guard rack.count < traySlots else { return }

        guard MahjongEngine.isFree(tile.id, slots: tiles.map(\.slot), present: present) else {
            blockedTaps += 1
            hint = "that tile is blocked — it needs an open side and nothing on top"
            withAnimation(.linear(duration: 0.34)) {
                shakes[tile.id, default: 0] += 1
            }
            GameFeel.shared.uiTick(0.35)
            return
        }

        hint = ""
        let partner = rack.first { tiles[$0].face == tile.face }

        // The pick flies to the rack either way.
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            boardIDs.remove(tile.id)
            rack.append(tile.id)
        }
        GameFeel.shared.uiTick(0.6)

        if let partner {
            match(picked: tile.id, partner: partner)
        } else {
            lastMove = .pick(tile.id)
            if rack.count >= traySlots {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8).delay(0.25)) {
                    outOfSpace = true
                }
                GameFeel.shared.play(.wrong)
            }
        }
    }

    /// The twin just landed next to its partner: flash the pair gold, then
    /// clear both from the rack.
    private func match(picked: Int, partner: Int) {
        guard let tiles else { return }
        lastMove = .match(picked: picked, partner: partner)
        withAnimation(.spring(response: 0.2, dampingFraction: 0.6).delay(0.20)) {
            popping = [picked, partner]
        }
        GameFeel.shared.play(.correct(combo: 1))

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            GameFeel.shared.uiSuccess()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                rack.removeAll { popping.contains($0) }
                clearedIDs.insert(picked)
                clearedIDs.insert(partner)
                popping = []
            }
            if clearedIDs.count == tiles.count {
                checkCompletion()
            }
        }
    }

    /// Rewinds ONE move — the last one, once. A lone pick returns to the
    /// board; undoing a match restores the partner to the rack and the pick
    /// to the board. Making another move re-arms the button.
    private func undo() {
        guard !finished, popping.isEmpty, !outOfSpace, let last = lastMove else { return }
        lastMove = nil
        undos += 1
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            switch last {
            case .pick(let id):
                rack.removeAll { $0 == id }
                boardIDs.insert(id)
            case .match(let picked, let partner):
                clearedIDs.remove(picked)
                clearedIDs.remove(partner)
                rack.append(partner)
                boardIDs.insert(picked)
            }
        }
    }

    /// The one rewarded revive per attempt: every rack tile flies home to its
    /// board slot, leaving the rack empty.
    private func revive() {
        guard !adBusy, canRevive else { return }
        adBusy = true
        AdManager.shared.showRewarded { earned in
            adBusy = false
            guard earned else { return }   // closed early — the offer stands
            reviveUsed = true
            revives += 1
            lastMove = nil
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                outOfSpace = false
                boardIDs.formUnion(rack)
                rack.removeAll()
            }
            GameFeel.shared.uiSuccess()
        }
    }

    /// A fresh attempt at the same deal: board, rack, clock, and the revive
    /// all reset as if the level had just loaded.
    private func restart() {
        guard !finished, popping.isEmpty, let tiles,
              !clearedIDs.isEmpty || !rack.isEmpty else { return }
        restarts += 1
        lastMove = nil
        reviveUsed = false
        rack = []
        clearedIDs = []
        hint = ""
        elapsed = 0
        timerStartedAt = Date()
        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
            outOfSpace = false
            boardIDs = Set(tiles.map(\.id))
        }
        // replay the deal-in cascade
        dealt = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            dealt = true
        }
    }

    // MARK: Flow

    private func setUpAndRun() async {
        if tiles == nil {
            AdManager.shared.loadRewardedIfNeeded()
            let generated = MahjongEngine.generate(mapLevel: mapLevel,
                                                   seed: cfg.resolvedRandomSeed())
            tiles = generated.tiles
            spec = generated.spec
            boardIDs = Set(generated.tiles.map(\.id))
            timerStartedAt = Date()
            try? await Task.sleep(for: .milliseconds(60))
            dealt = true
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            guard !finished else { return }
            elapsed = cfg.activeElapsed(since: timerStartedAt)
        }
    }

    private func checkCompletion() {
        guard !finished else { return }
        finished = true
        GameFeel.shared.play(.newBest)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            finish(solved: true)
        }
    }

    /// Out of space with the revive spent: the run ends and grades as a
    /// partial clear (never a pass) — the host offers retry / back from there.
    private func finishFailed() {
        guard !finished else { return }
        finished = true
        GameFeel.shared.play(.gameOver)
        finish(solved: false)
    }

    private func finish(solved: Bool) {
        let seconds = max(1, elapsed)
        let pairCount = Double(max(1, pairs))
        let clearFraction = Double(clearedIDs.count) / Double(max(1, tiles?.count ?? 1))
        // Undos are the real mistakes (a pick that trapped the rack); taps on
        // blocked tiles cost a little — reading what's free is the skill.
        let cleanliness = min(1, pairCount / (pairCount + Double(undos) + Double(blockedTaps) * 0.25))
        let timeEfficiency = min(1, parSeconds / seconds)
        // Clearing earns the floor and clean play dominates the rest; a
        // failed run grades purely on how far it got, below the pass line.
        let accuracy = solved
            ? max(0, min(1, 0.30 + cleanliness * 0.60 + timeEfficiency * 0.10))
            : min(0.55, 0.55 * clearFraction)
        let score = solved
            ? max(0, Int((pairCount * 26 + cleanliness * 1200 + timeEfficiency * 400).rounded()))
            : max(0, Int(clearFraction * pairCount * 26))

        var result = GameResult(game: .mahjong, score: score, accuracy: accuracy)
        result.trials = pairs
        result.startedAt = startedAt
        result.durationMs = Int(seconds * 1000)
        result.raw = [
            "efficiency": (cleanliness * 100).rounded(),
            "pairs": pairCount,
            "clearedPairs": Double(clearedIDs.count / 2),
            "solved": solved ? 1 : 0,
            "tiles": Double(tiles?.count ?? 0),
            "traySlots": Double(traySlots),
            "undos": Double(undos),
            "restarts": Double(restarts),
            "revives": Double(revives),
            "blockedTaps": Double(blockedTaps),
            "parSeconds": parSeconds.rounded(),
            "seconds": seconds.rounded(),
            "mahjongLevel": level
        ]
        onResult(result)
    }

    private func showHelp() {
        hint = "free tiles have an open side and nothing on top — bank them, twins pair off. drag any tile aside to peek underneath"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            if !finished {
                hint = ""
            }
        }
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// A quick side-to-side "nope" jiggle. Each bump of `shakes` animates one
/// unit of progress → three oscillations that settle back at rest.
private struct TileShake: GeometryEffect {
    var travel: CGFloat = 5
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(shakes * .pi * 6), y: 0))
    }
}

// MARK: - Tile

/// One drawn tile: ivory face over the classic jade-green side, dimmed when
/// something rests on it. Purely visual — freeness and matching live in the
/// engine.
struct MahjongTileView: View {
    let face: MahjongFace
    let width: CGFloat
    let height: CGFloat
    let depth: CGFloat
    var dimmed = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
        ZStack {
            shape
                .fill(Color(hexAny: dimmed ? 0x2E5B45 : 0x3E7A5C))
                .frame(width: width, height: height)
                .offset(x: depth * 0.45, y: depth)
            shape
                .fill(LinearGradient(colors: [Color(hexAny: 0xFFFBEF), Color(hexAny: 0xF1E8CF)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: width, height: height)
                .overlay {
                    MahjongFaceView(face: face)
                        .frame(width: width * 0.8, height: height * 0.8)
                }
                .overlay {
                    // the depth cue: buried tiles fall into shade
                    shape.fill(.black.opacity(dimmed ? 0.30 : 0))
                }
                .overlay {
                    shape.strokeBorder(.black.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 3, y: 2)
        }
        .saturation(dimmed ? 0.7 : 1)
        .frame(width: width + depth * 0.45, height: height + depth, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: width * 0.14, style: .continuous))
    }
}

// MARK: - Faces

/// Original SwiftUI renditions of the traditional suits. Everything scales
/// off the given frame, so the same view draws board tiles, rack tiles, and
/// poster art.
struct MahjongFaceView: View {
    let face: MahjongFace

    private static let numerals = ["一", "二", "三", "四", "五", "六", "七", "八", "九"]
    private static let windGlyphs = ["東", "南", "西", "北"]

    private static let inkBlue = Color(hexAny: 0x22437A)
    private static let inkRed = Color(hexAny: 0xC93B3B)
    private static let inkGreen = Color(hexAny: 0x2F7D4F)

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height * 0.92)
            ZStack {
                switch face.suit {
                case .dots:
                    pips(rank: face.rank, size: s) { index, d in
                        Circle()
                            .fill(Self.pipColor(index))
                            .overlay(Circle().strokeBorder(.black.opacity(0.18), lineWidth: max(0.5, d * 0.06)))
                            .frame(width: d, height: d)
                    }
                case .bamboo:
                    pips(rank: face.rank, size: s) { index, d in
                        Capsule()
                            .fill(face.rank == 1 ? Self.inkRed : (index.isMultiple(of: 3) ? Self.inkRed : Self.inkGreen))
                            .frame(width: d * 0.38, height: d * 1.15)
                    }
                case .characters:
                    VStack(spacing: -s * 0.02) {
                        glyph(Self.numerals[max(0, min(8, face.rank - 1))], size: s * 0.46, color: Self.inkBlue)
                        glyph("萬", size: s * 0.46, color: Self.inkRed)
                    }
                case .winds:
                    glyph(Self.windGlyphs[max(0, min(3, face.rank - 1))], size: s * 0.72, color: Self.inkBlue)
                case .dragons:
                    switch face.rank {
                    case 1: glyph("中", size: s * 0.72, color: Self.inkRed)
                    case 2: glyph("發", size: s * 0.72, color: Self.inkGreen)
                    default:
                        RoundedRectangle(cornerRadius: s * 0.08, style: .continuous)
                            .strokeBorder(Self.inkBlue, lineWidth: max(1.5, s * 0.055))
                            .frame(width: s * 0.62, height: s * 0.78)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func glyph(_ text: String, size: CGFloat, color: Color) -> some View {
        Text(verbatim: text)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }

    /// Pip layouts on a 3×3 grid, shared by dots and bamboo.
    private static let pipGrid: [Int: [(Int, Int)]] = [
        1: [(1, 1)],
        2: [(1, 0), (1, 2)],
        3: [(0, 0), (1, 1), (2, 2)],
        4: [(0, 0), (2, 0), (0, 2), (2, 2)],
        5: [(0, 0), (2, 0), (1, 1), (0, 2), (2, 2)],
        6: [(0, 0), (2, 0), (0, 1), (2, 1), (0, 2), (2, 2)],
        7: [(0, 0), (2, 0), (0, 1), (1, 1), (2, 1), (0, 2), (2, 2)],
        8: [(0, 0), (1, 0), (2, 0), (0, 1), (2, 1), (0, 2), (1, 2), (2, 2)],
        9: [(0, 0), (1, 0), (2, 0), (0, 1), (1, 1), (2, 1), (0, 2), (1, 2), (2, 2)],
    ]

    private static func pipColor(_ index: Int) -> Color {
        [inkBlue, inkRed, inkGreen][index % 3]
    }

    @ViewBuilder
    private func pips<Pip: View>(rank: Int, size: CGFloat,
                                 @ViewBuilder pip: @escaping (Int, CGFloat) -> Pip) -> some View {
        let positions = Self.pipGrid[max(1, min(9, rank))] ?? []
        let cell = size / 3
        let d = rank <= 4 ? cell * 0.72 : cell * 0.62
        ZStack {
            ForEach(positions.indices, id: \.self) { index in
                let p = positions[index]
                pip(index, d)
                    .position(x: cell * (CGFloat(p.0) + 0.5),
                              y: cell * (CGFloat(p.1) + 0.5))
            }
        }
        .frame(width: size, height: size)
    }
}
