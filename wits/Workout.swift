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

    /// Builds the day's workout: a rotating window over the live library so the
    /// set varies day to day while still covering every game over time.
    static func build(for day: Date, calendar: Calendar = .current) -> DailyWorkout {
        let pool = GameID.live
        let start = calendar.startOfDay(for: day)
        guard !pool.isEmpty else { return DailyWorkout(day: start, games: []) }
        let doy = calendar.ordinality(of: .day, in: .year, for: day) ?? 0
        let count = min(size, pool.count)
        let offset = (doy * count) % pool.count
        let rotated = pool[offset...] + pool[..<offset]
        let games = Array(rotated.prefix(count))
        return DailyWorkout(id: UUID(), day: start, games: games)
    }
}
