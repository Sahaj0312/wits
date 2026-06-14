//
//  Notifications.swift
//  wits
//
//  Local daily reminder. Wraps UNUserNotificationCenter. We never fire the iOS
//  permission prompt cold — a branded primer is shown after the first value
//  moment, and we cap at one reminder a day with a rotating, positive message
//  pool. The reminder is a training wheel: it brings the habit back, not nags.
//

import Foundation
import UserNotifications

@MainActor
enum WitsNotifications {
    private static let dailyID = "wits.daily.reminder"

    static let messages: [String] = [
        "two minutes. keep your streak alive.",
        "your brain's quickest workout is one tap away.",
        "a sharper you is 60 seconds away.",
        "beat yesterday's score?",
        "tiny session, real progress. let's go.",
        "your streak misses you.",
        "quick — squeeze in today's workout.",
    ]

    static func authStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func scheduleDaily(hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dailyID])

        var date = DateComponents()
        date.hour = hour
        date.minute = minute

        let content = UNMutableNotificationContent()
        content.title = "wits"
        content.body = messages.randomElement() ?? "time to train."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        center.add(UNNotificationRequest(identifier: dailyID, content: content, trigger: trigger))
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [dailyID])
    }
}
