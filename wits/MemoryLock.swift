//
//  MemoryLock.swift
//  wits
//
//  Word deduction with fading feedback. Guess the hidden word from Wordle-style
//  clues, but previous row colors disappear, forcing the player to hold the
//  letter evidence in memory.
//

import SwiftUI

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

    /// Adaptive challenge: clues stay up ~1.4s at level 1 and fade in ~0.55s
    /// by level 10, so higher levels lean harder on lexical memory.
    static func clueSeconds(for level: Double) -> Double {
        max(0.55, 1.45 - 0.09 * DifficultyState.clamp(level))
    }

    private var progressText: String {
        cfg.isSurvival ? "survival" : "\(roundsPlayed + 1)/\(Self.roundsPerRun)"
    }

    var body: some View {
        GeometryReader { geo in
            let availableHeight = geo.size.height
            let cramped = availableHeight < 620
            let compact = availableHeight < 790
            VStack(spacing: 0) {
                if !cfg.isSurvival {
                    topBar
                }

                wordleGrid(width: geo.size.width - (compact ? 28 : 24),
                           availableHeight: availableHeight,
                           compact: compact,
                           cramped: cramped)
                    .witsShake(trigger: missShakeTrigger, intensity: cramped ? 7 : 11)
                    .padding(.top, cramped ? 6 : compact ? 22 : 28)
                    .overlay(alignment: .top) {
                        statusOverlay(compact: compact)
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.82), value: answerReveal)
                    .animation(.easeOut(duration: 0.16), value: message)

                Spacer(minLength: 0)

                keyboard(compact: compact, cramped: cramped)
                    .padding(.horizontal, compact ? 8 : 10)
                    .frame(maxWidth: 720)
            }
            .padding(.top, cfg.isSurvival ? 6 : 4)
            .padding(.bottom, compact ? 8 : 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color.witsBg.ignoresSafeArea())
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
                .foregroundStyle(Color.witsInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.witsTint, in: Capsule())
                .offset(y: compact ? -18 : -22)
                .transition(.opacity)
        }
    }

    private var topBar: some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Text("\(score)").foregroundStyle(Color.witsAccent)) pts")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                    .monospacedDigit()
                Spacer()
                Text(progressText)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsMuted)
                    .monospacedDigit()
            }
            ProgressTrack(fraction: Double(roundsPlayed) / Double(Self.roundsPerRun), animated: true)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.leading, cfg.isSurvival ? 0 : 42)
    }

    private func wordleGrid(width: CGFloat, availableHeight: CGFloat, compact: Bool, cramped: Bool) -> some View {
        let rowSpacing: CGFloat = cramped ? 4 : compact ? 5 : 7
        let cellSpacing: CGFloat = cramped ? 4 : compact ? 5 : 7
        let widthAvailable = width - CGFloat(wordLength - 1) * cellSpacing
        let heightBudget = availableHeight * (cramped ? 0.42 : compact ? 0.56 : 0.58)
        let heightAvailable = heightBudget - CGFloat(maxGuesses - 1) * rowSpacing
        let minTile: CGFloat = cramped ? 22 : 36
        let maxTile: CGFloat = cramped ? 42 : compact ? 70 : 76
        let tile = min(maxTile,
                       max(minTile, floor(widthAvailable / CGFloat(wordLength))),
                       max(minTile, floor(heightAvailable / CGFloat(maxGuesses))))
        let height = tile * CGFloat(maxGuesses) + rowSpacing * CGFloat(maxGuesses - 1)

        return VStack(spacing: rowSpacing) {
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
        .frame(maxWidth: .infinity)
        .frame(height: height)
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
                    Text("enter")
                        .font(.system(size: cramped ? 8 : compact ? 10 : 11, weight: .heavy, design: .rounded))
                case "delete":
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: cramped ? 12 : compact ? 14 : 15, weight: .heavy))
                default:
                    Text(value)
                        .font(.system(size: cramped ? 13 : compact ? 15 : 16, weight: .heavy, design: .rounded))
                }
            }
            .foregroundStyle(Color.white)
            .frame(width: width)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(height: cramped ? 34 : compact ? 58 : 64)
            .background(value == "enter" ? Color.witsAccent : Color.witsFaint.opacity(0.58),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(locked || finished)
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
                .foregroundStyle(Color.witsBg.opacity(0.72))

            HStack(spacing: 5) {
                ForEach(Array(letters.enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(.system(size: compact ? 16 : 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsBg)
                        .frame(width: tileSize, height: tileSize)
                        .background(Color.witsBg.opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Color.witsAccent.opacity(0.38), lineWidth: 1)
                        )
                }
            }
        }
        .padding(.horizontal, compact ? 14 : 16)
        .padding(.vertical, compact ? 10 : 12)
        .background(Color.witsInk, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: Color.witsShadow, radius: 14, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("word was \(word)")
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
                Text(index < letters.count ? letters[index].uppercased() : "")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(foreground(for: index))
                    .frame(width: tileSize, height: tileSize)
                    .background(background(for: index),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(border(for: index), lineWidth: 1.5)
                    )
            }
        }
        .animation(.easeOut(duration: 0.18), value: showClues)
    }

    private func foreground(for index: Int) -> Color {
        guard marks != nil, showClues else { return Color.witsInk }
        return .white
    }

    private func background(for index: Int) -> Color {
        guard let marks, index < marks.count else {
            return letters.indices.contains(index) && !letters[index].isEmpty ? Color.witsCard : Color.witsTint
        }
        guard showClues else { return Color.witsCard }
        switch marks[index] {
        case .correct: return Color.witsAccent
        case .present: return Color.witsMustard
        case .absent: return Color.witsFaint.opacity(0.55)
        }
    }

    private func border(for index: Int) -> Color {
        if let marks, showClues, index < marks.count {
            switch marks[index] {
            case .correct: return Color.witsAccent.opacity(0.3)
            case .present: return Color.witsMustard.opacity(0.3)
            case .absent: return Color.clear
            }
        }
        return Color.witsLine
    }
}
