//
//  PurchasesManager.swift
//  wits
//
//  StoreKit 2 wrapper for the one-time ad-free unlock. Apple owns product
//  loading, purchase confirmation, verification, restoration, and refunds.
//  A cached entitlement prevents ads flashing during an offline cold launch;
//  StoreKit's signed current entitlements remain the source of truth.
//

import Foundation
import Observation
import StoreKit

@Observable
@MainActor
final class PurchasesManager {
    static let shared = PurchasesManager()

    /// Must exactly match the non-consumable product ID in App Store Connect.
    static let adFreeLifetimeProductID = "com.sahaj03.wits.lifetime"

    private static let cachedAdFreeKey = "wits.purchases.isAdFree"

    private(set) var isAdFree: Bool
    private(set) var adFreeProduct: Product?
    private(set) var productLoadFailureReason: String?
    @ObservationIgnored private var transactionUpdates: Task<Void, Never>?

    private init() {
        isAdFree = UserDefaults.standard.bool(forKey: Self.cachedAdFreeKey)
    }

    /// Starts StoreKit observation once at app launch and refreshes the local
    /// product plus the signed entitlement state.
    func start() {
        guard transactionUpdates == nil else { return }

        transactionUpdates = Task { [weak self] in
            guard let self else { return }
            for await update in StoreKit.Transaction.updates {
                if case .verified(let transaction) = update,
                   transaction.productID == Self.adFreeLifetimeProductID {
                    await transaction.finish()
                }
                await refreshEntitlements()
            }
        }

        Task {
            _ = await adFreeLifetimeProduct()
            await refreshEntitlements()
        }
    }

    /// Loads Apple's non-consumable product and caches it for both paywalls.
    func adFreeLifetimeProduct() async -> Product? {
        if let adFreeProduct { return adFreeProduct }

        productLoadFailureReason = nil

        do {
            let products = try await Product.products(for: [Self.adFreeLifetimeProductID])
            let product = products.first { $0.id == Self.adFreeLifetimeProductID }
            adFreeProduct = product

            if product == nil {
                let failure = "The App Store returned no product for ID \(Self.adFreeLifetimeProductID)."
                productLoadFailureReason = failure
#if DEBUG
                print("[StoreKit] \(failure) bundle=\(Bundle.main.bundleIdentifier ?? "unknown")")
#endif
            }

            return product
        } catch {
            productLoadFailureReason = error.localizedDescription
#if DEBUG
            print("[StoreKit] Product load failed: \(error.localizedDescription)")
#endif
            return nil
        }
    }

    /// Starts Apple's purchase sheet. User cancellation and Ask to Buy pending
    /// states return false without being presented as errors.
    func purchase(_ product: Product) async throws -> Bool {
        switch try await product.purchase() {
        case .success(let verification):
            let transaction = try verified(verification)
            await transaction.finish()
            await refreshEntitlements()
            return isAdFree

        case .userCancelled, .pending:
            return false

        @unknown default:
            return false
        }
    }

    /// Shows Apple's sign-in/sync flow, then checks signed entitlements again.
    func restore() async throws -> Bool {
        try await AppStore.sync()
        await refreshEntitlements()
        return isAdFree
    }

    func refreshEntitlements() async {
        var ownsUnlock = false

        for await entitlement in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            guard transaction.productID == Self.adFreeLifetimeProductID else { continue }
            ownsUnlock = transaction.revocationDate == nil
        }

        isAdFree = ownsUnlock
        UserDefaults.standard.set(ownsUnlock, forKey: Self.cachedAdFreeKey)
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified(_, let error):
            throw error
        }
    }
}
