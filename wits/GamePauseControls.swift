//
//  GamePauseControls.swift
//  wits
//
//  Shared in-game pause affordances for workout and free-play hosts.
//

import SwiftUI

struct GamePauseButton: View {
    var game: GameID
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "pause.fill")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(game.world.ink)
                .frame(width: 44, height: 44)
                .background(game.world.surface.opacity(0.88), in: Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel("pause game")
    }
}

struct GamePauseButtonLayer: View {
    var game: GameID
    var action: () -> Void

    var body: some View {
        // Sits in the safe-area coordinate space: directly below the status
        // bar, aligned with the leading slot games reserve in their top bars.
        GeometryReader { _ in
            GamePauseButton(game: game, action: action)
                .position(x: 36,
                          y: 26)
        }
    }
}

struct GamePausedOverlay: View {
    var game: GameID
    var controller: GamePauseController
    var quitTitle = "quit game"
    var onQuit: () -> Void
    private var world: GameWorld { game.world }

    var body: some View {
        ZStack {
            // Lighter scrim while counting back in, so the player can read
            // the board they're about to rejoin.
            Color.black.opacity(controller.resumeCountdown == nil ? 0.44 : 0.22)
                .ignoresSafeArea()

            if let count = controller.resumeCountdown {
                Text("\(count)")
                    .font(.system(size: 96, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
                    .id(count)
                    .transition(.scale(scale: 1.5).combined(with: .opacity))
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(world.accent)
                        .frame(width: 62, height: 62)
                        .background(world.accent.opacity(0.14), in: Circle())

                    VStack(spacing: 4) {
                        Text("paused")
                            .font(.system(size: 30, weight: .black, design: world.titleDesign))
                            .foregroundStyle(world.ink)
                        Text(game.worldTitle())
                            .font(.system(size: 14, weight: .bold, design: world.bodyDesign))
                            .foregroundStyle(world.muted)
                    }

                    VStack(spacing: 12) {
                        Button { controller.beginResumeCountdown() } label: {
                            Text("RESUME")
                                .font(.system(size: 16, weight: .black, design: world.titleDesign))
                                .foregroundStyle(world.background)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(world.accent, in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(PressScale())
                        Button(action: onQuit) {
                            Text(quitTitle.uppercased())
                                .font(.system(size: 11.5, weight: .black, design: world.bodyDesign))
                                .foregroundStyle(world.muted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
                .padding(28)
                .frame(maxWidth: 340)
                .background(world.surface, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(world.accent.opacity(0.35), lineWidth: 1))
                .padding(.horizontal, WitsMetrics.screenPadding)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: controller.resumeCountdown)
        .transition(.opacity)
    }
}
