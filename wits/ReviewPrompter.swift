//
//  ReviewPrompter.swift
//  wits
//
//  Asks for an App Store review right after a finished game, the moment the
//  player has just accomplished something. Apple never reports whether the
//  user actually reviewed (or even saw the prompt), so the schedule assumes
//  "not reviewed yet" and simply re-asks with spacing: the first game ever
//  finished, then at most once a day on the first game finished in a fresh
//  app session, up to 3 asks total (Apple's own yearly cap).
//
//  Asking only on a session's first finished game also keeps the prompt from
//  ever stacking with an interstitial, those need three finished games in a
//  session before they can show.
//

import StoreKit
import UIKit

@MainActor
enum ReviewPrompter {
    static let maxRequests = 3
    /// Re-ask spacing. Short in DEBUG so the flow can be exercised without
    /// waiting out the production cooldown.
    #if DEBUG
    static let minSecondsBetweenRequests: TimeInterval = 60
    #else
    static let minSecondsBetweenRequests: TimeInterval = 24 * 60 * 60
    #endif

    private static let countKey = "wits.review.requestCount"
    private static let lastAskKey = "wits.review.lastRequestAt"

    private static var askedThisSession = false

    /// Call once per finished game, any game. No-ops itself down to at most
    /// one system prompt per session / day / lifetime cap.
    static func gameFinished(now: Date = Date()) {
        guard !askedThisSession else { return }
        let d = UserDefaults.standard
        let count = d.integer(forKey: countKey)
        guard count < maxRequests else { return }
        if let last = d.object(forKey: lastAskKey) as? Date,
           now.timeIntervalSince(last) < minSecondsBetweenRequests { return }

        askedThisSession = true
        d.set(count + 1, forKey: countKey)
        d.set(now, forKey: lastAskKey)
        Task {
            // Let the result card settle before the system sheet slides up.
            try? await Task.sleep(for: .seconds(1.2))
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else { return }
            AppStore.requestReview(in: scene)
        }
    }
}
