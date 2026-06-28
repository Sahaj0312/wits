//
//  ReminderFlow.swift
//  wits
//
//  The branded pre-permission primer (shown after the first completed workout)
//  and the reminder settings sheet (from the You tab). The OS prompt only fires
//  after the user opts in here.
//

import SwiftUI

private func components(_ date: Date) -> (Int, Int) {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return (c.hour ?? 9, c.minute ?? 0)
}

private func defaultTime(hour: Int, minute: Int) -> Date {
    Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
}

struct NotificationPrimer: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var time = defaultTime(hour: 9, minute: 0)
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(Color.witsAccent)
                Text("keep the habit")
                    .font(.witsDisplay(28))
                    .foregroundStyle(Color.witsInk)
                Text("one gentle nudge a day is the difference between a streak and a forgotten app. pick a time that fits your routine.")
                    .font(.witsBody(15.5))
                    .foregroundStyle(Color.witsMuted)
                    .multilineTextAlignment(.center)
                DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.wheel)
                    .frame(height: 120)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .cardSurface()
            Spacer()
            Cta(title: working ? "…" : "turn on reminders") {
                guard !working else { return }
                working = true
                Task {
                    let granted = await WitsNotifications.requestAuthorization()
                    let (h, m) = components(time)
                    app.setReminder(hour: h, minute: m, enabled: granted)
                    working = false
                    dismiss()
                }
            }
            QuietButton(title: "not now") { dismiss() }
                .padding(.top, 6)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 20)
        .background(Color.witsBg.ignoresSafeArea())
    }
}

struct ReminderSettingsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var enabled: Bool
    @State private var time: Date

    init(app: AppModel) {
        _enabled = State(initialValue: app.profile.notificationsEnabled)
        _time = State(initialValue: defaultTime(hour: app.profile.reminderHour ?? 9,
                                                minute: app.profile.reminderMinute))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("notification plan")
                .font(.witsDisplay(26))
                .foregroundStyle(Color.witsInk)
                .padding(.top, 8)

            Toggle(isOn: $enabled) {
                Text("remind me to train")
                    .font(.witsBody(16, weight: .semibold))
                    .foregroundStyle(Color.witsInk)
            }
            .tint(.witsAccent)
            .padding(16)
            .cardSurface()

            if enabled {
                DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .cardSurface()
            }

            Spacer()
            Cta(title: "save") {
                Task {
                    let (h, m) = components(time)
                    var canEnable = enabled
                    if enabled {
                        let status = await WitsNotifications.authStatus()
                        if status == .notDetermined {
                            canEnable = await WitsNotifications.requestAuthorization()
                        } else if status == .denied {
                            canEnable = false
                        }
                    }
                    app.setReminder(hour: h, minute: m, enabled: canEnable)
                    dismiss()
                }
            }
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 16)
        .background(Color.witsBg.ignoresSafeArea())
    }
}
