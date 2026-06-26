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
    @State private var message = "use the clues before they fade"
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

    private let startedAt = Date()
    private let level: Double
    private let wordLength: Int
    private let maxGuesses: Int
    private let clueSeconds: Double

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        self.level = cfg.difficulty.level
        self.wordLength = cfg.difficulty.level >= 6 ? 6 : 5
        self.maxGuesses = cfg.difficulty.level >= 6 ? 7 : 6
        self.clueSeconds = max(0.85, 2.45 - cfg.difficulty.level * 0.16)
        _target = State(initialValue: Self.pickWord(length: cfg.difficulty.level >= 6 ? 6 : 5))
    }

    private var progressText: String {
        cfg.isSurvival ? "survival" : "\(roundsPlayed + 1)/\(Self.roundsPerRun)"
    }

    var body: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top
            let safeBottom = geo.safeAreaInsets.bottom
            let availableHeight = geo.size.height - safeTop - safeBottom
            let compact = availableHeight < 790
            let keyboardHeight: CGFloat = compact ? 126 : 140
            let chromeHeight: CGFloat = cfg.isSurvival ? 44 : 92
            let boardMaxHeight = max(300, min(compact ? 370 : 410,
                                               availableHeight - keyboardHeight - chromeHeight))
            VStack(spacing: compact ? 8 : 10) {
                if !cfg.isSurvival {
                    topBar
                }

                roundHeader

                board(width: geo.size.width - WitsMetrics.screenPadding * 2,
                      maxHeight: boardMaxHeight,
                      compact: compact)

                Text(message)
                    .font(.witsBody(13, weight: .semibold))
                    .foregroundStyle(Color.witsMuted)
                    .frame(height: compact ? 14 : 18)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 0)

                keyboard(compact: compact)
            }
            .padding(.horizontal, WitsMetrics.screenPadding)
            .padding(.top, safeTop + (cfg.isSurvival ? 6 : 4))
            .padding(.bottom, safeBottom + (compact ? 4 : 6))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color.witsBg.ignoresSafeArea())
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
        .padding(.leading, cfg.isSurvival ? 0 : 42)
    }

    private var roundHeader: some View {
        HStack(spacing: 8) {
            statusChip(icon: "lock.fill", text: "\(wordLength) letters")
            statusChip(icon: "eye.slash.fill", text: String(format: "%.1fs clues", clueSeconds))
            Spacer(minLength: 6)
            statusChip(icon: "checkmark.seal.fill", text: "\(wordsSolved) solved")
        }
    }

    private func statusChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Color.witsAccent)
            Text(text)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsInk)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.witsTint, in: Capsule())
    }

    private func board(width: CGFloat, maxHeight: CGFloat, compact: Bool) -> some View {
        let outerPadding: CGFloat = compact ? 10 : 12
        let rowSpacing: CGFloat = compact ? 5 : 6
        let cellSpacing: CGFloat = compact ? 5 : 6
        let widthAvailable = width - outerPadding * 2 - CGFloat(wordLength - 1) * cellSpacing
        let heightAvailable = maxHeight - outerPadding * 2 - CGFloat(maxGuesses - 1) * rowSpacing
        let maxTile: CGFloat = compact ? 52 : 56
        let tile = min(maxTile,
                       max(36, floor(widthAvailable / CGFloat(wordLength))),
                       max(36, floor(heightAvailable / CGFloat(maxGuesses))))
        let height = tile * CGFloat(maxGuesses) + rowSpacing * CGFloat(maxGuesses - 1) + outerPadding * 2

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
        .padding(outerPadding)
        .background(Color.witsTint, in: RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous))
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

    private func keyboard(compact: Bool) -> some View {
        let rows = ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]
        return VStack(spacing: compact ? 5 : 6) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: compact ? 4 : 5) {
                    if row == "ZXCVBNM" {
                        key("enter", width: compact ? 46 : 50, compact: compact)
                    }
                    ForEach(Array(row).map(String.init), id: \.self) { letter in
                        key(letter, compact: compact)
                    }
                    if row == "ZXCVBNM" {
                        key("delete", width: compact ? 46 : 50, compact: compact)
                    }
                }
            }
        }
    }

    private func key(_ value: String, width: CGFloat? = nil, compact: Bool) -> some View {
        Button { press(value) } label: {
            Group {
                switch value {
                case "enter":
                    Image(systemName: "checkmark")
                        .font(.system(size: compact ? 14 : 15, weight: .heavy))
                case "delete":
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: compact ? 14 : 15, weight: .heavy))
                default:
                    Text(value)
                        .font(.system(size: compact ? 15 : 16, weight: .heavy, design: .rounded))
                }
            }
            .foregroundStyle(value == "enter" ? .white : Color.witsInk)
            .frame(width: width)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(height: compact ? 40 : 44)
            .background(value == "enter" ? Color.witsAccent : Color.witsTint,
                        in: RoundedRectangle(cornerRadius: compact ? 9 : 10, style: .continuous))
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
        let marks = Self.evaluate(guess: guessWord, target: target)
        let guess = SubmittedGuess(word: guessWord.uppercased(), marks: marks)
        guesses.append(guess)
        visibleClueIDs.insert(guess.id)
        current = ""
        totalGuesses += 1

        if guessWord == target {
            solve(guessCount: guesses.count)
            return
        }

        if guesses.count >= maxGuesses {
            miss()
            return
        }

        message = String(format: "clues fade in %.1fs", clueSeconds)
        fade(guess.id)
    }

    private func solve(guessCount: Int) {
        locked = true
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
        message = "word was \(target.uppercased())"
        cfg.report(.miss)
        revealAllClues()
        scheduleNextRound()
    }

    private func scheduleNextRound() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
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
        message = "use the clues before they fade"
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
        result.durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        result.raw = [
            "wordsSolved": Double(wordsSolved),
            "bestStreak": Double(bestStreak),
            "guesses": Double(totalGuesses),
            "wordLength": Double(wordLength)
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

    private static func pickWord(length: Int, excluding used: Set<String> = []) -> String {
        let pool = length == 6 ? sixLetterWords : fiveLetterWords
        let available = pool.filter { !used.contains($0) }
        return (available.isEmpty ? pool : available).randomElement() ?? "crane"
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
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
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
        case .present: return Color.witsWarm
        case .absent: return Color.witsFaint.opacity(0.55)
        }
    }

    private func border(for index: Int) -> Color {
        if let marks, showClues, index < marks.count {
            switch marks[index] {
            case .correct: return Color.witsAccent.opacity(0.3)
            case .present: return Color.witsWarm.opacity(0.3)
            case .absent: return Color.clear
            }
        }
        return Color.witsLine
    }
}
