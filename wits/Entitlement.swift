//
//  Entitlement.swift
//  wits
//
//  Trial / subscription model. The 3-day trial clock starts when onboarding
//  completes (stamped on profiles.trial_started_at). Enforcement (routing the
//  expired user to the paywall) is wired in Phase 3 alongside StoreKit; this
//  type is modelled now so the rest of the app can read it.
//

import Foundation

enum Entitlement: Equatable {
    case unknown
    case trial(endsAt: Date)
    case subscribed(until: Date)
    case expired

    var allowsTraining: Bool {
        switch self {
        case .trial, .subscribed: true
        case .unknown, .expired: false
        }
    }

    var isExpired: Bool { self == .expired }

    /// Whole days left in the trial (0 if not on trial).
    var trialDaysLeft: Int {
        guard case let .trial(endsAt) = self else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: endsAt).day ?? 0
        return max(0, days + 1)
    }
}

enum EntitlementEngine {
    static let trialDays = 3

    static func evaluate(trialStartedAt: Date?, subscriptionUntil: Date?, now: Date = Date()) -> Entitlement {
        if let sub = subscriptionUntil, sub > now { return .subscribed(until: sub) }
        if let start = trialStartedAt {
            let end = Calendar.current.date(byAdding: .day, value: trialDays, to: start) ?? start
            return end > now ? .trial(endsAt: end) : .expired
        }
        return .unknown
    }
}
