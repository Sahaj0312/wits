//
//  CrosswordScreen.swift
//  wits
//
//  The playable mini-crossword screen. Tap a square to aim, tap it again to
//  flip between across and down, and type on the built-in letter keyboard;
//  the clue bar walks the words in order. Reveal fills the selected square as
//  an escape hatch, but clean solves grade higher. The board is generated
//  behind a spinner (Crossword.swift) and the clock starts once it's up.
//

import SwiftUI

struct CrosswordScreen: View {
    var cfg: GameConfig
    var onResult: (GameResult) -> Void

    @State private var puzzle: CrosswordPuzzle?
    @State private var entries: [[String]] = []
    @State private var selected = CrosswordCellPos(r: 0, c: 0)
    @State private var acrossMode = true
    @State private var elapsed = 0.0
    @State private var timerStartedAt = Date()
    @State private var hints = 0
    @State private var wrongChecks = 0
    @State private var finished = false
    @State private var hint = ""
    @State private var shakeBoard = 0

    private let startedAt = Date()
    private let level: Double
    private let mapLevel: Int
    private var world: GameWorld { GameID.crossword.world }

    init(cfg: GameConfig, onResult: @escaping (GameResult) -> Void) {
        self.cfg = cfg
        self.onResult = onResult
        self.level = cfg.difficulty.level
        self.mapLevel = cfg.mapLevel ?? DifficultyScale.contentLevel(for: .crossword,
                                                                     legacyDifficulty: cfg.difficulty.level)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                GameStageBackground(game: .crossword)
                if let puzzle {
                    VStack(spacing: 0) {
                        topBar
                            .padding(.top, 8)
                            .padding(.horizontal, WitsMetrics.screenPadding)

                        Spacer(minLength: 10)

                        gridView(puzzle, in: geo.size)
                            .modifier(ShakeEffect(shakes: CGFloat(shakeBoard)))
                            .animation(.linear(duration: 0.3), value: shakeBoard)

                        Text(hint)
                            .font(.system(size: 13, weight: .bold, design: world.bodyDesign))
                            .foregroundStyle(world.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(height: 24)
                            .padding(.top, 2)

                        Spacer(minLength: 8)

                        clueBar(puzzle)
                            .padding(.horizontal, WitsMetrics.screenPadding)

                        keyboard
                            .padding(.horizontal, 6)
                            .padding(.top, 10)
                            .padding(.bottom, 10)
                    }
                } else {
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(world.ink)
                        Text("setting the grid…")
                            .font(.system(size: 14, weight: .semibold, design: world.bodyDesign))
                            .foregroundStyle(world.muted)
                    }
                }
            }
        }
        .task { await setUpAndRun() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Crossword")
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 6) {
            // clears the pause button the host overlays at top-leading
            Spacer()
                .frame(width: 38)

            HStack(spacing: 10) {
                Text(Self.clock(elapsed))
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Spacer(minLength: 0)
                Text(hints > 0 ? "reveals \(hints)" : "no reveals")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(world.ink)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(world.ink.opacity(0.07), in: Capsule())

            Button {
                reveal()
            } label: {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(world.ink)
                    .frame(width: 42, height: 42)
                    .background(world.ink.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(finished)
            .accessibilityLabel("Reveal the selected square")

            Button {
                showHelp()
            } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(world.ink)
                    .frame(width: 42, height: 42)
                    .background(world.ink.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show rule reminder")
        }
    }

    // MARK: Grid

    private func gridView(_ puzzle: CrosswordPuzzle, in size: CGSize) -> some View {
        let side = min(size.width - WitsMetrics.screenPadding * 2, 390)
        let cell = side / CGFloat(puzzle.size)
        let wordCells = Set(currentWord(puzzle)?.cells ?? [])

        return VStack(spacing: 0) {
            ForEach(0..<puzzle.size, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<puzzle.size, id: \.self) { c in
                        cellView(puzzle, r: r, c: c,
                                 cell: cell,
                                 inWord: wordCells.contains(CrosswordCellPos(r: r, c: c)))
                    }
                }
            }
        }
        .background(world.ink)
        .overlay(Rectangle().strokeBorder(world.ink, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: world.ink.opacity(0.14), radius: 10, y: 5)
        .frame(width: side, height: side)
    }

    @ViewBuilder
    private func cellView(_ puzzle: CrosswordPuzzle, r: Int, c: Int, cell: CGFloat, inWord: Bool) -> some View {
        let pos = CrosswordCellPos(r: r, c: c)
        if puzzle.isBlock[r][c] {
            Rectangle()
                .fill(world.ink)
                .frame(width: cell, height: cell)
        } else {
            let isSelected = pos == selected
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(isSelected ? world.accent.opacity(0.45)
                          : (inWord ? world.accent.opacity(0.16) : world.surface))
                Rectangle()
                    .strokeBorder(world.ink.opacity(0.25), lineWidth: 0.5)
                if puzzle.numbers[r][c] > 0 {
                    Text("\(puzzle.numbers[r][c])")
                        .font(.system(size: cell * 0.2, weight: .bold, design: world.bodyDesign))
                        .foregroundStyle(world.ink.opacity(0.6))
                        .padding(.top, 1.5)
                        .padding(.leading, 3)
                }
                Text(entries[r][c])
                    .font(.system(size: cell * 0.52, weight: .heavy, design: world.titleDesign))
                    .foregroundStyle(world.ink)
                    .frame(width: cell, height: cell)
                    .offset(y: cell * 0.04)
            }
            .frame(width: cell, height: cell)
            .contentShape(Rectangle())
            .onTapGesture { tap(pos) }
            .accessibilityLabel("Row \(r + 1) column \(c + 1), \(entries[r][c].isEmpty ? "empty" : entries[r][c])")
        }
    }

    // MARK: Clue bar

    private func clueBar(_ puzzle: CrosswordPuzzle) -> some View {
        let word = currentWord(puzzle)
        return HStack(spacing: 8) {
            Button { step(puzzle, by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(world.ink)
                    .frame(width: 40, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous clue")

            VStack(spacing: 2) {
                Text(word?.label ?? "")
                    .font(.system(size: 10.5, weight: .black, design: world.bodyDesign))
                    .foregroundStyle(world.accent)
                Text(word?.clue ?? "")
                    .font(.system(size: 15, weight: .bold, design: world.bodyDesign))
                    .foregroundStyle(world.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity)

            Button { step(puzzle, by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(world.ink)
                    .frame(width: 40, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next clue")
        }
        .frame(height: 58)
        .background(world.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // MARK: Keyboard

    private var keyboard: some View {
        let rows = ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]
        return GeometryReader { geo in
            let keyWidth = (geo.size.width - 9 * 4) / 10
            VStack(spacing: 7) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 4) {
                        if row.count == 7 {
                            ForEach(Array(row), id: \.self) { letter in
                                key(String(letter), width: keyWidth)
                            }
                            backspaceKey(width: keyWidth * 1.6)
                        } else {
                            ForEach(Array(row), id: \.self) { letter in
                                key(String(letter), width: keyWidth)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: 3 * 46 + 2 * 7)
        .frame(maxWidth: 520)
    }

    private func key(_ letter: String, width: CGFloat) -> some View {
        Button {
            type(letter)
        } label: {
            Text(letter)
                .font(.system(size: 19, weight: .bold, design: world.bodyDesign))
                .foregroundStyle(world.ink)
                .frame(width: width, height: 46)
                .background(world.surface, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(world.ink.opacity(0.16), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(finished)
    }

    private func backspaceKey(width: CGFloat) -> some View {
        Button {
            backspace()
        } label: {
            Image(systemName: "delete.left.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(world.ink)
                .frame(width: width, height: 46)
                .background(world.raised, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(world.ink.opacity(0.16), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(finished)
        .accessibilityLabel("Delete")
    }

    // MARK: Word navigation

    /// The word containing the selection in the active direction, falling
    /// back to the crossing word when the selection only runs the other way.
    private func currentWord(_ puzzle: CrosswordPuzzle) -> CrosswordWord? {
        let here = puzzle.words.filter { $0.cells.contains(selected) }
        return here.first { $0.isAcross == acrossMode } ?? here.first
    }

    private func step(_ puzzle: CrosswordPuzzle, by delta: Int) {
        guard let word = currentWord(puzzle),
              let index = puzzle.words.firstIndex(where: { $0.id == word.id }) else { return }
        let next = puzzle.words[(index + delta + puzzle.words.count) % puzzle.words.count]
        acrossMode = next.isAcross
        selected = next.cells.first { entries[$0.r][$0.c].isEmpty } ?? next.cells[0]
    }

    private func tap(_ pos: CrosswordCellPos) {
        guard !finished else { return }
        if pos == selected {
            acrossMode.toggle()
        } else {
            selected = pos
        }
        // If no word runs the active way through this cell, flip to the one
        // that does.
        if let puzzle, !puzzle.words.contains(where: { $0.isAcross == acrossMode && $0.cells.contains(selected) }) {
            acrossMode.toggle()
        }
    }

    // MARK: Input

    private func type(_ letter: String) {
        guard let puzzle, !finished else { return }
        entries[selected.r][selected.c] = letter
        GameFeel.shared.play(.correct(combo: 1))
        advance(puzzle)
        checkCompletion(puzzle)
    }

    private func advance(_ puzzle: CrosswordPuzzle) {
        guard let word = currentWord(puzzle),
              let at = word.cells.firstIndex(of: selected) else { return }
        // Next empty square after the cursor in this word, then the next
        // word's first empty square.
        if let nextEmpty = word.cells.dropFirst(at + 1).first(where: { entries[$0.r][$0.c].isEmpty }) {
            selected = nextEmpty
            return
        }
        if at + 1 < word.cells.count {
            selected = word.cells[at + 1]
            return
        }
        step(puzzle, by: 1)
    }

    private func backspace() {
        guard let puzzle, !finished else { return }
        if !entries[selected.r][selected.c].isEmpty {
            entries[selected.r][selected.c] = ""
            return
        }
        guard let word = currentWord(puzzle),
              let at = word.cells.firstIndex(of: selected), at > 0 else { return }
        selected = word.cells[at - 1]
        entries[selected.r][selected.c] = ""
    }

    private func reveal() {
        guard let puzzle, !finished, !puzzle.isBlock[selected.r][selected.c] else { return }
        if entries[selected.r][selected.c] == puzzle.solution[selected.r][selected.c] {
            advance(puzzle)
            return
        }
        hints += 1
        entries[selected.r][selected.c] = puzzle.solution[selected.r][selected.c]
        GameFeel.shared.play(.nearMiss)
        advance(puzzle)
        checkCompletion(puzzle)
    }

    // MARK: Flow

    private func setUpAndRun() async {
        if puzzle == nil {
            let target = mapLevel
            let seed = cfg.resolvedRandomSeed()
            let generated = await Task.detached(priority: .userInitiated) {
                CrosswordEngine.generate(mapLevel: target, seed: seed)
            }.value
            puzzle = generated
            entries = Array(repeating: Array(repeating: "", count: generated.size),
                            count: generated.size)
            // Start on 1-Across.
            if let first = generated.words.first {
                selected = first.cells[0]
                acrossMode = first.isAcross
            }
            timerStartedAt = Date()
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            guard !finished else { return }
            elapsed = cfg.activeElapsed(since: timerStartedAt)
        }
    }

    private func checkCompletion(_ puzzle: CrosswordPuzzle) {
        for r in 0..<puzzle.size {
            for c in 0..<puzzle.size where !puzzle.isBlock[r][c] {
                if entries[r][c].isEmpty { return }
            }
        }
        if gridMatches(puzzle) {
            finished = true
            hint = ""
            GameFeel.shared.play(.newBest)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                finish(puzzle)
            }
        } else {
            wrongChecks += 1
            shakeBoard += 1
            hint = "the grid is full, but something's off"
            GameFeel.shared.play(.wrong)
        }
    }

    private func gridMatches(_ puzzle: CrosswordPuzzle) -> Bool {
        for r in 0..<puzzle.size {
            for c in 0..<puzzle.size where !puzzle.isBlock[r][c] {
                if entries[r][c] != puzzle.solution[r][c] { return false }
            }
        }
        return true
    }

    private func finish(_ puzzle: CrosswordPuzzle) {
        let seconds = max(1, elapsed)
        let openCells = (0..<puzzle.size).flatMap { r in
            (0..<puzzle.size).filter { !puzzle.isBlock[r][$0] }
        }.count
        // Clean solving dominates: every reveal spends a chunk, every full-but
        // -wrong check a smaller one. Time keeps a minor weight so deliberate
        // solving still grades well.
        let cleanness = max(0, 1 - Double(hints) * 0.12 - Double(wrongChecks) * 0.08)
        let timeEfficiency = min(1, puzzle.parSeconds / seconds)
        let accuracy = max(0, min(1, 0.30 + cleanness * 0.60 + timeEfficiency * 0.10))
        let score = max(0, Int((Double(puzzle.words.count) * 80 + cleanness * 1200 + timeEfficiency * 400).rounded()))

        var result = GameResult(game: .crossword, score: score, accuracy: accuracy)
        result.trials = puzzle.words.count
        result.startedAt = startedAt
        result.durationMs = Int(seconds * 1000)
        result.raw = [
            "efficiency": (cleanness * 100).rounded(),
            "correct": Double(puzzle.words.count),
            "words": Double(puzzle.words.count),
            "cells": Double(openCells),
            "reveals": Double(hints),
            "wrongChecks": Double(wrongChecks),
            "seconds": seconds.rounded(),
            "parSeconds": puzzle.parSeconds.rounded(),
            "crosswordLevel": level
        ]
        onResult(result)
    }

    private func showHelp() {
        hint = "tap a square to aim, tap again to flip across/down"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if !finished { hint = "" }
        }
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// Small horizontal shake used when a full grid doesn't check out.
private struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(shakes * .pi * 4) * 5, y: 0))
    }
}
