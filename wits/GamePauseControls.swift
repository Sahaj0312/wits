//
//  GamePauseControls.swift
//  wits
//
//  Shared in-game pause affordances for workout and free-play hosts.
//

import SwiftUI

struct GamePauseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "pause.fill")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Color.witsInk)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel("pause game")
    }
}

struct GamePauseButtonLayer: View {
    var action: () -> Void

    var body: some View {
        // Sits in the safe-area coordinate space: directly below the status
        // bar, aligned with the leading slot games reserve in their top bars.
        GeometryReader { _ in
            GamePauseButton(action: action)
                .position(x: 36,
                          y: 26)
        }
    }
}

struct GamePausedOverlay: View {
    var game: GameID?
    var controller: GamePauseController
    var quitTitle = "quit game"
    var onQuit: () -> Void

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
                        .foregroundStyle(Color.witsAccent)
                        .frame(width: 62, height: 62)
                        .background(Color.witsAccent.opacity(0.14), in: Circle())

                    VStack(spacing: 4) {
                        Text("paused")
                            .font(.witsDisplay(30))
                            .foregroundStyle(Color.witsInk)
                        if let game {
                            Text(game.displayName)
                                .font(.witsBody(15, weight: .semibold))
                                .foregroundStyle(Color.witsMuted)
                        }
                    }

                    VStack(spacing: 12) {
                        Cta(title: "resume", action: { controller.beginResumeCountdown() })
                        QuietButton(title: quitTitle, action: onQuit)
                    }
                    .padding(.top, 4)
                }
                .padding(28)
                .frame(maxWidth: 340)
                .cardSurface()
                .padding(.horizontal, WitsMetrics.screenPadding)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: controller.resumeCountdown)
        .transition(.opacity)
    }
}
