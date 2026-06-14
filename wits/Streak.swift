//
//  Streak.swift
//  wits
//
//  Daily-streak state machine. Pure, calendar-injectable logic so it can be
//  unit-tested with synthetic dates. Loss aversion is the strongest daily
//  driver we have; the rules here are deliberately forgiving (freezes absorb a
//  single missed day) so a slip doesn't push the user off the cliff.
//

import Foundation

struct StreakState: Codable, Equatable {
    var current: Int = 0
    var longest: Int = 0
    var lastActiveDay: Date? = nil   // start-of-day of the last meaningful session
    var freezes: Int = 0

    static let empty = StreakState()
}

enum StreakEngine {
    /// Call once a *meaningful* session completes (≥1 full game). Same-day repeats
    /// don't double-count; a one-day gap covered by a freeze keeps the streak.
    static func recordActivity(_ s: StreakState, today: Date, calendar: Calendar = .current) -> StreakState {
        let day = calendar.startOfDay(for: today)
        var next = s

        if let last = s.lastActiveDay {
            let lastDay = calendar.startOfDay(for: last)
            let gap = calendar.dateComponents([.day], from: lastDay, to: day).day ?? 0
            if gap <= 0 {
                return s                                   // already counted today (or clock skew)
            } else if gap == 1 {
                next.current += 1                          // consecutive day
            } else if gap == 2 && s.freezes > 0 {
                next.current += 1                          // a freeze absorbed the missed day
                next.freezes -= 1
            } else {
                next.current = 1                           // streak broke — start fresh
            }
        } else {
            next.current = 1                               // first ever session
        }

        next.lastActiveDay = day
        next.longest = max(next.longest, next.current)
        return next
    }

    /// Call at day rollover (foreground/midnight). Resolves whether an inactive
    /// streak survives on a freeze or breaks.
    static func rollover(_ s: StreakState, today: Date, calendar: Calendar = .current)
        -> (state: StreakState, broke: Bool, usedFreeze: Bool) {
        guard let last = s.lastActiveDay, s.current > 0 else { return (s, false, false) }
        let day = calendar.startOfDay(for: today)
        let lastDay = calendar.startOfDay(for: last)
        let gap = calendar.dateComponents([.day], from: lastDay, to: day).day ?? 0

        if gap <= 1 { return (s, false, false) }           // active today or yesterday — safe
        if gap == 2 && s.freezes > 0 {                     // missed exactly one day; a freeze saves it
            var next = s
            next.freezes -= 1
            next.lastActiveDay = calendar.date(byAdding: .day, value: -1, to: day)
            return (next, false, true)
        }
        var next = s                                       // broke
        next.current = 0
        return (next, true, false)
    }
}
