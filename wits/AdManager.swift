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

    private var rewarded: RewardedAd?
    private var isLoadingRewarded = false
    private var rewardedWatcher: FullScreenAdWatcher?   // strong ref while presenting
    private var interstitialWatcher: FullScreenAdWatcher?

    private init() {}

    /// Idempotent. Asks for tracking consent first so the SDK knows whether
    /// it may use the IDFA, then warms up the first interstitial.
    func startIfNeeded() async {
        guard !started, !adFreeProvider() else { return }
        started = true
        _ = await ATTrackingManager.requestTrackingAuthorization()
        await MobileAds.shared.start()
        loadInterstitial()
        loadRewardedIfNeeded()
    }

    // MARK: Rewarded (opt-in "watch to continue" — not gated by ad-free)

    var rewardedReady: Bool { rewarded != nil }

    func loadRewardedIfNeeded() {
        guard started, rewarded == nil, !isLoadingRewarded else { return }
        isLoadingRewarded = true
        Task {
            defer { isLoadingRewarded = false }
            rewarded = try? await RewardedAd.load(with: Self.rewardedUnitID,
                                                  request: Request())
        }
    }

    /// Presents a rewarded ad. `completion(earned)` fires once the ad is
    /// dismissed — resuming gameplay any earlier would run it behind the ad.
    func showRewarded(completion: @escaping (Bool) -> Void) {
        guard let ad = rewarded, let top = Self.topViewController() else {
            loadRewardedIfNeeded()
            completion(false)
            return
        }
        rewarded = nil
        var earned = false
        let watcher = FullScreenAdWatcher { [weak self] in
            self?.rewardedWatcher = nil
            self?.loadRewardedIfNeeded()
            completion(earned)
        }
        rewardedWatcher = watcher
        ad.fullScreenContentDelegate = watcher
        ad.present(from: top) { earned = true }
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
        let priorCompleted = completedGames
        let priorShownAt = lastAdShownAt
        completedGames = 0
        lastAdShownAt = Date()
        interstitial = nil
        let watcher = FullScreenAdWatcher(
            onDismiss: { [weak self] in
                guard let self else { return }
                self.interstitialWatcher = nil
                AdFreeOfferGate.recordInterstitialShown()
                if AdFreeOfferGate.shouldOfferNow(isAdFree: self.adFreeProvider()) {
                    // The pitch lands directly behind the ad it follows — the
                    // moment the pain of the ad is most concrete.
                    self.presentAdFreeOffer()
                }
            },
            onFail: { [weak self] in
                guard let self else { return }
                self.interstitialWatcher = nil
                // Never shown (expired ad, presentation mid-transition):
                // give the frequency cap back so the next static screen
                // retries, and keep the phantom ad out of the offer gate.
                self.completedGames = priorCompleted
                self.lastAdShownAt = priorShownAt
                self.loadInterstitial()
            })
        interstitialWatcher = watcher
        ad.fullScreenContentDelegate = watcher
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

    /// Presents the one-time-purchase upsell over whatever is on screen —
    /// UIKit presentation, like the ads themselves, so it works above the
    /// game's fullScreenCover where a root SwiftUI sheet cannot appear.
    private func presentAdFreeOffer() {
        guard let top = Self.topViewController() else { return }
        AdFreeOfferGate.recordOfferShown()
        top.present(UIHostingController(rootView: AdFreeOfferView()), animated: true)
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

/// Fires onDismiss when a full-screen ad closes after really showing, and
/// onFail when it never opened — callers that count impressions must not
/// treat the two the same. Omitting onFail folds both into onDismiss.
private final class FullScreenAdWatcher: NSObject, FullScreenContentDelegate {
    private let onDismiss: () -> Void
    private let onFail: () -> Void

    init(onDismiss: @escaping () -> Void, onFail: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
        self.onFail = onFail ?? onDismiss
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        onDismiss()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        onFail()
    }
}
