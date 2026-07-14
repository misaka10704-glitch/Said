import Foundation
import AVFoundation

enum AudioRecorderError: Error, LocalizedError {
    case permissionDenied
    case sessionFailed
    case recordFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "未获得麦克风权限"
        case .sessionFailed: return "无法启动录音会话"
        case .recordFailed: return "录音失败"
        }
    }
}

/// 16 kHz mono WAV recorder — matches desktop ffmpeg avfoundation output for Azure.
final class AudioRecorder: NSObject {
    private var recorder: AVAudioRecorder?
    private(set) var fileURL: URL?
    private(set) var isRecording = false

    func requestPermission(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { ok in
            DispatchQueue.main.async { completion(ok) }
        }
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("speaking_\(Int(Date().timeIntervalSince1970)).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.isMeteringEnabled = true
        guard recorder?.record() == true else { throw AudioRecorderError.recordFailed }
        fileURL = url
        isRecording = true
    }

    func stop() -> URL? {
        recorder?.stop()
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return fileURL
    }

    func cancel() {
        recorder?.stop()
        isRecording = false
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        fileURL = nil
    }
}

final class AudioPlayer {
    private var player: AVAudioPlayer?

    func play(url: URL) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        let audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer.prepareToPlay()
        guard audioPlayer.play() else {
            throw AudioRecorderError.sessionFailed
        }
        player = audioPlayer
    }

    func stop() {
        player?.stop()
        player = nil
    }
}
