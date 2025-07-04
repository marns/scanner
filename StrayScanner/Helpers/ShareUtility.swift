//
//  ShareUtility.swift
//  StrayScanner
//
//  Created by Claude on 6/24/25.
//

import Foundation
import Compression

/// Utility class for creating shareable archives from recording datasets
class ShareUtility {
    
    /// Creates a shareable ZIP archive from a recording's dataset
    /// - Parameter recording: The recording to create a ZIP archive for
    /// - Returns: URL of the created ZIP file
    static func createShareableArchive(for recording: Recording) async throws -> URL {
        guard let sourceDirectory = recording.directoryPath() else {
            throw NSError(domain: "ShareError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to get recording directory path"])
        }
        
        let tempDirectory = FileManager.default.temporaryDirectory
        let archiveName = "\(recording.name ?? "Recording")_\(recording.id?.uuidString.prefix(8) ?? "unknown").zip"
        let archiveURL = tempDirectory.appendingPathComponent(archiveName)
        
        // Remove existing archive if it exists
        try? FileManager.default.removeItem(at: archiveURL)
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try createZipArchive(sourceDirectory: sourceDirectory, destinationURL: archiveURL)
                    continuation.resume(returning: archiveURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private static func createZipArchive(sourceDirectory: URL, destinationURL: URL) throws {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        
        coordinator.coordinate(readingItemAt: sourceDirectory, options: [.forUploading], error: &error) { (zipURL) in
            do {
                _ = zipURL.startAccessingSecurityScopedResource()
                defer { zipURL.stopAccessingSecurityScopedResource() }
                
                try FileManager.default.copyItem(at: zipURL, to: destinationURL)
            } catch {
                print("Failed to create zip: \(error)")
            }
        }
        
        if let error = error {
            throw error
        }
    }
}
