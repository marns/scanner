//
//  ShareUtility.swift
//  StrayScanner
//
//  Created by Claude on 6/24/25.
//

import Foundation

/// Utility for creating shareable archives from recording datasets.
nonisolated enum ShareUtility {

    /// Creates a shareable ZIP archive of a dataset directory.
    /// - Parameter sourceDirectory: The recording's dataset directory.
    /// - Returns: URL of the created ZIP file in the temporary directory.
    static func createShareableArchive(from sourceDirectory: URL) async throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let archiveURL = tempDirectory.appendingPathComponent(sourceDirectory.lastPathComponent + ".zip")

        // Remove existing archive if it exists
        try? FileManager.default.removeItem(at: archiveURL)

        let work = Task.detached(priority: .userInitiated) {
            try createZipArchive(sourceDirectory: sourceDirectory, destinationURL: archiveURL)
            return archiveURL
        }
        return try await work.value
    }

    private static func createZipArchive(sourceDirectory: URL, destinationURL: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var copyError: Error?

        coordinator.coordinate(readingItemAt: sourceDirectory, options: [.forUploading], error: &coordinatorError) { zipURL in
            do {
                try FileManager.default.copyItem(at: zipURL, to: destinationURL)
            } catch {
                copyError = error
            }
        }

        if let error = coordinatorError ?? copyError {
            throw error
        }
    }
}
