//
//  DatasetEncoder.swift
//  StrayScanner
//
//  Created by Kenneth Blomqvist on 1/2/21.
//  Copyright © 2021 Stray Robots. All rights reserved.
//

import Foundation
import ARKit
import CryptoKit
import CoreMotion
import Synchronization
import UIKit

/// Bounded in-flight frame counter. Replaces the old DispatchSemaphore-based
/// backpressure: when `limit` frames are queued but not yet written, new frames
/// are dropped (never buffered) so ARKit's pixel buffer pool is not starved.
nonisolated final class InFlightFrames: Sendable {
    private let count: Mutex<Int>
    private let limit: Int

    init(limit: Int) {
        self.count = Mutex(0)
        self.limit = limit
    }

    func tryAcquire() -> Bool {
        count.withLock { value in
            if value < limit {
                value += 1
                return true
            }
            return false
        }
    }

    func release() {
        count.withLock { $0 -= 1 }
    }
}

@MainActor
class DatasetEncoder {
    enum Status {
        case allGood
        case videoEncodingError
        case directoryCreationError
    }

    /// Everything the writer needs from an ARFrame, extracted at the delegate
    /// boundary so the ARFrame itself never outlives the session callback.
    ///
    /// @unchecked Sendable: CVPixelBuffer is not Sendable in the SDK, but the
    /// capture-produced buffers are never written after capture, the renderer
    /// reads them synchronously before this struct is enqueued, and exactly one
    /// consumer (FrameWriter) processes each instance.
    nonisolated struct FrameData: @unchecked Sendable {
        let image: CVPixelBuffer
        let depth: CVPixelBuffer?
        let confidence: CVPixelBuffer?
        let timestamp: TimeInterval
        let transform: simd_float4x4
        let intrinsics: simd_float3x3
        let distortionCenter: CGPoint?
        let distortionTable: Data?
    }

    nonisolated enum Item: Sendable {
        case frame(FrameData, number: Int)
        case accelerometer(timestamp: Double, value: simd_double3)
        case gyroscope(timestamp: Double, value: simd_double3)
    }

    private nonisolated let continuation: AsyncStream<Item>.Continuation
    private nonisolated let inFlight = InFlightFrames(limit: 3)
    private let writer: FrameWriter
    private let writerTask: Task<Void, Never>
    private let datasetDirectory: URL
    private var currentFrame: Int = -1
    private var savedFrames: Int = 0
    private var latestIntrinsics: simd_float3x3?
    private var directoryError = false
    private let frameInterval: Int // Only save every frameInterval-th frame.
    public let id: UUID
    public let rgbFilePath: URL // Relative to app document directory.
    public let depthFilePath: URL // Relative to app document directory.
    public let cameraMatrixPath: URL

    // Adaptive mode properties
    private let adaptiveModeEnabled: Bool
    private let positionThreshold: Float
    private let angleThresholdCos: Float // Cosine of angle threshold for efficient comparison
    private var lastSavedTransform: simd_float4x4?
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .light)

    init(arConfiguration: ARWorldTrackingConfiguration, fpsDivider: Int = 1) {
        self.frameInterval = fpsDivider

        // Check if we're in adaptive mode (indicated by the FPS button selection)
        let currentFpsSetting = UserDefaults.standard.integer(forKey: FpsUserDefaultsKey)
        self.adaptiveModeEnabled = (currentFpsSetting == AdaptiveModeIndex)

        // Load adaptive mode thresholds with defaults
        let posThreshold = UserDefaults.standard.double(forKey: AdaptiveThresholdPositionKey)
        let angleThresholdDegrees = UserDefaults.standard.double(forKey: AdaptiveThresholdAngleKey)
        self.positionThreshold = Float(posThreshold > 0 ? posThreshold : DefaultAdaptiveThresholdPosition)

        // Convert angle threshold to cosine for efficient comparison
        let angleThresholdRadians = Float(angleThresholdDegrees > 0 ? angleThresholdDegrees : DefaultAdaptiveThresholdAngle) * Float.pi / 180.0
        self.angleThresholdCos = cos(angleThresholdRadians)

        if self.adaptiveModeEnabled {
            hapticGenerator.prepare()
        }

        let width = arConfiguration.videoFormat.imageResolution.width
        let height = arConfiguration.videoFormat.imageResolution.height
        var theId: UUID = UUID()
        var directoryError = false
        let datasetDirectory = DatasetEncoder.createDirectory(id: &theId, error: &directoryError)
        self.datasetDirectory = datasetDirectory
        self.directoryError = directoryError
        self.id = theId
        self.rgbFilePath = datasetDirectory.appendingPathComponent("rgb.mp4")
        self.depthFilePath = datasetDirectory.appendingPathComponent("depth", isDirectory: true)
        self.cameraMatrixPath = datasetDirectory.appendingPathComponent("camera_matrix.csv", isDirectory: false)

        let (stream, continuation) = AsyncStream.makeStream(of: Item.self)
        self.continuation = continuation
        let writer = FrameWriter(
            datasetDirectory: datasetDirectory,
            rgbFilePath: rgbFilePath,
            depthFilePath: depthFilePath,
            width: width,
            height: height,
            inFlight: inFlight)
        self.writer = writer
        self.writerTask = Task {
            await writer.run(stream)
        }
    }

    func add(frame: ARFrame) {
        currentFrame = currentFrame + 1

        // Check if we should skip this frame based on frame interval
        if (currentFrame % frameInterval != 0) {
            return
        }

        // If adaptive mode is enabled, decide whether the pose has changed
        // enough to warrant saving this frame.
        let currentTransform = frame.camera.transform
        if adaptiveModeEnabled, let lastTransform = lastSavedTransform {
            // Calculate position change
            let lastPos = simd_float3(lastTransform.columns.3.x, lastTransform.columns.3.y, lastTransform.columns.3.z)
            let currentPos = simd_float3(currentTransform.columns.3.x, currentTransform.columns.3.y, currentTransform.columns.3.z)
            let positionDelta = simd_distance(lastPos, currentPos)

            // Calculate forward vector dot product for rotation comparison
            // Forward is -Z in ARKit's coordinate system
            let lastForward = -simd_float3(lastTransform.columns.2.x, lastTransform.columns.2.y, lastTransform.columns.2.z)
            let currentForward = -simd_float3(currentTransform.columns.2.x, currentTransform.columns.2.y, currentTransform.columns.2.z)
            let dotProduct = simd_dot(lastForward, currentForward)

            // Skip frame if changes are below thresholds
            // Note: dotProduct > angleThresholdCos means angle < threshold (cosine decreases as angle increases)
            if positionDelta < positionThreshold && dotProduct > angleThresholdCos {
                return
            }
        }

        // Drop the frame if encoding is backed up, so ARFrame pixel buffers
        // are never queued without bound. Do this before committing any
        // adaptive-mode state so a dropped frame does not advance the pose
        // baseline or fire a "captured" haptic for a frame that is not saved.
        guard inFlight.tryAcquire() else {
            return
        }

        if adaptiveModeEnabled {
            lastSavedTransform = currentTransform
            hapticGenerator.impactOccurred()
        }

        let frameNumber: Int = savedFrames
        savedFrames = savedFrames + 1

        latestIntrinsics = frame.camera.intrinsics
        let calibration = frame.capturedDepthData?.cameraCalibrationData
        let sceneDepth = frame.sceneDepth
        if sceneDepth == nil {
            print("warning: scene depth missing.")
        } else if sceneDepth?.confidenceMap == nil {
            print("warning: confidence map missing.")
        }
        let data = FrameData(
            image: frame.capturedImage,
            depth: sceneDepth?.depthMap,
            confidence: sceneDepth?.confidenceMap,
            timestamp: frame.timestamp,
            transform: frame.camera.transform,
            intrinsics: frame.camera.intrinsics,
            distortionCenter: calibration?.lensDistortionCenter,
            distortionTable: calibration?.lensDistortionLookupTable)
        continuation.yield(.frame(data, number: frameNumber))
    }

    nonisolated func addRawAccelerometer(data: CMAccelerometerData) {
        let acceleration = simd_double3(data.acceleration.x, data.acceleration.y, data.acceleration.z)
        continuation.yield(.accelerometer(timestamp: data.timestamp, value: acceleration))
    }

    nonisolated func addRawGyroscope(data: CMGyroData) {
        let rotationRate = simd_double3(data.rotationRate.x, data.rotationRate.y, data.rotationRate.z)
        continuation.yield(.gyroscope(timestamp: data.timestamp, value: rotationRate))
    }

    /// Finishes the stream, waits until every queued item has been written,
    /// finalizes all files, and returns the aggregated status.
    func wrapUp() async -> Status {
        continuation.finish()
        await writerTask.value
        let writersOK = await writer.finish()
        writeIntrinsics()
        if directoryError {
            return .directoryCreationError
        }
        return writersOK ? .allGood : .videoEncodingError
    }

    private func writeIntrinsics() {
        if let cameraMatrix = latestIntrinsics {
            let rows = cameraMatrix.transpose.columns
            var csv: [String] = []
            for row in [rows.0, rows.1, rows.2] {
                let csvLine = "\(row.x), \(row.y), \(row.z)"
                csv.append(csvLine)
            }
            let contents = csv.joined(separator: "\n")
            do {
                try contents.write(to: self.cameraMatrixPath, atomically: true, encoding: String.Encoding.utf8)
            } catch let error {
                print("Could not write camera matrix. \(error.localizedDescription)")
            }
        }
    }

    static private func createDirectory(id: inout UUID, error directoryError: inout Bool) -> URL {
        let directoryId = hashUUID(id: id)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        var directory = URL(fileURLWithPath: directoryId, relativeTo: url)
        if FileManager.default.fileExists(atPath: directory.path) {
            // Just in case the first 5 characters clash, try again.
            id = UUID()
            directory = DatasetEncoder.createDirectory(id: &id, error: &directoryError)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        } catch let error as NSError {
            print("Error creating directory. \(error), \(error.userInfo)")
            directoryError = true
        }
        return directory
    }

    static private func hashUUID(id: UUID) -> String {
        var hasher: SHA256 = SHA256()
        hasher.update(data: id.uuidString.data(using: .ascii)!)
        let digest = hasher.finalize()
        var string = ""
        digest.makeIterator().prefix(5).forEach { (byte: UInt8) in
            string += String(format: "%02x", byte)
        }
        return string
    }
}

/// Single consumer of the encoding stream. Serial by construction, which keeps
/// writes FIFO: presentation times stay monotonic and frame numbering stays
/// contiguous across all per-frame outputs.
actor FrameWriter {
    private let rgbEncoder: VideoEncoder
    private let depthEncoder: DepthEncoder
    private let confidenceEncoder: ConfidenceEncoder
    private let odometryEncoder: OdometryEncoder
    private let imuEncoder: IMUEncoder
    private let distortionEncoder: DistortionEncoder
    private let inFlight: InFlightFrames
    private var latestAccelerometer: (timestamp: Double, value: simd_double3)?
    private var latestGyroscope: (timestamp: Double, value: simd_double3)?

    init(datasetDirectory: URL, rgbFilePath: URL, depthFilePath: URL, width: CGFloat, height: CGFloat, inFlight: InFlightFrames) {
        self.inFlight = inFlight
        self.rgbEncoder = VideoEncoder(file: rgbFilePath, width: width, height: height)
        self.depthEncoder = DepthEncoder(outDirectory: depthFilePath)
        let confidencePath = datasetDirectory.appendingPathComponent("confidence", isDirectory: true)
        self.confidenceEncoder = ConfidenceEncoder(outDirectory: confidencePath)
        let odometryPath = datasetDirectory.appendingPathComponent("odometry.csv", isDirectory: false)
        self.odometryEncoder = OdometryEncoder(url: odometryPath)
        let imuPath = datasetDirectory.appendingPathComponent("imu.csv", isDirectory: false)
        self.imuEncoder = IMUEncoder(url: imuPath)
        self.distortionEncoder = DistortionEncoder(datasetDirectory: datasetDirectory)
    }

    func run(_ items: AsyncStream<DatasetEncoder.Item>) async {
        for await item in items {
            switch item {
            case .frame(let frame, let number):
                if let depth = frame.depth {
                    depthEncoder.encodeFrame(frame: depth, frameNumber: number)
                    if let confidence = frame.confidence {
                        confidenceEncoder.encodeFrame(frame: confidence, frameNumber: number)
                    }
                }
                await rgbEncoder.add(frame: VideoEncoderInput(buffer: frame.image, time: frame.timestamp), currentFrame: number)
                odometryEncoder.add(
                    timestamp: frame.timestamp,
                    transform: frame.transform,
                    intrinsics: frame.intrinsics,
                    distortionCenter: frame.distortionCenter,
                    currentFrame: number)
                distortionEncoder.add(lookupTable: frame.distortionTable, currentFrame: number)
                inFlight.release()
            case .accelerometer(let timestamp, let value):
                latestAccelerometer = (timestamp, value)
                tryWritingIMUData()
            case .gyroscope(let timestamp, let value):
                latestGyroscope = (timestamp, value)
                tryWritingIMUData()
            }
        }
    }

    /// Finalizes all output files. Returns true when every encoder finished cleanly.
    func finish() async -> Bool {
        let rgbStatus = await rgbEncoder.finishEncoding()
        imuEncoder.done()
        odometryEncoder.done()
        distortionEncoder.done()
        if depthEncoder.status != .allGood {
            print("Something went wrong encoding depth.")
        }
        if confidenceEncoder.status != .allGood {
            print("Something went wrong encoding confidence values.")
        }
        return rgbStatus == .allGood
            && depthEncoder.status == .allGood
            && confidenceEncoder.status == .allGood
    }

    private func tryWritingIMUData() {
        guard
            let accelerometer = latestAccelerometer,
            let gyroscope = latestGyroscope
        else {
            return
        }

        // Write the row to the CSV with the most recent timestamp
        let timestamp = max(accelerometer.timestamp, gyroscope.timestamp)
        imuEncoder.add(
            timestamp: timestamp,
            linear: accelerometer.value,
            angular: gyroscope.value
        )

        // Clear the buffers after writing
        latestAccelerometer = nil
        latestGyroscope = nil
    }
}
