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
    /// Builds the day's workout. With three live games we play all three, but the
    /// order rotates by day so the first game (the one most likely to get the
    /// freshest attention) cycles.
    static func build(for day: Date, calendar: Calendar = .current) -> DailyWorkout {
        let pool = GameID.live
        guard !pool.isEmpty else { return DailyWorkout(day: calendar.startOfDay(for: day), games: []) }
        let doy = calendar.ordinality(of: .day, in: .year, for: day) ?? 0
        let shift = doy % pool.count
        let rotated = Array(pool[shift...] + pool[..<shift])
        return DailyWorkout(id: UUID(), day: calendar.startOfDay(for: day), games: rotated)
    }
}
