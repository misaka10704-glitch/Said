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

struct IELTSPhonemeScore {
    let phoneme: String
    let accuracy: Double
}

struct IELTSWordScore {
    let word: String
    let accuracy: Double
    let error: String
    let phonemes: [IELTSPhonemeScore]
}

struct IELTSPronunciationResult {
    var accuracy: Double = 0
    var fluency: Double = 0
    var completeness: Double = 0
    var words: [IELTSWordScore] = []
    var error: String?

    init(score: ScoreResult) {
        accuracy = score.accuracy
        fluency = score.fluency
        completeness = score.completeness
        error = score.error
        words = score.words.map { value in
            let phonemes = (value["phonemes"] as? [[String: Any]] ?? []).map {
                IELTSPhonemeScore(
                    phoneme: $0["phoneme"] as? String ?? "",
                    accuracy: IELTSPronunciationResult.number($0["accuracy"])
                )
            }
            return IELTSWordScore(
                word: value["word"] as? String ?? "",
                accuracy: IELTSPronunciationResult.number(value["accuracy"]),
                error: value["error"] as? String ?? "",
                phonemes: phonemes
            )
        }
    }

    private static func number(_ value: Any?) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return 0
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
