//
//  PaywallView.swift
//  wits
//
//  Placeholder paywall. Subscriptions will be handled by RevenueCat — for now
//  this is a non-blocking screen: closing it leaves the user with full access.
//  The gate is disabled via EntitlementEngine.paywallEnabled, so this isn't
//  presented automatically yet; it's here to wire RevenueCat into later.
//

import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    var dismissable = true

    var body: some View {
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
                    .font(.system(size: 42, weight: .heavy))
                    .foregroundStyle(Color.witsAccent)
                Text("wits premium")
                    .font(.witsDisplay(30))
                    .foregroundStyle(Color.witsInk)
                Text("subscriptions are coming soon. for now, everything's unlocked — enjoy full access.")
                    .font(.witsBody(15.5))
                    .foregroundStyle(Color.witsMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .cardSurface()
            Spacer()
            Cta(title: "continue") { dismiss() }
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 14)
        .background(Color.witsBg.ignoresSafeArea())
    }
}
