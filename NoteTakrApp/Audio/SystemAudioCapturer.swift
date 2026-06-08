// System-audio capture skeleton using ScreenCaptureKit (macOS 13+).
// IMPORTANT: Requires screen recording permission in System Settings > Privacy & Security.
// Verified only on the macOS CI runner / physical Mac.
// Full end-to-end audio output has not been confirmed without real hardware.
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
import AVFoundation
import Foundation

final class SystemAudioCapturer: NSObject, SCStreamDelegate, SCStreamOutput, @unchecked Sendable {
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var sessionStarted = false

    func startCapture(to url: URL) async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw SystemAudioError.noDisplayAvailable
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = false
        config.sampleRate = 44_100
        config.channelCount = 2

        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let audioSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        writer.startWriting()
        assetWriter = writer
        audioInput = input
        sessionStarted = false

        let captureStream = SCStream(filter: filter, configuration: config, delegate: self)
        try captureStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        try await captureStream.startCapture()
        stream = captureStream
    }

    func stopCapture() async throws {
        try await stream?.stopCapture()
        stream = nil
        audioInput?.markAsFinished()
        await assetWriter?.finishWriting()
        assetWriter = nil
        audioInput = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio,
              sampleBuffer.isValid,
              let input = audioInput,
              input.isReadyForMoreMediaData else { return }

        if !sessionStarted {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            assetWriter?.startSession(atSourceTime: pts)
            sessionStarted = true
        }
        input.append(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("NoteTakr system audio stream stopped with error: \(error.localizedDescription)")
    }
}

enum SystemAudioError: Error {
    case noDisplayAvailable
}
#endif
