//
//  WaterSortScreen.swift
//  wits
//
//  The playable water sort screen. Tap a tube to pick it up, tap another to
//  pour; a pour lands only on a matching colour or an empty tube. The board
//  is generated behind a spinner with an exact A* par (WaterSort.swift), and
//  the clock starts once the tubes are on screen.
//
//  A pour physically animates: the source tube flies over the destination,
//  tilts to ~55–70° while a stream falls from its lip, and the liquid inside
//  stays level with the world (drawn as a diagonal cut across the tilted
//  tube). Engine state updates at tap time; the animation is display-only.
//

import SwiftUI

/// Reports each tube's resting frame in the board coordinate space so a pour
/// can be choreographed between two slots.
private struct TubeFramesKey: PreferenceKey {
    nonisolated static let defaultValue: [Int: CGRect] = [:]
    nonisolated static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct WaterSortScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    @State private var tubes: [WaterSortEngine.Tube]?
    @State private var capacity = 4
    @State private var colorCount = 0
    @State private var par = 0
    @State private var moves = 0
    @State private var elapsed = 0.0
    @State private var timerStartedAt = Date()
    @State private var hint = "tap a tube, then tap where to pour"
    @State private var selected: Int?
    @State private var finished = false
    @State private var pour: ActivePour?
    @State private var preTubes: [WaterSortEngine.Tube]?
    @State private var tubeFrames: [Int: CGRect] = [:]
    @State private var initialTubes: [WaterSortEngine.Tube]?
    @State private var history: [[WaterSortEngine.Tube]] = []
    @State private var undos = 0
    @State private var restarts = 0
    @State private var deadEnd = false
    @State private var positionRevision = 0

    private let startedAt = Date()
    private let level: Double
    private let mapLevel: Int
    private var world: GameWorld { GameID.waterSort.world }

    /// Liquid palette, indexed by 1-based engine colour. Fixed hexAny values
    /// chosen to stay distinct from each other and the world chrome.
    private static let liquid: [Color] = [
        Color(hexAny: 0xF25757), // red
        Color(hexAny: 0xF7A72F), // orange
        Color(hexAny: 0xF8E14B), // yellow
        Color(hexAny: 0x5BC96A), // green
        Color(hexAny: 0x3ED8C3), // teal
        Color(hexAny: 0x4D8DF7), // blue
        Color(hexAny: 0xA06DF2), // violet
        Color(hexAny: 0xF06CB4)  // pink
    ]

    private static let liquidNames = ["red", "orange", "yellow", "green", "teal", "blue", "violet", "pink"]

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        self.level = cfg.difficulty.level
        self.mapLevel = cfg.mapLevel ?? DifficultyScale.contentLevel(for: .waterSort,
                                                                     legacyDifficulty: cfg.difficulty.level)
    }

    /// Time budget prices in planning, not just execution — deep thought on a
    /// hard board shouldn't tank the grade.
    private var parSeconds: Double { Double(par) * 5.0 + 30 }

    /// Full move credit within ~20% of par: par is A*-optimal, and matching a
    /// computer within a fifth is mastery for a human.
    private var graceMoves: Int { Int(ceil(Double(par) * 1.2)) + 1 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                GameStageBackground(game: .waterSort)
                if let tubes {
                    VStack(spacing: 0) {
                        topBar
                            .padding(.top, 8)
                            .padding(.horizontal, WitsMetrics.screenPadding)

                        Spacer(minLength: 20)

                        Text(hint)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.horizontal, WitsMetrics.screenPadding)
                            .opacity(hint.isEmpty ? 0 : 1)

                        tubesView(tubes, in: geo.size)
                            .padding(.top, 22)

                        Spacer(minLength: 24)

                        progressStrip
                            .padding(.horizontal, WitsMetrics.screenPadding)
                            .padding(.bottom, 12)
                    }

                    if deadEnd {
                        deadEndCard
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                } else {
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(.white)
                        Text("filling the tubes…")
                            .font(.system(size: 14, weight: .semibold, design: world.bodyDesign))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
        .task { await setUpAndRun() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Water sort")
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            // clears the pause button the host overlays at top-leading
            Spacer()
                .frame(width: 38)

            HStack(spacing: 10) {
                Text(Self.clock(elapsed))
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text("pours \(moves)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
                    .foregroundStyle(.white.opacity(history.isEmpty ? 0.35 : 1))
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(history.isEmpty || finished || pour != nil)
            .accessibilityLabel("Undo last pour")

            Button {
                restart()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white.opacity(moves == 0 ? 0.35 : 1))
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(moves == 0 || finished || pour != nil)
            .accessibilityLabel("Restart this board")

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

    /// Shown when no route to a solution remains. Some dead positions still
    /// allow a matching-colour pour, but only as a reversible loop.
    private var deadEndCard: some View {
        VStack(spacing: 14) {
            Text("this position is stuck")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("the remaining pours only loop — rewind a pour or start this board over")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button {
                    undo()
                } label: {
                    Label("undo pour", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(.white.opacity(0.18), in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    restart()
                } label: {
                    Label("restart", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black.opacity(0.85))
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(world.accent, in: Capsule())
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
    }

    private var progressStrip: some View {
        VStack(spacing: 8) {
            HStack {
                Label("\(colorCount) colours", systemImage: "drop.fill")
                Spacer()
                Text("par \(par)")
            }
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.78))

            ProgressView(value: min(1, Double(moves) / Double(max(1, graceMoves))))
                .tint(moves <= graceMoves ? world.secondary : world.accent)
                .background(.white.opacity(0.16), in: Capsule())
        }
    }

    // MARK: Pour animation

    /// One in-flight pour. The engine has already moved the liquid; this
    /// drives the display-only choreography: fly to the destination, tilt and
    /// stream, fly home.
    private struct ActivePour {
        let source: Int
        let dest: Int
        let color: UInt8
        let units: Int
        /// +1 pours over the right lip (destination to the right), -1 mirrored.
        let side: CGFloat
        let start: Date

        let travelDur = 0.22
        let returnDur = 0.22
        /// A bigger run streams longer, like the reference: ~0.35s for one
        /// unit, +0.14s per extra unit.
        var pourDur: Double { 0.35 + 0.14 * Double(units - 1) }
        var total: Double { travelDur + pourDur + returnDur }

        /// Tilt when the stream starts; deepens as the run drains so the
        /// liquid keeps reaching the lip.
        let baseAngle = 55.0
        let extraAngle = 14.0
    }

    /// Everything the renderer needs for one frame of the pour.
    private struct PourFrame {
        var angle = 0.0
        var offset = CGSize.zero
        var drained = 0.0
        var added: CGFloat = 0
        var stream: (x: CGFloat, top: CGFloat, bottom: CGFloat)?
    }

    private static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    private func pourFrame(_ p: ActivePour, at date: Date, tubeW: CGFloat, tubeH: CGFloat) -> PourFrame {
        guard let slot = tubeFrames[p.source], let dest = tubeFrames[p.dest] else { return PourFrame() }
        var f = PourFrame()
        let t = date.timeIntervalSince(p.start)
        let unitH = (tubeH - 6) / CGFloat(capacity)

        // Park the mouth above the destination's opening, shifted so the low
        // lip — where the stream leaves — sits over the destination's centre.
        let midTilt = (p.baseAngle + p.extraAngle / 2) * .pi / 180
        let mouthStart = CGPoint(x: slot.midX, y: slot.minY)
        let mouthTarget = CGPoint(x: dest.midX - p.side * tubeW / 2 * cos(midTilt),
                                  y: dest.minY - tubeH * 0.30)

        let travelF: Double
        var pourP = 0.0
        var lift = 0.0
        if t < p.travelDur {
            travelF = Self.easeInOut(t / p.travelDur)
            f.angle = p.baseAngle * travelF
            lift = selectedLift * (1 - travelF)
        } else if t < p.travelDur + p.pourDur {
            travelF = 1
            pourP = (t - p.travelDur) / p.pourDur
            f.angle = p.baseAngle + p.extraAngle * pourP
        } else {
            let back = Self.easeInOut(min(1, (t - p.travelDur - p.pourDur) / p.returnDur))
            travelF = 1 - back
            pourP = 1
            f.angle = (p.baseAngle + p.extraAngle) * travelF
        }
        f.angle *= p.side
        f.offset = CGSize(width: (mouthTarget.x - mouthStart.x) * travelF,
                          height: (mouthTarget.y - mouthStart.y) * travelF + lift)
        f.drained = Double(p.units) * pourP
        f.added = CGFloat(f.drained)

        if pourP > 0, pourP < 1 {
            let tilt = f.angle * .pi / 180
            let mouth = CGPoint(x: mouthStart.x + f.offset.width, y: mouthStart.y + f.offset.height)
            let surface = dest.maxY - 3 - (CGFloat(preTubes?[p.dest].count ?? 0) + f.added) * unitH
            f.stream = (x: mouth.x + p.side * tubeW / 2 * cos(tilt),
                        top: mouth.y + p.side * tubeW / 2 * sin(tilt),
                        bottom: surface)
        }
        return f
    }

    // MARK: Tubes

    private let selectedLift = -14.0

    private func tubesView(_ tubes: [WaterSortEngine.Tube], in size: CGSize) -> some View {
        let count = tubes.count
        let rows = count <= 5 ? 1 : 2
        let perRow = Int(ceil(Double(count) / Double(rows)))
        let hGap: CGFloat = 14
        let maxW = size.width - WitsMetrics.screenPadding * 2
        let tubeW = min(56, (maxW - hGap * CGFloat(perRow - 1)) / CGFloat(perRow))
        let tubeH = min(size.height * (rows == 1 ? 0.34 : 0.24), tubeW * 3.4)

        // During a pour the board renders the pre-pour snapshot; the frame
        // math drains the source and raises the destination display-only.
        let shown = (pour != nil ? preTubes : nil) ?? tubes

        return TimelineView(.animation(paused: pour == nil)) { timeline in
            let frame = pour.map { pourFrame($0, at: timeline.date, tubeW: tubeW, tubeH: tubeH) }

            VStack(spacing: 34) {
                ForEach(0..<rows, id: \.self) { row in
                    let indices = rowIndices(row: row, perRow: perRow, count: count)
                    HStack(spacing: hGap) {
                        ForEach(indices, id: \.self) { index in
                            tubeCell(index: index, shown: shown, frame: frame,
                                     width: tubeW, height: tubeH)
                        }
                    }
                    .zIndex(pour.map { indices.contains($0.source) ? 2.0 : 1.0 } ?? 1)
                }
            }
            .overlay { streamOverlay(frame) }
        }
        .coordinateSpace(name: "waterBoard")
        .onPreferenceChange(TubeFramesKey.self) { tubeFrames = $0 }
    }

    @ViewBuilder
    private func tubeCell(index: Int, shown: [WaterSortEngine.Tube], frame: PourFrame?,
                          width: CGFloat, height: CGFloat) -> some View {
        Group {
            if let pour, let frame, index == pour.source {
                pouringTubeView(shown[index], drained: frame.drained, angle: frame.angle,
                                width: width, height: height)
                    .rotationEffect(.degrees(frame.angle), anchor: .top)
                    .offset(frame.offset)
            } else if let pour, let frame, index == pour.dest {
                tubeView(shown[index], width: width, height: height,
                         extraFill: (Self.liquid[(Int(pour.color) - 1) % Self.liquid.count], frame.added))
            } else {
                tubeView(shown[index], width: width, height: height)
                    .offset(y: selected == index ? selectedLift : 0)
                    .animation(.spring(duration: 0.22), value: selected == index)
            }
        }
        .background(GeometryReader { geo in
            Color.clear.preference(key: TubeFramesKey.self,
                                   value: [index: geo.frame(in: .named("waterBoard"))])
        })
        .zIndex(index == pour?.source ? 2 : 1)
        .onTapGesture { tap(index) }
        .accessibilityLabel(tubeLabel(shown[index], index: index))
        .accessibilityAddTraits(selected == index ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func streamOverlay(_ frame: PourFrame?) -> some View {
        if let pour, let stream = frame?.stream, stream.bottom > stream.top {
            Path { path in
                path.addRoundedRect(in: CGRect(x: stream.x - 2.5, y: stream.top,
                                               width: 5, height: stream.bottom - stream.top),
                                    cornerSize: CGSize(width: 2.5, height: 2.5))
            }
            .fill(Self.liquid[(Int(pour.color) - 1) % Self.liquid.count])
            .allowsHitTesting(false)
        }
    }

    private func rowIndices(row: Int, perRow: Int, count: Int) -> Range<Int> {
        let start = row * perRow
        return start..<min(count, start + perRow)
    }

    private func tubeView(_ tube: WaterSortEngine.Tube, width: CGFloat, height: CGFloat,
                          extraFill: (color: Color, units: CGFloat)? = nil) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: width * 0.16,
                                           bottomLeadingRadius: width * 0.5,
                                           bottomTrailingRadius: width * 0.5,
                                           topTrailingRadius: width * 0.16,
                                           style: .continuous)
        let unitH = (height - 6) / CGFloat(capacity)
        let complete = WaterSortEngine.isComplete(tube, capacity: capacity)
        let fillUnits = CGFloat(tube.count) + (extraFill?.units ?? 0)

        return ZStack(alignment: .bottom) {
            shape.fill(.white.opacity(0.07))

            VStack(spacing: 0) {
                // liquid landing mid-pour rises smoothly above the stack
                if let extraFill, extraFill.units > 0 {
                    Rectangle()
                        .fill(extraFill.color)
                        .frame(height: unitH * extraFill.units)
                }
                ForEach(Array(tube.enumerated().reversed()), id: \.offset) { _, color in
                    Rectangle()
                        .fill(Self.liquid[(Int(color) - 1) % Self.liquid.count])
                        .frame(height: unitH)
                }
            }
            .padding(3)
            .clipShape(shape.inset(by: 3))

            // resting-surface sheen on the top unit
            if fillUnits > 0 {
                Rectangle()
                    .fill(.white.opacity(0.22))
                    .frame(height: 3)
                    .padding(.horizontal, 5)
                    .offset(y: -(fillUnits * unitH))
            }

            shape.strokeBorder(.white.opacity(complete ? 0.55 : 0.28), lineWidth: 2)
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
    }

    /// The tilted, draining source tube. The whole view is rotated by the
    /// caller, so liquid surfaces are drawn with the opposite slope to stay
    /// level with the world — the signature water sort look.
    private func pouringTubeView(_ tube: WaterSortEngine.Tube, drained: Double, angle: Double,
                                 width: CGFloat, height: CGFloat) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: width * 0.16,
                                           bottomLeadingRadius: width * 0.5,
                                           bottomTrailingRadius: width * 0.5,
                                           topTrailingRadius: width * 0.16,
                                           style: .continuous)
        let capacity = self.capacity

        return ZStack {
            shape.fill(.white.opacity(0.07))

            Canvas { ctx, size in
                ctx.clip(to: shape.inset(by: 3).path(in: CGRect(origin: .zero, size: size)))
                let w = size.width
                let unitH = (size.height - 6) / CGFloat(capacity)
                let slope = CGFloat(tan(angle * .pi / 180))
                let total = Double(tube.count) - drained
                guard total > 0 else { return }

                // Paint each colour as everything below its level surface,
                // top colour first, so deeper colours overwrite from below.
                func surface(at units: Double, x: CGFloat) -> CGFloat {
                    let yMid = (size.height - 3) - CGFloat(units) * unitH
                    return yMid - (x - w / 2) * slope
                }
                for layer in stride(from: tube.count - 1, through: 0, by: -1) {
                    let units = min(Double(layer + 1), total)
                    guard units > 0 else { continue }
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: surface(at: units, x: 0)))
                    path.addLine(to: CGPoint(x: w, y: surface(at: units, x: w)))
                    path.addLine(to: CGPoint(x: w, y: size.height))
                    path.addLine(to: CGPoint(x: 0, y: size.height))
                    path.closeSubpath()
                    ctx.fill(path, with: .color(Self.liquid[(Int(tube[layer]) - 1) % Self.liquid.count]))
                }

                var sheen = Path()
                sheen.move(to: CGPoint(x: 0, y: surface(at: total, x: 0)))
                sheen.addLine(to: CGPoint(x: w, y: surface(at: total, x: w)))
                ctx.stroke(sheen, with: .color(.white.opacity(0.22)), lineWidth: 3)
            }

            shape.strokeBorder(.white.opacity(0.28), lineWidth: 2)
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
    }

    private func tubeLabel(_ tube: WaterSortEngine.Tube, index: Int) -> String {
        guard !tube.isEmpty else { return "Tube \(index + 1), empty" }
        let colors = tube.reversed().map { Self.liquidNames[(Int($0) - 1) % Self.liquidNames.count] }
        return "Tube \(index + 1), top to bottom: \(colors.joined(separator: ", "))"
    }

    // MARK: Interaction

    private func tap(_ index: Int) {
        guard !finished, !deadEnd, pour == nil, let current = tubes else { return }

        if let source = selected {
            if source == index {
                selected = nil
                return
            }
            if WaterSortEngine.canPour(current, from: source, to: index, capacity: capacity) {
                startPour(from: source, to: index)
                return
            }
        }

        // Nothing poured: treat the tap as picking (or re-picking) a source.
        if !current[index].isEmpty && !WaterSortEngine.isComplete(current[index], capacity: capacity) {
            selected = index
        } else if selected != nil {
            selected = nil
        }
    }

    /// Applies the pour to the engine immediately, then runs the flight
    /// choreography against a pre-pour snapshot. Taps are ignored until the
    /// tube is home (< 1s).
    private func startPour(from source: Int, to dest: Int) {
        guard var current = tubes, let color = current[source].last else { return }
        let snapshot = current
        let moved = WaterSortEngine.pour(&current, from: source, to: dest, capacity: capacity)
        guard moved > 0 else { return }
        tubes = current
        positionRevision &+= 1
        moves += 1
        hint = ""
        selected = nil
        preTubes = snapshot
        history.append(snapshot)

        let side: CGFloat
        if let s = tubeFrames[source], let d = tubeFrames[dest], d.midX < s.midX {
            side = -1
        } else {
            side = 1
        }
        let active = ActivePour(source: source, dest: dest, color: color,
                                units: moved, side: side, start: Date())
        pour = active
        Task {
            try? await Task.sleep(for: .seconds(active.total))
            finishPour()
        }
    }

    private func finishPour() {
        guard let p = pour else { return }
        pour = nil
        preTubes = nil
        if let tubes, WaterSortEngine.isComplete(tubes[p.dest], capacity: capacity) {
            GameFeel.shared.play(.correct(combo: 3))
        }
        checkCompletion()
        guard let tubes, !finished else { return }
        if !playerCanPour(tubes) {
            presentDeadEnd()
        } else if !tubes.contains(where: \.isEmpty) {
            verifyReachability(of: tubes, revision: positionRevision)
        }
    }

    /// With no empty tube, a board can retain one legal pour that merely
    /// shuttles a colour run back and forth forever. Confirm reachability off
    /// the main thread so that loop counts as a stalemate too.
    private func verifyReachability(of candidate: [WaterSortEngine.Tube], revision: Int) {
        let cap = capacity
        Task {
            let isSolvable = await Task.detached(priority: .utility) {
                WaterSortEngine.solve(candidate, capacity: cap) != nil
            }.value
            guard !Task.isCancelled, !isSolvable, !finished,
                  revision == positionRevision,
                  let current = tubes,
                  WaterSortEngine.key(current) == WaterSortEngine.key(candidate) else { return }
            presentDeadEnd()
        }
    }

    private func presentDeadEnd() {
        guard !deadEnd, !finished else { return }
        selected = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            deadEnd = true
        }
        GameFeel.shared.play(.wrong)
    }

    /// A pour the player could actually make: complete tubes can't be picked
    /// up, so a technically-legal complete → empty pour doesn't count.
    private func playerCanPour(_ tubes: [WaterSortEngine.Tube]) -> Bool {
        for source in tubes.indices
        where !tubes[source].isEmpty && !WaterSortEngine.isComplete(tubes[source], capacity: capacity) {
            for dest in tubes.indices
            where WaterSortEngine.canPour(tubes, from: source, to: dest, capacity: capacity) {
                return true
            }
        }
        return false
    }

    /// Rewinds one pour. The spent move is not refunded — undo is an escape
    /// hatch, not a free trial-and-error loop toward par.
    private func undo() {
        guard pour == nil, !finished, let last = history.popLast() else { return }
        positionRevision &+= 1
        undos += 1
        selected = nil
        hint = ""
        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
            deadEnd = false
            tubes = last
        }
    }

    /// A fresh attempt at the same deal: board, pours, and clock all reset,
    /// exactly as if the level had just loaded.
    private func restart() {
        guard pour == nil, !finished, let initialTubes else { return }
        positionRevision &+= 1
        restarts += 1
        history = []
        selected = nil
        moves = 0
        hint = ""
        elapsed = 0
        timerStartedAt = Date()
        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
            deadEnd = false
            tubes = initialTubes
        }
    }

    // MARK: Flow

    private func setUpAndRun() async {
        if tubes == nil {
            let target = mapLevel
            let seed = cfg.resolvedRandomSeed()
            let generated = await Task.detached(priority: .userInitiated) {
                WaterSortEngine.generate(mapLevel: target, seed: seed)
            }.value
            tubes = generated.tubes
            initialTubes = generated.tubes
            par = generated.par
            capacity = generated.spec.capacity
            colorCount = generated.spec.colors
            timerStartedAt = Date()
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            guard !finished else { return }
            elapsed = cfg.activeElapsed(since: timerStartedAt)
        }
    }

    private func checkCompletion() {
        guard let tubes, WaterSortEngine.isSolved(tubes, capacity: capacity), !finished else { return }
        finished = true
        selected = nil
        GameFeel.shared.play(.newBest)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            finish()
        }
    }

    private func finish() {
        let seconds = max(1, elapsed)
        let moveEfficiency = min(1, Double(graceMoves) / Double(max(1, moves)))
        let timeEfficiency = min(1, parSeconds / seconds)
        // Solving at all earns the floor, and pour quality dominates the rest,
        // so a slow, deliberate near-optimal solve still grades to a clean pass.
        // Time keeps a small weight to reward decisiveness at the margins.
        let accuracy = max(0, min(1, 0.30 + moveEfficiency * 0.60 + timeEfficiency * 0.10))
        let score = max(0, Int((Double(par) * 24 + moveEfficiency * 1300 + timeEfficiency * 500).rounded()))

        var result = GameResult(game: .waterSort, score: score, accuracy: accuracy)
        result.trials = moves
        result.startedAt = startedAt
        result.durationMs = Int(seconds * 1000)
        result.raw = [
            "efficiency": (moveEfficiency * 100).rounded(),
            "moves": Double(moves),
            "parMoves": Double(par),
            "graceMoves": Double(graceMoves),
            "parSeconds": parSeconds.rounded(),
            "seconds": seconds.rounded(),
            "colors": Double(colorCount),
            "tubes": Double(tubes?.count ?? 0),
            "undos": Double(undos),
            "restarts": Double(restarts),
            "waterLevel": level
        ]
        onResult(result)
    }

    private func showHelp() {
        hint = "a pour lands only on the same colour or an empty tube. one colour per tube wins"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
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
