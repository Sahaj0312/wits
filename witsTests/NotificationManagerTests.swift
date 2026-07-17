import XCTest
@testable import wits

final class NotificationManagerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testPlansTwoRemindersPerDayAtFixedTimes() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 16,
                                                                   hour: 10, minute: 30)))
        let plans = DailyReminderPlanner.plans(now: now,
                                               lastActiveDay: nil,
                                               streakCount: 0,
                                               horizonDays: 5,
                                               calendar: calendar)

        XCTAssertEqual(plans.count, 10)
        XCTAssertEqual(Set(plans.map(\.identifier)).count, 10)
        XCTAssertEqual(Set(plans.map { calendar.component(.hour, from: $0.date) }), [11, 20])
    }

    func testPlayingTodaySkipsTodayAndStartsTomorrow() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 16,
                                                                   hour: 10)))
        let plans = DailyReminderPlanner.plans(now: now,
                                               lastActiveDay: now,
                                               streakCount: 4,
                                               horizonDays: 5,
                                               calendar: calendar)

        let first = try XCTUnwrap(plans.first)
        XCTAssertTrue(calendar.isDate(first.date,
                                      inSameDayAs: calendar.date(byAdding: .day, value: 1, to: now)!))
        let tomorrow = plans.filter { calendar.isDate($0.date, inSameDayAs: first.date) }
        XCTAssertEqual(tomorrow.count, 2)
        XCTAssertEqual(tomorrow.filter { $0.body.contains("4-day streak") }.count, 1)
    }

    func testStreakCopyAppearsOnlyOnTheNextEligibleDay() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 16,
                                                                   hour: 10)))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let plans = DailyReminderPlanner.plans(now: now,
                                               lastActiveDay: yesterday,
                                               streakCount: 7,
                                               horizonDays: 5,
                                               calendar: calendar)

        XCTAssertEqual(plans.filter { $0.body.contains("7-day streak") }.count, 1)
        XCTAssertEqual(calendar.component(.hour,
                                          from: try XCTUnwrap(plans.first { $0.body.contains("streak") }).date),
                       20)
    }

    func testPastReminderTimeStartsTomorrow() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 16,
                                                                   hour: 20)))
        let plans = DailyReminderPlanner.plans(now: now,
                                               lastActiveDay: nil,
                                               streakCount: 0,
                                               horizonDays: 5,
                                               calendar: calendar)

        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        XCTAssertTrue(calendar.isDate(try XCTUnwrap(plans.first).date, inSameDayAs: tomorrow))
    }

    func testAfterMorningOnlyEveningRemainsToday() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 16,
                                                                   hour: 14)))
        let plans = DailyReminderPlanner.plans(now: now,
                                               lastActiveDay: nil,
                                               streakCount: 0,
                                               horizonDays: 2,
                                               calendar: calendar)

        let today = plans.filter { calendar.isDate($0.date, inSameDayAs: now) }
        XCTAssertEqual(today.count, 1)
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(today.first).date), 20)
    }
}
