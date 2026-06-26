import Darwin
import Foundation
import FluidAudio
import NoteTakrCore

enum ProbeModelVersion: String {
    case v3
    case v2
    case tdtCtc110m
}

enum ProbeError: Error, CustomStringConvertible {
    case missingValue(String)
    case missingInput
    case missingModelSource
    case invalidVersion(String)
    case invalidArguments(String)
    case missingSessionAudio(String)
    case anchorMatchFailed

    var description: String {
        switch self {
        case .missingValue(let option):
            return "Missing value for \(option)"
        case .missingInput:
            return "Missing required --audio /path/to/audio.wav or --session /path/to/session.json"
        case .missingModelSource:
            return "Pass either --model-folder /path/to/model-folder or --auto-download"
        case .invalidVersion(let value):
            return "Invalid --version \(value). Use v3, v2, or tdtCtc110m"
        case .invalidArguments(let message):
            return message
        case .missingSessionAudio(let role):
            return "Session is missing \(role) audio"
        case .anchorMatchFailed:
            return "Mixed transcription finished, but mic VAD did not confidently match a diarized speaker"
        }
    }
}

struct ProbeOptions {
    var audioURL: URL?
    var sessionURL: URL?
    var modelFolderURL: URL?
    var autoDownload = false
    var version: ProbeModelVersion = .v3
    var diarizeOnly = false
    var writeSession = false
}

struct ProbeOutput: Encodable {
    let text: String
    let durationSeconds: Double
    let modelVersion: String
}

struct DiarizationProbeOutput: Encodable {
    struct Span: Encodable {
        let speakerId: String
        let start: Double
        let end: Double
    }

    let durationSeconds: Double
    let sampleCount: Int
    let spanCount: Int
    let speakerIds: [String]
    let spans: [Span]
}

struct SessionRerunProbeOutput: Encodable {
    struct Segment: Encodable {
        let timestamp: Double
        let speaker: String?
        let text: String
    }

    struct AnchorMatch: Encodable {
        let speaker: String
        let anchorCoverage: Double
        let speakerCoverage: Double
        let score: Double
        let overlapDuration: Double
    }

    struct SpeechWindow: Encodable {
        let start: Double
        let end: Double
        let microphoneRMS: Float
        let systemAudioRMS: Float
        let systemToMicrophoneRMSRatio: Float
    }

    let sessionId: UUID
    let title: String
    let durationSeconds: Double
    let sampleCount: Int
    let microphoneSpeechWindowCount: Int
    let systemAudioSpeechWindowCount: Int
    let microphoneOnlySpeechWindowCount: Int
    let anchorSpeechWindowCount: Int
    let speechWindowCount: Int
    let diarizedSpanCount: Int
    let segmentCount: Int
    let speakers: [String]
    let anchorMatch: AnchorMatch
    let anchorSpeechWindows: [SpeechWindow]
    let wroteSession: Bool
    let segments: [Segment]
}

private struct ProbeTranscriptionResult {
    var segments: [TranscriptSegment]
    var speakerSpans: [SpeakerSpan]
    var sampleCount: Int
}

@main
struct NoteTakrTranscriptionProbe {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments.contains("--help") || arguments.contains("-h") {
                print(usage)
                return
            }
            let options = try parseArguments(arguments)
            if options.sessionURL != nil {
                let output = try await rerunSession(options: options)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(output)
                print(String(decoding: data, as: UTF8.self))
                return
            }
            let audioURL = try requireAudioURL(options.audioURL)
            let startedAt = Date()
            if options.diarizeOnly {
                let output = try await diarize(audioURL: audioURL)
                let data = try JSONEncoder().encode(output)
                print(String(decoding: data, as: UTF8.self))
                return
            }
            let text = try await transcribe(audioURL: audioURL, options: options)
            let output = ProbeOutput(
                text: text,
                durationSeconds: Date().timeIntervalSince(startedAt),
                modelVersion: options.version.rawValue
            )
            let data = try JSONEncoder().encode(output)
            print(String(decoding: data, as: UTF8.self))
        } catch {
            writeError(error)
            exit(1)
        }
    }

    private static func parseArguments(_ arguments: [String]) throws -> ProbeOptions {
        var options = ProbeOptions()
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--audio":
                options.audioURL = URL(fileURLWithPath: try value(after: argument, in: arguments, at: index))
                index += 2
            case "--session":
                options.sessionURL = URL(fileURLWithPath: try value(after: argument, in: arguments, at: index))
                index += 2
            case "--model-folder":
                options.modelFolderURL = URL(
                    fileURLWithPath: try value(after: argument, in: arguments, at: index),
                    isDirectory: true
                )
                index += 2
            case "--auto-download":
                options.autoDownload = true
                index += 1
            case "--version":
                let rawValue = try value(after: argument, in: arguments, at: index)
                guard let version = ProbeModelVersion(rawValue: rawValue) else {
                    throw ProbeError.invalidVersion(rawValue)
                }
                options.version = version
                index += 2
            case "--diarize-only":
                options.diarizeOnly = true
                index += 1
            case "--write-session":
                options.writeSession = true
                index += 1
            default:
                throw ProbeError.invalidArguments("Unknown argument: \(argument)\n\(usage)")
            }
        }

        if options.audioURL != nil, options.sessionURL != nil {
            throw ProbeError.invalidArguments("Use only one input: --audio or --session")
        }
        if options.sessionURL != nil, options.diarizeOnly {
            throw ProbeError.invalidArguments("--diarize-only only works with --audio")
        }
        if options.autoDownload, options.modelFolderURL != nil {
            throw ProbeError.invalidArguments("Use only one model source: --model-folder or --auto-download")
        }
        guard options.diarizeOnly || options.autoDownload || options.modelFolderURL != nil else {
            throw ProbeError.missingModelSource
        }
        return options
    }

    private static func value(after option: String, in arguments: [String], at index: Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count, !arguments[valueIndex].hasPrefix("--") else {
            throw ProbeError.missingValue(option)
        }
        return arguments[valueIndex]
    }

    private static func requireAudioURL(_ audioURL: URL?) throws -> URL {
        guard let audioURL else {
            throw ProbeError.missingInput
        }
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.audioFileNotFound
        }
        return audioURL
    }

    private static func transcribe(audioURL: URL, options: ProbeOptions) async throws -> String {
        let models: AsrModels
        if options.autoDownload {
            models = try await downloadModels(version: options.version)
        } else if let modelFolderURL = options.modelFolderURL {
            models = try await loadModels(from: modelFolderURL, version: options.version)
        } else {
            throw ProbeError.missingModelSource
        }

        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        var decoderState = try TdtDecoderState()
        let result = try await manager.transcribe(audioURL, decoderState: &decoderState)
        return result.text
    }

    private static func diarize(audioURL: URL) async throws -> DiarizationProbeOutput {
        let samples = try AudioConverter().resampleAudioFile(audioURL)
        let manager = OfflineDiarizerManager(config: .default)
        try await manager.prepareModels()
        let result = try await manager.process(audio: samples)
        let spans = result.segments.map {
            DiarizationProbeOutput.Span(
                speakerId: $0.speakerId,
                start: Double($0.startTimeSeconds),
                end: Double($0.endTimeSeconds)
            )
        }
        return DiarizationProbeOutput(
            durationSeconds: Double(samples.count) / 16_000,
            sampleCount: samples.count,
            spanCount: spans.count,
            speakerIds: Array(Set(spans.map(\.speakerId))).sorted(),
            spans: spans
        )
    }

    private static func rerunSession(options: ProbeOptions) async throws -> SessionRerunProbeOutput {
        let sessionFile = try requireSessionURL(options.sessionURL)
        let sessionDir = sessionFile.deletingLastPathComponent()
        let store = SessionStore(baseURL: sessionDir.deletingLastPathComponent())

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var session = try decoder.decode(MeetingSession.self, from: Data(contentsOf: sessionFile))

        let microphoneURL = try audioURL(in: session, sessionDir: sessionDir, role: .microphone)
        let systemAudioURL = try audioURL(in: session, sessionDir: sessionDir, role: .systemAudio)
        let converter = AudioConverter()
        let microphoneSamples = try converter.resampleAudioFile(microphoneURL)
        let systemAudioSamples = try converter.resampleAudioFile(systemAudioURL)
        let mixedSamples = mixSamples(microphoneSamples, systemAudioSamples)

        let vadManager = try await VadManager(config: VadConfig(defaultThreshold: 0.70))
        async let microphoneSpeechWindows = detectSpeechWindows(samples: microphoneSamples, manager: vadManager)
        async let systemAudioSpeechWindows = detectSpeechWindows(samples: systemAudioSamples, manager: vadManager)
        async let mixedResult = transcribeMixed(samples: mixedSamples, options: options)

        let micWindows = try await microphoneSpeechWindows
        let systemWindows = try await systemAudioSpeechWindows
        let micOnlyWindows = TranscriptMerger.microphoneOnlySpeechWindows(
            microphoneWindows: micWindows,
            systemAudioWindows: systemWindows
        )
        let anchorWindows = microphoneDominantSpeechWindows(
            micOnlyWindows,
            microphoneSamples: microphoneSamples,
            systemAudioSamples: systemAudioSamples
        )
        let result = try await mixedResult
        guard let anchored = TranscriptMerger.promoteAnchoredSpeaker(
            in: result.segments,
            speakerSpans: result.speakerSpans,
            anchorWindows: anchorWindows,
            requireAnchorOverlapForPrimary: true
        ) else {
            throw ProbeError.anchorMatchFailed
        }

        if options.writeSession {
            session.transcriptSegments = anchored.segments
            try store.save(session)
            let noteURL = store.sessionURL(for: session).appendingPathComponent("note.md")
            let markdown = MarkdownNoteRenderer.render(session: session)
            try markdown.write(to: noteURL, atomically: true, encoding: .utf8)
        }

        let speakers = Array(Set(anchored.segments.compactMap(\.speaker))).sorted()
        return SessionRerunProbeOutput(
            sessionId: session.id,
            title: session.title,
            durationSeconds: Double(result.sampleCount) / 16_000.0,
            sampleCount: result.sampleCount,
            microphoneSpeechWindowCount: micWindows.count,
            systemAudioSpeechWindowCount: systemWindows.count,
            microphoneOnlySpeechWindowCount: micOnlyWindows.count,
            anchorSpeechWindowCount: anchorWindows.count,
            speechWindowCount: anchorWindows.count,
            diarizedSpanCount: result.speakerSpans.count,
            segmentCount: anchored.segments.count,
            speakers: speakers,
            anchorMatch: SessionRerunProbeOutput.AnchorMatch(
                speaker: anchored.match.speaker,
                anchorCoverage: anchored.match.anchorCoverage,
                speakerCoverage: anchored.match.speakerCoverage,
                score: anchored.match.score,
                overlapDuration: anchored.match.overlapDuration
            ),
            anchorSpeechWindows: anchorWindows.map {
                windowOutput($0, microphoneSamples: microphoneSamples, systemAudioSamples: systemAudioSamples)
            },
            wroteSession: options.writeSession,
            segments: anchored.segments.map {
                SessionRerunProbeOutput.Segment(
                    timestamp: $0.timestamp,
                    speaker: $0.speaker,
                    text: $0.text
                )
            }
        )
    }

    private static func requireSessionURL(_ sessionURL: URL?) throws -> URL {
        guard let sessionURL else {
            throw ProbeError.missingInput
        }
        let fileURL: URL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sessionURL.path, isDirectory: &isDirectory) else {
            throw TranscriptionError.audioFileNotFound
        }
        if isDirectory.boolValue {
            fileURL = sessionURL.appendingPathComponent("session.json")
        } else {
            fileURL = sessionURL
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw TranscriptionError.audioFileNotFound
        }
        return fileURL
    }

    private static func audioURL(
        in session: MeetingSession,
        sessionDir: URL,
        role: AudioSourceType
    ) throws -> URL {
        let prefix = role.fileNamePrefix
        for path in session.audioFilePaths {
            let url = URL(fileURLWithPath: path)
            if url.lastPathComponent.hasPrefix(prefix), FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            let healed = sessionDir.appendingPathComponent(url.lastPathComponent)
            if healed.lastPathComponent.hasPrefix(prefix), FileManager.default.fileExists(atPath: healed.path) {
                return healed
            }
        }
        let fallback = sessionDir.appendingPathComponent("\(prefix).m4a")
        if FileManager.default.fileExists(atPath: fallback.path) {
            return fallback
        }
        throw ProbeError.missingSessionAudio(role.displayName)
    }

    private static func transcribeMixed(samples: [Float], options: ProbeOptions) async throws -> ProbeTranscriptionResult {
        let models: AsrModels
        if options.autoDownload {
            models = try await downloadModels(version: options.version)
        } else if let modelFolderURL = options.modelFolderURL {
            models = try await loadModels(from: modelFolderURL, version: options.version)
        } else {
            throw ProbeError.missingModelSource
        }

        async let asrResult = transcribe(samples: samples, models: models)
        async let diarizedSpans = diarize(samples: samples)
        let asr = try await asrResult
        let spans = try await diarizedSpans
        let words = reconstructWords(from: asr.tokenTimings, fallbackText: asr.text)
        var segments = TranscriptAssembler.assemble(
            words: words,
            speakerSpans: spans,
            sameSpeakerSplitGap: 2.0
        )
        if shouldUseCoarseTimingFallback(segments: segments, speakerSpans: spans) {
            let fallbackText = words.map(\.text).joined(separator: " ")
            let fallback = TranscriptAssembler.assembleFallback(
                text: fallbackText.isEmpty ? asr.text : fallbackText,
                speakerSpans: spans
            )
            if !fallback.isEmpty {
                segments = fallback
            }
        }
        if segments.isEmpty {
            segments = [TranscriptSegment(timestamp: 0, speaker: nil, text: asr.text)]
        }
        return ProbeTranscriptionResult(segments: segments, speakerSpans: spans, sampleCount: samples.count)
    }

    private static func transcribe(samples: [Float], models: AsrModels) async throws -> ASRResult {
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        var decoderState = try TdtDecoderState()
        return try await manager.transcribe(samples, decoderState: &decoderState)
    }

    private static func diarize(samples: [Float]) async throws -> [SpeakerSpan] {
        let manager = OfflineDiarizerManager(config: .default)
        try await manager.prepareModels()
        let result = try await manager.process(audio: samples)
        return result.segments.map {
            SpeakerSpan(
                speakerId: $0.speakerId,
                start: TimeInterval($0.startTimeSeconds),
                end: TimeInterval($0.endTimeSeconds)
            )
        }
    }

    private static func detectSpeechWindows(
        samples: [Float],
        manager: VadManager
    ) async throws -> [TranscriptMerger.SpeechWindow] {
        let config = VadSegmentationConfig(
            minSpeechDuration: 0.25,
            minSilenceDuration: 0.45,
            maxSpeechDuration: 20.0,
            speechPadding: 0.15
        )
        let segments = try await manager.segmentSpeech(samples, config: config)
        return segments.map {
            TranscriptMerger.SpeechWindow(start: $0.startTime, end: $0.endTime)
        }
    }

    private static func mixSamples(_ left: [Float], _ right: [Float]) -> [Float] {
        let count = max(left.count, right.count)
        guard count > 0 else { return [] }
        var mixed = Array(repeating: Float(0), count: count)
        var peak = Float(0)
        for index in 0..<count {
            let leftSample = index < left.count ? left[index] : 0
            let rightSample = index < right.count ? right[index] : 0
            let sample = leftSample + rightSample
            mixed[index] = sample
            peak = max(peak, abs(sample))
        }
        guard peak > 1 else { return mixed }
        let scale = 1 / peak
        return mixed.map { $0 * scale }
    }

    private static func microphoneDominantSpeechWindows(
        _ windows: [TranscriptMerger.SpeechWindow],
        microphoneSamples: [Float],
        systemAudioSamples: [Float],
        maxSystemToMicrophoneRMSRatio: Float = 0.80,
        minMicrophoneRMS: Float = 0.0005
    ) -> [TranscriptMerger.SpeechWindow] {
        windows.filter { window in
            let microphoneRMS = rms(samples: microphoneSamples, window: window)
            guard microphoneRMS >= minMicrophoneRMS else { return false }
            let systemRMS = rms(samples: systemAudioSamples, window: window)
            return systemRMS / microphoneRMS <= maxSystemToMicrophoneRMSRatio
        }
    }

    private static func windowOutput(
        _ window: TranscriptMerger.SpeechWindow,
        microphoneSamples: [Float],
        systemAudioSamples: [Float]
    ) -> SessionRerunProbeOutput.SpeechWindow {
        let microphoneRMS = rms(samples: microphoneSamples, window: window)
        let systemRMS = rms(samples: systemAudioSamples, window: window)
        let ratio = microphoneRMS > 0 ? systemRMS / microphoneRMS : .infinity
        return SessionRerunProbeOutput.SpeechWindow(
            start: window.start,
            end: window.end,
            microphoneRMS: microphoneRMS,
            systemAudioRMS: systemRMS,
            systemToMicrophoneRMSRatio: ratio
        )
    }

    private static func rms(
        samples: [Float],
        window: TranscriptMerger.SpeechWindow,
        sampleRate: Double = 16_000
    ) -> Float {
        guard !samples.isEmpty, window.end > window.start else { return 0 }
        let start = max(0, min(samples.count, Int((window.start * sampleRate).rounded(.down))))
        let end = max(start, min(samples.count, Int((window.end * sampleRate).rounded(.up))))
        guard end > start else { return 0 }

        var sum = Double(0)
        for sample in samples[start..<end] {
            let value = Double(sample)
            sum += value * value
        }
        return Float((sum / Double(end - start)).squareRoot())
    }

    private static func shouldUseCoarseTimingFallback(
        segments: [TranscriptSegment],
        speakerSpans: [SpeakerSpan]
    ) -> Bool {
        let detectedSpeakerCount = Set(speakerSpans.map(\.speakerId)).count
        guard detectedSpeakerCount > 1 else { return false }
        let assembledSpeakerCount = Set(segments.compactMap(\.speaker)).count
        return assembledSpeakerCount <= 1
    }

    private static func reconstructWords(from timings: [TokenTiming]?, fallbackText: String) -> [TimedWord] {
        guard let timings, !timings.isEmpty else {
            let trimmed = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [TimedWord(text: trimmed, start: 0, end: 0)]
        }

        let wordBoundary: Character = "\u{2581}"
        var words: [TimedWord] = []
        var currentText = ""
        var currentStart: TimeInterval = 0
        var currentEnd: TimeInterval = 0

        func flush() {
            let clean = currentText.trimmingCharacters(in: .whitespaces)
            guard !clean.isEmpty else { currentText = ""; return }
            words.append(TimedWord(text: clean, start: currentStart, end: currentEnd))
            currentText = ""
        }

        for timing in timings {
            let token = timing.token
            if token.isEmpty || token == "<blank>" || token == "<pad>" {
                continue
            }
            let startsWord = token.hasPrefix(String(wordBoundary)) || token.hasPrefix(" ")
            var piece = token
            if piece.hasPrefix(String(wordBoundary)) {
                piece.removeFirst()
            }
            while piece.hasPrefix(" ") {
                piece.removeFirst()
            }

            if startsWord || currentText.isEmpty {
                if startsWord { flush() }
                if currentText.isEmpty { currentStart = timing.startTime }
            }
            currentText += piece
            currentEnd = timing.endTime
        }
        flush()

        return words
    }

    private static func downloadModels(version: ProbeModelVersion) async throws -> AsrModels {
        switch version {
        case .v3:
            return try await AsrModels.downloadAndLoad(version: .v3)
        case .v2:
            return try await AsrModels.downloadAndLoad(version: .v2)
        case .tdtCtc110m:
            return try await AsrModels.downloadAndLoad(version: .tdtCtc110m)
        }
    }

    private static func loadModels(from url: URL, version: ProbeModelVersion) async throws -> AsrModels {
        switch version {
        case .v3:
            return try await AsrModels.load(from: url, version: .v3)
        case .v2:
            return try await AsrModels.load(from: url, version: .v2)
        case .tdtCtc110m:
            return try await AsrModels.load(from: url, version: .tdtCtc110m)
        }
    }

    private static var usage: String {
        """
        Usage:
          swift run NoteTakrTranscriptionProbe --audio /path/to/audio.wav --model-folder /path/to/parakeet-tdt-0.6b-v3-coreml --version v3
          swift run NoteTakrTranscriptionProbe --audio /path/to/audio.wav --auto-download --version tdtCtc110m
          swift run NoteTakrTranscriptionProbe --audio /path/to/audio.wav --diarize-only
        """
    }

    private static func writeError(_ error: Error) {
        let message: String
        if let probeError = error as? ProbeError {
            message = "\(probeError.description)\n"
        } else {
            message = "\(error)\n"
        }
        FileHandle.standardError.write(Data(message.utf8))
    }
}
