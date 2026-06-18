//
//  Streak.swift
//  wits
//
//  Daily-streak state machine. Pure, calendar-injectable logic so it can be
//  unit-tested with synthetic dates. Miss a day and the streak resets to zero.
//

import Foundation

struct StreakState: Codable, Equatable {
    var current: Int = 0
    var longest: Int = 0
    var lastActiveDay: Date? = nil   // start-of-day of the last meaningful session

    static let empty = StreakState()
}

enum StreakEngine {
    /// Call once a *meaningful* session completes (≥1 full game). Same-day repeats
    /// don't double-count; a consecutive day extends, any gap resets to 1.
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
            } else {
                next.current = 1                           // missed a day — start fresh
            }
        } else {
            next.current = 1                               // first ever session
        }

        next.lastActiveDay = day
        next.longest = max(next.longest, next.current)
        return next
    }

    /// Call at day rollover (foreground/midnight). Breaks the streak if a full day
    /// was missed.
    static func rollover(_ s: StreakState, today: Date, calendar: Calendar = .current) -> StreakState {
        guard let last = s.lastActiveDay, s.current > 0 else { return s }
        let day = calendar.startOfDay(for: today)
        let lastDay = calendar.startOfDay(for: last)
        let gap = calendar.dateComponents([.day], from: lastDay, to: day).day ?? 0
        guard gap > 1 else { return s }                    // active today or yesterday — safe
        var next = s
        next.current = 0                                   // missed a day — streak broke
        return next
    }
}
