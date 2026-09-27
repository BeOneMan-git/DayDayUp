import Foundation
import AVFoundation
import Observation

/// Plays one stretch of an audio file and says when it has ended:
/// an original sentence from the article audio, or one of the learner's recordings.
/// Used by 听原句, 回放 and A/B (original, a short gap, then the recording).
///
/// Every wait ends: at the end of the stretch, on failure, on an audio interruption
/// (call, Siri), when something else starts playing, or after a watchdog timeout.
@MainActor
@Observable
final class SegmentPlayer {
    enum Source: Equatable {
        case none, original, mine
    }

    private(set) var playing: Source = .none

    /// Created on first use, so views can build this object cheaply.
    @ObservationIgnored private var avPlayer: AVPlayer?
    private var player: AVPlayer {
        if let p = avPlayer { return p }
        let p = AVPlayer()
        p.automaticallyWaitsToMinimizeStalling = false
        avPlayer = p
        return p
    }
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var waiter: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var sequence: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init() {}

    /// Plays [start, end] of `url` at `rate`. Returns true if it reached the end.
    /// Cancels an A/B sequence that is still running.
    @discardableResult
    func play(_ url: URL, from start: Double = 0, to end: Double? = nil, rate: Double = 1,
              as source: Source) async -> Bool {
        sequence?.cancel()
        sequence = nil
        return await playStretch(url, from: start, to: end, rate: rate, as: source)
    }

    /// Original sentence, a gap, then the learner's recording.
    func playAB(original: URL, from start: Double, to end: Double, rate: Double, mine: URL, gap: Double = 0.5) {
        stop()
        sequence = Task { [weak self] in
            guard let self else { return }
            let reached = await self.playStretch(original, from: start, to: end, rate: rate, as: .original)
            guard reached, !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self.playStretch(mine, from: 0, to: nil, rate: 1, as: .mine)
        }
    }

    func stop() {
        sequence?.cancel()
        sequence = nil
        generation += 1
        endCurrent(reached: false)
    }

    // MARK: Internals

    @discardableResult
    private func playStretch(_ url: URL, from start: Double, to end: Double?, rate: Double,
                             as source: Source) async -> Bool {
        endCurrent(reached: false)
        generation += 1
        let myGeneration = generation

        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain
        if let end, end > start {
            item.forwardPlaybackEndTime = CMTime(seconds: end + 0.05, preferredTimescale: 44_100)
        }
        player.replaceCurrentItem(with: item)
        if start > 0 {
            _ = await player.seek(to: CMTime(seconds: max(0, start - 0.03), preferredTimescale: 44_100),
                                  toleranceBefore: .zero, toleranceAfter: .zero)
        }
        // Another play() or stop() came in while seeking.
        guard myGeneration == generation, !Task.isCancelled else { return false }

        try? AVAudioSession.sharedInstance().setActive(true)
        playing = source
        ActivityClock.shared.touch()
        return await withCheckedContinuation { continuation in
            waiter = continuation
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish(reached: true, generation: myGeneration) }
            })
            observers.append(center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification,
                                                object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    DiagLog.shared.log("audio", "segment failed: \(url.lastPathComponent)")
                    self?.finish(reached: false, generation: myGeneration)
                }
            })
            observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                                object: nil, queue: .main) { [weak self] note in
                let raw = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
                MainActor.assumeIsolated {
                    if AVAudioSession.InterruptionType(rawValue: raw) == .began {
                        self?.finish(reached: false, generation: myGeneration)
                    }
                }
            })
            statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
                guard observed.status == .failed else { return }
                Task { @MainActor in
                    DiagLog.shared.log("audio", "segment item failed: \(url.lastPathComponent)")
                    self?.finish(reached: false, generation: myGeneration)
                }
            }
            if let end, end > start {
                // Safety net in case the end notification never arrives.
                let limit = (end - start) / max(rate, 0.25) + 3
                watchdog = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(limit * 1_000_000_000))
                    guard !Task.isCancelled, let self else { return }
                    let reached = self.player.currentTime().seconds >= end - 0.3
                    self.finish(reached: reached, generation: myGeneration)
                }
            }
            player.playImmediately(atRate: Float(rate))
        }
    }

    private func finish(reached: Bool, generation g: Int) {
        guard g == generation else { return }
        endCurrent(reached: reached)
    }

    private func endCurrent(reached: Bool) {
        avPlayer?.pause()
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
        statusObservation?.invalidate()
        statusObservation = nil
        watchdog?.cancel()
        watchdog = nil
        playing = .none
        let w = waiter
        waiter = nil
        w?.resume(returning: reached)
    }
}
