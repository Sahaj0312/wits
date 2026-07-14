//
//  AdFreeOfferView.swift
//  wits
//
//  Post-interstitial upsell: a one-time purchase that removes ads forever.
//  AdFreeOfferGate decides when the offer is due (every few interstitials,
//  at most once a day); AdManager presents this page from the top view
//  controller the moment such an interstitial is dismissed, so the pitch
//  always lands directly behind the ad that motivates it.
//

import SwiftUI
import RevenueCat

// MARK: - When to show it

/// The offer only ever appears right after an interstitial, and only when the
/// player has sat through a few of them since the last pitch — the moment the
/// value of paying is most concrete, without nagging every single ad.
enum AdFreeOfferGate {
    /// Interstitials the player must watch between offers.
    static let interstitialsPerOffer = 2
    /// Never pitch more than once a day. Short in DEBUG so the flow can be
    /// exercised repeatedly without waiting out the production cooldown.
    #if DEBUG
    static let minSecondsBetweenOffers: TimeInterval = 60
    #else
    static let minSecondsBetweenOffers: TimeInterval = 24 * 60 * 60
    #endif

    private static let countKey = "wits.adFreeOffer.interstitialsSinceOffer"
    private static let lastShownKey = "wits.adFreeOffer.lastShownAt"

    static func recordInterstitialShown() {
        let d = UserDefaults.standard
        d.set(d.integer(forKey: countKey) + 1, forKey: countKey)
    }

    static func shouldOfferNow(isAdFree: Bool, now: Date = Date()) -> Bool {
        guard !isAdFree else { return false }
        let d = UserDefaults.standard
        guard d.integer(forKey: countKey) >= interstitialsPerOffer else { return false }
        if let last = d.object(forKey: lastShownKey) as? Date,
           now.timeIntervalSince(last) < minSecondsBetweenOffers { return false }
        return true
    }

    static func recordOfferShown(now: Date = Date()) {
        let d = UserDefaults.standard
        d.set(0, forKey: countKey)
        d.set(now, forKey: lastShownKey)
    }
}

// MARK: - The page

struct AdFreeOfferView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var package: Package?
    @State private var loaded = false
    @State private var purchasing = false
    @State private var note: String?

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
                Image(systemName: "rectangle.badge.xmark")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(
                        LinearGradient(colors: [.witsAccent, .witsSky],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: WitsMetrics.panelRadius, style: .continuous)
                    )
                    .shadow(color: Color.witsAccent.opacity(0.4), radius: 12, y: 6)
                Text("remove ads forever")
                    .font(.witsDisplay(30))
                    .foregroundStyle(Color.witsInk)
                    .multilineTextAlignment(.center)
                Text("one purchase, yours for life — no subscription.")
                    .font(.witsBody(15.5))
                    .foregroundStyle(Color.witsMuted)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 10) {
                    benefit("no more ads between games")
                    benefit("pay once — never again")
                    benefit("every future game included")
                }
                .padding(.top, 6)

                if let note {
                    Text(note)
                        .font(.witsBody(13))
                        .foregroundStyle(Color.witsFaint)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .cardSurface(radius: WitsMetrics.panelRadius, elevation: .hero)
            .rise()

            Spacer()

            Cta(title: ctaTitle, dimmed: purchasing || (loaded && package == nil)) { buy() }
            HStack {
                QuietButton(title: "restore purchase") { restore() }
                Spacer()
                QuietButton(title: "no thanks") { dismiss() }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, WitsMetrics.screenPadding)
        .padding(.vertical, 14)
        .background(Color.witsBg.ignoresSafeArea())
        .task {
            package = await PurchasesManager.shared.adFreeLifetimePackage()
            loaded = true
            if loaded, package == nil {
                note = "the one-time purchase isn't available right now."
            }
        }
    }

    private var ctaTitle: String {
        if purchasing { return "one moment…" }
        if let price = package?.localizedPriceString { return "go ad-free · \(price)" }
        return "go ad-free"
    }

    private func benefit(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.witsAccent)
            Text(text)
                .font(.witsBody(15))
                .foregroundStyle(Color.witsInk)
        }
    }

    private func buy() {
        guard let package, !purchasing else { return }
        purchasing = true
        note = nil
        Task {
            defer { purchasing = false }
            do {
                if try await PurchasesManager.shared.purchase(package) {
                    dismiss()
                }
                // A false return with no error is a user cancel — stay quiet.
            } catch {
                note = "the purchase didn't complete. you haven't been charged."
            }
        }
    }

    private func restore() {
        guard !purchasing else { return }
        note = nil
        Task {
            if (try? await PurchasesManager.shared.restore()) == true {
                dismiss()
            } else {
                note = "no previous purchase found."
            }
        }
    }
}
