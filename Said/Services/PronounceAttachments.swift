import Foundation

struct PronounceAudioAttachment: Equatable {
    enum Kind: String {
        case reference
        case recording
    }

    let kind: Kind
    let fileURL: URL
    let mediaName: String?
}

protocol PronounceReferenceAudioProviding {
    @discardableResult
    func audio(
        for target: PronounceTarget,
        card: AnkiCardSnapshot,
        completion: @escaping (Result<PronounceAudioAttachment, Error>) -> Void
    ) -> PronounceCancellable
}

protocol PronounceRecordingProviding: AnyObject {
    var isRecording: Bool { get }
    func requestPermission(completion: @escaping (Bool) -> Void)
    func start() throws
    func stop() -> PronounceAudioAttachment?
    func cancel()
}

enum PronounceAttachmentError: Error, LocalizedError {
    case referenceAudioNotFound
    case invalidMediaName
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .referenceAudioNotFound: return "未找到参考音频"
        case .invalidMediaName: return "音频文件名无效"
        case .copyFailed(let value): return "保存录音失败：\(value)"
        }
    }
}

final class NativePronounceRecorder: PronounceRecordingProviding {
    private let recorder: AudioRecorder

    init(recorder: AudioRecorder = AudioRecorder()) {
        self.recorder = recorder
    }

    var isRecording: Bool { recorder.isRecording }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        recorder.requestPermission(completion: completion)
    }

    func start() throws {
        try recorder.start()
    }

    func stop() -> PronounceAudioAttachment? {
        recorder.stop().map { PronounceAudioAttachment(kind: .recording, fileURL: $0, mediaName: nil) }
    }

    func cancel() {
        recorder.cancel()
    }
}

final class AnkiMediaReferenceAudioProvider: PronounceReferenceAudioProviding {
    @discardableResult
    func audio(
        for target: PronounceTarget,
        card: AnkiCardSnapshot,
        completion: @escaping (Result<PronounceAudioAttachment, Error>) -> Void
    ) -> PronounceCancellable {
        let token = PronounceCancellation()
        DispatchQueue.global(qos: .userInitiated).async {
            let candidates = Self.soundNames(in: card.fields + [card.frontHTML, card.backHTML])
            let fileManager = FileManager.default
            let found = candidates.lazy
                .map { card.mediaDir.appendingPathComponent($0) }
                .first { fileManager.fileExists(atPath: $0.path) }
            guard !token.isCancelled else { return }
            DispatchQueue.main.async {
                guard !token.isCancelled else { return }
                if let found = found {
                    completion(.success(PronounceAudioAttachment(
                        kind: .reference,
                        fileURL: found,
                        mediaName: found.lastPathComponent
                    )))
                } else {
                    completion(.failure(PronounceAttachmentError.referenceAudioNotFound))
                }
            }
        }
        return token
    }

    private static func soundNames(in values: [String]) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "(?i)\\[sound:([^\\]]+)\\]") else { return [] }
        var result: [String] = []
        for value in values {
            for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)) {
                guard let range = Range(match.range(at: 1), in: value) else { continue }
                let name = String(value[range]).removingPercentEncoding ?? String(value[range])
                guard !name.contains("/"), !name.contains("\\"), name != ".", name != ".." else { continue }
                if !result.contains(name) { result.append(name) }
            }
        }
        return result
    }
}

final class FallbackPronounceReferenceAudioProvider: PronounceReferenceAudioProviding {
    private let providers: [PronounceReferenceAudioProviding]

    init(providers: [PronounceReferenceAudioProviding]) {
        self.providers = providers
    }

    @discardableResult
    func audio(
        for target: PronounceTarget,
        card: AnkiCardSnapshot,
        completion: @escaping (Result<PronounceAudioAttachment, Error>) -> Void
    ) -> PronounceCancellable {
        let aggregate = PronounceCancellation()
        func attempt(_ index: Int) {
            guard !aggregate.isCancelled else { return }
            guard index < providers.count else {
                completion(.failure(PronounceAttachmentError.referenceAudioNotFound))
                return
            }
            let active = providers[index].audio(for: target, card: card) { result in
                guard !aggregate.isCancelled else { return }
                switch result {
                case .success: completion(result)
                case .failure: attempt(index + 1)
                }
            }
            aggregate.install { active.cancel() }
        }
        attempt(0)
        return aggregate
    }
}

enum PronounceRecordingAttachmentStore {
    static func persist(_ attachment: PronounceAudioAttachment, target: PronounceTarget) throws -> PronounceAudioAttachment {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pronounce/recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let destination = base.appendingPathComponent("rec_\(target.cacheKey).wav")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        do {
            try FileManager.default.copyItem(at: attachment.fileURL, to: destination)
        } catch {
            throw PronounceAttachmentError.copyFailed(error.localizedDescription)
        }
        return PronounceAudioAttachment(kind: .recording, fileURL: destination, mediaName: nil)
    }

    static func attachToAnkiMedia(
        _ attachment: PronounceAudioAttachment,
        target: PronounceTarget,
        mediaDirectory: URL
    ) throws -> PronounceAudioAttachment {
        let name = "pronounce_\(target.cacheKey).wav"
        guard !name.contains("/"), !name.contains("\\") else {
            throw PronounceAttachmentError.invalidMediaName
        }
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let destination = mediaDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: attachment.fileURL, to: destination)
        return PronounceAudioAttachment(kind: .recording, fileURL: destination, mediaName: name)
    }

    static func soundTag(for attachment: PronounceAudioAttachment) -> String? {
        attachment.mediaName.map { "[sound:\($0)]" }
    }
}
