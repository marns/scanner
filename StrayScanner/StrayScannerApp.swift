//
//  StrayScannerApp.swift
//  StrayScanner
//
//  Created by Kenneth Blomqvist on 11/15/20.
//  Copyright © 2020 Stray Robots. All rights reserved.
//

import SwiftUI
import SwiftData

@main
struct StrayScannerApp: App {
    let container = PersistenceController.makeContainer()

    var body: some Scene {
        WindowGroup {
            SessionList()
                .task {
                    AppDaemon.removeDeletedEntries(context: container.mainContext)
                }
        }
        .modelContainer(container)
    }
}
