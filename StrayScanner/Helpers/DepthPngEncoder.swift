//
//  DepthPngEncoder.swift
//  StrayScanner
//
//  Encodes a Float32 depth buffer (meters) as a 16-bit big-endian grayscale
//  PNG whose sample values are depth in millimeters. This is the on-disk
//  format downstream tools rely on (e.g. cv2.imread(path, -1)); see
//  docs/format.md. Replaces the previously vendored lodepng-based encoder.
//

import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

nonisolated enum DepthPngEncoder {
    /// Converts a row-major Float32 depth buffer (meters) into 16-bit PNG data.
    /// Values are stored as millimeters, rounded to the nearest integer.
    static func encode(depth: UnsafePointer<Float32>, width: Int, height: Int) -> Data? {
        var samples = [UInt16](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let millimeters = (depth[i] * 1000.0).rounded()
            // ARKit can report NaN/Inf for invalid depth pixels; map those to 0
            // (no measurement). UInt16(NaN) would otherwise trap. Finite values
            // are clamped into range since capture noise can exceed 65.535 m.
            if millimeters.isFinite {
                samples[i] = UInt16(min(max(millimeters, 0), Float32(UInt16.max)))
            } else {
                samples[i] = 0
            }
        }

        let bytesPerRow = width * MemoryLayout<UInt16>.size
        guard let data = CFDataCreateMutable(nil, bytesPerRow * height) else { return nil }
        // PNG stores 16-bit samples big-endian; write bytes in that order so the
        // bitmap is byteOrder16Big and no per-pixel swap is needed at read time.
        samples.withUnsafeBufferPointer { buffer in
            for sample in buffer {
                var bigEndian = sample.bigEndian
                withUnsafeBytes(of: &bigEndian) { raw in
                    CFDataAppendBytes(data, raw.bindMemory(to: UInt8.self).baseAddress!, 2)
                }
            }
        }

        guard let provider = CGDataProvider(data: data) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
            .union(.byteOrder16Big)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearGray) ?? CGColorSpace(name: CGColorSpace.genericGrayGamma2_2),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 16,
                bitsPerPixel: 16,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent)
        else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
