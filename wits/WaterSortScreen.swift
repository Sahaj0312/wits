//
//  WaterSortScreen.swift
//  wits
//
//  The playable water sort screen. Tap a tube to pick it up, tap another to
//  pour; a pour lands only on a matching colour or an empty tube. The board
//  is generated behind a spinner with an exact A* par (WaterSort.swift), and
//  the clock starts once the tubes are on screen.
//

import SwiftUI

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
        HStack(spacing: 10) {
            Spacer()
                .frame(width: 38)

            HStack(spacing: 16) {
                Text(Self.clock(elapsed))
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 66, alignment: .leading)
                Spacer(minLength: 0)
                Text("pours: \(moves)")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 42)
            .background(Color.black.opacity(0.35), in: Capsule())

            Button {
                showHelp()
            } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show rule reminder")
        }
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

    // MARK: Tubes

    private func tubesView(_ tubes: [WaterSortEngine.Tube], in size: CGSize) -> some View {
        let count = tubes.count
        let rows = count <= 5 ? 1 : 2
        let perRow = Int(ceil(Double(count) / Double(rows)))
        let hGap: CGFloat = 14
        let maxW = size.width - WitsMetrics.screenPadding * 2
        let tubeW = min(56, (maxW - hGap * CGFloat(perRow - 1)) / CGFloat(perRow))
        let tubeH = min(size.height * (rows == 1 ? 0.34 : 0.24), tubeW * 3.4)

        return VStack(spacing: 34) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: hGap) {
                    ForEach(rowIndices(row: row, perRow: perRow, count: count), id: \.self) { index in
                        tubeView(tubes[index], width: tubeW, height: tubeH)
                            .offset(y: selected == index ? -14 : 0)
                            .onTapGesture { tap(index) }
                            .accessibilityLabel(tubeLabel(tubes[index], index: index))
                            .accessibilityAddTraits(selected == index ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
        }
    }

    private func rowIndices(row: Int, perRow: Int, count: Int) -> Range<Int> {
        let start = row * perRow
        return start..<min(count, start + perRow)
    }

    private func tubeView(_ tube: WaterSortEngine.Tube, width: CGFloat, height: CGFloat) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: width * 0.16,
                                           bottomLeadingRadius: width * 0.5,
                                           bottomTrailingRadius: width * 0.5,
                                           topTrailingRadius: width * 0.16,
                                           style: .continuous)
        let unitH = (height - 6) / CGFloat(capacity)
        let complete = WaterSortEngine.isComplete(tube, capacity: capacity)

        return ZStack(alignment: .bottom) {
            shape.fill(.white.opacity(0.07))

            VStack(spacing: 0) {
                ForEach(Array(tube.enumerated().reversed()), id: \.offset) { _, color in
                    Rectangle()
                        .fill(Self.liquid[(Int(color) - 1) % Self.liquid.count])
                        .frame(height: unitH)
                }
            }
            .padding(3)
            .clipShape(shape.inset(by: 3))

            // resting-surface sheen on the top unit
            if !tube.isEmpty {
                Rectangle()
                    .fill(.white.opacity(0.22))
                    .frame(height: 3)
                    .padding(.horizontal, 5)
                    .offset(y: -(CGFloat(tube.count) * unitH))
            }

            shape.strokeBorder(.white.opacity(complete ? 0.55 : 0.28), lineWidth: 2)
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
        guard !finished, var current = tubes else { return }

        if let source = selected {
            if source == index {
                selected = nil
                return
            }
            if WaterSortEngine.canPour(current, from: source, to: index, capacity: capacity) {
                WaterSortEngine.pour(&current, from: source, to: index, capacity: capacity)
                tubes = current
                moves += 1
                hint = ""
                selected = nil
                let completed = WaterSortEngine.isComplete(current[index], capacity: capacity)
                GameFeel.shared.play(.correct(combo: completed ? 3 : 1))
                checkCompletion()
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

    // MARK: Flow

    private func setUpAndRun() async {
        if tubes == nil {
            let target = mapLevel
            let seed = cfg.resolvedRandomSeed()
            let generated = await Task.detached(priority: .userInitiated) {
                WaterSortEngine.generate(mapLevel: target, seed: seed)
            }.value
            tubes = generated.tubes
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
