//
//  Rewards.swift
//  wits
//
//  Day-seeded variety: the optional surprise daily challenge. Deterministic per
//  day so it's not exploitable, and it always sits beside a finite daily loop.
//

import Foundation

/// Tiny deterministic RNG (SplitMix64) so rewards are reproducible per seed.
struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

enum RewardEngine {
    /// An optional surprise daily challenge (an extra game) — appears some days.
    static func dailyChallenge(seed: UInt64) -> GameID? {
        var rng = SeededRNG(seed: seed &* 0x2545F4914F6CDD1D)
        guard rng.unit() < 0.5 else { return nil }
        let live = GameID.live
        guard !live.isEmpty else { return nil }
        return live[Int(rng.next() % UInt64(live.count))]
    }

    /// Stable per-day seed.
    static func daySeed(_ day: Date) -> UInt64 {
        UInt64(max(0, day.timeIntervalSince1970)) / 86_400
    }
}
