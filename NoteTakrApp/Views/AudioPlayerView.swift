import AVFoundation
import SwiftUI
import NoteTakrKit

// MARK: - AudioPlaybackState

/// Describes the state of the post-recording audio player.
/// Stored in the view layer; actual playback is macOS-only via AVFoundation.
enum AudioPlaybackState: Equatable {
    case idle
    case ready(duration: Double)
    case playing(currentTime: Double, duration: Double)
    case paused(currentTime: Double, duration: Double)
}

// MARK: - AudioPlayerView

/// Seekable audio player shown in the frontmatter Transcript row after recording finishes.
/// Matches the `.player` design in frontmatter.html: play/pause + scrubber + mm:ss / mm:ss.
/// Verified only on macOS runner — AVFoundation paths are not available on Linux.
struct AudioPlayerView: View {
    let state: AudioPlaybackState
    let onTogglePlay: () -> Void
    let onSeek: (Double) -> Void
    @Environment(\.themeColors) private var theme

    var body: some View {
        HStack(spacing: 8) {
            playPauseButton

            scrubber
                .frame(maxWidth: .infinity)

            durationLabel
        }
        .frame(height: 24)
    }

    // MARK: - Play/pause

    private var playPauseButton: some View {
        Button(action: onTogglePlay) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.secondaryText.swiftUIColor)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .disabled(state == .idle)
    }

    // MARK: - Scrubber

    private var scrubber: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.hairline.swiftUIColor)
                    .frame(height: 3)

                Capsule()
                    .fill(theme.secondaryText.swiftUIColor)
                    .frame(width: progressWidth(in: geo.size.width), height: 3)

                Circle()
                    .fill(theme.primaryText.swiftUIColor)
                    .frame(width: 10, height: 10)
                    .offset(x: progressWidth(in: geo.size.width) - 5)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = max(0, min(1, value.location.x / geo.size.width))
                        onSeek(fraction * totalDuration)
                    }
            )
        }
        .frame(height: 10)
    }

    // MARK: - Duration label

    private var durationLabel: some View {
        Text(durationText)
            .font(.system(size: 10.5, design: .monospaced).monospacedDigit())
            .foregroundStyle(theme.tertiaryText.swiftUIColor)
    }

    // MARK: - Helpers

    private var isPlaying: Bool {
        if case .playing = state { return true }
        return false
    }

    private var currentTime: Double {
        switch state {
        case .playing(let t, _), .paused(let t, _): return t
        default: return 0
        }
    }

    private var totalDuration: Double {
        switch state {
        case .ready(let d), .playing(_, let d), .paused(_, let d): return d
        default: return 0
        }
    }

    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        guard totalDuration > 0 else { return 0 }
        return CGFloat(currentTime / totalDuration) * totalWidth
    }

    private var durationText: String {
        "\(FrontmatterPresenter.formatElapsed(currentTime)) / \(FrontmatterPresenter.formatElapsed(totalDuration))"
    }
}

// MARK: - AudioPlaybackController

/// Real AVAudioPlayer-backed playback for the Transcript-row player.
/// Owns the player + a UI tick timer and publishes `AudioPlaybackState`.
@MainActor
final class AudioPlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var state: AudioPlaybackState = .idle

    private var player: AVAudioPlayer?
    private var tickTimer: Timer?

    /// Loads (or reloads) the audio file. Safe to call with nil — resets to idle.
    func load(url: URL?) {
        stopTimer()
        player?.stop()
        player = nil
        guard let url, FileManager.default.fileExists(atPath: url.path),
              let p = try? AVAudioPlayer(contentsOf: url) else {
            state = .idle
            return
        }
        p.delegate = self
        p.prepareToPlay()
        player = p
        state = .ready(duration: p.duration)
    }

    func togglePlay() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            stopTimer()
            state = .paused(currentTime: player.currentTime, duration: player.duration)
        } else {
            player.play()
            startTimer()
            state = .playing(currentTime: player.currentTime, duration: player.duration)
        }
    }

    func seek(to time: Double) {
        guard let player else { return }
        player.currentTime = max(0, min(time, player.duration))
        if player.isPlaying {
            state = .playing(currentTime: player.currentTime, duration: player.duration)
        } else {
            state = .paused(currentTime: player.currentTime, duration: player.duration)
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stopTimer()
            self.state = .ready(duration: player.duration)
        }
    }

    private func startTimer() {
        stopTimer()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player, player.isPlaying else { return }
                self.state = .playing(currentTime: player.currentTime, duration: player.duration)
            }
        }
    }

    private func stopTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
    }
}
