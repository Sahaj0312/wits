//
//  LevelMapView.swift
//  wits
//
//  The star map: a game's pregame surface (design doc §4). Marathon card
//  pinned on top, then paginated pages of 10 level tiles with star grades,
//  locks, and page gates. Replaces the old GameCard detail sheet in the
//  library.
//

import SwiftUI

struct LevelMapView: View {
    let game: GameID
    var onPlayLevel: (Int) -> Void
    var onPlayMarathon: (Int) -> Void   // start level
    var onClose: () -> Void

    private struct SelectedLevel: Identifiable {
        let level: Int
        var id: Int { level }
    }

    @Environment(AppModel.self) private var app
    @State private var page: Int
    @State private var selectedLevel: SelectedLevel?
    @State private var marathonStart: Int

    init(game: GameID,
         onPlayLevel: @escaping (Int) -> Void,
         onPlayMarathon: @escaping (Int) -> Void,
         onClose: @escaping () -> Void) {
        self.game = game
        self.onPlayLevel = onPlayLevel
        self.onPlayMarathon = onPlayMarathon
        self.onClose = onClose
        _page = State(initialValue: 0)
        _marathonStart = State(initialValue: 1)
    }

    private var levelCount: Int { LevelLadder.levelCount(for: game) }
    private var frontier: Int { app.levels.frontier(for: game) }
    private var isMarathonOnly: Bool { game == .split }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    marathonCard
                    if !isMarathonOnly {
                        pageStrip
                        levelGrid
                        gateFooter
                    }
                }
                .padding(.horizontal, WitsMetrics.screenPadding)
                .padding(.top, 6)
                .padding(.bottom, 16)
            }
            if !isMarathonOnly {
                footer
            }
        }
        .background(Color.witsBg.ignoresSafeArea())
        .onAppear {
            page = LevelLadder.page(of: min(frontier, levelCount))
            marathonStart = max(1, frontier - 2)
        }
        .sheet(item: $selectedLevel) { selected in
            LevelDetailCard(
                game: game,
                level: selected.level,
                record: app.levels.record(for: game, level: selected.level),
                unlocked: app.levels.isUnlocked(game, level: selected.level),
                onPlay: {
                    selectedLevel = nil
                    onPlayLevel(selected.level)
                }
            )
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: game.symbol)
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    LinearGradient(colors: [game.domain.color, game.domain.heroTopColor],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: WitsMetrics.chipRadius, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(game.displayName)
                    .font(.witsDisplay(24))
                    .foregroundStyle(Color.witsInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 5) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color.witsWarm)
                    Text("\(app.levels.totalStars(for: game)) / \(levelCount * 3)")
                        .font(.witsLabel(12))
                        .foregroundStyle(Color.witsMuted)
                        .monospacedDigit()
                    Text("·")
                        .foregroundStyle(Color.witsFaint)
                    Text(game.subskill)
                        .font(.witsLabel(12))
                        .foregroundStyle(game.domain.color)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Color.witsMuted)
                    .frame(width: 40, height: 40)
                    .background(Color.witsCard, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("close")
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: Marathon

    private var marathonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("marathon", systemImage: "infinity")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                if let best = app.levels.marathonBest(for: game) {
                    Text("best: level \(best.depth)")
                        .font(.witsLabel(12))
                        .foregroundStyle(.white.opacity(0.85))
                        .monospacedDigit()
                }
            }
            Text(isMarathonOnly
                 ? "one life. how far can you go?"
                 : "no stars, no safety net — climb until you break.")
                .font(.witsBody(13.5))
                .foregroundStyle(.white.opacity(0.8))

            HStack(spacing: 10) {
                if !isMarathonOnly, frontier > 1 {
                    Menu {
                        ForEach(startOptions, id: \.self) { option in
                            Button("start at level \(option)") { marathonStart = option }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text("from level \(marathonStart)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.white.opacity(0.18), in: Capsule())
                    }
                }
                Button {
                    onPlayMarathon(isMarathonOnly ? 1 : marathonStart)
                } label: {
                    Text("run")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(game.domain.color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(PressScale())
            }
        }
        .padding(16)
        .background(
            LinearGradient(colors: [game.domain.color, game.domain.heroTopColor],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    /// Start-level choices: level 1, every 5th passed level, and just below
    /// the frontier (the default).
    private var startOptions: [Int] {
        var options: Set<Int> = [1, max(1, frontier - 2)]
        var l = 5
        while l < frontier {
            options.insert(l)
            l += 5
        }
        return options.sorted()
    }

    // MARK: Pages

    private var pageStrip: some View {
        HStack(spacing: 8) {
            ForEach(0..<LevelLadder.pageCount(for: game), id: \.self) { p in
                let unlocked = app.levels.isPageUnlocked(game, page: p)
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { page = p }
                } label: {
                    HStack(spacing: 4) {
                        if !unlocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9, weight: .heavy))
                        }
                        Text("\(p + 1)")
                            .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(page == p ? .white : unlocked ? Color.witsInk : Color.witsFaint)
                    .frame(minWidth: 40)
                    .padding(.vertical, 8)
                    .background(page == p ? game.domain.color : Color.witsCard, in: Capsule())
                    .overlay(Capsule().strokeBorder(page == p ? .clear : Color.witsLine, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var levelGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
            ForEach(Array(LevelLadder.levels(inPage: page, of: game)), id: \.self) { level in
                LevelTile(
                    level: level,
                    stars: app.levels.stars(for: game, level: level),
                    unlocked: app.levels.isUnlocked(game, level: level),
                    isFrontier: level == frontier,
                    tint: game.domain.color
                ) {
                    if app.levels.isUnlocked(game, level: level) {
                        selectedLevel = SelectedLevel(level: level)
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: page)
    }

    @ViewBuilder
    private var gateFooter: some View {
        if !app.levels.isPageUnlocked(game, page: page) {
            let have = app.levels.starsInPage(game, page: page - 1)
            Label("earn \(LevelLadder.pageGateStars - have) more ★ on page \(page) to unlock",
                  systemImage: "lock.fill")
                .font(.witsLabel(12))
                .foregroundStyle(Color.witsMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.witsTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Cta(title: frontier <= levelCount && app.levels.isUnlocked(game, level: frontier)
                ? "play level \(frontier)"
                : "replay for stars") {
                onPlayLevel(app.levels.workoutLevel(for: game))
            }
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }
}

// MARK: - Tile

private struct LevelTile: View {
    let level: Int
    let stars: Int
    let unlocked: Bool
    let isFrontier: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                if unlocked {
                    Text("\(level)")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(isFrontier ? .white : Color.witsInk)
                        .monospacedDigit()
                    HStack(spacing: 1.5) {
                        ForEach(0..<3, id: \.self) { i in
                            Image(systemName: i < stars ? "star.fill" : "star")
                                .font(.system(size: 7.5, weight: .heavy))
                                .foregroundStyle(i < stars
                                                 ? (isFrontier ? .white : Color.witsWarm)
                                                 : (isFrontier ? .white.opacity(0.45) : Color.witsFaint))
                        }
                    }
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Color.witsFaint)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(isFrontier ? tint : Color.witsCard,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isFrontier ? .clear : Color.witsLine, lineWidth: 1.5)
            )
            .opacity(unlocked ? 1 : 0.55)
        }
        .buttonStyle(PressScale())
        .disabled(!unlocked)
        .accessibilityLabel("level \(level)")
        .accessibilityValue(unlocked ? "\(stars) of 3 stars" : "locked")
    }
}

// MARK: - Level detail card

private struct LevelDetailCard: View {
    let game: GameID
    let level: Int
    let record: LevelRecord?
    let unlocked: Bool
    let onPlay: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("level \(level)")
                .font(.witsDisplay(26))
                .foregroundStyle(Color.witsInk)
                .padding(.top, 18)

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: i < (record?.stars ?? 0) ? "star.fill" : "star")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(i < (record?.stars ?? 0) ? Color.witsWarm : Color.witsFaint)
                }
            }

            VStack(spacing: 4) {
                Text("difficulty \(level) of \(LevelLadder.levelCount(for: game))")
                    .font(.witsBody(14))
                    .foregroundStyle(Color.witsMuted)
                    .monospacedDigit()
                if let record, record.bestQuality > 0 {
                    Text("best run: \(Int((record.bestQuality * 100).rounded()))%")
                        .font(.witsBody(13))
                        .foregroundStyle(Color.witsFaint)
                        .monospacedDigit()
                }
            }

            Cta(title: (record?.stars ?? 0) > 0 ? "replay" : "play", action: onPlay)
                .padding(.horizontal, WitsMetrics.screenPadding)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(Color.witsBg)
    }
}
