//
//  LevelResultView.swift
//  wits
//
//  Result surface for one difficulty-track level.
//

import SwiftUI

struct DifficultyLevelResultView: View {
    let game: GameID
    let difficulty: ChallengeDifficulty
    let level: Int
    let stars: Int
    let quality: Double
    let improved: Bool
    let onRetry: () -> Void
    let onNext: () -> Void
    let onSelector: () -> Void

    private var passed: Bool { stars >= 1 }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: difficulty.symbol)
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(.black.opacity(0.8))
                .frame(width: 76, height: 76)
                .background(difficulty.color, in: Circle())
                .rise()

            Text(difficulty.title)
                .font(.witsLabel(13))
                .foregroundStyle(difficulty.color)
                .padding(.top, 14)
                .rise(0.04)

            Text(passed ? "level \(level) cleared" : "level \(level)")
                .font(.witsDisplay(32))
                .foregroundStyle(Color.witsInk)
                .multilineTextAlignment(.center)
                .padding(.top, 5)
                .rise(0.08)

            Text(headline)
                .font(.witsBody(15.5))
                .foregroundStyle(Color.witsMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .rise(0.12)

            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: index < stars ? "star.fill" : "star")
                        .font(.system(size: 42, weight: .heavy))
                        .foregroundStyle(index < stars ? Color.witsWarm : Color.witsFaint)
                        .rise(0.16 + Double(index) * 0.08)
                }
            }
            .padding(.top, 24)

            Text("\(Int((quality * 100).rounded()))%")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsMuted)
                .monospacedDigit()
                .padding(.top, 13)
                .rise(0.32)

            Spacer()

            VStack(spacing: 11) {
                if passed {
                    Button(action: onNext) {
                        Label("level \(level + 1)", systemImage: "arrow.right")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(difficulty.color,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(PressScale())
                }

                Button(action: onRetry) {
                    Text(passed ? "replay level" : "try again")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.witsInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.witsCard,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.witsLine, lineWidth: 1.5)
                        )
                }
                .buttonStyle(PressScale())

                Button(action: onSelector) {
                    Text("change difficulty")
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.witsMuted)
                }
                .buttonStyle(.plain)
                .padding(.top, 3)
            }
            .rise(0.38)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.witsBg.ignoresSafeArea())
        .overlay {
            if improved && passed {
                ConfettiBurst().ignoresSafeArea()
            }
        }
    }

    private var headline: String {
        switch (passed, stars, improved) {
        case (false, _, _): "not this time. try the same level again."
        case (true, 3, true): "perfect run. the next level is ready."
        case (true, _, true): "new best. the next level is ready."
        case (true, 3, false): "still perfect."
        default: "cleared. keep this track moving."
        }
    }
}
