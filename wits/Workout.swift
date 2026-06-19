//
//  Workout.swift
//  wits
//
//  The daily workout: a short, finite set of games the user runs once a day.
//  Finite by design — it ends, giving a natural stopping point (the opposite of
//  infinite scroll). The rotation varies day-to-day so it doesn't feel identical.
//

import Foundation

struct DailyWorkout: Identifiable, Codable {
    var id: UUID = UUID()
    var day: Date
    var games: [GameID]
    var results: [GameResult] = []

    var completed: Bool { results.count >= games.count }
}

enum WorkoutBuilder {
    /// Up to this many games per daily workout — keeps a session ~3-4 minutes
    /// even as the library grows.
    static let size = 4

    /// Builds the day's workout.
    ///
    /// `priorities` is a per-domain "needs training" score (higher = train more);
    /// see `ProgressMath.domainPriorities`. When supplied, the lineup tilts toward
    /// the user's weakest / most-neglected cognitive domains so the daily session
    /// actually works on what's lagging instead of training everything equally.
    /// When empty (a brand-new player with no history, or a caller that just wants
    /// a stable preview) it falls back to the original day-of-year rotating window.
    static func build(for day: Date,
                      priorities: [CognitiveDomain: Double] = [:],
                      calendar: Calendar = .current) -> DailyWorkout {
        let pool = GameID.live
        let start = calendar.startOfDay(for: day)
        guard !pool.isEmpty else { return DailyWorkout(day: start, games: []) }
        let count = min(size, pool.count)
        let doy = calendar.ordinality(of: .day, in: .year, for: day) ?? 0

        // No signal yet → rotating window: varies day to day, covers all games.
        guard !priorities.isEmpty else {
            let offset = (doy * count) % pool.count
            let rotated = pool[offset...] + pool[..<offset]
            return DailyWorkout(day: start, games: Array(rotated.prefix(count)))
        }

        // Group the live library by cognitive domain (grouping preserves the
        // pool order within each domain, so the daily within-domain rotation
        // below is deterministic).
        let byDomain = Dictionary(grouping: pool, by: { $0.domain })

        // Order domains most-in-need first. Near-ties rotate by day-of-year so
        // equally-weak domains (and the long tail) keep cycling instead of the
        // lineup freezing on one fixed set.
        let order = CognitiveDomain.allCases
        func dayRank(_ d: CognitiveDomain) -> Int {
            let i = order.firstIndex(of: d) ?? 0
            return (i + doy) % max(1, order.count)
        }
        let domains = byDomain.keys.sorted { a, b in
            let pa = priorities[a] ?? 0, pb = priorities[b] ?? 0
            if abs(pa - pb) > 0.5 { return pa > pb }
            return dayRank(a) < dayRank(b)
        }

        // Round-robin: one game from each domain in priority order, rotating
        // which game within a domain by day, until the workout is full. Extra
        // passes wrap back to the neediest domains only if there aren't enough
        // distinct domains to fill every slot.
        var games: [GameID] = []
        var pass = 0
        while games.count < count {
            var progressed = false
            for d in domains {
                guard let gs = byDomain[d], !gs.isEmpty else { continue }
                let g = gs[(doy + pass) % gs.count]
                if !games.contains(g) {
                    games.append(g)
                    progressed = true
                    if games.count >= count { break }
                }
            }
            pass += 1
            if !progressed { break }   // every game already chosen — stop
        }
        return DailyWorkout(day: start, games: games)
    }
}
