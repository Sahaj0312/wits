//
//  witsApp.swift
//  wits
//
//  Created by Sahajdeep Chhabra on 2026-06-11.
//

import SwiftUI

@main
struct witsApp: App {
    @State private var app = AppModel(supa: .shared)
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        ScoringDiagnostics.runDebugAssertions()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(SupabaseManager.shared)
                .environment(app)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { app.startOfDayRollover() }
                }
        }
    }
}
