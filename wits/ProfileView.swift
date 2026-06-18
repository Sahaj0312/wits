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
    @State private var showFriends = false
    @State private var showName = false

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
                Text("you")
                    .font(.witsDisplay(30))
                    .foregroundStyle(Color.witsInk)
                    .padding(.top, 8)

                HStack(spacing: 12) {
                    stat(value: "\(app.streak.current)", label: "current streak")
                    stat(value: "\(app.streak.longest)", label: "longest")
                    stat(value: "\(app.streak.freezes)", label: "freezes")
                }

                Button { showName = true } label: {
                    infoRow(icon: "person.fill", title: "your name",
                            value: app.profile.displayName?.isEmpty == false ? app.profile.displayName! : "add")
                }
                .buttonStyle(.plain)
                Button { showReminder = true } label: {
                    infoRow(icon: "bell.fill", title: "daily reminder", value: reminderLabel)
                }
                .buttonStyle(.plain)
                infoRow(icon: "creditcard.fill", title: "plan", value: entitlementLabel)
                Button { showFriends = true } label: {
                    infoRow(icon: "person.2.fill", title: "friends", value: app.friends.isEmpty ? "add" : "\(app.friends.count)")
                }
                .buttonStyle(.plain)

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
        .sheet(isPresented: $showFriends) {
            FriendsSheet()
        }
        .sheet(isPresented: $showName) {
            NameSettingsSheet()
                .presentationDetents([.height(240)])
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

/// Small editor for the user's display name — the name friends see in the ranking.
struct NameSettingsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("your name")
                .font(.witsDisplay(24))
                .foregroundStyle(Color.witsInk)
            Text("this is what your friends see next to your score.")
                .font(.witsBody(13.5))
                .foregroundStyle(Color.witsMuted)

            TextField("your name", text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(Color.witsTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                Task { await save() }
            } label: {
                Text(working ? "…" : "save")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.witsAccent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(WitsMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.witsBg.ignoresSafeArea())
        .onAppear { name = app.profile.displayName ?? "" }
    }

    private func save() async {
        working = true
        await app.setDisplayName(name)
        working = false
        dismiss()
    }
}
