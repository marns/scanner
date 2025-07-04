//
//  ShareUtility.swift
//  StrayScanner
//
//  Created by Claude on 6/24/25.
//

import Foundation
import ZIPFoundation

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
        let folderName = generateArchiveName(for: recording)
        let archiveURL = tempDirectory.appendingPathComponent("\(folderName).zip")
        
        // Remove existing archive if it exists
        try? FileManager.default.removeItem(at: archiveURL)
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try createArchive(from: sourceDirectory, to: archiveURL, rootFolderName: folderName)
                    continuation.resume(returning: archiveURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private static func generateArchiveName(for recording: Recording) -> String {
        if let created = recording.createdAt {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm"
            return dateFormatter.string(from: created)
        } else {
            return recording.name ?? "Recording"
        }
    }
    
    /// Creates a ZIP archive from the sourceDirectory - preserving structure (no extra subdir) under rootFolderName
    private static func createArchive(from sourceDirectory: URL, to destinationURL: URL, rootFolderName: String) throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destinationURL)

        let archive = try Archive(url: destinationURL, accessMode: .create)

        // Get contents of the source directory
        let contents = try fileManager.contentsOfDirectory(at: sourceDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        
        for item in contents {
            try addToArchive(archive: archive, itemURL: item, basePath: sourceDirectory, rootFolderName: rootFolderName)
        }
    }
    
    private static func addToArchive(archive: Archive, itemURL: URL, basePath: URL, rootFolderName: String) throws {
        let fileManager = FileManager.default
        let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])
        let isDirectory = resourceValues.isDirectory ?? false
        
        if isDirectory {
            // Recursively add directory contents
            let dirName = itemURL.lastPathComponent
            let contents = try fileManager.contentsOfDirectory(at: itemURL, includingPropertiesForKeys: nil, options: [])
            
            for subItem in contents {
                let entryPath = "\(rootFolderName)/\(dirName)/\(subItem.lastPathComponent)"
                try archive.addEntry(with: entryPath, fileURL: subItem)
            }
        } else {
            // Add file directly to root
            let fileName = itemURL.lastPathComponent
            let entryPath = "\(rootFolderName)/\(fileName)"
            try archive.addEntry(with: entryPath, fileURL: itemURL)
        }
    }
}
