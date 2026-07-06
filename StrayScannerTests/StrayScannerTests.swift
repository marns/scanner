//
//  StrayScannerTests.swift
//  StrayScannerTests
//
//  Tests for the depth PNG encoder. These pin down the on-disk depth format
//  (16-bit big-endian grayscale PNG, values in millimeters) that downstream
//  tools such as StrayVisualizer and cv2.imread(path, -1) depend on.
//

import XCTest
import ImageIO
@testable import StrayScanner

class PngEncoderTests: XCTestCase {

    // MARK: - Helpers

    private func encode(depthMeters: [Float], width: Int, height: Int) -> Data {
        precondition(depthMeters.count == width * height)
        var input = depthMeters
        let data: Data? = input.withUnsafeBufferPointer { buffer in
            DepthPngEncoder.encode(depth: buffer.baseAddress!, width: width, height: height)
        }
        return data!
    }


    /// Decodes a PNG and returns its pixels as host-order UInt16 grayscale values.
    private func decodeGray16(_ data: Data) throws -> (width: Int, height: Int, pixels: [UInt16]) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))

        XCTAssertEqual(image.bitsPerComponent, 16, "Depth PNG must be 16 bits per component")
        XCTAssertEqual(image.bitsPerPixel, 16, "Depth PNG must be single-channel grayscale")

        let width = image.width
        let height = image.height
        let bytesPerRow = image.bytesPerRow
        let raw = try XCTUnwrap(image.dataProvider?.data) as Data

        let littleEndian = image.bitmapInfo.intersection(.byteOrderMask) == .byteOrder16Little
        var pixels = [UInt16](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 2
                let b0 = UInt16(raw[offset])
                let b1 = UInt16(raw[offset + 1])
                pixels[y * width + x] = littleEndian ? (b1 << 8 | b0) : (b0 << 8 | b1)
            }
        }
        return (width, height, pixels)
    }

    /// Millimeter value the encoder is expected to produce for a depth in meters,
    /// mirroring the encoder's float arithmetic (value * 1000, round half away from zero).
    private func expectedMillimeters(_ meters: Float) -> UInt16 {
        return UInt16((meters * 1000.0).rounded(.toNearestOrAwayFromZero))
    }

    // MARK: - Tests

    func testEncodesKnownValuesAsMillimeters() throws {
        let width = 3
        let height = 2
        let depths: [Float] = [0.0, 0.001, 1.0, 2.5, 65.535, 0.9996]
        let png = encode(depthMeters: depths, width: width, height: height)

        let decoded = try decodeGray16(png)
        XCTAssertEqual(decoded.width, width)
        XCTAssertEqual(decoded.height, height)
        for (i, meters) in depths.enumerated() {
            XCTAssertEqual(decoded.pixels[i], expectedMillimeters(meters),
                           "Pixel \(i) (\(meters) m) has wrong millimeter value")
        }
    }

    func testInvalidDepthValuesEncodeAsZeroWithoutCrashing() throws {
        // ARKit can emit NaN/Inf for invalid pixels and values beyond UInt16 range.
        // These must not trap; invalid values become 0, large values clamp.
        let width = 3
        let height = 2
        let depths: [Float] = [.nan, .infinity, -.infinity, -1.0, 70.0, 1.0]
        let png = encode(depthMeters: depths, width: width, height: height)

        let decoded = try decodeGray16(png)
        XCTAssertEqual(decoded.pixels[0], 0, "NaN should encode as 0")
        XCTAssertEqual(decoded.pixels[1], 0, "+Inf should encode as 0")
        XCTAssertEqual(decoded.pixels[2], 0, "-Inf should encode as 0")
        XCTAssertEqual(decoded.pixels[3], 0, "negative depth should clamp to 0")
        XCTAssertEqual(decoded.pixels[4], UInt16.max, "70 m clamps to 65535 mm")
        XCTAssertEqual(decoded.pixels[5], 1000, "1 m encodes as 1000 mm")
    }

    func testFullResolutionGradientRoundTrips() throws {
        // Same resolution as the LiDAR depth maps the app records.
        let width = 256
        let height = 192
        var depths = [Float](repeating: 0, count: width * height)
        for i in 0..<depths.count {
            depths[i] = Float(i % 65536) / 1000.0
        }
        let png = encode(depthMeters: depths, width: width, height: height)

        let decoded = try decodeGray16(png)
        XCTAssertEqual(decoded.width, width)
        XCTAssertEqual(decoded.height, height)
        for i in 0..<depths.count {
            let expected = expectedMillimeters(depths[i])
            if decoded.pixels[i] != expected {
                XCTFail("Pixel \(i): got \(decoded.pixels[i]), expected \(expected)")
                return
            }
        }
    }

}
