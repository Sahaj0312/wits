//
//  AdManager.swift
//  wits
//
//  Interstitial ads between games keep the app fully free. Placement rule:
//  ads are only ever presented over static screens (result cards, workout
//  interludes, the summary) — never over live gameplay, where a covered
//  timer would eat the player's run.
//
//  Call sites:
//   - gameCompleted()          → every finished game (workout or level play)
//   - maybeShowInterstitial()  → on arrival at a static break screen
//

import SwiftUI
import GoogleMobileAds
import AppTrackingTransparency

@Observable
final class AdManager {
    static let shared = AdManager()

    /// DEBUG builds use Google's public test units — clicking real ads in
    /// your own builds violates AdMob policy and risks the account.
    #if DEBUG
    private static let interstitialUnitID = "ca-app-pub-3940256099942544/4411468910"
    static let rewardedUnitID = "ca-app-pub-3940256099942544/1712485313"
    #else
    private static let interstitialUnitID = "ca-app-pub-9813826155312094/4859812107"
    static let rewardedUnitID = "ca-app-pub-9813826155312094/2153757716"   // not wired up yet
    #endif

    /// Frequency cap: one ad per `gamesPerAd` completed games, never more
    /// often than `minSecondsBetweenAds`.
    private static let gamesPerAd = 3
    private static let minSecondsBetweenAds: TimeInterval = 90

    /// Wired at startup so paid subscribers never see ads.
    var adFreeProvider: () -> Bool = { false }

    private var started = false
    private var interstitial: InterstitialAd?
    private var isLoading = false
    private var completedGames = 0
    private var lastAdShownAt: Date?

    private init() {}

    /// Idempotent. Asks for tracking consent first so the SDK knows whether
    /// it may use the IDFA, then warms up the first interstitial.
    func startIfNeeded() async {
        guard !started, !adFreeProvider() else { return }
        started = true
        _ = await ATTrackingManager.requestTrackingAuthorization()
        await MobileAds.shared.start()
        loadInterstitial()
    }

    func gameCompleted() {
        completedGames += 1
    }

    /// Presents an interstitial if the frequency cap allows and one is ready.
    /// Safe to call optimistically — it's a no-op most of the time.
    func maybeShowInterstitial() {
        guard started, !adFreeProvider() else { return }
        guard completedGames >= Self.gamesPerAd else { return }
        if let last = lastAdShownAt, Date().timeIntervalSince(last) < Self.minSecondsBetweenAds { return }
        guard let ad = interstitial, let top = Self.topViewController() else {
            loadInterstitial()   // not ready — make sure one is on the way
            return
        }
        completedGames = 0
        lastAdShownAt = Date()
        interstitial = nil
        ad.present(from: top)
        loadInterstitial()       // prefetch the next one behind the ad
    }

    private func loadInterstitial() {
        guard interstitial == nil, !isLoading else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            interstitial = try? await InterstitialAd.load(with: Self.interstitialUnitID,
                                                          request: Request())
        }
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
