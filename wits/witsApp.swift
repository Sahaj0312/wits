//
//  witsApp.swift
//  wits
//
//  Created by Sahajdeep Chhabra on 2026-06-11.
//

import SwiftUI

@main
struct witsApp: App {
    @State private var app = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        ScoringDiagnostics.runDebugAssertions()
        #endif
        PurchasesManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(app)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { app.startOfDayRollover() }
                }
        }
    }
}
