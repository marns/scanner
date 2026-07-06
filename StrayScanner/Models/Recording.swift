//
//  Recording.swift
//  StrayScanner
//
//  SwiftData model for a recorded dataset. This adopts the store originally
//  created by Core Data (entity "Recording"), so attribute names and types
//  must match the legacy model exactly and no new constraints (e.g. .unique)
//  may be added — see PersistenceController for how the legacy store is opened.
//

import Foundation
import SwiftData

@Model
final class Recording {
    var createdAt: Date = Date()
    var depthFilePath: String?
    var duration: Double = 0
    var id: UUID = UUID()
    var name: String = ""
    var rgbFilePath: String?

    init(id: UUID, name: String, createdAt: Date, duration: Double,
         rgbFilePath: String? = nil, depthFilePath: String? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.duration = duration
        self.rgbFilePath = rgbFilePath
        self.depthFilePath = depthFilePath
    }

    private func pathsRelativeTo() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    func absoluteRgbPath() -> URL? {
        rgbFilePath.map { URL(fileURLWithPath: $0, relativeTo: pathsRelativeTo()) }
    }

    func absoluteDepthPath() -> URL? {
        depthFilePath.map { URL(fileURLWithPath: $0, relativeTo: pathsRelativeTo()) }
    }

    func directoryPath() -> URL? {
        absoluteRgbPath()?.deletingLastPathComponent()
    }

    func deleteFiles() {
        guard let directory = directoryPath(),
              FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.removeItem(at: directory)
            print("Deleted dataset directory \(directory.path)")
        } catch let error as NSError {
            print("Could not delete dataset directory \(directory.path). \(error), \(error.userInfo)")
        }
    }
}
