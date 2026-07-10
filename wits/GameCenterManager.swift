//
//  GameCenterManager.swift
//  wits
//
//  Game Center: sign-in, Split's endless leaderboard, a total-stars
//  leaderboard, and run/streak achievements. Everything degrades silently
//  when the player is not signed in — the app never blocks on Game Center.
//
//  Leaderboard IDs (create these in App Store Connect; immutable once live):
//    wits.split.survival      split's best level reached
//    wits.stars.total         total stars across all games
//  Achievement IDs:
//    wits.ach.first3star                  first 3★ on any level
//    wits.ach.stars.50 / .150 / .300      star-total milestones
//    wits.ach.streak.7 / .30              longest-streak milestones
//

import GameKit
import Observation
import UIKit

@Observable
@MainActor
final class GameCenterManager {
    static let shared = GameCenterManager()

    private(set) var isAuthenticated = false
    /// Called on each successful sign-in; the app wires this to resubmit
    /// local bests so Game Center converges without a persistent queue.
    @ObservationIgnored var onAuthenticated: (() -> Void)?
    /// Achievement IDs already reported at 100% (re-reporting is harmless but
    /// noisy; this keeps the network quiet across runs).
    @ObservationIgnored private var reportedAchievements: Set<String>

    private static let reportedKey = "wits.gamecenter.reportedAchievements.v1"

    private init() {
        reportedAchievements = Set(UserDefaults.standard.stringArray(forKey: Self.reportedKey) ?? [])
    }

    // MARK: Auth

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            Task { @MainActor in
                guard let self else { return }
                if let viewController {
                    Self.topViewController()?.present(viewController, animated: true)
                    return
                }
                let wasAuthenticated = self.isAuthenticated
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                if self.isAuthenticated && !wasAuthenticated {
                    self.onAuthenticated?()
                }
            }
        }
    }

    /// The floating Game Center bubble on the home screen.
    func setAccessPointActive(_ active: Bool) {
        GKAccessPoint.shared.location = .topTrailing
        GKAccessPoint.shared.isActive = active && isAuthenticated
    }

    /// Open the Game Center overlay on the leaderboards page.
    func presentDashboard() {
        GKAccessPoint.shared.trigger(state: .leaderboards) {}
    }

    // MARK: Leaderboards

    static func leaderboardID(for game: GameID) -> String {
        game == .split ? "wits.split.survival" : "wits.marathon.\(game.rawValue)"
    }
    static let totalStarsLeaderboardID = "wits.stars.total"

    func submitMarathonBest(game: GameID, levels: LevelProgressStore) {
        guard isAuthenticated, let best = levels.marathonBest(for: game) else { return }
        // Split's headline number is the level reached. The non-Split branch
        // remains for decoding leaderboard bests created by older app builds.
        submit(game == .split ? best.depth : best.score, to: Self.leaderboardID(for: game))
    }

    private func submit(_ value: Int, to leaderboardID: String) {
        GKLeaderboard.submitScore(value, context: 0, player: GKLocalPlayer.local,
                                  leaderboardIDs: [leaderboardID]) { _ in }
    }

    // MARK: Progress → leaderboard + achievements

    /// Called after every recorded run: refresh the star-total board and any
    /// newly earned achievements. All predicates are computed from local
    /// state, so re-evaluating is idempotent.
    func recordProgress(levels: LevelProgressStore, streak: StreakState) {
        guard isAuthenticated else { return }
        let totalStars = GameID.live.reduce(0) { $0 + levels.totalStars(for: $1) }
        submit(totalStars, to: Self.totalStarsLeaderboardID)

        var earned: [String] = []

        if GameID.live.contains(where: { levels.hasThreeStarLevel(for: $0) }) {
            earned.append("wits.ach.first3star")
        }

        for milestone in [50, 150, 300] where totalStars >= milestone {
            earned.append("wits.ach.stars.\(milestone)")
        }
        for milestone in [7, 30] where streak.longest >= milestone {
            earned.append("wits.ach.streak.\(milestone)")
        }

        report(achievements: earned)
    }

    /// Push everything local up after sign-in (new device, reinstall, or runs
    /// recorded while signed out).
    func syncLocalBests(levels: LevelProgressStore, streak: StreakState) {
        guard isAuthenticated else { return }
        for game in GameID.allCases where levels.marathonBest(for: game) != nil {
            submitMarathonBest(game: game, levels: levels)
        }
        // Force a clean re-report on fresh sign-ins.
        reportedAchievements = []
        recordProgress(levels: levels, streak: streak)
    }

    private func report(achievements ids: [String]) {
        let fresh = ids.filter { !reportedAchievements.contains($0) }
        guard !fresh.isEmpty else { return }
        reportedAchievements.formUnion(fresh)
        UserDefaults.standard.set(Array(reportedAchievements).sorted(), forKey: Self.reportedKey)
        let reports = fresh.map { id -> GKAchievement in
            let a = GKAchievement(identifier: id)
            a.percentComplete = 100
            a.showsCompletionBanner = true
            return a
        }
        GKAchievement.report(reports) { _ in }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
