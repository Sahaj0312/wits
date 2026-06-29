//
//  Notifications.swift
//  wits
//
//  Local notification planning. Wits stays local-only for now: the app rebuilds
//  the next week of pending notifications from profile preferences + current
//  activity state, then cancels stale Wits-owned requests as the user trains.
//

import Foundation
@preconcurrency import UserNotifications

enum WitsNotificationKind: String, CaseIterable {
    case dailyWorkout = "daily"
    case streakRescue = "rescue"
    case trialEndingSoon = "trial_soon"
    case trialEndsToday = "trial_end"
    case reactivation = "reactivation"
}

enum WitsNotificationPermissionState {
    case ready
    case notDetermined
    case disabled
}

struct WitsNotificationPlanContext: Equatable {
    var now = Date()
    var todayWorkoutDone = false
    var streak = StreakState.empty
    var hasAnyProgress = false
}

struct WitsNotificationEvent: Equatable {
    var id: String
    var kind: WitsNotificationKind
    var fireDate: Date
    var title: String
    var body: String
}

enum WitsNotificationPlanner {
    static let horizonDays = 7

    static func events(profile: ProfileSnapshot,
                       context: WitsNotificationPlanContext,
                       calendar rawCalendar: Calendar = .current) -> [WitsNotificationEvent] {
        guard profile.notificationsEnabled, let hour = profile.reminderHour else { return [] }

        var calendar = rawCalendar
        calendar.locale = Locale(identifier: "en_US_POSIX")

        let today = calendar.startOfDay(for: context.now)
        let horizonEnd = calendar.date(byAdding: .day, value: horizonDays, to: today) ?? today
        let primaryMinutes = clampedMinutes(hour: hour, minute: profile.reminderMinute)
        var events: [WitsNotificationEvent] = []

        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  isTrainingDay(day, trainingDays: profile.trainingDays, calendar: calendar) else { continue }
            let isToday = calendar.isDate(day, inSameDayAs: today)
            let workoutDone = isToday && context.todayWorkoutDone

            if !workoutDone,
               let fire = date(on: day, minutes: primaryMinutes, calendar: calendar),
               fire > context.now {
                events.append(event(.dailyWorkout, fire: fire, profile: profile, calendar: calendar))
            }

            if !workoutDone,
               let rescueMinutes = rescueMinutes(primaryMinutes: primaryMinutes, profile: profile),
               let fire = date(on: day, minutes: rescueMinutes, calendar: calendar),
               fire > context.now {
                events.append(event(.streakRescue, fire: fire, profile: profile, calendar: calendar))
            }
        }

        events.append(contentsOf: trialEvents(profile: profile,
                                             context: context,
                                             horizonEnd: horizonEnd,
                                             calendar: calendar))
        events.append(contentsOf: reactivationEvents(profile: profile,
                                                     context: context,
                                                     primaryMinutes: primaryMinutes,
                                                     horizonEnd: horizonEnd,
                                                     calendar: calendar))

        return Dictionary(grouping: suppressDailyReactivationOverlap(events, calendar: calendar), by: \.id)
            .compactMap { $0.value.sorted { $0.fireDate < $1.fireDate }.first }
            .sorted { $0.fireDate < $1.fireDate }
    }

    static func id(for kind: WitsNotificationKind, fireDate: Date, calendar: Calendar = .current) -> String {
        "wits.local.\(kind.rawValue).\(dayKey(fireDate, calendar: calendar))"
    }

    private static func trialEvents(profile: ProfileSnapshot,
                                    context: WitsNotificationPlanContext,
                                    horizonEnd: Date,
                                    calendar: Calendar) -> [WitsNotificationEvent] {
        guard let started = profile.trialStartedAt else { return [] }
        if let sub = profile.subscriptionUntil, sub > context.now { return [] }

        guard let trialEnd = calendar.date(byAdding: .day, value: EntitlementEngine.trialDays, to: started),
              trialEnd > context.now else { return [] }

        let endDay = calendar.startOfDay(for: trialEnd)
        let soonDay = calendar.date(byAdding: .day, value: -1, to: endDay) ?? endDay
        let reminderMinutes = clampedMinutes(hour: profile.reminderHour ?? 9, minute: profile.reminderMinute)
        let soonMinutes = min(max(reminderMinutes, 10 * 60), 15 * 60)
        let endMinutes = min(max(reminderMinutes + 4 * 60, 15 * 60), 19 * 60)

        return [
            (.trialEndingSoon, soonDay, soonMinutes),
            (.trialEndsToday, endDay, endMinutes),
        ].compactMap { kind, day, minutes in
            guard let fire = date(on: day, minutes: minutes, calendar: calendar),
                  fire > context.now,
                  fire < horizonEnd else { return nil }
            return event(kind, fire: fire, profile: profile, calendar: calendar)
        }
    }

    private static func reactivationEvents(profile: ProfileSnapshot,
                                           context: WitsNotificationPlanContext,
                                           primaryMinutes: Int,
                                           horizonEnd: Date,
                                           calendar: Calendar) -> [WitsNotificationEvent] {
        let today = calendar.startOfDay(for: context.now)
        let inactiveDays: Int
        if let last = context.streak.lastActiveDay {
            inactiveDays = calendar.dateComponents([.day],
                                                   from: calendar.startOfDay(for: last),
                                                   to: today).day ?? 0
        } else if context.hasAnyProgress {
            inactiveDays = 2
        } else {
            inactiveDays = 0
        }
        guard inactiveDays >= 2 || (context.hasAnyProgress && context.streak.current == 0) else { return [] }

        let minutes = min(max(primaryMinutes + 60, 10 * 60), 16 * 60)
        var events: [WitsNotificationEvent] = []
        for offset in 0..<min(3, horizonDays) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = date(on: day, minutes: minutes, calendar: calendar),
                  fire > context.now,
                  fire < horizonEnd else { continue }
            events.append(event(.reactivation, fire: fire, profile: profile, calendar: calendar))
        }
        return events
    }

    private static func suppressDailyReactivationOverlap(_ events: [WitsNotificationEvent],
                                                         calendar: Calendar) -> [WitsNotificationEvent] {
        let reactivationDays = Set(events
            .filter { $0.kind == .reactivation }
            .map { dayKey($0.fireDate, calendar: calendar) })
        guard !reactivationDays.isEmpty else { return events }
        return events.filter { event in
            event.kind != .dailyWorkout || !reactivationDays.contains(dayKey(event.fireDate, calendar: calendar))
        }
    }

    private static func event(_ kind: WitsNotificationKind,
                              fire: Date,
                              profile: ProfileSnapshot,
                              calendar: Calendar) -> WitsNotificationEvent {
        WitsNotificationEvent(
            id: id(for: kind, fireDate: fire, calendar: calendar),
            kind: kind,
            fireDate: fire,
            title: "wits",
            body: body(for: kind, fire: fire, profile: profile, calendar: calendar)
        )
    }

    private static func body(for kind: WitsNotificationKind,
                             fire: Date,
                             profile: ProfileSnapshot,
                             calendar: Calendar) -> String {
        let goal = goalPhrase(profile.goals)
        let tough = profile.encouragementStyle?.localizedCaseInsensitiveContains("tough") == true
        let advanced = profile.difficultyPreference?.localizedCaseInsensitiveContains("advanced") == true
        let activeBody = profile.exerciseFrequency?.localizedCaseInsensitiveContains("daily") == true
            || profile.exerciseFrequency?.localizedCaseInsensitiveContains("few") == true
        let lowSleep = isLowSleep(profile.sleepHours)
        let key = "\(kind.rawValue).\(dayKey(fire, calendar: calendar)).\(goal).\(profile.encouragementStyle ?? "")"

        let pool: [String]
        switch kind {
        case .dailyWorkout:
            if lowSleep {
                pool = [
                    "Keep it light today: a short \(goal) session is ready.",
                    "A quick brain warmup, no grind required.",
                ]
            } else if advanced || tough {
                pool = [
                    "No drift today. Push your \(goal) score.",
                    "Today's workout is ready. Beat your baseline.",
                ]
            } else if activeBody {
                pool = [
                    "Stack this with your routine: a quick \(goal) workout is ready.",
                    "A small session after movement keeps the habit easy.",
                ]
            } else {
                pool = [
                    "A steady \(goal) session is ready when you are.",
                    "Two minutes. Keep your training rhythm alive.",
                ]
            }
        case .streakRescue:
            pool = tough ? [
                "Last call for today's workout. Keep the streak intact.",
                "Do not let today go blank. One short session.",
            ] : [
                "Still time to keep your streak moving.",
                "A quick session tonight keeps the habit warm.",
            ]
        case .trialEndingSoon:
            pool = [
                "Your trial ends tomorrow. Get one more progress check in.",
                "One day left in your trial. See what today's workout says.",
            ]
        case .trialEndsToday:
            pool = [
                "Your trial ends today. Train once more before it wraps.",
                "Final trial day: finish today's workout and check your score.",
            ]
        case .reactivation:
            pool = tough ? [
                "Reset the streak today. One workout gets you moving again.",
                "You fell off for a minute. Get one clean session in.",
            ] : [
                "Pick the habit back up with one short workout.",
                "No catch-up needed. Just start with today's session.",
            ]
        }

        return pool[stableIndex(key, count: pool.count)]
    }

    private static func rescueMinutes(primaryMinutes: Int, profile: ProfileSnapshot) -> Int? {
        let lowSleep = isLowSleep(profile.sleepHours)
        let floor = lowSleep ? 18 * 60 : 20 * 60
        let cap = lowSleep ? 19 * 60 + 30 : 21 * 60
        guard primaryMinutes < cap else { return nil }
        return min(max(primaryMinutes + 3 * 60, floor), cap)
    }

    private static func isTrainingDay(_ date: Date, trainingDays: Int, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        let days: Set<Int>
        switch trainingDays {
        case 7: days = [1, 2, 3, 4, 5, 6, 7]
        case 6: days = [2, 3, 4, 5, 6, 7]
        case 4: days = [2, 3, 5, 7]
        case 3: days = [2, 4, 6]
        default: days = [2, 3, 4, 5, 6]
        }
        return days.contains(weekday)
    }

    private static func goalPhrase(_ goals: [String]) -> String {
        let joined = goals.joined(separator: " ").lowercased()
        if joined.contains("memory") { return "memory" }
        if joined.contains("faster") { return "speed" }
        if joined.contains("focus") || joined.contains("attention") { return "focus" }
        if joined.contains("active") { return "mind" }
        return "wits"
    }

    private static func isLowSleep(_ sleep: String?) -> Bool {
        guard let s = sleep?.lowercased() else { return false }
        return s.contains("4 hours") || s.contains("5–6") || s.contains("5-6")
    }

    private static func date(on day: Date, minutes: Int, calendar: Calendar) -> Date? {
        var c = calendar.dateComponents([.year, .month, .day], from: day)
        c.hour = minutes / 60
        c.minute = minutes % 60
        c.second = 0
        return calendar.date(from: c)
    }

    private static func clampedMinutes(hour: Int, minute: Int) -> Int {
        max(0, min(23 * 60 + 59, hour * 60 + minute))
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func stableIndex(_ key: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var hash: UInt64 = 5381
        for byte in key.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return Int(hash % UInt64(count))
    }
}

@MainActor
enum WitsNotifications {
    private static let legacyDailyID = "wits.daily.reminder"
    private static let idPrefix = "wits.local."

    static func authStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func permissionState() async -> WitsNotificationPermissionState {
        switch await authStatus() {
        case .authorized, .provisional, .ephemeral:
            return .ready
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .disabled
        @unknown default:
            return .disabled
        }
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func schedulePlan(profile: ProfileSnapshot, context: WitsNotificationPlanContext) {
        let events = WitsNotificationPlanner.events(profile: profile, context: context)
        let plannedRequests = events.map(request(for:))
        let prefix = idPrefix
        let legacy = legacyDailyID
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) || $0 == legacy }
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
            for request in plannedRequests {
                center.add(request)
            }
        }
    }

    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        let prefix = idPrefix
        let legacy = legacyDailyID
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) || $0 == legacy }
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }

    static func pendingRequests() async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
    }

    private static func request(for event: WitsNotificationEvent) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: event.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: event.id, content: content, trigger: trigger)
    }
}
