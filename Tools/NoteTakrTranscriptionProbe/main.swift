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
    case missingAudio
    case missingModelSource
    case invalidVersion(String)
    case invalidArguments(String)

    var description: String {
        switch self {
        case .missingValue(let option):
            return "Missing value for \(option)"
        case .missingAudio:
            return "Missing required --audio /path/to/audio.wav"
        case .missingModelSource:
            return "Pass either --model-folder /path/to/model-folder or --auto-download"
        case .invalidVersion(let value):
            return "Invalid --version \(value). Use v3, v2, or tdtCtc110m"
        case .invalidArguments(let message):
            return message
        }
    }
}

struct ProbeOptions {
    var audioURL: URL?
    var modelFolderURL: URL?
    var autoDownload = false
    var version: ProbeModelVersion = .v3
    var diarizeOnly = false
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
            default:
                throw ProbeError.invalidArguments("Unknown argument: \(argument)\n\(usage)")
            }
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
            throw ProbeError.missingAudio
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
