//
//  AppDaemon.swift
//  StrayScanner
//
//  Created by Kenneth Blomqvist on 1/17/21.
//  Copyright © 2021 Stray Robots. All rights reserved.
//

import Foundation
import SwiftData

@MainActor
enum AppDaemon {
    /// Removes recordings whose dataset folder no longer exists on disk. This
    /// is the main mechanism through which datasets are "exported": the user
    /// moves or deletes the folder via Finder/iTunes or the Files app, and the
    /// corresponding entry is cleaned up here on next launch.
    static func removeDeletedEntries(context: ModelContext) {
        let descriptor = FetchDescriptor<Recording>()
        do {
            let recordings = try context.fetch(descriptor)
            for recording in recordings {
                guard let path = recording.absoluteRgbPath() else {
                    print("Session \(recording.id) does not have an rgb file.")
                    continue
                }
                let enclosingFolder = path.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: enclosingFolder.path) {
                    recording.deleteFiles()
                    context.delete(recording)
                }
            }
            try context.save()
        } catch let error as NSError {
            print("Something went wrong pruning deleted recordings. Error: \(error), \(error.userInfo)")
        }
    }
}
