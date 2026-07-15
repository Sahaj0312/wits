//
//  witsApp.swift
//  wits
//
//  Created by Sahajdeep Chhabra on 2026-06-11.
//

import SwiftUI
import UIKit

final class WitsAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }
}

/// iPadOS 26 replaces the old full-screen orientation opt-out with a visible
/// controller preference. Wrapping SwiftUI's generated hosting controller
/// lets the whole app request a portrait lock without relying on deprecated
/// `UIRequiresFullScreen` behavior.
private final class PortraitLockingController: UIViewController {
    private let content: UIViewController

    init(content: UIViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(content)
        content.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content.view)
        NSLayoutConstraint.activate([
            content.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.view.topAnchor.constraint(equalTo: view.topAnchor),
            content.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        content.didMove(toParent: self)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }
    override var prefersInterfaceOrientationLocked: Bool { true }
    override var childForStatusBarStyle: UIViewController? { content }
    override var childForStatusBarHidden: UIViewController? { content }
    override var childForHomeIndicatorAutoHidden: UIViewController? { content }
}

private struct PortraitLockInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView { InstallerView() }
    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async {
                guard let root = window.rootViewController,
                      !(root is PortraitLockingController) else { return }
                let locked = PortraitLockingController(content: root)
                window.rootViewController = locked
                locked.setNeedsUpdateOfSupportedInterfaceOrientations()
                locked.setNeedsUpdateOfPrefersInterfaceOrientationLocked()
            }
        }
    }
}

@main
struct witsApp: App {
    @UIApplicationDelegateAdaptor(WitsAppDelegate.self) private var appDelegate
    @State private var app = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        ScoringDiagnostics.runDebugAssertions()
        #endif
        PurchasesManager.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(app)
                .background(PortraitLockInstaller())
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { app.startOfDayRollover() }
                }
        }
    }
}
