//
//  PersistenceController.swift
//  StrayScanner
//
//  Builds the SwiftData container. It deliberately opens the SQLite store at
//  the location Core Data used (Application Support/Stray_Scanner.sqlite) so
//  that recordings created by earlier (Core Data) versions of the app survive
//  the upgrade. Using SwiftData's default container would create a fresh,
//  empty `default.store` and silently orphan existing users' data.
//

import Foundation
import SwiftData

enum PersistenceController {
    /// URL of the store created by the legacy `NSPersistentContainer(name: "Stray_Scanner")`.
    static var legacyStoreURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Stray_Scanner.sqlite")
    }

    static func makeContainer() -> ModelContainer {
        let storeURL = legacyStoreURL
        let configuration = ModelConfiguration(schema: Schema([Recording.self]), url: storeURL)
        do {
            let container = try ModelContainer(for: Recording.self, configurations: configuration)
            #if DEBUG
            // The legacy store lives at storeURL. If SwiftData ever created a
            // fresh `default.store` instead, adoption failed silently.
            let defaultStore = URL.applicationSupportDirectory.appendingPathComponent("default.store")
            assert(!FileManager.default.fileExists(atPath: defaultStore.path),
                   "SwiftData created default.store; legacy Core Data store was not adopted.")
            #endif
            return container
        } catch {
            fatalError("Failed to open recordings store at \(storeURL.path): \(error)")
        }
    }
}
