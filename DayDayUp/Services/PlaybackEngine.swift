import Foundation
import AVFoundation
import MediaPlayer
import Observation

/// One audio player for the whole app, so playback keeps going when the learner
/// switches tabs or locks the screen (UIBackgroundModes = audio).
/// A second player plays single-word clips without moving the main position.
@MainActor
@Observable
final class PlaybackEngine {
    private(set) var isPlaying = false
    private(set) var time: Double = 0
    private(set) var duration: Double = 1
    private(set) var rate: Double = 1.0
    private(set) var hasAudio = false

    /// Called on every clock tick (about 30 times a second while playing) and after each seek.
    @ObservationIgnored var onTick: ((Double) -> Void)?
    @ObservationIgnored var onNextSentence: (() -> Void)?
    @ObservationIgnored var onPreviousSentence: (() -> Void)?

    private let player = AVPlayer()
    private let clipPlayer = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var currentURL: URL?
    @ObservationIgnored private var nowTitle = ""
    @ObservationIgnored private var nowAlbum = ""
    @ObservationIgnored private var wantsToPlay = false

    init() {
        player.automaticallyWaitsToMinimizeStalling = false
        clipPlayer.automaticallyWaitsToMinimizeStalling = false
        configureAudioSession()
        observeSystemEvents()
        setupRemoteCommands()

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            let seconds = t.seconds
            MainActor.assumeIsolated {
                self?.clockTick(seconds)
            }
        }
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                let playing = self.player.timeControlStatus != .paused
                guard self.isPlaying != playing else { return }
                self.isPlaying = playing
                self.updateNowPlaying()
            }
        }
    }

    // MARK: Loading

    func load(url: URL, title: String, album: String, duration: Double, startAt position: Double) {
        guard url != currentURL else { return }
        pause()
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain
        player.replaceCurrentItem(with: item)

        let clipItem = AVPlayerItem(url: url)
        clipItem.audioTimePitchAlgorithm = .timeDomain
        clipPlayer.replaceCurrentItem(with: clipItem)

        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.wantsToPlay = false
                self?.isPlaying = false
                self?.updateNowPlaying()
            }
        }

        currentURL = url
        hasAudio = true
        self.duration = max(1, duration)
        nowTitle = title
        nowAlbum = album
        seek(to: position >= self.duration - 1 ? 0 : position)
    }

    // MARK: Transport

    func play() {
        guard hasAudio else { return }
        activateAudioSession()
        clipPlayer.pause()
        if time >= duration - 0.2 { seek(to: 0) }
        wantsToPlay = true
        player.playImmediately(atRate: Float(rate))
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        wantsToPlay = false
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: Double) {
        let target = max(0, min(duration - 0.05, seconds))
        time = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 44_100),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        onTick?(target)
        updateNowPlaying()
    }

    func skip(_ delta: Double) {
        seek(to: time + delta)
    }

    func setRate(_ newRate: Double) {
        rate = newRate
        player.defaultRate = Float(newRate)
        if isPlaying { player.rate = Float(newRate) }
        updateNowPlaying()
    }

    /// Plays one word from the original narration, then stops.
    func playClip(from start: Double, to end: Double) {
        guard let item = clipPlayer.currentItem else { return }
        if isPlaying { pause() }
        clipPlayer.pause()
        activateAudioSession()
        item.forwardPlaybackEndTime = CMTime(seconds: end + 0.06, preferredTimescale: 44_100)
        clipPlayer.seek(to: CMTime(seconds: max(0, start - 0.04), preferredTimescale: 44_100),
                        toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard finished else { return }
            Task { @MainActor in
                self?.clipPlayer.playImmediately(atRate: 1.0)
            }
        }
    }

    // MARK: Clock

    private func clockTick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        if isPlaying || abs(seconds - time) > 0.01 {
            time = seconds
        }
        onTick?(seconds)
    }

    // MARK: Audio session and system events

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [])
    }

    private func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func observeSystemEvents() {
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo ?? [:]
            let rawType = (info[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
            let rawOptions = (info[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
                switch type {
                case .began:
                    self.isPlaying = false
                    self.updateNowPlaying()
                case .ended:
                    let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                    if options.contains(.shouldResume) && self.wantsToPlay { self.play() }
                @unknown default:
                    break
                }
            }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let raw = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
            MainActor.assumeIsolated {
                // Headphones unplugged: pause, as Apple's audio guidelines ask.
                if AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable {
                    self?.pause()
                }
            }
        }
    }

    // MARK: Lock screen and headphones

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        _ = c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        _ = c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        _ = c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }
        _ = c.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onNextSentence?() }
            return .success
        }
        _ = c.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPreviousSentence?() }
            return .success
        }
        _ = c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = e.positionTime
            Task { @MainActor in self?.seek(to: position) }
            return .success
        }
        c.skipForwardCommand.isEnabled = false
        c.skipBackwardCommand.isEnabled = false
    }

    private func updateNowPlaying() {
        guard hasAudio else { return }
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: nowTitle,
            MPMediaItemPropertyArtist: "The Economist",
            MPMediaItemPropertyAlbumTitle: nowAlbum,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: time,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: rate,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
