//
//  AdFreeOfferGate.swift
//  wits
//
//  Controls how often the ad-free paywall appears after an interstitial.
//

import Foundation

/// The offer only ever appears right after an interstitial, and only when the
/// player has sat through a few of them since the last pitch.
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
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: countKey) + 1, forKey: countKey)
    }

    static func shouldOfferNow(isAdFree: Bool, now: Date = Date()) -> Bool {
        guard !isAdFree else { return false }
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: countKey) >= interstitialsPerOffer else { return false }
        if let lastShownAt = defaults.object(forKey: lastShownKey) as? Date,
           now.timeIntervalSince(lastShownAt) < minSecondsBetweenOffers {
            return false
        }
        return true
    }

    static func recordOfferShown(now: Date = Date()) {
        let defaults = UserDefaults.standard
        defaults.set(0, forKey: countKey)
        defaults.set(now, forKey: lastShownKey)
    }
}
