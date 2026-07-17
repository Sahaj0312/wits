//
//  Celebration.swift
//  wits
//
//  The moment-of-completion toolkit: score count-up with haptic ticks and a
//  one-shot confetti burst. Used by the result screens so finishing a run
//  feels like an event, not a receipt.
//

import SwiftUI

// MARK: - Count-up score

/// Rolls a number up from 0 with an ease-out curve, ticking haptics along the
/// way and landing with a success notification.
struct CountUpText: View {
    let value: Int
    var duration: Double = 1.0
    var font: Font = .system(size: 64, weight: .heavy, design: .rounded)
    var color: Color = .witsInk
    var haptics = true

    @State private var shown = 0

    var body: some View {
        Text("\(shown)")
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(shown)))
            .task(id: value) {
                guard value > 0 else { shown = value; return }
                let start = Date()
                var lastTickDecile = 0
                while !Task.isCancelled {
                    let p = min(1, Date().timeIntervalSince(start) / duration)
                    let eased = 1 - pow(1 - p, 3)
                    shown = Int(Double(value) * eased)
                    let decile = Int(eased * 8)
                    if haptics, decile > lastTickDecile {
                        lastTickDecile = decile
                        GameFeel.shared.uiTick()
                    }
                    if p >= 1 { break }
                    try? await Task.sleep(nanoseconds: 22_000_000)
                }
                shown = value
                if haptics { GameFeel.shared.uiTick(1) }
            }
    }
}

// MARK: - Confetti

/// One-shot confetti burst rendered in Canvas, deterministic particles, no
/// state churn, removes itself from the render loop when finished.
struct ConfettiBurst: View {
    var colors: [Color] = [.witsAccent, .witsGold, .witsViolet, .witsPink, .witsSky, .witsWarm]
    var particleCount = 110
    var duration: Double = 3.0

    @State private var startDate: Date?

    private struct Particle {
        let angle: Double       // launch direction (radians)
        let speed: Double       // points/sec
        let size: CGFloat
        let colorIndex: Int
        let spin: Double        // radians/sec
        let drift: Double       // horizontal wobble
        let delay: Double
    }

    private var particles: [Particle] {
        var seed: UInt64 = 0x5DEECE66D
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) % 10_000) / 10_000
        }
        return (0..<particleCount).map { _ in
            Particle(
                angle: (-95 + rnd() * 100 - 50) * .pi / 180,   // mostly upward fan
                speed: 380 + rnd() * 520,
                size: 5 + rnd() * 6,
                colorIndex: Int(rnd() * 100) % colors.count,
                spin: (rnd() - 0.5) * 14,
                drift: (rnd() - 0.5) * 90,
                delay: rnd() * 0.12
            )
        }
    }

    private var isFinished: Bool {
        guard let startDate else { return false }
        return Date().timeIntervalSince(startDate) > duration + 0.3
    }

    var body: some View {
        TimelineView(.animation(paused: isFinished)) { timeline in
            Canvas { ctx, size in
                draw(in: &ctx, size: size, date: timeline.date)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            startDate = Date()
            GameFeel.shared.uiSuccess()
        }
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, date: Date) {
        guard let start = startDate else { return }
        let t = date.timeIntervalSince(start)
        guard t > 0, t < duration else { return }
        let origin = CGPoint(x: size.width / 2, y: size.height * 0.42)
        let gravity = 620.0
        for p in particles {
            let pt = t - p.delay
            guard pt > 0 else { continue }
            let fade: Double = max(0, min(1, (duration - 0.55 - pt) / 0.55 + 1))
            guard fade > 0 else { continue }
            let x: Double = origin.x + cos(p.angle) * p.speed * pt * 0.62 + p.drift * pt
            let y: Double = origin.y + sin(p.angle) * p.speed * pt * 0.62 + 0.5 * gravity * pt * pt
            guard y < size.height + 30 else { continue }
            let rect = CGRect(x: -p.size / 2, y: -p.size * 0.35, width: p.size, height: p.size * 0.7)
            var pc = ctx
            pc.translateBy(x: x, y: y)
            pc.rotate(by: .radians(p.spin * pt))
            pc.opacity = fade
            pc.fill(Path(roundedRect: rect, cornerRadius: 1.5),
                    with: .color(colors[p.colorIndex]))
        }
    }
}

// MARK: - Pop-in badge

/// Springy scale-in used for "NEW BEST" style badges.
struct PopIn: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.3)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.58).delay(delay)) {
                    shown = true
                }
            }
    }
}

extension View {
    func popIn(_ delay: Double = 0) -> some View {
        modifier(PopIn(delay: delay))
    }
}
