//
//  SettingsView.swift
//  wits
//
//  Settings sheet: feel toggles and the lifetime ad-free unlock.
//

import SwiftUI
import StoreKit
import SafariServices
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @AppStorage("wits.soundEffectsEnabled") private var soundEffectsEnabled = true
    @AppStorage("wits.hapticsEnabled") private var hapticsEnabled = true
    @State private var notifications = NotificationManager.shared
    @State private var showPaywall = false
    @State private var showNotificationSettingsAlert = false
    @State private var supportPage: SupportPage?
    @State private var restoreMessage: String?
    @State private var restoring = false

    // The home screen's fixed dark chrome, not the adaptive wits palette ,
    // this sheet sits directly over the library and should read as one place.
    private let pageBg = Color(hexAny: 0x09090B)
    private let cardFill = Color(hexAny: 0x1B1B20)
    private let hairline = Color.white.opacity(0.10)

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

                settingsSection("notifications") {
                    settingsToggleRow(icon: "bell.fill",
                                      tint: .witsSky,
                                      title: "daily reminders",
                                      isOn: notificationToggle)
                }

                settingsSection("support") {
                    ShareLink(item: shareMessage) {
                        settingsValueRow(icon: "square.and.arrow.up",
                                         tint: .witsViolet,
                                         title: "share Wits",
                                         value: "",
                                         showsChevron: true)
                    }
                    .buttonStyle(TactilePressScale(feedback: .selection))

                    settingsDivider

                    Button {
                        GameFeel.shared.uiPrimary()
                        requestReview()
                    } label: {
                        settingsValueRow(icon: "star.fill",
                                         tint: .witsGold,
                                         title: "rate us",
                                         value: "",
                                         showsChevron: true)
                    }
                    .buttonStyle(.plain)

                    settingsDivider

                    Button {
                        GameFeel.shared.uiTap()
                        emailSupport()
                    } label: {
                        settingsValueRow(icon: "envelope.fill",
                                         tint: .witsSky,
                                         title: "email support",
                                         value: "",
                                         showsChevron: true)
                    }
                    .buttonStyle(.plain)
                }

                settingsSection("about") {
                    Button {
                        supportPage = .faq
                    } label: {
                        settingsValueRow(icon: "questionmark.circle.fill",
                                         tint: .witsAccent,
                                         title: "FAQ",
                                         value: "",
                                         showsChevron: true)
                    }
                    .buttonStyle(TactilePressScale(feedback: .selection))

                    settingsDivider

                    Button {
                        supportPage = .privacy
                    } label: {
                        settingsValueRow(icon: "hand.raised.fill",
                                         tint: .witsPink,
                                         title: "privacy policy",
                                         value: "",
                                         showsChevron: true)
                    }
                    .buttonStyle(TactilePressScale(feedback: .selection))

                    settingsDivider

                    Button {
                        supportPage = .terms
                    } label: {
                        settingsValueRow(icon: "doc.text.fill",
                                         tint: .witsWarm,
                                         title: "terms of service",
                                         value: "",
                                         showsChevron: true)
                    }
                    .buttonStyle(TactilePressScale(feedback: .selection))
                }

                settingsSection("ad-free") {
                    if PurchasesManager.shared.isAdFree {
                        settingsValueRow(icon: "checkmark.seal.fill",
                                         tint: .witsAccent,
                                         title: "ad-free",
                                         value: "active")
                    } else {
                        Button {
                            GameFeel.shared.uiTap()
                            showPaywall = true
                        } label: {
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
                        GameFeel.shared.uiPrimary()
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
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                }

                Text("wits · made for quick daily play")
                    .font(.witsBody(14))
                    .foregroundStyle(.white.opacity(0.32))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
                    .padding(.bottom, 60)
            }
        }
        .background(pageBg.ignoresSafeArea())
        .fullScreenCover(isPresented: $showPaywall) { PaywallView() }
        .sheet(item: $supportPage) { page in
            SupportBrowser(url: page.url)
                .ignoresSafeArea()
        }
        .alert("notifications are off", isPresented: $showNotificationSettingsAlert) {
            Button("not now", role: .cancel) {}
            Button("open settings") { openSystemSettings() }
        } message: {
            Text("allow notifications in iOS Settings to turn on your daily Wits reminder.")
        }
        .onAppear {
            syncGameFeelSettings()
            Task { await notifications.appBecameActive(streak: app.streak) }
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
            VStack(alignment: .leading, spacing: 6) {
                Text("settings")
                    .font(.system(size: 29, weight: .black, design: .default))
                    .foregroundStyle(.white)
                Rectangle()
                    .fill(Color.witsAccent)
                    .frame(width: 30, height: 4)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(cardFill, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(TactilePressScale())
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
                restoreMessage = "restore failed. try again later."
            }
        }
    }

    private var shareMessage: String {
        "I’ve been playing Wits, a collection of quick brain games for memory, logic, words, maths, and focus. Give it a try!"
    }

    private func emailSupport() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "sahajchhabra03@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Wits Support"),
            URLQueryItem(name: "body", value: supportEmailDetails)
        ]
        guard let url = components.url else { return }
        openURL(url)
    }

    private var supportEmailDetails: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return "\n\nWits version \(version) (\(build))\niOS \(UIDevice.current.systemVersion)"
    }

    private func settingsSection<Content: View>(_ title: String,
                                                @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.witsLabel(12.5))
                .foregroundStyle(.white.opacity(0.45))
                .textCase(.uppercase)
                .kerning(0.8)
                .padding(.horizontal, WitsMetrics.screenPadding + 16)
                .padding(.top, 24)
                .padding(.bottom, 10)

            VStack(spacing: 0) {
                content()
            }
            .background(cardFill,
                        in: RoundedRectangle(cornerRadius: WitsMetrics.panelRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: WitsMetrics.panelRadius, style: .continuous)
                    .strokeBorder(hairline, lineWidth: 1)
            )
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
                    ? AnyShapeStyle(Color.white.opacity(0.22))
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
                .foregroundStyle(.white)
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
                .foregroundStyle(isDimmed ? .white.opacity(0.35) : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .layoutPriority(1)

            Spacer(minLength: 8)

            if !value.isEmpty {
                Text(value)
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(isDimmed ? 0.35 : 0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.trailing)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private var notificationToggle: Binding<Bool> {
        Binding(get: { notifications.isEnabled },
                set: { requested in
                    Task {
                        let enabled = await notifications.setEnabled(requested, streak: app.streak)
                        if requested, !enabled, notifications.authorizationStatus == .denied {
                            showNotificationSettingsAlert = true
                        }
                    }
                })
    }

    private var settingsDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 60)
    }

    private func syncGameFeelSettings() {
        GameFeel.shared.soundEnabled = soundEffectsEnabled
        GameFeel.shared.hapticsEnabled = hapticsEnabled
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private enum SupportPage: String, Identifiable {
    case faq
    case privacy
    case terms

    var id: String { rawValue }

    var url: URL {
        URL(string: "https://sahaj0312.github.io/wits-support/\(rawValue)/")!
    }
}

private struct SupportBrowser: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator { dismiss() }
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.barCollapsingEnabled = true
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.delegate = context.coordinator
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        private let onDone: () -> Void

        init(onDone: @escaping () -> Void) {
            self.onDone = onDone
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onDone()
        }
    }
}
