import Foundation
import AVFoundation
import Observation

/// Switches the shared audio session between listening and recording.
@MainActor
enum AudioSessionControl {
    /// Listening only (the reader and lock-screen playback).
    static func usePlayback() {
        let session = AVAudioSession.sharedInstance()
        guard session.category != .playback else { return }
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
        } catch {
            DiagLog.shared.log("audio", "setCategory playback failed: \(error.localizedDescription)")
        }
    }

    /// Recording plus playback (跟读, 口语). Sound goes to the speaker or to Bluetooth headphones;
    /// the microphone is the iPad's own or a wired headset.
    static func useRecording() throws {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        }
        try session.setActive(true)
    }

    /// 影子跟读: record while the original plays. Asks the system for echo-cancelled input (iPadOS 18.2+),
    /// which only helps on some hardware; returns whether the request was accepted.
    @discardableResult
    static func useShadowing() throws -> Bool {
        try useRecording()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setPrefersEchoCancelledInput(true)
            return true
        } catch {
            DiagLog.shared.log("audio", "echo-cancelled input not available: \(error.localizedDescription)")
            return false
        }
    }

    /// Turns the echo-cancelled input request off again (other modes record the plain microphone).
    static func endShadowing() {
        try? AVAudioSession.sharedInstance().setPrefersEchoCancelledInput(false)
    }

    /// True when sound comes out of the iPad's own speaker, so the original can leak into the recording (ACC-17).
    static var outputIsSpeaker: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
    }

    /// Output names, for the take record ("耳机", "扬声器" …).
    static var outputText: String {
        let outs = AVAudioSession.sharedInstance().currentRoute.outputs
        if outs.isEmpty { return "未知" }
        return outs.map { port -> String in
            switch port.portType {
            case .builtInSpeaker: return "扬声器"
            case .headphones: return "有线耳机"
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: return "蓝牙耳机"
            case .airPlay: return "AirPlay"
            default: return port.portName
            }
        }.joined(separator: "、")
    }
}

struct RecordingResult: Equatable {
    var file: String
    var seconds: Double
    var peakDb: Double
    var silent: Bool
    var interrupted: Bool
}

enum RecorderError: LocalizedError {
    case cannotStart

    var errorDescription: String? {
        switch self {
        case .cannotStart: return "录音没有启动。可能是麦克风正被别的 App 使用。"
        }
    }
}

/// Microphone recording for 跟读 and 口语. One recorder for the whole app.
/// Permission is asked the first time the learner taps record (not at launch).
/// An interruption (phone call, Siri) or leaving the app stops and saves the take.
@MainActor
@Observable
final class RecorderService {
    enum Phase: Equatable {
        case idle
        case recording
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var denied = false
    private(set) var elapsed: Double = 0
    private(set) var level: Double = 0          // 0...1, for the meter
    private(set) var owner: String?             // which screen started the recording

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var fileURL: URL?
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private var maxPeak: Float = -160
    @ObservationIgnored private var maxDuration: Double = 60
    @ObservationIgnored private var silenceStop: Double?
    @ObservationIgnored private var quietSince: Date?
    @ObservationIgnored private var heardVoice = false
    @ObservationIgnored private var onFinish: ((RecordingResult) -> Void)?
    @ObservationIgnored private var starting = false

    /// Peak level (dBFS) that counts as speech. Below this for the whole take = "只录到静音".
    static let voiceThreshold: Float = -38
    static let quietThreshold: Float = -45

    init() {
        denied = AVAudioApplication.shared.recordPermission == .denied
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                                               object: nil, queue: .main) { [weak self] note in
            let raw = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
            MainActor.assumeIsolated {
                if AVAudioSession.InterruptionType(rawValue: raw) == .began {
                    self?.interrupt(reason: "interruption")
                }
            }
        }
    }

    var isRecording: Bool { phase == .recording }

    /// Recording, or asking for permission / starting up. A second start is ignored then.
    var isBusy: Bool { starting || phase == .recording }

    func refreshPermission() {
        denied = AVAudioApplication.shared.recordPermission == .denied
    }

    /// Starts recording into `url`. Returns false if permission is missing or the recorder fails.
    /// `onFinish` runs once when the take ends for any reason.
    func start(into url: URL, owner: String, maxDuration: Double, stopAfterSilence: Double? = nil,
               onFinish: @escaping (RecordingResult) -> Void) async -> Bool {
        guard phase != .recording, !starting else { return false }
        starting = true
        defer { starting = false }
        let granted = await RecorderService.ensurePermission()
        denied = !granted
        guard granted else {
            DiagLog.shared.log("record", "microphone permission denied")
            return false
        }
        do {
            try AudioSessionControl.useRecording()
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 22_050.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32_000,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.isMeteringEnabled = true
            guard r.prepareToRecord(), r.record() else { throw RecorderError.cannotStart }
            recorder = r
            fileURL = url
            self.owner = owner
            self.maxDuration = maxDuration
            silenceStop = stopAfterSilence
            self.onFinish = onFinish
            maxPeak = -160
            quietSince = nil
            heardVoice = false
            elapsed = 0
            level = 0
            phase = .recording
            startMeter()
            DiagLog.shared.log("record", "start owner=\(owner) max=\(Int(maxDuration))s route=\(RecorderService.routeText())")
            return true
        } catch {
            phase = .failed(error.localizedDescription)
            DiagLog.shared.log("record", "start failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Normal stop (the learner tapped stop).
    func stop() {
        finish(interrupted: false)
    }

    /// Stops and marks the take as interrupted (call, Siri, app sent to background).
    func interrupt(reason: String) {
        guard phase == .recording else { return }
        DiagLog.shared.log("record", "interrupted: \(reason)")
        finish(interrupted: true)
    }

    func clearFailure() {
        if case .failed = phase { phase = .idle }
    }

    private func finish(interrupted: Bool) {
        guard phase == .recording, let r = recorder, let url = fileURL else { return }
        r.updateMeters()
        maxPeak = max(maxPeak, r.peakPower(forChannel: 0))
        let seconds = max(elapsed, r.currentTime)
        r.stop()
        meterTask?.cancel()
        meterTask = nil
        recorder = nil
        fileURL = nil
        phase = .idle
        level = 0
        let result = RecordingResult(file: url.lastPathComponent, seconds: seconds, peakDb: Double(maxPeak),
                                     silent: maxPeak < RecorderService.voiceThreshold, interrupted: interrupted)
        DiagLog.shared.log("record", "stop \(String(format: "%.1f", seconds))s peak=\(Int(maxPeak))dB silent=\(result.silent) interrupted=\(interrupted)")
        let done = onFinish
        onFinish = nil
        owner = nil
        done?(result)
    }

    private func startMeter() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self else { return }
                self.meterTick()
            }
        }
    }

    private func meterTick() {
        guard phase == .recording, let r = recorder else { return }
        r.updateMeters()
        let peak = r.peakPower(forChannel: 0)
        let average = r.averagePower(forChannel: 0)
        maxPeak = max(maxPeak, peak)
        elapsed = r.currentTime
        level = Double(max(0, min(1, (average + 50) / 50)))
        if peak > RecorderService.voiceThreshold {
            heardVoice = true
            quietSince = nil
        } else if average < RecorderService.quietThreshold, quietSince == nil {
            quietSince = Date()
        }
        if let limit = silenceStop, heardVoice, let since = quietSince, Date().timeIntervalSince(since) >= limit {
            finish(interrupted: false)
            return
        }
        if elapsed >= maxDuration {
            finish(interrupted: false)
        }
    }

    /// nonisolated: the system calls the completion handler on its own queue.
    nonisolated static func ensurePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        default:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    static func routeText() -> String {
        let route = AVAudioSession.sharedInstance().currentRoute
        let inputs = route.inputs.map { $0.portType.rawValue }.joined(separator: ",")
        let outputs = route.outputs.map { $0.portType.rawValue }.joined(separator: ",")
        return "in=\(inputs) out=\(outputs)"
    }
}
