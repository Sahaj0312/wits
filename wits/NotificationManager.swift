//
//  NotificationManager.swift
//  wits
//
//  Two respectful local reminders per unplayed day. The app keeps a rolling
//  set of one-off requests instead of a repeating trigger so completing a
//  game can remove today's reminder without disabling tomorrow's.
//

import Foundation
import Observation
import UserNotifications

struct DailyReminderPlan: Equatable {
    let identifier: String
    let date: Date
    let title: String
    let body: String
}

/// Pure planning kept separate from UserNotifications so date, streak, and
/// frequency behavior can be verified without asking the OS for permission.
enum DailyReminderPlanner {
    static let horizonDays = 30
    /// Late morning and evening, interpreted in the user's current calendar
    /// and time zone whenever the schedule is refreshed.
    static let reminderHours = [11, 20]

    private static let genericCopy: [(title: String, body: String)] = [
        ("a quick brain break", "a Wits challenge is ready when you are."),
        ("sharpen up", "a few minutes. one sharper brain."),
        ("your daily Wits", "trade a little scroll time for a quick game."),
        ("ready when you are", "pick a game and give your brain a quick workout.")
    ]

    static func plans(now: Date,
                      lastActiveDay: Date?,
                      streakCount: Int,
                      horizonDays: Int = horizonDays,
                      calendar: Calendar = .current) -> [DailyReminderPlan] {
        guard horizonDays > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        let activeDay = lastActiveDay.map { calendar.startOfDay(for: $0) }
        var result: [DailyReminderPlan] = []

        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }

            // A completed game makes this calendar day ineligible.
            if let activeDay, calendar.isDate(day, inSameDayAs: activeDay) { continue }

            let components = calendar.dateComponents([.year, .month, .day], from: day)
            let dayKey = String(format: "%04d-%02d-%02d",
                                components.year ?? 0,
                                components.month ?? 0,
                                components.day ?? 0)

            for (slot, hour) in reminderHours.enumerated() {
                guard let fireDate = calendar.date(bySettingHour: hour,
                                                   minute: 0,
                                                   second: 0,
                                                   of: day),
                      fireDate > now else { continue }

                let copy: (title: String, body: String)
                // The evening touch is the only streak reminder. The morning
                // notification stays light, and a completed game cancels the
                // evening request before it can fire.
                if hour == reminderHours.last,
                   streakCount > 0,
                   let activeDay,
                   calendar.dateComponents([.day], from: activeDay, to: day).day == 1 {
                    copy = ("keep the streak alive",
                            "your \(streakCount)-day streak is waiting. one quick game keeps it going.")
                } else {
                    let ordinal = calendar.ordinality(of: .day, in: .era, for: day) ?? offset
                    copy = genericCopy[(abs(ordinal) * reminderHours.count + slot) % genericCopy.count]
                }

                result.append(DailyReminderPlan(identifier: "wits.daily-reminder.\(dayKey).\(hour)",
                                                date: fireDate,
                                                title: copy.title,
                                                body: copy.body))
            }
        }
        return result
    }
}

@MainActor
@Observable
final class NotificationManager {
    static let shared = NotificationManager()

    private(set) var isEnabled: Bool
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var scheduleRevision = 0

    private static let enabledKey = "wits.dailyReminderEnabled"
    private static let requestPrefix = "wits.daily-reminder."

    private init() {
        isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    /// First-run entry point. This is called only after the user taps Get
    /// Started, keeping the system prompt off the welcome screen until then.
    func requestAfterWelcome(streak: StreakState) async {
        let allowed = await ensureAuthorization()
        setStoredEnabled(allowed)
        if allowed {
            await replaceSchedule(streak: streak)
        } else {
            await cancelManagedRequests()
        }
    }

    /// Returns the actual resulting state. A denied system permission leaves
    /// the in-app toggle off so Settings never promises reminders iOS blocks.
    @discardableResult
    func setEnabled(_ enabled: Bool, streak: StreakState) async -> Bool {
        guard enabled else {
            setStoredEnabled(false)
            await cancelManagedRequests()
            return false
        }

        let allowed = await ensureAuthorization()
        setStoredEnabled(allowed)
        if allowed {
            await replaceSchedule(streak: streak)
        } else {
            await cancelManagedRequests()
        }
        return allowed
    }

    /// Foreground refresh catches time-zone changes and permission changes
    /// made in iOS Settings without presenting a permission prompt.
    func appBecameActive(streak: StreakState) async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        guard isEnabled else { return }
        guard Self.isAllowed(settings.authorizationStatus) else {
            setStoredEnabled(false)
            await cancelManagedRequests()
            return
        }
        await replaceSchedule(streak: streak)
    }

    /// A meaningful completed game cancels today's reminder and rebuilds the
    /// future window using the newly updated streak.
    func activityCompleted(streak: StreakState) {
        guard isEnabled else { return }
        Task { await replaceSchedule(streak: streak) }
    }

    private func ensureAuthorization() async -> Bool {
        var settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            settings = await center.notificationSettings()
            authorizationStatus = settings.authorizationStatus
        }
        return Self.isAllowed(settings.authorizationStatus)
    }

    private static func isAllowed(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    private func setStoredEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    private func replaceSchedule(streak: StreakState) async {
        scheduleRevision &+= 1
        let revision = scheduleRevision
        let plans = DailyReminderPlanner.plans(now: Date(),
                                               lastActiveDay: streak.lastActiveDay,
                                               streakCount: streak.current)
        let pending = await center.pendingNotificationRequests()
        await removeDeliveredManagedNotifications()
        guard revision == scheduleRevision, isEnabled else { return }

        // Requests with the same identifier are replaced by add(). Only
        // remove dates that are no longer planned; removing every identifier
        // and immediately re-adding it can race the notification daemon.
        let plannedIdentifiers = Set(plans.map(\.identifier))
        let obsoleteIdentifiers = pending.map(\.identifier).filter {
            $0.hasPrefix(Self.requestPrefix) && !plannedIdentifiers.contains($0)
        }
        if !obsoleteIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: obsoleteIdentifiers)
        }

        for plan in plans {
            guard revision == scheduleRevision, isEnabled else { return }
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            content.threadIdentifier = "wits.daily-reminder"
            content.userInfo = ["destination": "library"]

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute],
                                                              from: plan.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: plan.identifier,
                                                content: content,
                                                trigger: trigger)
            // A later reschedule increments the revision and stops this batch
            // before its next add; matching identifiers make the newer batch
            // replace any request this one already submitted.
            try? await center.add(request)
        }
    }

    private func cancelManagedRequests() async {
        scheduleRevision &+= 1
        await removeManagedRequests()
        await removeDeliveredManagedNotifications()
    }

    private func removeManagedRequests() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(Self.requestPrefix) }
        if !identifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    private func removeDeliveredManagedNotifications() async {
        let delivered = await center.deliveredNotifications()
        let identifiers = delivered.map { $0.request.identifier }
            .filter { $0.hasPrefix(Self.requestPrefix) }
        if !identifiers.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }
}
