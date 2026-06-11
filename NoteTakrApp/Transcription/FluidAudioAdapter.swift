import Foundation
import FluidAudio
import NoteTakrKit
import NoteTakrCore

// MARK: - Injectable seams

/// ASR seam: decodes nothing, just runs speech-to-text on 16 kHz mono samples.
protocol FluidAudioRuntimeProtocol: Sendable {
    func transcribe(samples: [Float], settings: TranscriptionModelSettings) async throws -> ASRResult
}

/// Decodes an audio file to 16 kHz mono Float samples (shared by ASR + diarization).
protocol AudioSampleLoading: Sendable {
    func loadSamples(from url: URL) throws -> [Float]
}

/// Speaker diarization seam: "who spoke when" as plain time spans.
protocol SpeakerDiarizing: Sendable {
    func diarize(samples: [Float]) async throws -> [SpeakerSpan]
}

/// Vocabulary-boosting seam: returns confident word replacements for the transcript.
protocol VocabularyBoosting: Sendable {
    func boost(
        samples: [Float],
        transcript: String,
        tokenTimings: [TokenTiming],
        entries: [VocabularyEntry]
    ) async throws -> [WordReplacement]
}

// MARK: - ASR runtime (Parakeet TDT)

actor FluidAudioRuntime: FluidAudioRuntimeProtocol {
    private var loadedSettings: TranscriptionModelSettings?
    private var manager: AsrManager?

    func transcribe(samples: [Float], settings: TranscriptionModelSettings) async throws -> ASRResult {
        guard settings.source != .notConfigured else {
            throw TranscriptionError.modelUnavailable
        }
        let manager = try await manager(for: settings)
        var decoderState = try TdtDecoderState()
        return try await manager.transcribe(samples, decoderState: &decoderState)
    }

    private func manager(for settings: TranscriptionModelSettings) async throws -> AsrManager {
        if let manager, loadedSettings == settings {
            return manager
        }
        let models = try await loadModels(for: settings)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
        loadedSettings = settings
        return manager
    }

    private func loadModels(for settings: TranscriptionModelSettings) async throws -> AsrModels {
        switch settings.source {
        case .notConfigured:
            throw TranscriptionError.modelUnavailable
        case .localFolder(let url):
            switch settings.modelVersion {
            case .v3: return try await AsrModels.load(from: url, version: .v3)
            case .v2: return try await AsrModels.load(from: url, version: .v2)
            case .tdtCtc110m: return try await AsrModels.load(from: url, version: .tdtCtc110m)
            }
        case .fluidAudioDefaultCache:
            switch settings.modelVersion {
            case .v3: return try await AsrModels.downloadAndLoad(version: .v3)
            case .v2: return try await AsrModels.downloadAndLoad(version: .v2)
            case .tdtCtc110m: return try await AsrModels.downloadAndLoad(version: .tdtCtc110m)
            }
        }
    }
}

// MARK: - Audio loading

struct FluidAudioSampleLoader: AudioSampleLoading {
    func loadSamples(from url: URL) throws -> [Float] {
        try AudioConverter().resampleAudioFile(url)
    }
}

// MARK: - Diarization runtime (Pyannote Community-1 offline pipeline)

actor OfflineDiarizationRuntime: SpeakerDiarizing {
    private let manager = OfflineDiarizerManager(config: .default)

    func diarize(samples: [Float]) async throws -> [SpeakerSpan] {
        // `process` lazily downloads + prepares the CoreML models on first use.
        let result = try await manager.process(audio: samples)
        return result.segments.map {
            SpeakerSpan(
                speakerId: $0.speakerId,
                start: TimeInterval($0.startTimeSeconds),
                end: TimeInterval($0.endTimeSeconds)
            )
        }
    }
}

// MARK: - Vocabulary boosting (CTC keyword spotting + rescoring)

actor FluidAudioVocabularyBooster: VocabularyBoosting {
    func boost(
        samples: [Float],
        transcript: String,
        tokenTimings: [TokenTiming],
        entries: [VocabularyEntry]
    ) async throws -> [WordReplacement] {
        guard !entries.isEmpty, !tokenTimings.isEmpty else { return [] }

        // FluidAudio tokenizes terms from a "simple format" file (one phrase per
        // line, optional "phrase: alias1, alias2"). Write the enabled vocabulary
        // to a temp file, then load + tokenize against the CTC tokenizer.
        let vocabFile = try writeSimpleVocabularyFile(entries)
        defer { try? FileManager.default.removeItem(at: vocabFile) }

        let (vocab, ctcModels) = try await CustomVocabularyContext.loadWithCtcTokens(
            from: vocabFile.path
        )
        guard !vocab.terms.isEmpty else { return [] }

        let spotter = CtcKeywordSpotter(models: ctcModels, blankId: ctcModels.vocabulary.count)
        let spot = try await spotter.spotKeywordsWithLogProbs(
            audioSamples: samples,
            customVocabulary: vocab,
            minScore: nil
        )
        guard !spot.logProbs.isEmpty else { return [] }

        let rescorer = try await VocabularyRescorer.create(
            spotter: spotter,
            vocabulary: vocab,
            config: .default,
            ctcModelDirectory: CtcModels.defaultCacheDirectory(for: ctcModels.variant)
        )
        let output = rescorer.ctcTokenRescore(
            transcript: transcript,
            tokenTimings: tokenTimings,
            logProbs: spot.logProbs,
            frameDuration: spot.frameDuration
        )
        guard output.wasModified else { return [] }

        return output.replacements.compactMap { result in
            guard result.shouldReplace, let replacement = result.replacementWord else { return nil }
            return WordReplacement(original: result.originalWord, replacement: replacement)
        }
    }

    private func writeSimpleVocabularyFile(_ entries: [VocabularyEntry]) throws -> URL {
        var lines: [String] = []
        for entry in entries {
            let phrase = entry.phrase.trimmingCharacters(in: .whitespaces)
            guard !phrase.isEmpty else { continue }
            if entry.aliases.isEmpty {
                lines.append(phrase)
            } else {
                lines.append("\(phrase): \(entry.aliases.joined(separator: ", "))")
            }
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notetakr-vocab-\(UUID().uuidString).txt")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - Adapter

/// Runs the full local transcription pipeline: ASR + speaker diarization +
/// optional vocabulary boosting, producing speaker-labelled transcript segments.
final class FluidAudioAdapter: TranscriptionEngine, @unchecked Sendable {
    private let settingsStore: TranscriptionSettingsStore
    private let runtime: any FluidAudioRuntimeProtocol
    private let audioLoader: any AudioSampleLoading
    private let diarizer: any SpeakerDiarizing
    private let booster: any VocabularyBoosting

    init(
        settingsStore: TranscriptionSettingsStore,
        runtime: any FluidAudioRuntimeProtocol = FluidAudioRuntime(),
        audioLoader: any AudioSampleLoading = FluidAudioSampleLoader(),
        diarizer: any SpeakerDiarizing = OfflineDiarizationRuntime(),
        booster: any VocabularyBoosting = FluidAudioVocabularyBooster()
    ) {
        self.settingsStore = settingsStore
        self.runtime = runtime
        self.audioLoader = audioLoader
        self.diarizer = diarizer
        self.booster = booster
    }

    func transcribe(audioURL: URL, vocabulary: [VocabularyEntry]) async throws -> [TranscriptSegment] {
        let settings = settingsStore.load()
        guard settings.source != .notConfigured else {
            throw TranscriptionError.modelUnavailable
        }
        return try await transcribeSource(
            url: audioURL, vocabulary: vocabulary, settings: settings, diarize: true
        )
    }

    /// Multi-stream entry point: transcribes the microphone and system-audio files
    /// separately, then merges them into one timeline-ordered transcript. The
    /// microphone collapses to a single "Speaker 1 (You)" (no diarization needed);
    /// system-audio speakers are diarized and shifted to "Speaker 2", "Speaker 3", …
    ///
    /// With a single source we fall back to the legacy single-stream behaviour
    /// (normal diarization, "Speaker 1/2…"). The in-person/one-device case lands
    /// here too — the lone microphone then holds every voice, so speaker
    /// separation degrades to whatever diarization can recover (known limitation).
    func transcribe(sources: [TranscriptionSource], vocabulary: [VocabularyEntry]) async throws -> [TranscriptSegment] {
        let settings = settingsStore.load()
        guard settings.source != .notConfigured else {
            throw TranscriptionError.modelUnavailable
        }
        guard !sources.isEmpty else {
            throw TranscriptionError.audioFileNotFound
        }
        if sources.count == 1 {
            return try await transcribeSource(
                url: sources[0].url, vocabulary: vocabulary, settings: settings, diarize: true
            )
        }

        var groups: [[TranscriptSegment]] = []
        for source in sources {
            let diarize = source.role == .systemAudio
            let segments = try await transcribeSource(
                url: source.url, vocabulary: vocabulary, settings: settings, diarize: diarize
            )
            switch source.role {
            case .microphone:
                groups.append(TranscriptMerger.forceSingleSpeaker(segments, label: TranscriptMerger.primarySpeakerLabel))
            case .systemAudio:
                groups.append(TranscriptMerger.offsetSpeakers(segments, startingAt: 2))
            }
        }
        return TranscriptMerger.merge(groups)
    }

    /// Runs ASR (+ optional diarization + vocabulary boosting) on one audio file
    /// and assembles speaker-labelled segments. When `diarize` is false the result
    /// is a single un-labelled speaker (used for the microphone stream).
    private func transcribeSource(
        url: URL,
        vocabulary: [VocabularyEntry],
        settings: TranscriptionModelSettings,
        diarize: Bool
    ) async throws -> [TranscriptSegment] {
        let samples = try audioLoader.loadSamples(from: url)

        // ASR and diarization are independent — run them concurrently.
        async let asrResult = runtime.transcribe(samples: samples, settings: settings)
        async let diarizedSpans = Self.diarizeIfNeeded(diarize, diarizer: diarizer, samples: samples)

        let asr = try await asrResult
        let spans = await diarizedSpans

        var words = Self.reconstructWords(from: asr.tokenTimings, fallbackText: asr.text)

        let enabled = vocabulary.filter { $0.isEnabled }
        if !enabled.isEmpty, let timings = asr.tokenTimings, !timings.isEmpty {
            if let replacements = try? await booster.boost(
                samples: samples,
                transcript: asr.text,
                tokenTimings: timings,
                entries: enabled
            ) {
                words = TranscriptAssembler.applyBoost(to: words, replacements: replacements)
            }
        }

        let segments = TranscriptAssembler.assemble(words: words, speakerSpans: spans)
        if segments.isEmpty {
            return [TranscriptSegment(timestamp: 0, speaker: nil, text: asr.text)]
        }
        return segments
    }

    private static func diarizeIfNeeded(
        _ enabled: Bool,
        diarizer: any SpeakerDiarizing,
        samples: [Float]
    ) async -> [SpeakerSpan] {
        guard enabled else { return [] }
        return (try? await diarizer.diarize(samples: samples)) ?? []
    }

    /// Reconstructs word-level timings from SentencePiece token timings. Tokens
    /// that begin a new word are prefixed with "▁" (U+2581); continuation tokens
    /// are appended to the current word.
    static func reconstructWords(from timings: [TokenTiming]?, fallbackText: String) -> [TimedWord] {
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
            let startsWord = token.hasPrefix(String(wordBoundary))
            let piece = token.replacingOccurrences(of: String(wordBoundary), with: "")

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
}
