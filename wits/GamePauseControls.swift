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
        GeometryReader { _ in
            GamePauseButton(action: action)
                .position(x: 24,
                          y: 56)
        }
    }
}

struct GamePausedOverlay: View {
    var game: GameID?
    var quitTitle = "quit game"
    var onResume: () -> Void
    var onQuit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.44)
                .ignoresSafeArea()

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
                    Cta(title: "resume", action: onResume)
                    QuietButton(title: quitTitle, action: onQuit)
                }
                .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: 340)
            .cardSurface()
            .padding(.horizontal, WitsMetrics.screenPadding)
        }
        .transition(.opacity)
    }
}
