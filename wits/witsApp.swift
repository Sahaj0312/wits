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
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        app.startOfDayRollover()
                        Task {
                            await NotificationManager.shared.appBecameActive(streak: app.streak)
                        }
                    }
                }
        }
    }
}
