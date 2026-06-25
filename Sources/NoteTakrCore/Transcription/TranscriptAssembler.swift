import Foundation

/// A single word with its time span, reconstructed from ASR token timings.
public struct TimedWord: Equatable, Sendable {
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// A contiguous span of speech attributed to one speaker, produced by diarization.
public struct SpeakerSpan: Equatable, Sendable {
    public var speakerId: String
    public var start: TimeInterval
    public var end: TimeInterval

    public init(speakerId: String, start: TimeInterval, end: TimeInterval) {
        self.speakerId = speakerId
        self.start = start
        self.end = end
    }
}

/// A confident word replacement produced by vocabulary boosting.
public struct WordReplacement: Equatable, Sendable {
    public var original: String
    public var replacement: String

    public init(original: String, replacement: String) {
        self.original = original
        self.replacement = replacement
    }
}

/// Pure logic that turns ASR words + diarization spans into speaker-labelled
/// transcript segments, and applies vocabulary-boosting replacements. Kept free
/// of FluidAudio (and any I/O) so it can be unit-tested deterministically.
public enum TranscriptAssembler {

    /// Combines word timings with diarization spans into grouped transcript
    /// segments. Each word is attributed to the speaker span it overlaps most
    /// (falling back to the nearest span when there is no overlap). Raw speaker
    /// ids are relabelled to "Speaker 1", "Speaker 2", … by first appearance.
    /// Consecutive words from the same speaker are merged into one segment.
    ///
    /// When `speakerSpans` is empty (diarization unavailable or single speaker),
    /// the words are merged into one segment with no speaker label.
    public static func assemble(words: [TimedWord], speakerSpans: [SpeakerSpan]) -> [TranscriptSegment] {
        let cleanedWords = words.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !cleanedWords.isEmpty else { return [] }

        guard !speakerSpans.isEmpty else {
            let text = cleanedWords.map(\.text).joined(separator: " ")
            return [TranscriptSegment(timestamp: cleanedWords[0].start, speaker: nil, text: text)]
        }

        let labels = speakerLabels(for: speakerSpans)

        var segments: [TranscriptSegment] = []
        var currentSpeaker: String?
        var currentWords: [String] = []
        var currentStart: TimeInterval = cleanedWords[0].start

        func flush() {
            guard !currentWords.isEmpty else { return }
            segments.append(
                TranscriptSegment(
                    timestamp: currentStart,
                    speaker: currentSpeaker,
                    text: currentWords.joined(separator: " ")
                )
            )
            currentWords.removeAll(keepingCapacity: true)
        }

        for word in cleanedWords {
            let rawSpeaker = bestSpeaker(for: word, in: speakerSpans)
            let label = rawSpeaker.flatMap { labels[$0] }
            if currentWords.isEmpty {
                currentSpeaker = label
                currentStart = word.start
            } else if label != currentSpeaker {
                flush()
                currentSpeaker = label
                currentStart = word.start
            }
            currentWords.append(word.text)
        }
        flush()

        return segments
    }

    /// Last-resort assembly for ASR results without useful word timings. When
    /// diarization clearly detects multiple speakers but ASR timing collapses to
    /// one coarse text block, divide the transcript across diarized speaker runs
    /// by run duration so distinct speakers remain visible instead of silently
    /// flattening to one label.
    public static func assembleFallback(text: String, speakerSpans: [SpeakerSpan]) -> [TranscriptSegment] {
        let words = text
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !words.isEmpty else { return [] }

        let cleanedSpans = speakerSpans
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard !cleanedSpans.isEmpty else {
            return [TranscriptSegment(timestamp: 0, speaker: nil, text: words.joined(separator: " "))]
        }

        let labels = speakerLabels(for: cleanedSpans)
        let runs = speakerRuns(from: cleanedSpans)
        let totalDuration = runs.reduce(0) { $0 + max(0.001, $1.duration) }
        guard totalDuration > 0 else { return [] }

        var segments: [TranscriptSegment] = []
        var wordIndex = 0
        for (runIndex, run) in runs.enumerated() where wordIndex < words.count {
            let remainingWords = words.count - wordIndex
            let remainingRuns = runs.count - runIndex
            let count: Int
            if runIndex == runs.indices.last {
                count = remainingWords
            } else {
                let proportional = Int((Double(words.count) * run.duration / totalDuration).rounded())
                count = max(1, min(proportional, remainingWords - max(0, remainingRuns - 1)))
            }
            guard count > 0 else { continue }
            let nextIndex = min(words.count, wordIndex + count)
            let text = words[wordIndex..<nextIndex].joined(separator: " ")
            segments.append(
                TranscriptSegment(
                    timestamp: run.start,
                    speaker: labels[run.speakerId],
                    text: text
                )
            )
            wordIndex = nextIndex
        }

        return segments
    }

    /// Applies confident vocabulary-boosting replacements to the word list,
    /// preserving timing. Each replacement is matched (case-insensitively,
    /// ignoring surrounding punctuation) against the next not-yet-replaced word,
    /// left to right. Multi-word originals match a window of consecutive words.
    public static func applyBoost(to words: [TimedWord], replacements: [WordReplacement]) -> [TimedWord] {
        guard !replacements.isEmpty, !words.isEmpty else { return words }
        var result = words
        var consumed = Array(repeating: false, count: words.count)

        for replacement in replacements {
            let originalTokens = replacement.original
                .split(whereSeparator: { $0 == " " })
                .map { normalize(String($0)) }
                .filter { !$0.isEmpty }
            guard !originalTokens.isEmpty else { continue }

            if originalTokens.count == 1 {
                if let idx = nextMatch(of: originalTokens[0], in: result, consumed: consumed) {
                    result[idx].text = reapplyPunctuation(from: result[idx].text, to: replacement.replacement)
                    consumed[idx] = true
                }
            } else if let range = nextWindowMatch(of: originalTokens, in: result, consumed: consumed) {
                // Replace the first word in the window with the full replacement
                // and drop the trailing words by marking them consumed/empty.
                result[range.lowerBound].text = replacement.replacement
                for i in (range.lowerBound + 1)..<range.upperBound {
                    result[i].text = ""
                    consumed[i] = true
                }
                consumed[range.lowerBound] = true
            }
        }

        return result.filter { !$0.text.isEmpty }
    }

    // MARK: - Speaker helpers

    /// Maps raw diarization speaker ids to stable "Speaker N" labels in order of
    /// first appearance along the timeline.
    static func speakerLabels(for spans: [SpeakerSpan]) -> [String: String] {
        var labels: [String: String] = [:]
        var next = 1
        for span in spans.sorted(by: { $0.start < $1.start }) where labels[span.speakerId] == nil {
            labels[span.speakerId] = "Speaker \(next)"
            next += 1
        }
        return labels
    }

    static func bestSpeaker(for word: TimedWord, in spans: [SpeakerSpan]) -> String? {
        var bestOverlap: TimeInterval = 0
        var bestSpeaker: String?
        for span in spans {
            let overlap = min(word.end, span.end) - max(word.start, span.start)
            if overlap > bestOverlap {
                bestOverlap = overlap
                bestSpeaker = span.speakerId
            }
        }
        if bestSpeaker != nil { return bestSpeaker }

        // No overlap: attribute to the nearest span by midpoint distance.
        let wordMid = (word.start + word.end) / 2
        var bestDistance = TimeInterval.greatestFiniteMagnitude
        for span in spans {
            let spanMid = (span.start + span.end) / 2
            let distance = abs(spanMid - wordMid)
            if distance < bestDistance {
                bestDistance = distance
                bestSpeaker = span.speakerId
            }
        }
        return bestSpeaker
    }

    private struct SpeakerRun {
        var speakerId: String
        var start: TimeInterval
        var end: TimeInterval

        var duration: TimeInterval { max(0, end - start) }
    }

    private static func speakerRuns(from spans: [SpeakerSpan]) -> [SpeakerRun] {
        var runs: [SpeakerRun] = []
        for span in spans {
            if let last = runs.last, last.speakerId == span.speakerId {
                runs[runs.count - 1].end = max(last.end, span.end)
            } else {
                runs.append(SpeakerRun(speakerId: span.speakerId, start: span.start, end: span.end))
            }
        }
        return runs
    }

    // MARK: - Boost helpers

    private static func normalize(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }

    private static func nextMatch(of token: String, in words: [TimedWord], consumed: [Bool]) -> Int? {
        for idx in words.indices where !consumed[idx] {
            if normalize(words[idx].text) == token { return idx }
        }
        return nil
    }

    private static func nextWindowMatch(of tokens: [String], in words: [TimedWord], consumed: [Bool]) -> Range<Int>? {
        guard tokens.count >= 1, words.count >= tokens.count else { return nil }
        for start in 0...(words.count - tokens.count) {
            var matched = true
            for offset in tokens.indices {
                let idx = start + offset
                if consumed[idx] || normalize(words[idx].text) != tokens[offset] {
                    matched = false
                    break
                }
            }
            if matched { return start..<(start + tokens.count) }
        }
        return nil
    }

    /// Carries leading/trailing punctuation from the original word onto the
    /// replacement so e.g. "noatakr," becomes "NoteTakr,".
    private static func reapplyPunctuation(from original: String, to replacement: String) -> String {
        let leading = original.prefix { !$0.isLetter && !$0.isNumber }
        let trailing = original.reversed().prefix { !$0.isLetter && !$0.isNumber }.reversed()
        return String(leading) + replacement + String(trailing)
    }
}
