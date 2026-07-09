//
//  PaywallView.swift
//  wits
//
//  The ad-free subscription paywall. Renders RevenueCat's remotely configured
//  paywall when an offering is available; falls back to a friendly placeholder
//  while the RevenueCat project isn't wired up (e.g. dev builds).
//

import SwiftUI
import RevenueCat
import RevenueCatUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var offering: Offering?
    @State private var loaded = false

    var body: some View {
        Group {
            if let offering {
                RevenueCatUI.PaywallView(offering: offering)
                    .onPurchaseCompleted { _ in dismiss() }
                    .onRestoreCompleted { _ in dismiss() }
            } else if loaded {
                unavailableFallback
            } else {
                ZStack {
                    Color.witsBg.ignoresSafeArea()
                    ProgressView()
                }
            }
        }
        .task {
            offering = await PurchasesManager.shared.currentOffering()
            loaded = true
        }
    }

    /// Shown when no offering could be loaded (offline, or RC not configured).
    private var unavailableFallback: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Wordmark()
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Color.witsFaint)
                }
            }
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(
                        LinearGradient(colors: [.witsAccent, .witsSky],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: WitsMetrics.panelRadius, style: .continuous)
                    )
                    .shadow(color: Color.witsAccent.opacity(0.4), radius: 12, y: 6)
                Text("go ad-free")
                    .font(.witsDisplay(30))
                    .foregroundStyle(Color.witsInk)
                Text("the ad-free subscription isn't available right now. check your connection and try again.")
                    .font(.witsBody(15.5))
                    .foregroundStyle(Color.witsMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .cardSurface(radius: WitsMetrics.panelRadius, elevation: .hero)
            Spacer()
            Cta(title: "close") { dismiss() }
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 14)
        .background(Color.witsBg.ignoresSafeArea())
    }
}
