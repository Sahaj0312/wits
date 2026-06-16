//
//  ComboHUD.swift
//  wits
//
//  The survival top bar: a single chase-able score, a combo flame that escalates
//  with the streak, and three hearts. Also holds the near-miss helpers shared by
//  the spatial games.
//

import SwiftUI

struct ComboHUD: View {
    let score: Int
    var combo: Int = 0
    var multiplier: Int = 1
    var lives: Int? = nil
    var maxLives: Int = 3

    private var comboColor: Color {
        switch combo {
        case ..<3: .witsMuted
        case 3..<6: .witsAccent
        default: .witsWarm
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(score)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.witsInk)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("points")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.witsFaint)
            }

            if combo >= 2 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13, weight: .heavy))
                    Text("×\(multiplier)")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(comboColor)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(comboColor.opacity(0.14), in: Capsule())
                .scaleEffect(1 + min(CGFloat(combo), 20) * 0.012)
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: combo)
            }

            Spacer(minLength: 0)

            if let lives {
                HStack(spacing: 5) {
                    ForEach(0..<maxLives, id: \.self) { i in
                        Image(systemName: i < lives ? "heart.fill" : "heart")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(i < lives ? Color.witsWarm : Color.witsLine)
                    }
                }
            }
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
    }
}

/// Near-miss classification shared by games.
enum NearMiss {
    /// Two cell indices are neighbours in a `cols`-wide grid (incl. diagonals).
    static func adjacent(_ a: Int, _ b: Int, cols: Int) -> Bool {
        guard a != b, cols > 0 else { return false }
        let (ar, ac) = (a / cols, a % cols)
        let (br, bc) = (b / cols, b % cols)
        return abs(ar - br) <= 1 && abs(ac - bc) <= 1
    }

    /// A timed answer counts as a near-miss when it lands in the last `band`
    /// fraction of the response window (default last 15%).
    static func lateAnswer(windowFrac: Double, band: Double = 0.15) -> Bool {
        windowFrac > 0 && windowFrac <= band
    }
}
