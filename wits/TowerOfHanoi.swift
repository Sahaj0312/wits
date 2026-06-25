//
//  TowerOfHanoi.swift
//  wits
//
//  Sequential planning puzzle. Move the full stack from A to C, one top disk at
//  a time, without ever placing a larger disk on a smaller one.
//

import SwiftUI

struct TowerOfHanoiScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private struct TowerState: Equatable {
        var stacks: [[Int]]
    }

    private struct LevelSpec {
        let number: Int
        let disks: Int
        let source: Int
        let target: Int
    }

    @State private var state: TowerState
    @State private var campaignLevel: Int
    @State private var selectedTower: Int?
    @State private var moves = 0
    @State private var invalidMoves = 0
    @State private var elapsed = 0.0
    @State private var timerStartedAt = Date()
    @State private var completedPuzzles = 0
    @State private var hint = "tap a tower to pick up its top disk"
    @State private var flashTower: Int?
    @State private var finished = false

    private let startedAt = Date()
    private let baseDiskCount: Int
    private let level: Double
    private static let campaignLevelCount = 36
    private static let campaignLevelKey = "wits.towerOfHanoi.currentLevel"

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        self.level = cfg.difficulty.level
        self.baseDiskCount = Self.diskCount(for: cfg.difficulty.level)
        let savedLevel = Self.savedCampaignLevel()
        _campaignLevel = State(initialValue: savedLevel)
        _state = State(initialValue: TowerState(stacks: Self.initialStacks(for: Self.levelSpec(savedLevel))))
    }

    private var currentSpec: LevelSpec {
        cfg.isSurvival ? LevelSpec(number: completedPuzzles + 1, disks: diskCount, source: 0, target: 2) : Self.levelSpec(campaignLevel)
    }

    private var diskCount: Int {
        cfg.isSurvival ? min(6, baseDiskCount + completedPuzzles / 2) : currentSpec.disks
    }

    private var sourceTower: Int {
        currentSpec.source
    }

    private var targetTower: Int {
        currentSpec.target
    }

    private var optimalMoves: Int {
        (1 << diskCount) - 1
    }

    private var targetSeconds: Double {
        Double(optimalMoves) * 2.65
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                background
                VStack(spacing: 0) {
                    topBar
                        .padding(.top, geo.safeAreaInsets.top + 8)
                        .padding(.horizontal, WitsMetrics.screenPadding)

                    Spacer(minLength: 24)

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
                        .animation(.easeOut(duration: 0.18), value: hint)

                    HanoiBoard(
                        stacks: state.stacks,
                        selectedTower: selectedTower,
                        flashTower: flashTower,
                        diskCount: diskCount,
                        targetTower: targetTower,
                        tapTower: tapTower
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: min(geo.size.height * 0.48, 380))
                    .padding(.horizontal, 14)
                    .padding(.top, 18)

                    Spacer(minLength: 24)

                    if !cfg.isSurvival {
                        progressStrip
                            .padding(.horizontal, WitsMetrics.screenPadding)
                            .padding(.bottom, geo.safeAreaInsets.bottom + 12)
                    }
                }
                HanoiSkyline()
                    .fill(Color.black.opacity(0.12))
                    .frame(height: 100)
                    .allowsHitTesting(false)
            }
        }
        .task { await runTimer() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tower of Hanoi")
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(light: 0x24536A, dark: 0x16384A),
                Color(light: 0x1A465D, dark: 0x102E41)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
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
                Text("moves: \(moves)")
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
                Label("\(diskCount) disks", systemImage: "square.stack.3d.up.fill")
                Spacer()
                Text("level \(campaignLevel)/\(Self.campaignLevelCount)")
                Spacer()
                Text("optimal \(optimalMoves)")
            }
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.78))

            ProgressView(value: min(1, Double(state.stacks[targetTower].count) / Double(diskCount)))
                .tint(Color(red: 0.24, green: 0.82, blue: 0.20))
                .background(.white.opacity(0.16), in: Capsule())
        }
    }

    private func tapTower(_ tower: Int) {
        guard !finished else { return }

        if let selectedTower {
            if selectedTower == tower {
                self.selectedTower = nil
                hint = "tap a tower to pick up its top disk"
                return
            }
            attemptMove(from: selectedTower, to: tower)
            return
        }

        guard !state.stacks[tower].isEmpty else {
            flash(tower)
            hint = "that tower is empty"
            cfg.report(.nearMiss)
            return
        }

        selectedTower = tower
        hint = "now tap the tower where this disk should go"
    }

    private func attemptMove(from source: Int, to target: Int) {
        guard let disk = state.stacks[source].last else {
            selectedTower = nil
            return
        }

        if let top = state.stacks[target].last, disk > top {
            invalidMoves += 1
            selectedTower = nil
            flash(target)
            hint = "a larger disk cannot be placed on a smaller one"
            cfg.report(.miss)
            return
        }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            _ = state.stacks[source].popLast()
            state.stacks[target].append(disk)
            selectedTower = nil
            moves += 1
        }
        hint = state.stacks[targetTower].count == diskCount ? "" : "good. keep moving the stack to tower \(Self.towerName(targetTower))"
        GameFeel.shared.play(.correct(combo: max(1, min(6, moves))))
        checkCompletion()
    }

    private func checkCompletion() {
        guard state.stacks[targetTower].count == diskCount else { return }

        if cfg.isSurvival {
            completedPuzzles += 1
            cfg.report(.hit, points: survivalPuzzlePoints(), combo: completedPuzzles)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard !finished else { return }
                resetForNextSurvivalPuzzle()
            }
            return
        }

        finished = true
        unlockNextCampaignLevel()
        GameFeel.shared.play(.newBest)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            finish()
        }
    }

    private func resetForNextSurvivalPuzzle() {
        let nextDisks = diskCount
        state = TowerState(stacks: Self.initialStacks(disks: nextDisks, source: 0))
        selectedTower = nil
        moves = 0
        invalidMoves = 0
        elapsed = 0
        timerStartedAt = Date()
        hint = "next tower: \(nextDisks) disks"
    }

    private func survivalPuzzlePoints() -> Int {
        let moveEfficiency = min(1, Double(optimalMoves) / Double(max(1, moves)))
        return Int((Double(diskCount) * 180 + 420 * moveEfficiency).rounded())
    }

    private func finish() {
        let seconds = max(1, elapsed)
        let moveEfficiency = min(1, Double(optimalMoves) / Double(max(1, moves)))
        let timeEfficiency = min(1, targetSeconds / seconds)
        let penalty = max(0, 1 - Double(invalidMoves) * 0.10)
        let accuracy = max(0, min(1, (moveEfficiency * 0.75 + timeEfficiency * 0.25) * penalty))
        let score = max(0, Int((Double(diskCount) * 400 + moveEfficiency * 1200 + timeEfficiency * 800 - Double(invalidMoves) * 75).rounded()))

        var result = GameResult(game: .towerOfHanoi, score: score, accuracy: accuracy)
        result.trials = moves + invalidMoves
        result.startedAt = startedAt
        result.durationMs = Int(seconds * 1000)
        result.raw = [
            "efficiency": (moveEfficiency * 100).rounded(),
            "moves": Double(moves),
            "optimalMoves": Double(optimalMoves),
            "seconds": seconds.rounded(),
            "diskCount": Double(diskCount),
            "hanoiLevel": Double(campaignLevel),
            "hanoiLevelCount": Double(Self.campaignLevelCount),
            "sourceTower": Double(sourceTower),
            "targetTower": Double(targetTower),
            "invalidMoves": Double(invalidMoves)
        ]
        onResult(result)
    }

    private func unlockNextCampaignLevel() {
        guard !cfg.isSurvival, campaignLevel < Self.campaignLevelCount else { return }
        let next = campaignLevel + 1
        UserDefaults.standard.set(next, forKey: Self.campaignLevelKey)
    }

    private func flash(_ tower: Int) {
        flashTower = tower
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            if flashTower == tower { flashTower = nil }
        }
    }

    private func showHelp() {
        hint = "move all disks to tower \(Self.towerName(targetTower)). only smaller disks can sit on larger ones"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if !finished {
                hint = selectedTower == nil ? "tap a tower to pick up its top disk" : "now tap the tower where this disk should go"
            }
        }
    }

    private func runTimer() async {
        timerStartedAt = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            guard !finished else { return }
            elapsed = Date().timeIntervalSince(timerStartedAt)
        }
    }

    private static func diskCount(for level: Double) -> Int {
        min(6, max(2, Int((level + 1) / 2) + 1))
    }

    private static func savedCampaignLevel() -> Int {
        let saved = UserDefaults.standard.integer(forKey: campaignLevelKey)
        return min(campaignLevelCount, max(1, saved == 0 ? 1 : saved))
    }

    private static func levelSpec(_ level: Int) -> LevelSpec {
        let clamped = min(campaignLevelCount, max(1, level))
        let disks: Int
        switch clamped {
        case 1...6: disks = 2
        case 7...16: disks = 3
        case 17...26: disks = 4
        case 27...32: disks = 5
        default: disks = 6
        }

        let routes = [(0, 2), (0, 1), (1, 2), (2, 0), (1, 0), (2, 1)]
        let route = routes[(clamped - 1) % routes.count]
        return LevelSpec(number: clamped, disks: disks, source: route.0, target: route.1)
    }

    private static func initialStacks(for spec: LevelSpec) -> [[Int]] {
        initialStacks(disks: spec.disks, source: spec.source)
    }

    private static func initialStacks(disks: Int, source: Int) -> [[Int]] {
        var stacks: [[Int]] = [[], [], []]
        stacks[min(2, max(0, source))] = Array(stride(from: disks, through: 1, by: -1))
        return stacks
    }

    private static func towerName(_ tower: Int) -> String {
        ["A", "B", "C"][min(2, max(0, tower))]
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct HanoiBoard: View {
    var stacks: [[Int]]
    var selectedTower: Int?
    var flashTower: Int?
    var diskCount: Int
    var targetTower: Int
    var tapTower: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 10
            let towerWidth = (geo.size.width - spacing * 2) / 3
            let towerHeight = geo.size.height

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(0..<3, id: \.self) { index in
                    Button {
                        tapTower(index)
                    } label: {
                        HanoiTowerView(
                            label: ["A", "B", "C"][index],
                            disks: stacks[index],
                            diskCount: diskCount,
                            selected: selectedTower == index,
                            highlighted: index == targetTower,
                            flashing: flashTower == index
                        )
                        .frame(width: towerWidth, height: towerHeight)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Tower \(["A", "B", "C"][index])")
                    .accessibilityValue("\(stacks[index].count) disks")
                }
            }
        }
    }
}

private struct HanoiTowerView: View {
    var label: String
    var disks: [Int]
    var diskCount: Int
    var selected: Bool
    var highlighted: Bool
    var flashing: Bool

    private var towerColor: Color {
        highlighted ? Color(red: 0.25, green: 0.82, blue: 0.20) : .white
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(towerColor)
                    .frame(width: 9)
                    .padding(.bottom, 15)

                GeometryReader { geo in
                    let diskMaxWidth = max(52, geo.size.width - 18)

                    VStack(spacing: 0) {
                        Spacer()
                        ForEach(Array(disks.reversed().enumerated()), id: \.offset) { offset, disk in
                            diskView(disk, maxWidth: diskMaxWidth)
                                .offset(y: selected && offset == 0 ? -26 : 0)
                                .zIndex(selected && offset == 0 ? 2 : 1)
                        }
                        Capsule()
                            .fill(towerColor)
                            .frame(height: 9)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 7)
            .padding(.top, 16)
            .padding(.bottom, 4)
            .background(.white.opacity(flashing ? 0.28 : selected ? 0.20 : 0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(flashing ? Color.witsWarm : selected ? Color.white.opacity(0.75) : .clear, lineWidth: 2)
            )

            Text(label)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .animation(.easeOut(duration: 0.16), value: flashing)
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: disks)
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: selected)
    }

    private func diskView(_ disk: Int, maxWidth: CGFloat) -> some View {
        let fraction = CGFloat(disk) / CGFloat(max(1, diskCount))
        let width = 0.38 + fraction * 0.54
        return RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Self.diskColors[(disk - 1) % Self.diskColors.count])
            .frame(width: maxWidth * width, height: 27)
            .overlay {
                Text("\(disk)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .shadow(color: .black.opacity(0.14), radius: 5, y: 3)
    }

    private static let diskColors: [Color] = [
        Color(red: 0.91, green: 0.22, blue: 0.19),
        Color(red: 1.00, green: 0.34, blue: 0.02),
        Color(red: 0.98, green: 0.74, blue: 0.13),
        Color(red: 0.55, green: 0.83, blue: 0.10),
        Color(red: 0.18, green: 0.56, blue: 0.93),
        Color(red: 0.47, green: 0.36, blue: 0.86)
    ]
}

private struct HanoiSkyline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - 24))
        path.addLine(to: CGPoint(x: rect.width * 0.13, y: rect.maxY - 24))
        path.addLine(to: CGPoint(x: rect.width * 0.13, y: rect.maxY - 38))
        path.addLine(to: CGPoint(x: rect.width * 0.20, y: rect.maxY - 38))
        path.addLine(to: CGPoint(x: rect.width * 0.20, y: rect.maxY - 58))
        path.addLine(to: CGPoint(x: rect.width * 0.25, y: rect.maxY - 58))
        path.addLine(to: CGPoint(x: rect.width * 0.30, y: rect.maxY - 42))
        path.addLine(to: CGPoint(x: rect.width * 0.46, y: rect.maxY - 42))
        path.addLine(to: CGPoint(x: rect.width * 0.46, y: rect.maxY - 30))
        path.addLine(to: CGPoint(x: rect.width * 0.62, y: rect.maxY - 30))
        path.addLine(to: CGPoint(x: rect.width * 0.62, y: rect.maxY - 48))
        path.addLine(to: CGPoint(x: rect.width * 0.71, y: rect.maxY - 48))
        path.addLine(to: CGPoint(x: rect.width * 0.71, y: rect.maxY - 34))
        path.addLine(to: CGPoint(x: rect.width * 0.82, y: rect.maxY - 34))
        path.addLine(to: CGPoint(x: rect.width * 0.86, y: rect.maxY - 78))
        path.addLine(to: CGPoint(x: rect.width * 0.90, y: rect.maxY - 34))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 34))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
