//
//  Store.swift
//  wits
//
//  StoreKit 2. Loads the subscription products, runs purchase/restore, listens
//  for transaction updates, and reports the active subscription expiry up to
//  AppModel (which mirrors it to profiles.subscription_until and recomputes the
//  entitlement gate).
//
//  To test in the simulator, attach Products.storekit to the run scheme
//  (Edit Scheme → Run → Options → StoreKit Configuration). In production the
//  product IDs resolve from App Store Connect.
//

import StoreKit

@Observable
@MainActor
final class Store {
    static let yearlyID = "com.sahaj03.wits.yearly"
    static let weeklyID = "com.sahaj03.wits.weekly"
    static var ids: [String] { [yearlyID, weeklyID] }

    private(set) var products: [Product] = []
    private(set) var subscriptionExpiry: Date?
    private(set) var loaded = false

    /// Reported whenever entitlement changes (expiry date, or nil if none).
    var onExpiry: ((Date?) -> Void)?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = listenForTransactions()
    }

    func load() async {
        if let p = try? await Product.products(for: Self.ids) {
            products = p.sorted { $0.price > $1.price }   // yearly (higher) first
        }
        loaded = true
        await refreshEntitlement()
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        guard let result = try? await product.purchase() else { return false }
        switch result {
        case .success(let verification):
            guard case .verified(let txn) = verification else { return false }
            await txn.finish()
            await refreshEntitlement()
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        var latest: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let txn) = result, Self.ids.contains(txn.productID) else { continue }
            let exp = txn.expirationDate ?? .distantFuture
            if latest == nil || exp > latest! { latest = exp }
        }
        subscriptionExpiry = latest
        onExpiry?(latest)
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let txn) = result else { continue }
                await txn.finish()
                await self?.refreshEntitlement()
            }
        }
    }
}
