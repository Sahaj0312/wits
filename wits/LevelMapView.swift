//
//  LevelMapView.swift
//  wits
//
//  Pre-game difficulty selector. Each difficulty owns an independent,
//  unbounded level track.
//

import SwiftUI

struct DifficultySelectView: View {
    let game: GameID
    var onPlay: (ChallengeDifficulty, Int) -> Void
    var onClose: () -> Void

    @Environment(AppModel.self) private var app
    @State private var difficulty: ChallengeDifficulty = .easy
    @State private var showHelp = false

    private var level: Int {
        app.levels.currentLevel(for: game, difficulty: difficulty)
    }

    var body: some View {
        GeometryReader { proxy in
            let heroHeight = min(350, max(285, proxy.size.height * 0.37))
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    hero
                        .frame(height: heroHeight)

                    selector
                        .frame(minHeight: max(430, proxy.size.height - heroHeight))
                }
                .frame(minHeight: proxy.size.height)
            }
            .background(Color.witsBg)
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            difficulty = app.levels.selectedDifficulty(for: game)
        }
        .onChange(of: difficulty) { _, value in
            app.levels.select(value, for: game)
        }
        .sheet(isPresented: $showHelp) {
            GameHelpSheet(game: game)
        }
    }

    private var hero: some View {
        ZStack {
            game.posterBackground
            GamePosterArt(game: game)
                .scaleEffect(1.22)
                .opacity(0.62)
            Color.black.opacity(0.24)

            VStack(spacing: 0) {
                HStack {
                    circleButton(symbol: "chevron.left", label: "Close", action: onClose)
                    Spacer()
                    circleButton(symbol: "questionmark", label: "How to play") {
                        showHelp = true
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                Spacer(minLength: 12)

                Text(game.displayName.uppercased())
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                Text(game.cardHow)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.94))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.82)
                    .padding(.horizontal, 34)
                    .padding(.top, 12)

                Spacer(minLength: 28)
            }
        }
        .clipped()
    }

    private var selector: some View {
        VStack(spacing: 0) {
            DifficultyFace(difficulty: difficulty)
                .padding(.top, 22)

            Text(difficulty.title.uppercased())
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(difficulty.color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.top, 16)

            DifficultySlider(selection: $difficulty)
                .padding(.horizontal, 28)
                .padding(.top, 18)

            HStack(spacing: 0) {
                ForEach(ChallengeDifficulty.allCases) { option in
                    Text(option.shortTitle)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(option == difficulty ? option.color : Color.witsFaint)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 2)

            Spacer(minLength: 28)

            Button {
                onPlay(difficulty, level)
            } label: {
                VStack(spacing: 1) {
                    Text("PLAY")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                    Text("Level \(level)")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 78)
                .background(difficulty.color,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: difficulty.color.opacity(0.28), radius: 10, y: 6)
            }
            .buttonStyle(PressScale())
            .padding(.horizontal, 42)

            Spacer(minLength: 26)
        }
        .background(Color.witsBg)
    }

    private func circleButton(symbol: String,
                              label: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Color.black.opacity(0.64), in: Circle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(label)
    }
}

private struct DifficultyFace: View {
    let difficulty: ChallengeDifficulty

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hexAny: 0x3A3A3D))
            Circle()
                .fill(.black)
                .padding(10)
            Circle()
                .fill(difficulty.color)
                .padding(22)
            Image(systemName: difficulty.symbol)
                .font(.system(size: 39, weight: .black))
                .foregroundStyle(.black.opacity(0.88))
        }
        .frame(width: 116, height: 116)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: difficulty)
        .accessibilityHidden(true)
    }
}

private struct DifficultySlider: View {
    @Binding var selection: ChallengeDifficulty

    var body: some View {
        GeometryReader { proxy in
            let thumb: CGFloat = 58
            let inset = thumb / 2
            let usable = max(1, proxy.size.width - thumb)
            let step = usable / CGFloat(max(1, ChallengeDifficulty.allCases.count - 1))
            let x = inset + CGFloat(selection.ordinal) * step

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(hexAny: 0x3A3A3D))
                    .frame(height: 30)

                Capsule()
                    .fill(
                        LinearGradient(colors: ChallengeDifficulty.allCases.map(\.color),
                                       startPoint: .leading,
                                       endPoint: .trailing)
                    )
                    .frame(height: 18)
                    .padding(.horizontal, 6)

                ForEach(ChallengeDifficulty.allCases) { option in
                    Circle()
                        .fill(.white.opacity(option == selection ? 0 : 0.72))
                        .frame(width: 5, height: 5)
                        .position(x: inset + CGFloat(option.ordinal) * step,
                                  y: proxy.size.height / 2)
                }

                Circle()
                    .fill(.white)
                    .frame(width: thumb, height: thumb)
                    .overlay(Circle().fill(selection.color).padding(15))
                    .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
                    .position(x: x, y: proxy.size.height / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let raw = (gesture.location.x - inset) / usable
                        let ordinal = Int((raw * CGFloat(ChallengeDifficulty.allCases.count - 1)).rounded())
                        let clamped = min(ChallengeDifficulty.allCases.count - 1, max(0, ordinal))
                        if let next = ChallengeDifficulty(ordinal: clamped), next != selection {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                                selection = next
                            }
                        }
                    }
            )
        }
        .frame(height: 68)
        .accessibilityElement()
        .accessibilityLabel("Difficulty")
        .accessibilityValue(selection.title)
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? 1 : -1
            let ordinal = min(ChallengeDifficulty.allCases.count - 1,
                              max(0, selection.ordinal + delta))
            if let next = ChallengeDifficulty(ordinal: ordinal) { selection = next }
        }
    }
}

private struct GameHelpSheet: View {
    let game: GameID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: game.symbol)
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(game.domain.color,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(game.displayName)
                    .font(.witsDisplay(26))
                    .foregroundStyle(Color.witsInk)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Color.witsMuted)
                        .frame(width: 40, height: 40)
                        .background(Color.witsCard, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            Text(game.cardHow)
                .font(.witsBody(15.5, weight: .semibold))
                .foregroundStyle(Color.witsInk)

            Text(game.cardAbout)
                .font(.witsBody(14.5))
                .foregroundStyle(Color.witsMuted)

            Spacer(minLength: 0)
        }
        .padding(22)
        .background(Color.witsBg.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
