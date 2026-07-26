//
//  ReviewPrompter.swift
//  wits
//
//  Queues an App Store review after a finished game, then asks only once the
//  player returns to the home library. Apple never reports whether the user
//  actually reviewed (or even saw the prompt), so the schedule assumes "not
//  reviewed yet" and simply re-asks with spacing. The first automatic request
//  requires five finished games and at least a full day since first use. Later
//  requests happen only on an eligible home return in a fresh app session, up
//  to 3 asks total (Apple's own yearly cap).
//
//  Deferring the request until home ensures a quick replay can never put the
//  system prompt over a game in progress.
//

import Foundation

struct ReviewPromptPolicy {
    static let minimumFinishedGames = 5
    static let minimumFirstUseAge: TimeInterval = 24 * 60 * 60

    static func hasEnoughEngagement(finishedGames: Int,
                                    firstUseAt: Date?,
                                    now: Date) -> Bool {
        guard finishedGames >= minimumFinishedGames,
              let firstUseAt else { return false }
        return now.timeIntervalSince(firstUseAt) >= minimumFirstUseAge
    }
}

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
    private static let firstUseKey = "wits.review.firstUseAt"
    private static let finishedGamesKey = "wits.review.finishedGames"

    private static var askedThisSession = false
    private static var requestPending = false

    /// Records the first time the main app experience appears. Existing users
    /// upgrading from an older build begin the waiting period on that update,
    /// which also prevents an immediate review request after installation.
    static func appStarted(now: Date = Date(),
                           defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: firstUseKey) == nil else { return }
        defaults.set(now, forKey: firstUseKey)
    }

    /// Call once per finished game, any game. An eligible finish only queues
    /// the request; it never presents UI over a result or a replayed game.
    static func gameFinished(now: Date = Date(),
                             defaults: UserDefaults = .standard) {
        appStarted(now: now, defaults: defaults)

        let finishedGames = defaults.integer(forKey: finishedGamesKey) + 1
        defaults.set(finishedGames, forKey: finishedGamesKey)

        let firstUseAt = defaults.object(forKey: firstUseKey) as? Date
        guard ReviewPromptPolicy.hasEnoughEngagement(finishedGames: finishedGames,
                                                     firstUseAt: firstUseAt,
                                                     now: now) else { return }
        guard !askedThisSession, !requestPending else { return }
        let count = defaults.integer(forKey: countKey)
        guard count < maxRequests else { return }
        if let last = defaults.object(forKey: lastAskKey) as? Date,
           now.timeIntervalSince(last) < minSecondsBetweenRequests { return }

        requestPending = true
    }

    /// Called by the home library after its game cover has fully dismissed.
    /// Returns true exactly once when the caller should invoke requestReview.
    static func takePendingRequest(now: Date = Date(),
                                   defaults: UserDefaults = .standard) -> Bool {
        guard requestPending, !askedThisSession else { return false }
        let finishedGames = defaults.integer(forKey: finishedGamesKey)
        let firstUseAt = defaults.object(forKey: firstUseKey) as? Date
        guard ReviewPromptPolicy.hasEnoughEngagement(finishedGames: finishedGames,
                                                     firstUseAt: firstUseAt,
                                                     now: now) else {
            requestPending = false
            return false
        }

        let count = defaults.integer(forKey: countKey)
        guard count < maxRequests else {
            requestPending = false
            return false
        }
        if let last = defaults.object(forKey: lastAskKey) as? Date,
           now.timeIntervalSince(last) < minSecondsBetweenRequests { return false }

        requestPending = false
        askedThisSession = true
        defaults.set(count + 1, forKey: countKey)
        defaults.set(now, forKey: lastAskKey)
        return true
    }

    /// Keeps the persistent policy state intact while isolating unit tests
    /// from the process-wide per-session guards.
    static func resetSessionStateForTesting() {
        askedThisSession = false
        requestPending = false
    }
}
