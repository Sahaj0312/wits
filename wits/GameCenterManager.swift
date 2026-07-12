//
//  GameCenterManager.swift
//  wits
//
//  Game Center: sign-in, per-game recurring weekly leaderboards, Split's
//  endless leaderboard, and progress achievements. Everything degrades silently
//  when the player is not signed in — the app never blocks on Game Center.
//
//  Leaderboard IDs (create these in App Store Connect; immutable once live):
//    wits.split.survival.depth.v2   Split level plus fractional depth
//    wits.marathon.blockFit         Block Fit endless best score
//    wits.weekly.<game-id>    recurring every Monday at 00:00 UTC for 7 days
//  Achievement IDs:
//    wits.ach.levels.50 / .150 / .300     lifetime level-clear milestones
//    wits.ach.streak.7 / .30              longest-streak milestones
//

import GameKit
import Observation
import UIKit

@Observable
@MainActor
final class GameCenterManager {
    /// Master switch for all Game Center surfaces (sign-in, leaderboards,
    /// achievements, access point). Personal bests are tracked locally in
    /// LevelProgressStore either way. Flip to true and follow
    /// docs/game-center-setup.md to go live.
    static let isEnabled = false

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
        guard Self.isEnabled else { return }
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
        guard Self.isEnabled else { return }
        GKAccessPoint.shared.trigger(state: .leaderboards) {}
    }

    // MARK: Leaderboards

    static func leaderboardID(for game: GameID) -> String {
        game == .split ? "wits.split.survival.depth.v2" : "wits.marathon.\(game.rawValue)"
    }
    func submitMarathonBest(game: GameID, levels: LevelProgressStore) {
        guard isAuthenticated, let best = levels.marathonBest(for: game) else { return }
        submit(game == .split ? best.leaderboardScore : best.score,
               to: Self.leaderboardID(for: game))
    }

    func submitWeeklyBest(challenge: WeeklyChallenge, levels: LevelProgressStore) {
        guard isAuthenticated, let best = levels.weeklyBest(for: challenge) else { return }
        submit(best.score, to: challenge.leaderboardID, context: Int(truncatingIfNeeded: challenge.seed))
    }

    private func submit(_ value: Int, to leaderboardID: String, context: Int = 0) {
        GKLeaderboard.submitScore(value, context: context, player: GKLocalPlayer.local,
                                  leaderboardIDs: [leaderboardID]) { _ in }
    }

    // MARK: Progress → leaderboard + achievements

    /// Called after every recorded run: refresh newly earned achievements.
    /// Lifetime clears remain an achievement signal, never a grind leaderboard.
    /// All predicates are computed from local
    /// state, so re-evaluating is idempotent.
    func recordProgress(levels: LevelProgressStore, streak: StreakState) {
        guard isAuthenticated else { return }
        let totalClears = GameID.live.reduce(0) { $0 + levels.totalClears(for: $1) }

        var earned: [String] = []

        for milestone in [50, 150, 300] where totalClears >= milestone {
            earned.append("wits.ach.levels.\(milestone)")
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
        for game in GameID.standalone where levels.marathonBest(for: game) != nil {
            submitMarathonBest(game: game, levels: levels)
        }
        for game in GameID.allCases {
            submitWeeklyBest(challenge: .current(for: game), levels: levels)
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
