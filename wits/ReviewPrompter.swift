//
//  ReviewPrompter.swift
//  wits
//
//  Queues an App Store review after a finished game, then asks only once the
//  player returns to the home library. Apple never reports whether the user
//  actually reviewed (or even saw the prompt), so the schedule assumes "not
//  reviewed yet" and simply re-asks with spacing: the first game ever
//  finished, then at most once a day on the first eligible home return in a
//  fresh app session, up to 3 asks total (Apple's own yearly cap).
//
//  Deferring the request until home ensures a quick replay can never put the
//  system prompt over a game in progress.
//

import Foundation

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
    private static var requestPending = false

    /// Call once per finished game, any game. An eligible finish only queues
    /// the request; it never presents UI over a result or a replayed game.
    static func gameFinished(now: Date = Date()) {
        guard !askedThisSession, !requestPending else { return }
        let d = UserDefaults.standard
        let count = d.integer(forKey: countKey)
        guard count < maxRequests else { return }
        if let last = d.object(forKey: lastAskKey) as? Date,
           now.timeIntervalSince(last) < minSecondsBetweenRequests { return }

        requestPending = true
    }

    /// Called by the home library after its game cover has fully dismissed.
    /// Returns true exactly once when the caller should invoke requestReview.
    static func takePendingRequest(now: Date = Date()) -> Bool {
        guard requestPending, !askedThisSession else { return false }
        let d = UserDefaults.standard
        let count = d.integer(forKey: countKey)
        guard count < maxRequests else {
            requestPending = false
            return false
        }
        if let last = d.object(forKey: lastAskKey) as? Date,
           now.timeIntervalSince(last) < minSecondsBetweenRequests { return false }

        requestPending = false
        askedThisSession = true
        d.set(count + 1, forKey: countKey)
        d.set(now, forKey: lastAskKey)
        return true
    }
}
