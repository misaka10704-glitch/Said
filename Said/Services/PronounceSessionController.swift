import Foundation

enum PronounceSessionState {
    case idle
    case loadingReference
    case ready(reference: PronounceAudioAttachment?)
    case recording
    case recorded(PronounceAudioAttachment)
    case scoring(PronounceAudioAttachment)
    case completed(PronounceHistoryEntry)
    case failed(message: String, canRetry: Bool)
    case cancelled
}

final class PronounceSessionController {
    var onStateChange: ((PronounceSessionState) -> Void)?

    private let assessment: PronounceAssessmentProviding
    private let referenceAudio: PronounceReferenceAudioProviding
    private let recording: PronounceRecordingProviding
    private let history: PronounceHistoryStoring
    private var activeTask: PronounceCancellable?
    private var card: AnkiCardSnapshot?
    private(set) var target: PronounceTarget?
    private(set) var referenceAttachment: PronounceAudioAttachment?
    private(set) var recordingAttachment: PronounceAudioAttachment?
    private(set) var recordingDuration: TimeInterval?
    var isRecording: Bool { recording.isRecording }
    private var recordingStartedAt: Date?
    private var recordingIsPersistent = false
    private var generation = 0

    init(
        assessment: PronounceAssessmentProviding = RetryingPronounceAssessmentClient(
            base: AzurePronounceAssessmentClient()
        ),
        referenceAudio: PronounceReferenceAudioProviding = EdgeTTSReferenceAudioProvider(),
        recording: PronounceRecordingProviding = NativePronounceRecorder(),
        history: PronounceHistoryStoring = PronounceHistoryStore.shared
    ) {
        self.assessment = assessment
        self.referenceAudio = referenceAudio
        self.recording = recording
        self.history = history
    }

    func configure(card: AnkiCardSnapshot, deckHint: String? = nil) {
        reset()
        generation += 1
        self.card = card
        target = PronounceReferenceTargetParser.parse(card: card, deckHint: deckHint)
        referenceAttachment = nil
        recordingAttachment = nil
        recordingDuration = nil
        guard target != nil else {
            emit(.failed(message: "无法从此卡片解析发音目标", canRetry: false))
            return
        }
        emit(.idle)
    }

    /// Uses the same recorder/state machine for free-speaking modes without a pronunciation target.
    func configureRecording(card: AnkiCardSnapshot) {
        reset()
        generation += 1
        self.card = card
        target = nil
        referenceAttachment = nil
        recordingAttachment = nil
        recordingDuration = nil
        emit(.idle)
    }

    func loadReferenceAudio() {
        guard let target = target, let card = card else {
            emit(.failed(message: "尚未配置卡片", canRetry: false))
            return
        }
        activeTask?.cancel()
        let current = generation
        emit(.loadingReference)
        activeTask = referenceAudio.audio(for: target, card: card) { [weak self] result in
            guard let self = self, self.generation == current else { return }
            self.activeTask = nil
            switch result {
            case .success(let attachment):
                self.referenceAttachment = attachment
                self.emit(.ready(reference: attachment))
            case .failure:
                // Reference audio is optional; recording and assessment remain usable.
                self.emit(.ready(reference: nil))
            }
        }
    }

    func requestRecordingPermission(completion: @escaping (Bool) -> Void) {
        recording.requestPermission(completion: completion)
    }

    func startRecording() {
        activeTask?.cancel()
        activeTask = nil
        do {
            try recording.start()
            recordingStartedAt = Date()
            emit(.recording)
        } catch {
            emit(.failed(message: error.localizedDescription, canRetry: true))
        }
    }

    func stopRecording() {
        guard let temporary = recording.stop() else {
            emit(.failed(message: "录音未生成", canRetry: true))
            return
        }
        if let started = recordingStartedAt {
            recordingDuration = Date().timeIntervalSince(started)
        }
        recordingStartedAt = nil
        guard let target = target else {
            recordingAttachment = temporary
            recordingIsPersistent = false
            emit(.recorded(temporary))
            return
        }
        do {
            let persistent = try PronounceRecordingAttachmentStore.persist(temporary, target: target)
            MemoryGuard.purgeTemporaryAudio(url: temporary.fileURL)
            recordingAttachment = persistent
            recordingIsPersistent = true
            emit(.recorded(persistent))
        } catch {
            recordingAttachment = temporary
            recordingIsPersistent = false
            emit(.recorded(temporary))
        }
    }

    func score() {
        guard let target = target, let attachment = recordingAttachment else {
            emit(.failed(message: "请先完成录音", canRetry: false))
            return
        }
        activeTask?.cancel()
        let current = generation
        emit(.scoring(attachment))
        activeTask = assessment.assess(recordingURL: attachment.fileURL, target: target) { [weak self] result in
            guard let self = self, self.generation == current else { return }
            self.activeTask = nil
            switch result {
            case .success(let score):
                let entry = PronounceHistoryEntry(
                    target: target,
                    score: score,
                    recordingURL: attachment.fileURL
                )
                self.history.save(entry, completion: nil)
                self.emit(.completed(entry))
            case .failure(let error):
                let nsError = error as NSError
                if nsError.code == NSURLErrorCancelled {
                    self.emit(.cancelled)
                } else {
                    self.emit(.failed(message: error.localizedDescription, canRetry: true))
                }
            }
        }
    }

    func loadLatestHistory() {
        guard let target = target else { return }
        let current = generation
        history.latest(for: target) { [weak self] entry in
            guard let self = self, self.generation == current, let entry = entry else { return }
            self.emit(.completed(entry))
        }
    }

    func cancel() {
        generation += 1
        activeTask?.cancel()
        activeTask = nil
        if recording.isRecording { recording.cancel() }
        recordingStartedAt = nil
        emit(.cancelled)
    }

    func reset() {
        cancel()
        if !recordingIsPersistent, let url = recordingAttachment?.fileURL {
            MemoryGuard.purgeTemporaryAudio(url: url)
        }
        recordingAttachment = nil
        recordingDuration = nil
        recordingIsPersistent = false
    }

    private func emit(_ state: PronounceSessionState) {
        if Thread.isMainThread {
            onStateChange?(state)
        } else {
            DispatchQueue.main.async { [weak self] in self?.onStateChange?(state) }
        }
    }
}
