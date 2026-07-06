//
//  VideoEncoder.swift
//  StrayScanner
//
//  Created by Kenneth Blomqvist on 12/30/20.
//  Copyright © 2020 Stray Robots. All rights reserved.
//

import Foundation
import AVFoundation
import CoreVideo

nonisolated struct VideoEncoderInput: @unchecked Sendable {
    let buffer: CVPixelBuffer
    let time: TimeInterval // Relative to boot time.
}

nonisolated final class VideoEncoder {
    enum EncodingStatus {
        case allGood
        case error
    }

    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var videoAdapter: AVAssetWriterInputPixelBufferAdaptor?
    private let timeScale = CMTimeScale(60)
    public let width: CGFloat
    public let height: CGFloat
    private var previousFrame: Int = -1
    public var filePath: URL
    public var status: EncodingStatus = EncodingStatus.allGood

    init(file: URL, width: CGFloat, height: CGFloat) {
        self.filePath = file
        self.width = width
        self.height = height
        initializeFile()
    }

    func add(frame: VideoEncoderInput, currentFrame: Int) async {
        guard let input = videoWriterInput, let writer = videoWriter else { return }
        previousFrame = currentFrame
        while !input.isReadyForMoreMediaData {
            if writer.status == .failed {
                status = .error
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        encode(frame: frame, frameNumber: currentFrame)
    }

    func finishEncoding() async -> EncodingStatus {
        guard let writer = videoWriter else { return status }
        if writer.status == .failed {
            print("Something went wrong when writing video. \(writer.error?.localizedDescription ?? "unknown error")")
            status = .error
        } else {
            videoWriterInput?.markAsFinished()
            await writer.finishWriting()
            if writer.status == .failed {
                print("Finalizing video failed. \(writer.error?.localizedDescription ?? "unknown error")")
                status = .error
            }
        }
        videoWriter = nil
        videoWriterInput = nil
        videoAdapter = nil
        return status
    }

    private func initializeFile() {
        do {
            let videoWriter = try AVAssetWriter(outputURL: self.filePath, fileType: .mp4)
            let settings: [String : Any] = [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: self.width,
                AVVideoHeightKey: self.height
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            input.mediaTimeScale = timeScale
            input.performsMultiPassEncodingIfSupported = false
            videoAdapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
            if videoWriter.canAdd(input) {
                videoWriter.add(input)
                videoWriterInput = input
                videoWriter.startWriting()
                videoWriter.startSession(atSourceTime: .zero)
                self.videoWriter = videoWriter
            } else {
                print("Can't create writer.")
                status = .error
            }
        } catch let error as NSError {
            print("Creating AVAssetWriter failed. \(error), \(error.userInfo)")
            status = .error
        }
    }

    private func encode(frame: VideoEncoderInput, frameNumber: Int) {
        let image: CVPixelBuffer = frame.buffer
        let time = CMTime(value: Int64(frameNumber), timescale: timeScale)
        let success = videoAdapter!.append(image, withPresentationTime: time)
        if !success {
            print("Pixel buffer could not be appended. \(videoWriter!.error!.localizedDescription)")
        }
    }
}
