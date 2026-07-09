//
//  StreakBadge.swift
//  wits
//
//  The daily-streak flame and the compact pill shown in the home header.
//

import SwiftUI

/// The streak flame: gently pulses while a streak is alive.
struct StreakFlame: View {
    let active: Bool
    @State private var pulsing = false

    var body: some View {
        Image(systemName: "flame.fill")
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(
                active
                    ? AnyShapeStyle(LinearGradient(colors: [.witsGold, .witsWarm],
                                                   startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(Color.witsFaint)
            )
            .scaleEffect(active && pulsing ? 1.16 : 1)
            .shadow(color: active ? Color.witsWarm.opacity(pulsing ? 0.5 : 0.15) : .clear,
                    radius: 6)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}

/// Compact streak pill: flame + current run, styled like a card chip.
struct StreakPill: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            StreakFlame(active: count > 0)
            Text("\(count)")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsInk)
                .monospacedDigit()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(Color.witsCard, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.witsLine, lineWidth: 1))
        .shadow(color: .witsShadow, radius: 8, y: 4)
        .accessibilityLabel("daily streak: \(count)")
    }
}
