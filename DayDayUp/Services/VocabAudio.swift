import AVFoundation
import Foundation

/// The system voice with a completion, for 听词 and for words without original audio.
/// Always labelled "合成音" in the UI (READ-F06): it is not the article's narrator.
@MainActor
final class SpeechQueue: NSObject {
    static let shared = SpeechQueue()

    private let synth = AVSpeechSynthesizer()
    private var waiter: CheckedContinuation<Bool, Never>?
    private var current: ObjectIdentifier?

    override init() {
        super.init()
        synth.delegate = self
    }

    var isSpeaking: Bool { synth.isSpeaking }

    /// Speaks `text` and returns when it has finished (true) or was stopped (false).
    /// `rate` 1.0 = a little slower than the system default, like the word cards.
    @discardableResult
    func speak(_ text: String, language: String, rate: Double = 1.0) async -> Bool {
        stop()
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return true }
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: clean)
        u.voice = AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice(language: "en-GB")
        let base = Double(AVSpeechUtteranceDefaultSpeechRate) * 0.9 * rate
        u.rate = Float(min(Double(AVSpeechUtteranceMaximumSpeechRate), max(Double(AVSpeechUtteranceMinimumSpeechRate), base)))
        current = ObjectIdentifier(u)
        return await withCheckedContinuation { c in
            waiter = c
            synth.speak(u)
        }
    }

    func stop() {
        current = nil
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        let w = waiter
        waiter = nil
        w?.resume(returning: false)
    }

    /// A voice for this language is installed on the iPad (works offline).
    static func hasVoice(_ language: String) -> Bool {
        AVSpeechSynthesisVoice(language: language) != nil
    }

    fileprivate func finished(_ id: ObjectIdentifier, ok: Bool) {
        guard id == current else { return }      // a late callback of an older utterance
        current = nil
        let w = waiter
        waiter = nil
        w?.resume(returning: ok)
    }
}

extension SpeechQueue: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in SpeechQueue.shared.finished(id, ok: true) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in SpeechQueue.shared.finished(id, ok: false) }
    }
}

/// Where the sound of a word, chunk or sentence comes from.
enum ItemAudioSource: Equatable {
    case clip(URL, start: Double, end: Double)   // the article's original audio
    case tts(String)                              // system voice (合成音)
    case none

    var label: String {
        switch self {
        case .clip: return "原声"
        case .tts: return "合成音"
        case .none: return "没有声音"
        }
    }

    var isOriginal: Bool {
        if case .clip = self { return true }
        return false
    }
}

@MainActor
enum ItemAudio {
    /// An original clip is used only when the pack is installed, the sentence was not changed by an
    /// update, and the audio file is the one the clip was cut from.
    private static func usableAudio(_ o: Occurrence, packs: PackStore) -> URL? {
        guard o.unmapped != true, let url = packs.audioURL(o.ref),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        if let sha = o.audioSha, let now = packs.audioSha(o.ref), sha != now { return nil }
        return url
    }

    /// Sound of the word or chunk itself.
    static func word(_ item: VocabItem, occurrence: Occurrence?, packs: PackStore, preferOriginal: Bool) -> ItemAudioSource {
        if preferOriginal, let o = occurrence ?? item.firstSource, let clip = o.clip, clip.count == 2,
           let url = usableAudio(o, packs: packs) {
            return .clip(url, start: clip[0], end: clip[1])
        }
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? .none : .tts(text)
    }

    /// Sound of the whole sentence the item was met in.
    static func sentence(_ occurrence: Occurrence?, packs: PackStore, preferOriginal: Bool) -> ItemAudioSource {
        guard let o = occurrence else { return .none }
        if preferOriginal, let url = usableAudio(o, packs: packs),
           let s = packs.sentence(o.ref, sid: o.sid), let clip = OccurrenceBuilder.sentenceClip(s) {
            return .clip(url, start: clip[0], end: clip[1])
        }
        if let text = o.sentence, !text.isEmpty { return .tts(text) }
        return .none
    }

    /// Plays a source to the end. Returns false if it was stopped or failed.
    @discardableResult
    static func play(_ source: ItemAudioSource, player: SegmentPlayer, language: String, rate: Double = 1.0) async -> Bool {
        switch source {
        case .clip(let url, let start, let end):
            SpeechQueue.shared.stop()
            AudioSessionControl.usePlayback()
            return await player.play(url, from: start, to: end, rate: rate, as: .original)
        case .tts(let text):
            player.stop()
            AudioSessionControl.usePlayback()
            return await SpeechQueue.shared.speak(text, language: language, rate: rate)
        case .none:
            return false
        }
    }

    static func stop(player: SegmentPlayer) {
        player.stop()
        SpeechQueue.shared.stop()
    }
}
