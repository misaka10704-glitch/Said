import Foundation

enum IELTSStage: String, CaseIterable {
    case transcription
    case transcriptRepair
    case pronunciation
    case feedback
}

enum IELTSStageState: String {
    case pending, running, succeeded, failed, cancelled, skipped
}

struct IELTSStageReport {
    let stage: IELTSStage
    var state: IELTSStageState
    var attempts: Int
    var elapsed: TimeInterval
    var error: String?

    init(_ stage: IELTSStage, state: IELTSStageState = .pending) {
        self.stage = stage
        self.state = state
        attempts = 0
        elapsed = 0
        error = nil
    }
}

typealias IELTSPhonemeScore = PronunciationPhonemeScore
typealias IELTSWordScore = PronunciationWordScore

struct IELTSPronunciationResult {
    var accuracy: Double = 0
    var fluency: Double = 0
    var completeness: Double = 0
    var prosody: Double?
    var words: [IELTSWordScore] = []
    var error: String?

    init(score: ScoreResult) {
        accuracy = score.accuracy
        fluency = score.fluency
        completeness = score.completeness
        prosody = score.prosody
        error = score.error
        words = score.words
    }
}

struct IELTSFeedback {
    var modelAnswer = ""
    var critique = ""
    var minimalCorrection = ""
}

struct IELTSServiceRequest {
    let audioURL: URL
    let question: String
    let part: IELTSPart
    let duration: TimeInterval?

    init(audioURL: URL, question: String, part: IELTSPart, duration: TimeInterval? = nil) {
        self.audioURL = audioURL
        self.question = question
        self.part = part
        self.duration = duration
    }
}

struct IELTSServiceResult {
    let request: IELTSServiceRequest
    var rawTranscript = ""
    var repairedTranscript = ""
    var pronunciation: IELTSPronunciationResult?
    var feedback = IELTSFeedback()
    var stages: [IELTSStage: IELTSStageReport] = {
        var value: [IELTSStage: IELTSStageReport] = [:]
        IELTSStage.allCases.forEach { value[$0] = IELTSStageReport($0) }
        return value
    }()
    var totalElapsed: TimeInterval = 0

    var displayTranscript: String { rawTranscript }
    var failedStages: [IELTSStage] {
        IELTSStage.allCases.filter { stages[$0]?.state == .failed }
    }
}

final class IELTSServiceTask {
    private let lock = NSLock()
    private var cancelled = false
    private var tasks: [URLSessionTask] = []

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let current = tasks
        tasks.removeAll()
        lock.unlock()
        current.forEach { $0.cancel() }
    }

    func register(_ task: URLSessionTask) {
        lock.lock()
        if cancelled {
            lock.unlock()
            task.cancel()
            return
        }
        tasks.append(task)
        lock.unlock()
    }
}
