//
//  DepthEncoder.swift
//  StrayScanner
//
//  Created by Kenneth Blomqvist on 1/24/21.
//  Copyright © 2021 Stray Robots. All rights reserved.
//

import Foundation
import CoreVideo

nonisolated final class DepthEncoder {
    enum Status {
        case allGood
        case frameEncodingError
    }
    private let baseDirectory: URL
    public var status: Status = Status.allGood

    init(outDirectory: URL) {
        self.baseDirectory = outDirectory
        do {
            try FileManager.default.createDirectory(at: outDirectory.absoluteURL, withIntermediateDirectories: true, attributes: nil)
        } catch let error {
            print("Could not create folder. \(error.localizedDescription)")
            status = Status.frameEncodingError
        }
    }

    func encodeFrame(frame: CVPixelBuffer, frameNumber: Int) {
        let filename = String(format: "%06d", frameNumber)
        let framePath = self.baseDirectory.absoluteURL.appendingPathComponent(filename, isDirectory: false).appendingPathExtension("png")
        guard let data = convert(frame: frame) else {
            print("Could not encode depth image \(frameNumber).")
            status = .frameEncodingError
            return
        }
        do {
            try data.write(to: framePath)
        } catch let error {
            print("Could not save depth image \(frameNumber). \(error.localizedDescription)")
            status = .frameEncodingError
        }
    }

    private func convert(frame: CVPixelBuffer) -> Data? {
        assert(CVPixelBufferGetPixelFormatType(frame) == kCVPixelFormatType_DepthFloat32)
        let height = CVPixelBufferGetHeight(frame)
        let width = CVPixelBufferGetWidth(frame)
        CVPixelBufferLockBaseAddress(frame, CVPixelBufferLockFlags.readOnly)
        defer { CVPixelBufferUnlockBaseAddress(frame, CVPixelBufferLockFlags.readOnly) }
        guard let inBase = CVPixelBufferGetBaseAddress(frame) else { return nil }
        let inPixelData = inBase.assumingMemoryBound(to: Float32.self)
        return DepthPngEncoder.encode(depth: inPixelData, width: width, height: height)
    }
}
