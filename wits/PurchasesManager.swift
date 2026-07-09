//
//  PurchasesManager.swift
//  wits
//
//  RevenueCat wrapper for the single "ad_free" monthly subscription.
//  The last-known entitlement is cached in UserDefaults so an offline cold
//  start never flashes ads at a subscriber.
//

import Foundation
import Observation
import RevenueCat

@Observable
@MainActor
final class PurchasesManager {
    static let shared = PurchasesManager()

    static let entitlementID = "ad_free"
    /// RevenueCat public Apple API key (safe to ship in the binary).
    private static let apiKey = "appl_REPLACE_WITH_REVENUECAT_KEY"
    private static let cachedAdFreeKey = "wits.purchases.isAdFree"

    private(set) var isAdFree: Bool

    private init() {
        isAdFree = UserDefaults.standard.bool(forKey: Self.cachedAdFreeKey)
    }

    func configure() {
        guard !Self.apiKey.contains("REPLACE") else { return }   // not wired to a RC project yet
        Purchases.configure(withAPIKey: Self.apiKey)
        Task {
            for await info in Purchases.shared.customerInfoStream {
                apply(info)
            }
        }
    }

    var isConfigured: Bool { Purchases.isConfigured }

    func currentOffering() async -> Offering? {
        guard isConfigured else { return nil }
        return try? await Purchases.shared.offerings().current
    }

    /// Restore purchases; returns true when the ad-free entitlement came back.
    func restore() async throws -> Bool {
        guard isConfigured else { return false }
        let info = try await Purchases.shared.restorePurchases()
        apply(info)
        return isAdFree
    }

    private func apply(_ info: CustomerInfo) {
        let active = info.entitlements[Self.entitlementID]?.isActive == true
        isAdFree = active
        UserDefaults.standard.set(active, forKey: Self.cachedAdFreeKey)
    }
}
