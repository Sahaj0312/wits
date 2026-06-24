//
//  ProfileView.swift
//  wits
//
//  Streak, reminder, subscription status, and account actions.
//

import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(SupabaseManager.self) private var supa
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showReminder = false

    private var entitlementLabel: String {
        switch app.entitlement {
        case .unknown: "—"
        case .trial: "\(app.entitlement.trialDaysLeft)-day trial"
        case .subscribed: "full access"
        case .expired: "trial ended"
        }
    }

    private var reminderLabel: String {
        guard let h = app.profile.reminderHour else { return "off" }
        let m = app.profile.reminderMinute
        let suffix = h < 12 ? "am" : "pm"
        let hour12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", hour12, m, suffix)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    WitsBrandMark()
                    Text(app.profile.displayName?.isEmpty == false ? app.profile.displayName! : "you")
                        .font(.witsDisplay(30))
                        .foregroundStyle(Color.witsInk)
                }
                .padding(.top, 8)

                HStack(spacing: 12) {
                    stat(value: "\(app.streak.current)", label: "current streak")
                    stat(value: "\(app.streak.longest)", label: "longest")
                }

                Button { showReminder = true } label: {
                    infoRow(icon: "bell.fill", title: "daily reminder", value: reminderLabel)
                }
                .buttonStyle(.plain)
                infoRow(icon: "creditcard.fill", title: "plan", value: entitlementLabel)

                Button {
                    supa.signOut()
                    hasCompletedOnboarding = false
                } label: {
                    Text("sign out")
                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.witsWarm)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .cardSurface()
                }
                .buttonStyle(.plain)
                .padding(.top, 8)

                QuietButton(title: "replay onboarding") {
                    hasCompletedOnboarding = false
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, WitsMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .background(Color.witsBg.ignoresSafeArea())
        .sheet(isPresented: $showReminder) {
            ReminderSettingsSheet(app: app)
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.witsAccent)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.witsMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .cardSurface()
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Color.witsAccent)
                .frame(width: 38, height: 38)
                .background(Color.witsAccent.opacity(0.14), in: Circle())
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.witsInk)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.witsMuted)
        }
        .padding(14)
        .cardSurface()
    }
}
