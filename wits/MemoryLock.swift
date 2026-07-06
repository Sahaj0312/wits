//
//  MemoryLock.swift
//  wits
//
//  Word deduction with fading feedback. Guess the hidden word from Wordle-style
//  clues, but previous row colors disappear, forcing the player to hold the
//  letter evidence in memory.
//

import SwiftUI

private enum MemoryLockStyle {
    static let stageTop = Color(light: 0x123140, dark: 0x07131F)
    static let stageMid = Color(light: 0x111D32, dark: 0x091123)
    static let stageBottom = Color(light: 0x21143F, dark: 0x10091F)
    static let boardTop = Color(light: 0x172B3B, dark: 0x101C2C)
    static let boardBottom = Color(light: 0x0E1726, dark: 0x080E1B)
    static let boardStroke = Color.white.opacity(0.16)
    static let tileEmpty = Color.white.opacity(0.07)
    static let tileInputTop = Color(light: 0x26394A, dark: 0x1C2A3E)
    static let tileInputBottom = Color(light: 0x192637, dark: 0x111A2A)
    static let tileLockedTop = Color(light: 0x1C2736, dark: 0x151D2B)
    static let tileLockedBottom = Color(light: 0x111926, dark: 0x0D1420)
    static let keyTop = Color(light: 0x2B3C52, dark: 0x26344B)
    static let keyBottom = Color(light: 0x1B283A, dark: 0x171F31)
    static let ink = Color(light: 0xF3FAFF, dark: 0xF6FBFF)
    static let mutedInk = Color.white.opacity(0.62)
    static let faintInk = Color.white.opacity(0.38)
    static let accent = Color(light: 0x20C8AE, dark: 0x25D8BD)
    static let accentDeep = Color(light: 0x098978, dark: 0x0E9E8B)
    static let present = Color(light: 0xE9B949, dark: 0xF4C95A)
    static let presentDeep = Color(light: 0xB07B13, dark: 0xC4891D)
    static let absent = Color(light: 0x657184, dark: 0x4C586A)
    static let violet = Color(light: 0x8D71F2, dark: 0xA58BFF)

    static var stageGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: stageTop, location: 0),
                .init(color: stageMid, location: 0.56),
                .init(color: stageBottom, location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var boardGradient: LinearGradient {
        LinearGradient(colors: [boardTop, boardBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var inputTileGradient: LinearGradient {
        LinearGradient(colors: [tileInputTop, tileInputBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var lockedTileGradient: LinearGradient {
        LinearGradient(colors: [tileLockedTop, tileLockedBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var keyGradient: LinearGradient {
        LinearGradient(colors: [keyTop, keyBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct MemoryLockSafeAreaBackground: View {
    var body: some View {
        ZStack {
            MemoryLockStyle.stageGradient
            RadialGradient(
                colors: [MemoryLockStyle.accent.opacity(0.30), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 330
            )
            RadialGradient(
                colors: [MemoryLockStyle.violet.opacity(0.24), .clear],
                center: .bottomLeading,
                startRadius: 12,
                endRadius: 360
            )
            Canvas { ctx, size in
                let line = GraphicsContext.Shading.color(.white.opacity(0.055))
                let glow = GraphicsContext.Shading.color(MemoryLockStyle.accent.opacity(0.10))

                for i in 0..<7 {
                    let y = size.height * (0.10 + CGFloat(i) * 0.13)
                    var p = Path()
                    p.move(to: CGPoint(x: -24, y: y))
                    p.addLine(to: CGPoint(x: size.width * 0.22, y: y))
                    p.addLine(to: CGPoint(x: size.width * 0.32, y: y + 28))
                    p.addLine(to: CGPoint(x: size.width + 24, y: y + 28))
                    ctx.stroke(p, with: line, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round, dash: [7, 14]))
                }

                for i in 0..<5 {
                    let x = size.width * (0.14 + CGFloat(i) * 0.19)
                    let rect = CGRect(x: x, y: size.height * 0.18 + CGFloat(i % 2) * 92, width: 7, height: 7)
                    ctx.fill(Path(ellipseIn: rect), with: glow)
                }
            }
            Image(systemName: "lock.fill")
                .font(.system(size: 92, weight: .regular))
                .foregroundStyle(.white.opacity(0.035))
                .rotationEffect(.degrees(-11))
                .offset(x: -132, y: 318)
            Image(systemName: "key.fill")
                .font(.system(size: 78, weight: .regular))
                .foregroundStyle(MemoryLockStyle.present.opacity(0.06))
                .rotationEffect(.degrees(18))
                .offset(x: 142, y: -260)
        }
        .ignoresSafeArea()
    }
}

struct MemoryLockScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    private static let roundsPerRun = 3

    fileprivate enum Mark: Equatable {
        case absent, present, correct
    }

    private struct SubmittedGuess: Identifiable, Equatable {
        let id = UUID()
        let word: String
        let marks: [Mark]
    }

    @State private var target: String
    @State private var current = ""
    @State private var guesses: [SubmittedGuess] = []
    @State private var visibleClueIDs: Set<UUID> = []
    @State private var message = ""
    @State private var roundsPlayed = 0
    @State private var wordsSolved = 0
    @State private var wordsMissed = 0
    @State private var totalGuesses = 0
    @State private var streak = 0
    @State private var bestStreak = 0
    @State private var score = 0
    @State private var solvedWords: [String] = []
    @State private var missedWords: [String] = []
    @State private var locked = false
    @State private var finished = false
    @State private var answerReveal: String?
    @State private var missShakeTrigger = 0

    private let startedAt = Date()
    private let level: Double
    private let wordLength: Int
    private let maxGuesses: Int
    private let clueSeconds: Double

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        let level = cfg.difficulty.level
        self.level = level
        self.wordLength = Self.wordLength(for: level)
        self.maxGuesses = 6
        self.clueSeconds = Self.clueSeconds(for: level)
        _target = State(initialValue: Self.pickWord(length: Self.wordLength(for: level)))
    }

    /// Adaptive challenge: longer words from the middle of the ladder up.
    static func wordLength(for level: Double) -> Int {
        level >= 6 ? 6 : 5
    }

    /// Adaptive challenge: clues stay up ~1.0s at level 1 and fade to ~0.55s
    /// by level 10, so higher levels lean harder on lexical memory.
    static func clueSeconds(for level: Double) -> Double {
        max(0.55, 1.05 - 0.05 * DifficultyState.clamp(level))
    }

    private var progressText: String {
        cfg.isSurvival ? "survival" : "\(roundsPlayed + 1)/\(Self.roundsPerRun)"
    }

    var body: some View {
        GeometryReader { geo in
            let availableHeight = geo.size.height
            let cramped = availableHeight < 620
            let compact = availableHeight < 790
            let topPadding: CGFloat = cfg.isSurvival ? 8 : 6
            let bottomPadding: CGFloat = compact ? 8 : 10
            let boardGap = boardTopGap(compact: compact, cramped: cramped)
            let keyGap = keyboardGap(compact: compact, cramped: cramped)
            let boardHeight = boardHeightBudget(totalHeight: availableHeight,
                                                compact: compact,
                                                cramped: cramped,
                                                topPadding: topPadding,
                                                bottomPadding: bottomPadding,
                                                boardGap: boardGap,
                                                keyboardGap: keyGap)
            ZStack {
                MemoryLockSafeAreaBackground()

                VStack(spacing: 0) {
                    if !cfg.isSurvival {
                        topBar(compact: compact)
                    }

                    wordleGrid(width: geo.size.width - (compact ? 28 : 24),
                               availableHeight: boardHeight,
                               compact: compact,
                               cramped: cramped)
                        .padding(.top, boardGap)
                        .witsShake(trigger: missShakeTrigger, intensity: cramped ? 7 : 11)
                        .overlay(alignment: .top) {
                            statusOverlay(compact: compact)
                        }
                        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: answerReveal)
                        .animation(.easeOut(duration: 0.16), value: message)

                    keyboard(compact: compact, cramped: cramped)
                        .padding(.top, keyGap)
                        .padding(.horizontal, compact ? 8 : 10)
                        .frame(maxWidth: 720)
                }
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    @ViewBuilder
    private func statusOverlay(compact: Bool) -> some View {
        if let answerReveal {
            MemoryLockAnswerReveal(word: answerReveal, compact: compact)
                .offset(y: compact ? -12 : -16)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        } else if !message.isEmpty {
            Text(message)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(MemoryLockStyle.accent, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                .offset(y: compact ? -10 : -12)
                .transition(.opacity)
        }
    }

    private func topBar(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 10) {
            HStack(spacing: compact ? 8 : 10) {
                MemoryLockHudPill(icon: "bolt.fill",
                                  title: "score",
                                  value: "\(score)",
                                  tint: MemoryLockStyle.accent)
                MemoryLockRoundPill(text: progressText)
            }
            ProgressTrack(fraction: Double(roundsPlayed) / Double(Self.roundsPerRun),
                          animated: true,
                          tint: MemoryLockStyle.accent)
                .background(.white.opacity(0.10), in: Capsule())
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.leading, cfg.isSurvival ? 0 : 42)
    }

    private func boardTopGap(compact: Bool, cramped: Bool) -> CGFloat {
        cramped ? 8 : compact ? 14 : 18
    }

    private func keyboardGap(compact: Bool, cramped: Bool) -> CGFloat {
        cramped ? 8 : compact ? 12 : 16
    }

    private func keyboardHeight(compact: Bool, cramped: Bool) -> CGFloat {
        let keyHeight: CGFloat = cramped ? 34 : compact ? 58 : 64
        let rowSpacing: CGFloat = cramped ? 4 : compact ? 6 : 8
        return keyHeight * 3 + rowSpacing * 2
    }

    private func topBarHeight(compact: Bool) -> CGFloat {
        cfg.isSurvival ? 0 : 46 + (compact ? 8 : 10) + 6
    }

    private func boardHeightBudget(totalHeight: CGFloat,
                                   compact: Bool,
                                   cramped: Bool,
                                   topPadding: CGFloat,
                                   bottomPadding: CGFloat,
                                   boardGap: CGFloat,
                                   keyboardGap: CGFloat) -> CGFloat {
        let chrome = topPadding
            + bottomPadding
            + topBarHeight(compact: compact)
            + boardGap
            + keyboardGap
            + keyboardHeight(compact: compact, cramped: cramped)
        return max(cramped ? 240 : 360, totalHeight - chrome)
    }

    private func wordleGrid(width: CGFloat, availableHeight: CGFloat, compact: Bool, cramped: Bool) -> some View {
        let rowSpacing: CGFloat = cramped ? 4 : compact ? 5 : 7
        let cellSpacing: CGFloat = cramped ? 4 : compact ? 5 : 7
        let outerWidth = min(width, 560)
        let horizontalPadding: CGFloat = cramped ? 10 : compact ? 12 : 14
        let verticalPadding: CGFloat = cramped ? 10 : compact ? 12 : 14
        let traceHeight: CGFloat = cramped ? 22 : 28
        let innerGap: CGFloat = cramped ? 7 : 10
        let widthAvailable = outerWidth - horizontalPadding * 2 - CGFloat(wordLength - 1) * cellSpacing
        let heightBudget = availableHeight
        let heightAvailable = heightBudget - traceHeight - innerGap - verticalPadding * 2 - CGFloat(maxGuesses - 1) * rowSpacing
        let minTile: CGFloat = cramped ? 22 : 36
        let maxTile: CGFloat = cramped ? 42 : compact ? 70 : 76
        let tile = min(maxTile,
                       max(minTile, floor(widthAvailable / CGFloat(wordLength))),
                       max(minTile, floor(heightAvailable / CGFloat(maxGuesses))))
        let visibleRows = (0..<maxGuesses).map { showClues(for: $0) }

        return VStack(spacing: innerGap) {
            MemoryLockTraceStrip(guesses: guesses.count,
                                 visibleRows: visibleRows,
                                 maxGuesses: maxGuesses,
                                 compact: compact)
                .frame(height: traceHeight)

            VStack(spacing: rowSpacing) {
                ForEach(0..<maxGuesses, id: \.self) { row in
                    MemoryLockGuessRow(
                        letters: letters(for: row),
                        marks: marks(for: row),
                        showClues: showClues(for: row),
                        length: wordLength,
                        tileSize: tile,
                        spacing: cellSpacing
                    )
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(width: outerWidth, height: availableHeight, alignment: .center)
        .background(MemoryLockStyle.boardGradient, in: RoundedRectangle(cornerRadius: cramped ? 14 : 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cramped ? 14 : 18, style: .continuous)
                .strokeBorder(MemoryLockStyle.boardStroke, lineWidth: 1.2)
        )
        .shadow(color: .black.opacity(0.24), radius: 18, y: 10)
    }

    private func letters(for row: Int) -> [String] {
        if row < guesses.count {
            return Array(guesses[row].word).map(String.init)
        }
        if row == guesses.count {
            return paddedLetters(current)
        }
        return Array(repeating: "", count: wordLength)
    }

    private func marks(for row: Int) -> [Mark]? {
        guard row < guesses.count else { return nil }
        return guesses[row].marks
    }

    private func showClues(for row: Int) -> Bool {
        guard row < guesses.count else { return false }
        return visibleClueIDs.contains(guesses[row].id)
    }

    private func paddedLetters(_ word: String) -> [String] {
        let letters = Array(word).map(String.init)
        return letters + Array(repeating: "", count: max(0, wordLength - letters.count))
    }

    private func keyboard(compact: Bool, cramped: Bool) -> some View {
        let rows = ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]
        return VStack(spacing: cramped ? 4 : compact ? 6 : 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: cramped ? 4 : compact ? 5 : 6) {
                    if row == "ZXCVBNM" {
                        key("enter", width: cramped ? 44 : compact ? 54 : 60, compact: compact, cramped: cramped)
                    }
                    ForEach(Array(row).map(String.init), id: \.self) { letter in
                        key(letter, compact: compact, cramped: cramped)
                    }
                    if row == "ZXCVBNM" {
                        key("delete", width: cramped ? 44 : compact ? 54 : 60, compact: compact, cramped: cramped)
                    }
                }
            }
        }
    }

    private func key(_ value: String, width: CGFloat? = nil, compact: Bool, cramped: Bool) -> some View {
        Button { press(value) } label: {
            Group {
                switch value {
                case "enter":
                    Image(systemName: "arrow.turn.down.left")
                        .font(.system(size: cramped ? 12 : compact ? 14 : 15, weight: .heavy))
                case "delete":
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: cramped ? 12 : compact ? 14 : 15, weight: .heavy))
                default:
                    Text(value)
                        .font(.system(size: cramped ? 13 : compact ? 15 : 16, weight: .heavy, design: .rounded))
                }
            }
            .foregroundStyle(value == "enter" ? Color.white : MemoryLockStyle.ink)
            .frame(width: width)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(height: cramped ? 34 : compact ? 58 : 64)
            .background {
                let shape = RoundedRectangle(cornerRadius: cramped ? 5 : 7, style: .continuous)
                if value == "enter" {
                    shape.fill(MemoryLockStyle.accent)
                } else {
                    shape.fill(MemoryLockStyle.keyGradient)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cramped ? 5 : 7, style: .continuous)
                    .strokeBorder(value == "enter" ? .white.opacity(0.25) : .white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: value == "enter" ? MemoryLockStyle.accent.opacity(0.24) : .black.opacity(0.18),
                    radius: value == "enter" ? 8 : 5,
                    y: 3)
        }
        .buttonStyle(.plain)
        .disabled(locked || finished)
        .accessibilityLabel(value == "delete" ? "delete" : value == "enter" ? "enter" : value)
    }

    private func press(_ value: String) {
        guard !locked, !finished else { return }
        switch value {
        case "enter":
            submit()
        case "delete":
            guard !current.isEmpty else { return }
            current.removeLast()
        default:
            guard current.count < wordLength else { return }
            current.append(value)
        }
    }

    private func submit() {
        guard current.count == wordLength else {
            message = "\(wordLength) letters"
            GameFeel.shared.play(.wrong)
            return
        }

        let guessWord = current.lowercased()
        guard Self.isValidGuess(guessWord, length: wordLength) else {
            message = "not a word"
            GameFeel.shared.play(.wrong)
            return
        }

        let marks = Self.evaluate(guess: guessWord, target: target)
        let guess = SubmittedGuess(word: guessWord.uppercased(), marks: marks)
        guesses.append(guess)
        visibleClueIDs.insert(guess.id)
        current = ""
        message = ""
        totalGuesses += 1

        if guessWord == target {
            solve(guessCount: guesses.count)
            return
        }

        if guesses.count >= maxGuesses {
            miss()
            return
        }

        fade(guess.id)
    }

    private func solve(guessCount: Int) {
        locked = true
        answerReveal = nil
        wordsSolved += 1
        roundsPlayed += 1
        streak += 1
        bestStreak = max(bestStreak, streak)
        solvedWords.append(target)

        let efficiency = max(1, maxGuesses - guessCount + 1)
        let base = cfg.isSurvival ? 140 : 260
        let points = base + efficiency * 60 + min(streak, 5) * 25
        score += points
        message = "unlocked \(target.uppercased())"
        cfg.report(.hit, points: points, combo: streak)
        revealAllClues()
        scheduleNextRound()
    }

    private func miss() {
        locked = true
        wordsMissed += 1
        roundsPlayed += 1
        streak = 0
        missedWords.append(target)
        message = ""
        answerReveal = target.uppercased()
        missShakeTrigger += 1
        cfg.report(.miss)
        revealAllClues()
        scheduleNextRound(after: 1.8)
    }

    private func scheduleNextRound(after delay: Double = 1.05) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if cfg.isSurvival {
                startRound()
            } else if roundsPlayed >= Self.roundsPerRun {
                finish()
            } else {
                startRound()
            }
        }
    }

    private func startRound() {
        target = Self.pickWord(length: wordLength, excluding: Set(solvedWords + missedWords))
        guesses = []
        visibleClueIDs = []
        current = ""
        locked = false
        message = ""
        answerReveal = nil
    }

    private func fade(_ id: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + clueSeconds) {
            guard !locked else { return }
            _ = withAnimation(.easeOut(duration: 0.18)) {
                visibleClueIDs.remove(id)
            }
        }
    }

    private func revealAllClues() {
        visibleClueIDs = Set(guesses.map(\.id))
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        let total = max(1, wordsSolved + wordsMissed)
        let accuracy = Double(wordsSolved) / Double(total)
        var result = GameResult(game: .memoryLock, score: score, accuracy: accuracy)
        result.trials = total
        result.startedAt = startedAt
        result.durationMs = Int(cfg.activeElapsed(since: startedAt) * 1000)
        result.raw = [
            "wordsSolved": Double(wordsSolved),
            "bestStreak": Double(bestStreak),
            "guesses": Double(totalGuesses),
            "wordLength": Double(wordLength),
            "memoryLockLevel": level
        ]
        result.text = [
            "solved": solvedWords,
            "missed": missedWords
        ]
        onResult(result)
    }

    private static func evaluate(guess: String, target: String) -> [Mark] {
        let guessLetters = Array(guess)
        let targetLetters = Array(target)
        var marks = Array(repeating: Mark.absent, count: guessLetters.count)
        var remaining: [Character: Int] = [:]

        for index in targetLetters.indices {
            if guessLetters[index] == targetLetters[index] {
                marks[index] = .correct
            } else {
                remaining[targetLetters[index], default: 0] += 1
            }
        }

        for index in guessLetters.indices where marks[index] != .correct {
            let letter = guessLetters[index]
            if let count = remaining[letter], count > 0 {
                marks[index] = .present
                remaining[letter] = count - 1
            }
        }

        return marks
    }

    private static func isValidGuess(_ word: String, length: Int) -> Bool {
        EnglishWordValidator.isValidWord(word, length: length, acceptedWords: Set(answerPool(length: length)))
    }

    private static func pickWord(length: Int, excluding used: Set<String> = []) -> String {
        let pool = answerPool(length: length)
        let available = pool.filter { !used.contains($0) }
        return (available.isEmpty ? pool : available).randomElement() ?? "crane"
    }

    private static func answerPool(length: Int) -> [String] {
        length == 6 ? sixLetterWords : fiveLetterWords
    }

    private static let fiveLetterWords = [
        "crane", "plant", "stone", "flame", "grace", "trace", "light", "brave", "sharp", "clear",
        "pride", "dream", "grain", "shine", "brisk", "crown", "globe", "river", "field", "sound",
        "spark", "blend", "quest", "charm", "frost", "swing", "vivid", "north", "south", "pilot",
        "march", "lunar", "solid", "fresh", "orbit", "chair", "clock", "paint", "music", "frame",
        "glass", "heart", "mind", "logic", "story", "index", "token", "focus", "solve", "learn",
        "pause", "route", "scale", "shape", "space", "level", "match", "timer", "score", "brain",
        "voice", "scene", "guard", "quiet", "quick", "smart", "clean", "rapid", "angle", "array"
    ]

    private static let sixLetterWords = [
        "planet", "silver", "bridge", "forest", "signal", "bright", "memory", "letter", "method", "puzzle",
        "reason", "search", "stream", "thread", "window", "camera", "circle", "flight", "garden", "little",
        "modern", "phrase", "record", "spring", "travel", "yellow", "button", "charge", "choice", "detail",
        "energy", "future", "growth", "hidden", "impact", "jungle", "kernel", "legend", "motion", "number",
        "object", "prompt", "rhythm", "sample", "target", "unlock", "vision", "wonder", "writer", "zipper"
    ]
}

private struct MemoryLockAnswerReveal: View {
    let word: String
    let compact: Bool

    private var tileSize: CGFloat { compact ? 28 : 34 }
    private var letters: [String] { Array(word.uppercased()).map(String.init) }

    var body: some View {
        VStack(spacing: compact ? 6 : 8) {
            Text("word was")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.66))

            HStack(spacing: 5) {
                ForEach(Array(letters.enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(.system(size: compact ? 16 : 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: tileSize, height: tileSize)
                        .background(.white.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(MemoryLockStyle.accent.opacity(0.46), lineWidth: 1)
                        )
                }
            }
        }
        .padding(.horizontal, compact ? 14 : 16)
        .padding(.vertical, compact ? 10 : 12)
        .background(MemoryLockStyle.boardBottom, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.32), radius: 14, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("word was \(word)")
    }
}

private struct MemoryLockHudPill: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(MemoryLockStyle.faintInk)
                Text(value)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(MemoryLockStyle.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(.white.opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.13), lineWidth: 1))
    }
}

private struct MemoryLockRoundPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(MemoryLockStyle.accent)
            Text(text)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(MemoryLockStyle.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 96)
        .frame(height: 46)
        .background(
            LinearGradient(
                colors: [MemoryLockStyle.violet.opacity(0.28), MemoryLockStyle.accent.opacity(0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule()
        )
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
    }
}

private struct MemoryLockTraceStrip: View {
    let guesses: Int
    let visibleRows: [Bool]
    let maxGuesses: Int
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            Image(systemName: visibleRows.contains(true) ? "lock.open.fill" : "lock.fill")
                .font(.system(size: compact ? 11 : 12, weight: .heavy))
                .foregroundStyle(visibleRows.contains(true) ? MemoryLockStyle.accent : MemoryLockStyle.faintInk)
                .frame(width: compact ? 22 : 26, height: compact ? 22 : 26)
                .background(.white.opacity(0.08), in: Circle())

            HStack(spacing: compact ? 4 : 5) {
                ForEach(0..<maxGuesses, id: \.self) { index in
                    let visible = index < visibleRows.count && visibleRows[index]
                    let submitted = index < guesses
                    Capsule()
                        .fill(visible ? MemoryLockStyle.accent : submitted ? MemoryLockStyle.violet.opacity(0.42) : .white.opacity(0.12))
                        .frame(width: visible ? (compact ? 22 : 28) : (compact ? 13 : 16), height: compact ? 5 : 6)
                        .shadow(color: visible ? MemoryLockStyle.accent.opacity(0.42) : .clear, radius: 5)
                }
            }

            Spacer(minLength: 0)

            Text("\(guesses)/\(maxGuesses)")
                .font(.system(size: compact ? 11 : 12, weight: .heavy, design: .rounded))
                .foregroundStyle(MemoryLockStyle.mutedInk)
                .monospacedDigit()
        }
    }
}

private struct MemoryLockGuessRow: View {
    let letters: [String]
    let marks: [MemoryLockScreen.Mark]?
    let showClues: Bool
    let length: Int
    let tileSize: CGFloat
    let spacing: CGFloat

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<length, id: \.self) { index in
                MemoryLockTile(letter: index < letters.count ? letters[index].uppercased() : "",
                               mark: mark(for: index),
                               showClue: showClues,
                               size: tileSize)
            }
        }
        .animation(.easeOut(duration: 0.18), value: showClues)
    }

    private func mark(for index: Int) -> MemoryLockScreen.Mark? {
        guard let marks, index < marks.count else { return nil }
        return marks[index]
    }
}

private struct MemoryLockTile: View {
    let letter: String
    let mark: MemoryLockScreen.Mark?
    let showClue: Bool
    let size: CGFloat

    private var radius: CGFloat { max(5, min(10, size * 0.14)) }
    private var isSubmitted: Bool { mark != nil }

    var body: some View {
        Text(letter)
            .font(.system(size: max(14, min(28, size * 0.43)), weight: .heavy, design: .rounded))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background { fill }
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(border, lineWidth: showClue ? 1.5 : 1.1)
            )
            .overlay(alignment: .topTrailing) {
                if isSubmitted && !showClue && size >= 34 {
                    Image(systemName: "lock.fill")
                        .font(.system(size: max(7, size * 0.13), weight: .bold))
                        .foregroundStyle(MemoryLockStyle.faintInk)
                        .padding(max(4, size * 0.08))
                }
            }
            .shadow(color: shadow, radius: showClue ? 8 : 3, y: showClue ? 4 : 2)
    }

    private var foreground: Color {
        if showClue { return .white }
        if isSubmitted { return MemoryLockStyle.mutedInk }
        return letter.isEmpty ? .clear : MemoryLockStyle.ink
    }

    @ViewBuilder
    private var fill: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if let mark, showClue {
            switch mark {
            case .correct:
                shape.fill(LinearGradient(colors: [MemoryLockStyle.accent, MemoryLockStyle.accentDeep],
                                          startPoint: .topLeading,
                                          endPoint: .bottomTrailing))
            case .present:
                shape.fill(LinearGradient(colors: [MemoryLockStyle.present, MemoryLockStyle.presentDeep],
                                          startPoint: .topLeading,
                                          endPoint: .bottomTrailing))
            case .absent:
                shape.fill(MemoryLockStyle.absent)
            }
        } else if isSubmitted {
            shape.fill(MemoryLockStyle.lockedTileGradient)
        } else if !letter.isEmpty {
            shape.fill(MemoryLockStyle.inputTileGradient)
        } else {
            shape.fill(MemoryLockStyle.tileEmpty)
        }
    }

    private var border: Color {
        if let mark, showClue {
            switch mark {
            case .correct: return .white.opacity(0.30)
            case .present: return .white.opacity(0.25)
            case .absent: return .white.opacity(0.10)
            }
        }
        if isSubmitted { return MemoryLockStyle.violet.opacity(0.22) }
        return letter.isEmpty ? .white.opacity(0.10) : MemoryLockStyle.accent.opacity(0.36)
    }

    private var shadow: Color {
        guard let mark, showClue else { return .black.opacity(0.18) }
        switch mark {
        case .correct: return MemoryLockStyle.accent.opacity(0.34)
        case .present: return MemoryLockStyle.present.opacity(0.28)
        case .absent: return .black.opacity(0.20)
        }
    }
}
