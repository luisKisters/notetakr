import Foundation

/// Deterministic, privacy-safe PCM fixtures for tests. Each turn is a short
/// voice-like harmonic burst separated by silence; distinct fundamentals model
/// distinct speakers without recording or shipping anyone's real voice.
public enum SyntheticMeetingAudio {
    public struct Turn: Equatable, Sendable {
        public var fundamentalHz: Double
        public var duration: TimeInterval
        public var pauseAfter: TimeInterval

        public init(
            fundamentalHz: Double,
            duration: TimeInterval = 0.32,
            pauseAfter: TimeInterval = 0.08
        ) {
            self.fundamentalHz = fundamentalHz
            self.duration = duration
            self.pauseAfter = pauseAfter
        }
    }

    public static let microphoneConversation = [
        Turn(fundamentalHz: 155),
        Turn(fundamentalHz: 165),
        Turn(fundamentalHz: 158),
    ]

    public static let systemConversation = [
        Turn(fundamentalHz: 215),
        Turn(fundamentalHz: 285),
        Turn(fundamentalHz: 245),
        Turn(fundamentalHz: 292),
    ]

    public static func wavData(
        turns: [Turn],
        sampleRate: Int = 16_000,
        amplitude: Double = 0.28
    ) -> Data {
        var samples: [Int16] = []
        for turn in turns {
            let voicedCount = max(1, Int(turn.duration * Double(sampleRate)))
            for index in 0..<voicedCount {
                let t = Double(index) / Double(sampleRate)
                let progress = Double(index) / Double(voicedCount)
                let envelope = min(1, progress * 12) * min(1, (1 - progress) * 12)
                let fundamental = sin(2 * .pi * turn.fundamentalHz * t)
                let second = 0.42 * sin(2 * .pi * turn.fundamentalHz * 2.02 * t)
                let third = 0.18 * sin(2 * .pi * turn.fundamentalHz * 3.01 * t)
                let sample = max(-1, min(1, (fundamental + second + third) * amplitude * envelope))
                samples.append(Int16(sample * Double(Int16.max)))
            }
            samples.append(contentsOf: repeatElement(0, count: max(0, Int(turn.pauseAfter * Double(sampleRate)))))
        }
        return pcmWAV(samples: samples, sampleRate: sampleRate)
    }

    private static func pcmWAV(samples: [Int16], sampleRate: Int) -> Data {
        let dataByteCount = UInt32(samples.count * MemoryLayout<Int16>.size)
        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataByteCount, to: &data)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data) // linear PCM
        append(UInt16(1), to: &data) // mono
        append(UInt32(sampleRate), to: &data)
        append(UInt32(sampleRate * 2), to: &data)
        append(UInt16(2), to: &data)
        append(UInt16(16), to: &data)
        data.append(contentsOf: Array("data".utf8))
        append(dataByteCount, to: &data)
        for sample in samples {
            append(UInt16(bitPattern: sample), to: &data)
        }
        return data
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 24))
    }
}
