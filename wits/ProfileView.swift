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
        reminderEnabled ? "on · \(reminderLabel)" : "off"
    }

    private var latestSelfTest: (test: SelfTest, record: SelfTestRecord)? {
        SelfTestCatalog.all
            .compactMap { test -> (test: SelfTest, record: SelfTestRecord)? in
                guard let record = app.selfTests[test.id] else { return nil }
                return (test, record)
            }
            .max { $0.record.takenAt < $1.record.takenAt }
    }

    var body: some View {
        NavigationStack {
            profileContent
        }
    }

    private var profileContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                pageHeader

                settingsSection("settings") {
                    Button { showReminder = true } label: {
                        settingsValueRow(icon: "bell.fill",
                                         tint: .witsSky,
                                         title: "daily reminder",
                                         value: reminderStatusLabel,
                                         showsChevron: true)
                    }
                    .buttonStyle(.plain)
                    settingsDivider
                    settingsToggleRow(icon: "speaker.wave.2.fill",
                                      tint: .witsViolet,
                                      title: "sound effects",
                                      isOn: $soundEffectsEnabled)
                    settingsDivider
                    settingsToggleRow(icon: "hand.tap.fill",
                                      tint: .witsWarm,
                                      title: "haptics",
                                      isOn: $hapticsEnabled)
                }

                testsSection

                settingsSection("wits") {
                    settingsValueRow(icon: "person.fill",
                                     tint: .witsAccent,
                                     title: "account",
                                     value: accountStatus)
                    settingsDivider
                    settingsValueRow(icon: "creditcard.fill",
                                     tint: .witsGold,
                                     title: "plan",
                                     value: entitlementLabel)
                    settingsDivider
                    Button {
                        hasCompletedOnboarding = false
                    } label: {
                        settingsValueRow(icon: "arrow.clockwise",
                                         tint: .witsViolet,
                                         title: "replay onboarding",
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
                                         tint: .witsWarm,
                                         title: "sign out",
                                         value: "")
                    }
                    .buttonStyle(.plain)
                }

                Text("you're using \(entitlementLabel).")
                    .font(.witsBody(14))
                    .foregroundStyle(Color.witsFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
                    .padding(.bottom, 60)
            }
        }
        .background(Color.witsBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
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
            Text("hi \(displayName)")
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

    private var testsSection: some View {
        NavigationLink {
            SelfTestListView()
        } label: {
            testsSummaryCard
        }
        .buttonStyle(.plain)
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 24)
    }

    private var testsSummaryCard: some View {
        let shape = RoundedRectangle(cornerRadius: WitsMetrics.panelRadius, style: .continuous)
        let hasArt = UIImage(named: "selftest-profile-card") != nil
        // The illustration's own background color, used to scrim the text side.
        let artBg = Color(red: 0x0C / 255.0, green: 0x15 / 255.0, blue: 0x35 / 255.0)

        return HStack(alignment: .center, spacing: 14) {
            if !hasArt {
                Image(systemName: latestSelfTest?.test.icon ?? "list.clipboard.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.witsAccent)
                    .frame(width: 44, height: 44)
                    .background(Color.witsAccent.opacity(0.15), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }

            Text("self-assessments")
                .font(.witsHeading(hasArt ? 18 : 16.5))
                .foregroundStyle(hasArt ? .white : Color.witsInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hasArt ? .white.opacity(0.85) : Color.witsAccent)
        }
        .padding(16)
        .frame(height: hasArt ? 118 : nil)
        .background {
            if hasArt {
                Color.clear
                    .overlay {
                        Image("selftest-profile-card")
                            .resizable()
                            .scaledToFill()
                    }
                    .overlay {
                        LinearGradient(stops: [
                            .init(color: artBg.opacity(0.94), location: 0),
                            .init(color: artBg.opacity(0.55), location: 0.42),
                            .init(color: artBg.opacity(0), location: 0.72),
                        ], startPoint: .leading, endPoint: .trailing)
                    }
            } else {
                LinearGradient(colors: [
                    Color.witsAccent.opacity(0.16),
                    Color.witsSky.opacity(0.08),
                    Color.witsCard,
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.witsAccent.opacity(0.28), lineWidth: 1))
        .shadow(color: Color.witsAccent.opacity(0.22), radius: 13, y: 5)
        .accessibilityElement(children: .combine)
    }

    private func settingsSection<Content: View>(_ title: String,
                                                @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.witsLabel(12.5))
                .foregroundStyle(Color.witsFaint)
                .textCase(.uppercase)
                .kerning(0.8)
                .padding(.horizontal, WitsMetrics.screenPadding + 16)
                .padding(.top, 24)
                .padding(.bottom, 10)

            VStack(spacing: 0) {
                content()
            }
            .cardSurface(radius: WitsMetrics.panelRadius)
            .padding(.horizontal, WitsMetrics.screenPadding)
        }
    }

    private func settingsIcon(_ icon: String, tint: Color, dimmed: Bool = false) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(
                dimmed
                    ? AnyShapeStyle(Color.witsFaint)
                    : AnyShapeStyle(LinearGradient(colors: [tint.opacity(0.85), tint],
                                                   startPoint: .top, endPoint: .bottom)),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }

    private func settingsToggleRow(icon: String,
                                   tint: Color,
                                   title: String,
                                   isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            settingsIcon(icon, tint: tint)

            Text(title)
                .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.witsInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)

            Spacer(minLength: 12)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color.witsAccent)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private func settingsValueRow(icon: String,
                                  tint: Color,
                                  title: String,
                                  value: String,
                                  isDimmed: Bool = false,
                                  showsChevron: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 14) {
            settingsIcon(icon, tint: tint, dimmed: isDimmed)

            Text(title)
                .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                .foregroundStyle(isDimmed ? Color.witsFaint : Color.witsInk)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .layoutPriority(1)

            Spacer(minLength: 8)

            if !value.isEmpty {
                Text(value)
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(isDimmed ? Color.witsFaint : Color.witsMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.trailing)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.witsFaint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private var settingsDivider: some View {
        Rectangle()
            .fill(Color.witsLine)
            .frame(height: 1)
            .padding(.leading, 60)
    }

    private func syncGameFeelSettings() {
        GameFeel.shared.soundEnabled = soundEffectsEnabled
        GameFeel.shared.hapticsEnabled = hapticsEnabled
        if !soundEffectsEnabled {
            GameFeel.shared.teardown()
        }
    }
}
