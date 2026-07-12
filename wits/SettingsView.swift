//
//  SettingsView.swift
//  wits
//
//  Settings sheet: feel toggles, Game Center, and the ad-free subscription.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("wits.soundEffectsEnabled") private var soundEffectsEnabled = true
    @AppStorage("wits.hapticsEnabled") private var hapticsEnabled = true
    @State private var showPaywall = false
    @State private var restoreMessage: String?
    @State private var restoring = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                pageHeader

                settingsSection("game feel") {
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

                if GameCenterManager.isEnabled {
                    settingsSection("game center") {
                        Button {
                            if GameCenterManager.shared.isAuthenticated {
                                GameCenterManager.shared.presentDashboard()
                            } else {
                                GameCenterManager.shared.authenticate()
                            }
                        } label: {
                            settingsValueRow(icon: "trophy.fill",
                                             tint: .witsGold,
                                             title: "leaderboards & achievements",
                                             value: GameCenterManager.shared.isAuthenticated ? "" : "sign in",
                                             showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    }
                }

                settingsSection("subscription") {
                    if PurchasesManager.shared.isAdFree {
                        settingsValueRow(icon: "checkmark.seal.fill",
                                         tint: .witsAccent,
                                         title: "ad-free",
                                         value: "active")
                    } else {
                        Button { showPaywall = true } label: {
                            settingsValueRow(icon: "sparkles",
                                             tint: .witsAccent,
                                             title: "remove ads",
                                             value: "",
                                             showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    }
                    settingsDivider
                    Button {
                        restorePurchases()
                    } label: {
                        settingsValueRow(icon: "arrow.clockwise",
                                         tint: .witsSky,
                                         title: "restore purchases",
                                         value: restoring ? "…" : "")
                    }
                    .buttonStyle(.plain)
                    .disabled(restoring)
                }

                if let restoreMessage {
                    Text(restoreMessage)
                        .font(.witsBody(14))
                        .foregroundStyle(Color.witsMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                }

                Text("wits · made for quick daily play")
                    .font(.witsBody(14))
                    .foregroundStyle(Color.witsFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
                    .padding(.bottom, 60)
            }
        }
        .background(Color.witsBg.ignoresSafeArea())
        .fullScreenCover(isPresented: $showPaywall) { PaywallView() }
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
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                WitsBrandMark()
                Text("settings")
                    .font(.witsDisplay(30))
                    .foregroundStyle(Color.witsInk)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color.witsMuted)
                    .frame(width: 38, height: 38)
                    .background(Color.witsCard, in: Circle())
                    .overlay(Circle().strokeBorder(Color.witsLine, lineWidth: 1))
            }
            .buttonStyle(PressScale())
            .accessibilityLabel("Close settings")
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    private func restorePurchases() {
        restoring = true
        restoreMessage = nil
        Task {
            defer { restoring = false }
            do {
                let restored = try await PurchasesManager.shared.restore()
                restoreMessage = restored ? "purchases restored." : "no purchases to restore."
            } catch {
                restoreMessage = "restore failed — try again later."
            }
        }
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
