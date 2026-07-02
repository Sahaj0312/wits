//
//  TowerOfHanoi.swift
//  wits
//
//  Sequential planning puzzle, random-state edition. Each level deals a random
//  legal disk arrangement plus a random goal arrangement; rebuild the goal in
//  as few moves as possible. Difficulty scales by minimum solution length,
//  computed exactly with a BFS over the 3^n state space, so the memorized
//  full-stack transfer procedure never applies.
//

import SwiftUI

/// A single random-state puzzle. `start` and `goal` assign each disk (index 0
/// = smallest disk) to a peg 0...2. Any assignment is a legal state because
/// disks sharing a peg are necessarily ordered by size.
struct HanoiPuzzle: Equatable {
    let disks: Int
    let start: [Int]
    let goal: [Int]
    let optimal: Int

    static func stacks(from assignment: [Int]) -> [[Int]] {
        var stacks: [[Int]] = [[], [], []]
        for disk in stride(from: assignment.count, through: 1, by: -1) {
            stacks[assignment[disk - 1]].append(disk)
        }
        return stacks
    }
}

enum HanoiGenerator {
    /// Deal a puzzle whose optimal solution is `targetDistance` moves, or the
    /// closest achievable below it. A random goal's eccentricity can sit well
    /// under the graph diameter (2^n - 1), so re-roll the goal a few times
    /// when it cannot reach the requested distance.
    static func puzzle(disks: Int, targetDistance: Int) -> HanoiPuzzle {
        let stateCount = pow3(disks)
        let target = max(1, min(targetDistance, (1 << disks) - 1))
        var goal = Int.random(in: 0..<stateCount)
        var distances = bfs(from: goal, disks: disks)
        var attempts = 0
        while (distances.max() ?? 0) < target, attempts < 15 {
            let candidate = Int.random(in: 0..<stateCount)
            let candidateDistances = bfs(from: candidate, disks: disks)
            if (candidateDistances.max() ?? 0) > (distances.max() ?? 0) {
                goal = candidate
                distances = candidateDistances
            }
            attempts += 1
        }
        let want = min(target, distances.max() ?? 1)
        let starts = (0..<stateCount).filter { distances[$0] == want }
        let start = starts.randomElement() ?? goal
        return HanoiPuzzle(
            disks: disks,
            start: decode(start, disks: disks),
            goal: decode(goal, disks: disks),
            optimal: want
        )
    }

    /// Exact move distance from every state to `origin`.
    static func bfs(from origin: Int, disks: Int) -> [Int] {
        var distances = [Int](repeating: -1, count: pow3(disks))
        distances[origin] = 0
        var queue = [origin]
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            for next in neighbors(of: current, disks: disks) where distances[next] == -1 {
                distances[next] = distances[current] + 1
                queue.append(next)
            }
        }
        return distances
    }

    static func neighbors(of code: Int, disks: Int) -> [Int] {
        let pegs = decode(code, disks: disks)
        var top = [Int?](repeating: nil, count: 3)
        for disk in stride(from: disks, through: 1, by: -1) { top[pegs[disk - 1]] = disk }
        var result: [Int] = []
        for from in 0..<3 {
            guard let disk = top[from] else { continue }
            for to in 0..<3 where to != from {
                if let blocker = top[to], blocker < disk { continue }
                result.append(code + (to - from) * pow3(disk - 1))
            }
        }
        return result
    }

    static func encode(_ assignment: [Int]) -> Int {
        var code = 0
        for peg in assignment.reversed() { code = code * 3 + peg }
        return code
    }

    static func decode(_ code: Int, disks: Int) -> [Int] {
        var value = code
        return (0..<disks).map { _ in
            defer { value /= 3 }
            return value % 3
        }
    }

    static func pow3(_ n: Int) -> Int {
        var result = 1
        for _ in 0..<n { result *= 3 }
        return result
    }
}

struct TowerOfHanoiScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private struct TowerState: Equatable {
        var stacks: [[Int]]
    }

    private struct LevelSpec {
        let number: Int
        let disks: Int
        let moves: Int
    }

    @State private var puzzle: HanoiPuzzle
    @State private var state: TowerState
    @State private var campaignLevel: Int
    @State private var selectedTower: Int?
    @State private var moves = 0
    @State private var invalidMoves = 0
    @State private var elapsed = 0.0
    @State private var timerStartedAt = Date()
    @State private var completedPuzzles = 0
    @State private var hint = "rebuild the goal shown above the towers"
    @State private var flashTower: Int?
    @State private var finished = false

    private let startedAt = Date()
    private let baseDiskCount: Int
    private let level: Double
    private static let campaignLevelCount = 36
    private static let campaignLevelKey = "wits.towerOfHanoi.currentLevel"
    // Random-state puzzles need real lookahead, so the time budget per
    // optimal move is looser than the old rote-procedure 2.65s.
    private static let secondsPerOptimalMove = 3.1

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        self.level = cfg.difficulty.level
        self.baseDiskCount = Self.diskCount(for: cfg.difficulty.level)
        let savedLevel = Self.savedCampaignLevel()
        _campaignLevel = State(initialValue: savedLevel)
        let initialPuzzle: HanoiPuzzle
        if cfg.isSurvival {
            initialPuzzle = HanoiGenerator.puzzle(
                disks: Self.diskCount(for: cfg.difficulty.level),
                targetDistance: Self.survivalDistance(afterPuzzles: 0)
            )
        } else {
            let spec = Self.levelSpec(savedLevel)
            initialPuzzle = HanoiGenerator.puzzle(disks: spec.disks, targetDistance: spec.moves)
        }
        _puzzle = State(initialValue: initialPuzzle)
        _state = State(initialValue: TowerState(stacks: HanoiPuzzle.stacks(from: initialPuzzle.start)))
    }

    private var diskCount: Int {
        puzzle.disks
    }

    private var optimalMoves: Int {
        puzzle.optimal
    }

    private var targetSeconds: Double {
        Double(optimalMoves) * Self.secondsPerOptimalMove
    }

    private var goalStacks: [[Int]] {
        HanoiPuzzle.stacks(from: puzzle.goal)
    }

    /// Peg index per disk for the current board, comparable against
    /// `puzzle.goal` (an assignment fully determines the stacks).
    private var currentAssignment: [Int] {
        var pegs = [Int](repeating: 0, count: diskCount)
        for (peg, stack) in state.stacks.enumerated() {
            for disk in stack { pegs[disk - 1] = peg }
        }
        return pegs
    }

    private var matchedDisks: Int {
        zip(currentAssignment, puzzle.goal).filter(==).count
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                background
                VStack(spacing: 0) {
                    topBar
                        .padding(.top, 8)
                        .padding(.horizontal, WitsMetrics.screenPadding)

                    Spacer(minLength: 16)

                    HanoiGoalPreview(goalStacks: goalStacks, diskCount: diskCount)
                        .padding(.horizontal, WitsMetrics.screenPadding)

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
                        .padding(.top, 10)
                        .opacity(hint.isEmpty ? 0 : 1)
                        .animation(.easeOut(duration: 0.18), value: hint)

                    HanoiBoard(
                        stacks: state.stacks,
                        goalStacks: goalStacks,
                        selectedTower: selectedTower,
                        flashTower: flashTower,
                        diskCount: diskCount,
                        tapTower: tapTower
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: min(geo.size.height * 0.44, 360))
                    .padding(.horizontal, 14)
                    .padding(.top, 14)

                    Spacer(minLength: 20)

                    if !cfg.isSurvival {
                        progressStrip
                            .padding(.horizontal, WitsMetrics.screenPadding)
                            .padding(.bottom, 12)
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
        GameStageBackground(game: .towerOfHanoi)
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
                Text("optimal \(optimalMoves)")
            }
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.78))

            ProgressView(value: min(1, Double(matchedDisks) / Double(diskCount)))
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
        hint = ""
        GameFeel.shared.play(.correct(combo: max(1, min(6, moves))))
        checkCompletion()
    }

    private func checkCompletion() {
        guard currentAssignment == puzzle.goal else { return }

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
        let disks = min(6, max(3, baseDiskCount + completedPuzzles / 3))
        puzzle = HanoiGenerator.puzzle(
            disks: disks,
            targetDistance: Self.survivalDistance(afterPuzzles: completedPuzzles)
        )
        state = TowerState(stacks: HanoiPuzzle.stacks(from: puzzle.start))
        selectedTower = nil
        moves = 0
        invalidMoves = 0
        elapsed = 0
        timerStartedAt = Date()
        hint = "next puzzle: \(puzzle.optimal) moves to par"
    }

    private func survivalPuzzlePoints() -> Int {
        let moveEfficiency = min(1, Double(optimalMoves) / Double(max(1, moves)))
        return Int((Double(optimalMoves) * 50 + 420 * moveEfficiency).rounded())
    }

    private func finish() {
        let seconds = max(1, elapsed)
        let moveEfficiency = min(1, Double(optimalMoves) / Double(max(1, moves)))
        let timeEfficiency = min(1, targetSeconds / seconds)
        let penalty = max(0, 1 - Double(invalidMoves) * 0.10)
        let accuracy = max(0, min(1, (moveEfficiency * 0.75 + timeEfficiency * 0.25) * penalty))
        let score = max(0, Int((Double(optimalMoves) * 55 + moveEfficiency * 1200 + timeEfficiency * 800 - Double(invalidMoves) * 75).rounded()))

        var result = GameResult(game: .towerOfHanoi, score: score, accuracy: accuracy)
        result.trials = moves + invalidMoves
        result.startedAt = startedAt
        result.durationMs = Int(seconds * 1000)
        result.raw = [
            "efficiency": (moveEfficiency * 100).rounded(),
            "moves": Double(moves),
            "optimalMoves": Double(optimalMoves),
            "seconds": seconds.rounded(),
            "targetSeconds": targetSeconds,
            "diskCount": Double(diskCount),
            "hanoiLevel": Double(campaignLevel),
            // Campaign level to play next (finish() only runs on a solve in
            // campaign mode) — TowerPolicy pins the adaptive level to this.
            "hanoiLevelEnd": Double(cfg.isSurvival ? campaignLevel : min(Self.campaignLevelCount, campaignLevel + 1)),
            "hanoiLevelCount": Double(Self.campaignLevelCount),
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
        hint = "match the goal layout shown above. only smaller disks can sit on larger ones"
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
            elapsed = cfg.activeElapsed(since: timerStartedAt)
        }
    }

    private static func diskCount(for level: Double) -> Int {
        min(6, max(3, Int((level + 1) / 2) + 1))
    }

    private static func survivalDistance(afterPuzzles completed: Int) -> Int {
        4 + completed * 2
    }

    private static func savedCampaignLevel() -> Int {
        let saved = UserDefaults.standard.integer(forKey: campaignLevelKey)
        return min(campaignLevelCount, max(1, saved == 0 ? 1 : saved))
    }

    /// Difficulty ladder: disk count sets the board scale, `moves` sets the
    /// exact optimal-solution length the generator deals.
    private static func levelSpec(_ level: Int) -> LevelSpec {
        let clamped = min(campaignLevelCount, max(1, level))
        switch clamped {
        case 1...6:   return LevelSpec(number: clamped, disks: 3, moves: 1 + clamped)              // 2...7
        case 7...16:  return LevelSpec(number: clamped, disks: 4, moves: 6 + (clamped - 7))        // 6...15
        case 17...26: return LevelSpec(number: clamped, disks: 5, moves: 12 + 2 * (clamped - 17)) // 12...30
        default:      return LevelSpec(number: clamped, disks: 6, moves: 22 + 2 * (clamped - 27)) // 22...40
        }
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private enum HanoiPalette {
    static let diskColors: [Color] = [
        Color(red: 0.91, green: 0.22, blue: 0.19),
        Color(red: 1.00, green: 0.34, blue: 0.02),
        Color(red: 0.98, green: 0.74, blue: 0.13),
        Color(red: 0.55, green: 0.83, blue: 0.10),
        Color(red: 0.18, green: 0.56, blue: 0.93),
        Color(red: 0.47, green: 0.36, blue: 0.86)
    ]

    static func color(for disk: Int) -> Color {
        diskColors[(disk - 1) % diskColors.count]
    }
}

private struct HanoiGoalPreview: View {
    var goalStacks: [[Int]]
    var diskCount: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            Text("goal")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .padding(.bottom, 14)

            HStack(alignment: .bottom, spacing: 18) {
                ForEach(0..<3, id: \.self) { peg in
                    VStack(spacing: 3) {
                        VStack(spacing: 2) {
                            ForEach(goalStacks[peg].reversed(), id: \.self) { disk in
                                Capsule()
                                    .fill(HanoiPalette.color(for: disk))
                                    .frame(width: miniDiskWidth(disk), height: 7)
                            }
                        }
                        Capsule()
                            .fill(.white.opacity(0.5))
                            .frame(width: 48, height: 3)
                        Text(["A", "B", "C"][peg])
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Goal arrangement")
        .accessibilityValue(goalDescription)
    }

    private func miniDiskWidth(_ disk: Int) -> CGFloat {
        let fraction = CGFloat(disk) / CGFloat(max(1, diskCount))
        return 16 + fraction * 30
    }

    private var goalDescription: String {
        (0..<3).map { peg in
            let disks = goalStacks[peg]
            let list = disks.isEmpty ? "empty" : disks.map(String.init).joined(separator: ", ")
            return "Tower \(["A", "B", "C"][peg]): \(list)"
        }.joined(separator: ". ")
    }
}

private struct HanoiBoard: View {
    var stacks: [[Int]]
    var goalStacks: [[Int]]
    var selectedTower: Int?
    var flashTower: Int?
    var diskCount: Int
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
                            highlighted: !goalStacks[index].isEmpty && stacks[index] == goalStacks[index],
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
            .fill(HanoiPalette.color(for: disk))
            .frame(width: maxWidth * width, height: 27)
            .overlay {
                Text("\(disk)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .shadow(color: .black.opacity(0.14), radius: 5, y: 3)
    }
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
