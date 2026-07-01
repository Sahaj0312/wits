//
//  ProfileView.swift
//  wits
//
//  Settings-style profile page.
//

import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(SupabaseManager.self) private var supa
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("wits.soundEffectsEnabled") private var soundEffectsEnabled = true
    @AppStorage("wits.hapticsEnabled") private var hapticsEnabled = true
    @State private var showReminder = false

    private var displayName: String {
        app.profile.displayName?.isEmpty == false ? app.profile.displayName! : "you"
    }

    private var accountStatus: String {
        supa.isSignedIn ? "signed in" : "not signed in"
    }

    private var entitlementLabel: String {
        switch app.entitlement {
        case .unknown: "—"
        case .trial: "\(app.entitlement.trialDaysLeft)-day trial"
        case .subscribed: "full access"
        case .expired: "trial ended"
        }
    }

    private var reminderEnabled: Bool {
        app.profile.notificationsEnabled && app.profile.reminderHour != nil
    }

    private var reminderLabel: String {
        guard let h = app.profile.reminderHour else { return "off" }
        let m = app.profile.reminderMinute
        let suffix = h < 12 ? "am" : "pm"
        let hour12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", hour12, m, suffix)
    }

    private var reminderStatusLabel: String {
        reminderEnabled ? "On · \(reminderLabel)" : "Off"
    }

    private var goalsLabel: String {
        guard !app.profile.goals.isEmpty else { return "not set" }
        return app.profile.goals.prefix(2).joined(separator: ", ")
    }

    private var difficultyLabel: String {
        app.profile.difficultyPreference?.isEmpty == false ? app.profile.difficultyPreference! : "adaptive"
    }

    private var encouragementLabel: String {
        app.profile.encouragementStyle?.isEmpty == false ? app.profile.encouragementStyle! : "standard"
    }

    private var routineLabel: String {
        let exercise = app.profile.exerciseFrequency?.isEmpty == false ? app.profile.exerciseFrequency! : "exercise not set"
        let sleep = app.profile.sleepHours?.isEmpty == false ? app.profile.sleepHours! : "sleep not set"
        return "\(exercise) · \(sleep)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                pageHeader

                settingsSection("settings") {
                    Button { showReminder = true } label: {
                        settingsValueRow(icon: "bell.fill",
                                         tint: Color(light: 0x24A8FF, dark: 0x24A8FF),
                                         title: "Daily Reminder",
                                         value: reminderStatusLabel,
                                         showsChevron: true)
                    }
                    .buttonStyle(.plain)
                    settingsDivider
                    settingsToggleRow(icon: "speaker.wave.2.fill",
                                      tint: Color(light: 0x5B5CFF, dark: 0x7A78FF),
                                      title: "Sound Effects",
                                      isOn: $soundEffectsEnabled)
                    settingsDivider
                    settingsToggleRow(icon: "hand.tap.fill",
                                      tint: Color.witsWarm,
                                      title: "Haptics",
                                      isOn: $hapticsEnabled)
                }

                settingsSection("training") {
                    settingsValueRow(icon: "calendar.badge.clock",
                                     tint: Color.witsAccent,
                                     title: "Weekly Target",
                                     value: "\(app.profile.trainingDays) days")
                    settingsDivider
                    settingsValueRow(icon: "target",
                                     tint: Color(light: 0x24A8FF, dark: 0x24A8FF),
                                     title: "Goals",
                                     value: goalsLabel)
                    settingsDivider
                    settingsValueRow(icon: "slider.horizontal.3",
                                     tint: Color(light: 0x5B5CFF, dark: 0x7A78FF),
                                     title: "Difficulty",
                                     value: difficultyLabel)
                    settingsDivider
                    settingsValueRow(icon: "quote.bubble.fill",
                                     tint: Color(light: 0xD950C9, dark: 0xD950C9),
                                     title: "Encouragement",
                                     value: encouragementLabel)
                    settingsDivider
                    settingsValueRow(icon: "figure.run",
                                     tint: Color.witsWarm,
                                     title: "Routine",
                                     value: routineLabel)
                }

                settingsSection("wits") {
                    settingsValueRow(icon: "person.fill",
                                     tint: Color.witsAccent,
                                     title: "Account",
                                     value: accountStatus)
                    settingsDivider
                    settingsValueRow(icon: "creditcard.fill",
                                     tint: Color.witsWarm,
                                     title: "Plan",
                                     value: entitlementLabel)
                    settingsDivider
                    Button {
                        hasCompletedOnboarding = false
                    } label: {
                        settingsValueRow(icon: "arrow.clockwise",
                                         tint: Color(light: 0x5B5CFF, dark: 0x7A78FF),
                                         title: "Replay Onboarding",
                                         value: "",
                                         showsChevron: true)
                    }
                    .buttonStyle(.plain)
                }

                settingsSection("account") {
                    Button {
                        supa.signOut()
                        app.resetForSignOut()
                        hasCompletedOnboarding = false
                    } label: {
                        settingsValueRow(icon: "rectangle.portrait.and.arrow.right",
                                         tint: Color.witsWarm,
                                         title: "Sign Out",
                                         value: "")
                    }
                    .buttonStyle(.plain)
                }

                Text("You're using \(entitlementLabel).")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.witsMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
                    .padding(.bottom, 124)
            }
        }
        .background(Color.witsBg.ignoresSafeArea())
        .sheet(isPresented: $showReminder) {
            ReminderSettingsSheet(app: app)
        }
        .onAppear {
            syncGameFeelSettings()
        }
        .onChange(of: soundEffectsEnabled) { _, _ in
            syncGameFeelSettings()
        }
        .onChange(of: hapticsEnabled) { _, _ in
            syncGameFeelSettings()
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            WitsBrandMark()
            Text("Hi \(displayName)")
                .font(.witsDisplay(30))
                .foregroundStyle(Color.witsInk)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private func settingsSection<Content: View>(_ title: String,
                                                @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsInk)
                .textCase(.uppercase)
                .padding(.horizontal, 30)
                .padding(.top, 26)
                .padding(.bottom, 14)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.witsCard)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.witsLine)
                    .frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.witsLine)
                    .frame(height: 1)
            }
        }
    }

    private func settingsToggleRow(icon: String,
                                   tint: Color,
                                   title: String,
                                   isOn: Binding<Bool>) -> some View {
        HStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)

            Text(title)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(Color.witsInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)

            Spacer(minLength: 12)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color.witsAccent)
        }
        .padding(.horizontal, 30)
        .frame(minHeight: 74)
        .contentShape(Rectangle())
    }

    private func settingsValueRow(icon: String,
                                  tint: Color,
                                  title: String,
                                  value: String,
                                  isDimmed: Bool = false,
                                  showsChevron: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(isDimmed ? Color.witsFaint : tint)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(isDimmed ? Color.witsFaint : Color.witsInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                    .fixedSize(horizontal: false, vertical: true)

                if !value.isEmpty {
                    Text(value)
                        .font(.system(size: 16.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(isDimmed ? Color.witsFaint : Color.witsAccent)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.witsFaint)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 12)
        .frame(minHeight: 78)
        .contentShape(Rectangle())
    }

    private var settingsDivider: some View {
        Rectangle()
            .fill(Color.witsLine)
            .frame(height: 1)
            .padding(.leading, 86)
    }

    private func syncGameFeelSettings() {
        GameFeel.shared.soundEnabled = soundEffectsEnabled
        GameFeel.shared.hapticsEnabled = hapticsEnabled
        if !soundEffectsEnabled {
            GameFeel.shared.teardown()
        }
    }
}
